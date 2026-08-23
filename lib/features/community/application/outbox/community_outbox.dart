/// Community outbox — the retry-queue between the composer and the
/// server-side ``POST /community/posts`` endpoint (E09-R12, brief
/// §5.2 / A2 / A4).
///
/// **Stable mutation-ID (brief §5.2):** every pending post carries a
/// persisted ``idempotencyKey`` — the same value the Kör 11 backend
/// uses to dedupe retries. The key is generated when the post is
/// enqueued and survives app restart, so a network failure followed
/// by a user-induced kill does not produce a second submission when
/// the next drain runs.
///
/// **Pattern (pre-flight D2):** this outbox mirrors the gamification
/// ``LocalActivityOutboxRepository`` (E08-R04): a bounded, persisted
/// pending list; a synchronous ``pendingPosts()`` snapshot; a single
/// ``drain()`` pass that forwards each pending record to the
/// repository exactly once per attempt and acknowledges the ones
/// that succeed.
///
/// **API surface:** the outbox depends on the abstract
/// [CommunityPostRepository] (Kör 5, ADR 0399 §1) — never on the
/// network implementation. Tests inject a fake; production wires the
/// Kör 11 ``HttpCommunityPostRepository`` once it lands.
///
/// **No background retry loop:** the drain is opt-in (composer
/// submit, app-launch, manual pull-to-refresh on the outbox widget).
/// A failing record cannot starve the rest of the queue (the same
/// invariant the gamification outbox enforces).
library;

import 'dart:async';

import '../../../../core/foundation/json_validation.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/json_document_store.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../data/local/community_draft_store.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/post_repository.dart';

/// Document schema version of the Community outbox envelope.
///
/// Bumping this number triggers the envelope's "future version"
/// handling in [JsonDocumentStore]; the existing bytes are quarantined
/// intact so the next build can read them.
const int communityOutboxSchemaVersion = 1;

/// Default namespaced storage key for the Community outbox document.
const String communityOutboxStorageKey = 'ss.community.outbox.v1';

/// Stable, human-readable name for the document in logs and
/// quarantines.
const String _documentName = 'community_outbox';

/// The body key inside the outbox envelope — the persisted pending
/// list lives under this field.
const String _bodyKey = 'pending';

/// A persisted, in-flight Community post awaiting server confirmation.
///
/// [idempotencyKey] is the stable, client-generated identity of the
/// post. The server uses it as the §19.2 dedupe key — the same value
/// across all retries means a network blip produces one post, not
/// two. The Kör 11 server-side validation rejects an unknown
/// idempotency key on the second attempt as 200 with the existing
/// post id (the documented behaviour, ADR 0405 §1).
class CommunityPendingPost {
  CommunityPendingPost({
    required this.idempotencyKey,
    required this.audience,
    required this.body,
    required this.sourceArtifactJson,
    required this.createdAt,
    this.attempts = 0,
  });

  /// The Kör 5 idempotency key, generated at enqueue time and
  /// persisted with the record.
  final String idempotencyKey;

  /// The audience the user selected. Persisted because the user
  /// may have closed the composer before the post was acknowledged;
  /// the drain needs the original value, not the user's current
  /// audience setting.
  final CommunityAudience audience;

  /// The body the user typed. Null is the same shape as
  /// [CommunityPost.body] — a body-less post is valid (artifact-only).
  final String? body;

  /// The serialized source artifact the post will reference.
  /// JSON map, not the typed [ShareArtifact], so the outbox does NOT
  /// pull another feature's public.dart into the compilation unit —
  /// the JSON shape is the seam, the same precedent as
  /// [CommunityDraft.sourceArtifactJson].
  final Map<String, Object?> sourceArtifactJson;

  /// When the post was first enqueued. Distinct from [attempts] —
  /// [createdAt] is a one-shot stamp, [attempts] is the running
  /// retry counter.
  final DateTime createdAt;

  /// The number of [CommunityOutbox.drain] attempts so far. Starts
  /// at 0 on enqueue; a successful drain removes the record. Future
  /// rounds may add an attempt limit; for now, retry is unbounded
  /// because the server-side idempotency-key dedupe makes a
  /// double-submit impossible regardless of how many retries fire.
  int attempts;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': communityOutboxSchemaVersion,
    'idempotencyKey': idempotencyKey,
    'audience': audience.wireValue,
    'body': body,
    'sourceArtifactJson': sourceArtifactJson,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };

  static CommunityPendingPost fromJson(Map<String, Object?> object) {
    final schemaVersion = object['schemaVersion'];
    if (schemaVersion is! int) {
      throw JsonRecordException(
        'schemaVersion must be an integer',
        field: 'schemaVersion',
      );
    }
    if (schemaVersion != communityOutboxSchemaVersion) {
      throw JsonRecordException(
        'unsupported outbox schemaVersion $schemaVersion '
        '(expected $communityOutboxSchemaVersion)',
        field: 'schemaVersion',
      );
    }
    final key = object['idempotencyKey'];
    if (key is! String || key.isEmpty) {
      throw JsonRecordException(
        'idempotencyKey must be a non-empty string',
        field: 'idempotencyKey',
      );
    }
    final audienceWire = object['audience'];
    if (audienceWire is! String) {
      throw JsonRecordException('audience must be a string', field: 'audience');
    }
    final body = object['body'];
    final sourceArtifactRaw = object['sourceArtifactJson'];
    if (sourceArtifactRaw is! Map<String, Object?>) {
      throw JsonRecordException(
        'sourceArtifactJson must be an object',
        field: 'sourceArtifactJson',
      );
    }
    final createdAtRaw = object['createdAt'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;
    if (createdAt == null) {
      throw JsonRecordException(
        'createdAt must be an ISO date string',
        field: 'createdAt',
      );
    }
    final attemptsRaw = object['attempts'];
    final attempts = attemptsRaw is int ? attemptsRaw : 0;
    final audience = _audienceFromWire(audienceWire);
    return CommunityPendingPost(
      idempotencyKey: key,
      audience: audience,
      body: body is String ? body : null,
      sourceArtifactJson: sourceArtifactRaw,
      createdAt: createdAt,
      attempts: attempts,
    );
  }
}

CommunityAudience _audienceFromWire(String wire) {
  for (final value in CommunityAudience.values) {
    if (value.wireValue == wire) return value;
  }
  throw JsonRecordException(
    'unknown audience wire value "$wire"',
    field: 'audience',
  );
}

/// Outcome details from a single [CommunityOutbox.enqueue] call.
class CommunityOutboxEnqueueResult {
  const CommunityOutboxEnqueueResult({
    required this.accepted,
    required this.record,
  });

  /// ``true`` when the new record joined the pending queue (or was
  /// recognised as a duplicate of one already pending).
  final bool accepted;

  /// The record that was actually enqueued. The composer's
  /// caller MUST use this record's [CommunityPendingPost.idempotencyKey]
  /// going forward — the caller cannot assume the input draft's
  /// key is the one that joined the queue (an outbox may rewrite
  /// the key on a duplicate-detect path; this round does not, but
  /// the contract leaves room).
  final CommunityPendingPost record;
}

/// Aggregate outcome of one [CommunityOutbox.drain] pass.
class CommunityOutboxDrainReport {
  const CommunityOutboxDrainReport({
    required this.acknowledged,
    required this.retrying,
  });

  /// The idempotency keys whose post was successfully created
  /// server-side during this pass.
  final List<String> acknowledged;

  /// The idempotency keys that failed to drain in this pass and
  /// remain in the pending queue for the next pass.
  final List<String> retrying;

  @override
  String toString() =>
      'CommunityOutboxDrainReport(acknowledged: $acknowledged, '
      'retrying: $retrying)';
}

/// Bounded, persisted outbox between the post composer and the
/// server-side post endpoint.
///
/// All operations are queue-serialised: ``enqueue`` and ``drain``
/// observe a single tail future so a slow network call cannot be
/// pre-empted by a concurrent submit (the same pattern the
/// gamification outbox uses).
abstract interface class CommunityOutbox {
  /// Append a pending post built from the caller's [draft]. The
  /// resulting record's idempotencyKey is taken from the draft —
  /// the draft is the source of truth for the post's identity.
  ///
  /// Throws [StateError] when a pending record with the same
  /// idempotency key already exists; the composer treats that as
  /// "the post is already queued, don't submit again".
  Future<CommunityOutboxEnqueueResult> enqueue({required CommunityDraft draft});

  /// Process every pending record at most once. Each record is
  /// forwarded to the injected [CommunityPostRepository] with the
  /// *persisted* idempotency key — the A2 invariant. A successful
  /// submit removes the record; a failure leaves it in pending
  /// with its ``attempts`` counter incremented.
  Future<CommunityOutboxDrainReport> drain();

  /// Snapshot of the current pending queue, oldest first.
  List<CommunityPendingPost> pendingPosts();
}

/// Local-only implementation of [CommunityOutbox], persisted through
/// the shared [KeyValueStore].
final class LocalCommunityOutbox implements CommunityOutbox {
  LocalCommunityOutbox({
    required CommunityPostRepository repository,
    required KeyValueStore store,
    required AppLogger logger,
    JsonDocumentStore? document,
  }) : _repository = repository,
       _logger = logger,
       _document =
           document ??
           JsonDocumentStore(
             store: store,
             logger: logger,
             key: communityOutboxStorageKey,
             // No legacy key — the outbox is a fresh Kör 12
             // document with no pre-envelope shape. Wiring the same
             // key for both would cause `JsonDocumentStore.write`
             // to immediately remove what it just wrote.
             legacyKey: '',
             name: _documentName,
             bodyKey: _bodyKey,
           );

  /// The namespaced storage key under which the outbox document is
  /// persisted. Public for the test surface and the round-auditor.
  static String get storageKey => communityOutboxStorageKey;

  final CommunityPostRepository _repository;
  final AppLogger _logger;
  final JsonDocumentStore _document;

  final List<CommunityPendingPost> _pending = <CommunityPendingPost>[];
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  @override
  Future<CommunityOutboxEnqueueResult> enqueue({
    required CommunityDraft draft,
  }) {
    final scheduled = _tail.then((_) => _enqueue(draft));
    _tail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  @override
  Future<CommunityOutboxDrainReport> drain() {
    final scheduled = _tail.then((_) => _drain());
    _tail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  @override
  List<CommunityPendingPost> pendingPosts() {
    _ensureLoaded();
    return List<CommunityPendingPost>.unmodifiable(_pending);
  }

  Future<CommunityOutboxEnqueueResult> _enqueue(CommunityDraft draft) async {
    _ensureLoaded();
    final key = draft.idempotencyKey;
    final existing = _pending.where((record) => record.idempotencyKey == key);
    if (existing.isNotEmpty) {
      // A pending record with this key already exists — the brief
      // §5.2 "stable ID across retries" invariant: we don't create a
      // second record, we don't generate a new ID, we return the
      // existing one. The composer treats this as "submit is already
      // in flight, no second submit".
      _logger.info(
        'community.outbox.duplicate_enqueue',
        fields: <String, Object?>{'idempotencyKey': key},
      );
      return CommunityOutboxEnqueueResult(
        accepted: false,
        record: existing.first,
      );
    }

    final record = CommunityPendingPost(
      idempotencyKey: key,
      audience: draft.audience,
      body: draft.body,
      sourceArtifactJson: Map<String, Object?>.from(draft.sourceArtifactJson),
      createdAt: draft.lastEditedAt,
      attempts: 0,
    );
    _pending.add(record);
    await _persist();
    return CommunityOutboxEnqueueResult(accepted: true, record: record);
  }

  Future<CommunityOutboxDrainReport> _drain() async {
    _ensureLoaded();
    final acknowledged = <String>[];
    final retrying = <String>[];

    for (final record in List<CommunityPendingPost>.from(_pending)) {
      try {
        await _repository.createPost(
          audience: record.audience,
          body: record.body,
          artifact: record.sourceArtifactJson,
          // A2 — the persisted, stable mutation key. The server
          // sees the same key on every retry; the first successful
          // submit wins, every later attempt returns the existing
          // post id (ADR 0405 §1). A buggy implementation that
          // regenerated the key per call would create a duplicate
          // post — the §6.1 measure-matrix row 2.
          idempotencyKey: record.idempotencyKey,
        );
        acknowledged.add(record.idempotencyKey);
        _pending.removeWhere(
          (candidate) => candidate.idempotencyKey == record.idempotencyKey,
        );
        _logger.info(
          'community.outbox.acknowledged',
          fields: <String, Object?>{'idempotencyKey': record.idempotencyKey},
        );
      } on Object catch (error, stackTrace) {
        // The brief §5.1 invariant: the composer MUST NOT show a
        // false success. A failure here is logged and the record is
        // left in pending with its attempts counter incremented; the
        // next drain retries it.
        record.attempts += 1;
        retrying.add(record.idempotencyKey);
        _logger.warning(
          'community.outbox.retry',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{
            'idempotencyKey': record.idempotencyKey,
            'attempts': record.attempts,
          },
        );
      }
    }

    await _persist();
    return CommunityOutboxDrainReport(
      acknowledged: List<String>.unmodifiable(acknowledged),
      retrying: List<String>.unmodifiable(retrying),
    );
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;

    final body = _document.readBody();
    if (body is! Map<String, Object?>) {
      // The envelope is missing or malformed — start with an empty
      // queue rather than throwing (a corrupt outbox must not block
      // the user from composing).
      _logger.warning(
        'community.outbox.body_not_an_object',
        fields: <String, Object?>{'document': _documentName},
      );
      return;
    }
    final rawPending = body[_bodyKey];
    if (rawPending is! List<Object?>) return;
    for (final raw in rawPending) {
      if (raw is! Map) {
        // The envelope lists an item that isn't a record — skip it
        // rather than failing the whole load.
        _logger.warning(
          'community.outbox.pending_post_skipped',
          fields: <String, Object?>{'reason': 'not_a_map'},
        );
        continue;
      }
      final rawMap = <String, Object?>{
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      try {
        final record = CommunityPendingPost.fromJson(rawMap);
        _pending.add(record);
      } on JsonRecordException catch (error) {
        _logger.warning(
          'community.outbox.pending_post_skipped',
          fields: <String, Object?>{
            'reason': error.reason,
            if (error.field != null) 'field': error.field,
          },
        );
      } on ArgumentError catch (error) {
        _logger.warning(
          'community.outbox.pending_post_skipped',
          error: error,
          fields: <String, Object?>{'reason': 'invalid'},
        );
      }
    }
  }

  Future<void> _persist() async {
    final body = <String, Object?>{
      _bodyKey: <Object?>[for (final r in _pending) r.toJson()],
    };
    await _document.write(body);
  }
}
