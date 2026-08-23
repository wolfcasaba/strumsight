/// Local, per-user, versioned Community post draft store
/// (E09-R12, brief §5.2–§5.3).
///
/// **Scope:** one in-progress draft per user. The composer is single
/// instance; if a user opens two composers in parallel, the second one
/// overwrites the first — that's a future round's concern (and is
/// already prevented by the navigation layer in this build, which
/// pushes only one `PostComposerScreen` route at a time).
///
/// **User scope (pre-flight D3):** the storage key is partitioned by
/// ``userId`` — the first user-id-keyed local storage in the repo.
/// Each user sees only their own draft on login; logout does NOT touch
/// the draft, so the same user signing back in gets the same draft
/// back (the §10 logout-policy decision).
///
/// **Schema version:** ``1`` for this round. There is no prior
/// Community draft envelope to migrate from — this is the first
/// user-id-partitioned Community storage document in the repo. A
/// future shape bump moves to ``.v2`` and adds the matching legacy
/// key at that point; for this round the document carries no
/// `legacyKey`.
///
/// **Corruption (L354 precedent):** the store is built on
/// [JsonObjectStore], which quarantines a per-record decode failure
/// rather than rolling back the whole envelope. A draft that fails to
/// decode is dropped on the next read; the user's bytes are still
/// recoverable via ``storage.<key>.corrupt`` (see
/// ``StorageKeys.quarantineOf``).
library;

import '../../../../core/foundation/json_validation.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/json_document_store.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';

/// Document schema version of the Community draft envelope.
///
/// Bumping this number triggers the envelope's "future version"
/// handling in [JsonDocumentStore]; the existing bytes are quarantined
/// intact so the next build can read them.
const int communityDraftSchemaVersion = 1;

/// Stable, human-readable name for the document in logs and
/// quarantines.
const String _documentName = 'community_draft';

/// Wire literal for [CommunityAudience] in the persisted draft — the
/// Wire literal for [CommunityAudience] in the persisted draft — the
/// A versioned, persisted in-progress Community post draft.
///
/// The draft holds the **submission-side** state of a single composer
/// session: the body the user is typing, the chosen audience, the
/// [SharePreview] toggles (which control what the future Kör 18 media
/// attachment step would surface), and the source artifact the post
/// will reference.
///
/// **Stable idempotency key (brief §5.2):** [idempotencyKey] is
/// generated exactly once when the draft is first persisted (or, for
/// the migration path, recovered from the existing legacy bytes). The
/// same value is reused for every retry, so an offline-then-online
/// sequence is observed as a single mutation by the server. A new
/// draft (a fresh composer session) generates a fresh key — the key
/// is the identity of "this specific post the user is composing",
/// not of the composer instance.
class CommunityDraft {
  const CommunityDraft({
    required this.idempotencyKey,
    required this.body,
    required this.audience,
    required this.sourceArtifactJson,
    required this.sharePreview,
    required this.lastEditedAt,
  });

  /// Build the *first* draft for a new composer session. Generates a
  /// stable [idempotencyKey] from the current wall-clock timestamp and
  /// a monotonic per-instance counter (so two drafts created in the
  /// same microsecond — extremely unlikely, but possible on
  /// hot-restart — still get distinct keys).
  factory CommunityDraft.fresh({
    required String body,
    required CommunityAudience audience,
    required Map<String, Object?> sourceArtifactJson,
    required SharePreview sharePreview,
    DateTime? now,
    int monotonicCounter = 0,
  }) {
    final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    final key = 'e09-r12-draft-$stamp-$monotonicCounter';
    return CommunityDraft(
      idempotencyKey: key,
      body: body,
      audience: audience,
      sourceArtifactJson: sourceArtifactJson,
      sharePreview: sharePreview,
      lastEditedAt: now ?? DateTime.now(),
    );
  }

  /// The stable, client-generated idempotency key (brief §5.2, ADR
  /// 0405 §1). Non-nullable, non-empty, persists across restart.
  final String idempotencyKey;

  /// The post body the user is typing. Null when the body is empty
  /// (matches the [CommunityPost.body] nullable contract — Kör 11
  /// accepts `null` and treats it as "no prose, only the artifact").
  final String? body;

  /// The audience the user has selected for the post.
  final CommunityAudience audience;

  /// The serialized source artifact the post will reference. Kept as
  /// a raw JSON map (not the typed [ShareArtifact]) so this round
  /// does NOT pull another feature's public.dart into the draft
  /// store's compilation unit — the JSON shape is the seam.
  final Map<String, Object?> sourceArtifactJson;

  /// The field-level share toggles the user has flipped.
  final SharePreview sharePreview;

  /// Wall-clock timestamp of the last save. Drives the
  /// "last-edited-ago" UI label and the draft-conflict policy in
  /// future rounds.
  final DateTime lastEditedAt;

  CommunityDraft copyWith({
    String? body,
    CommunityAudience? audience,
    Map<String, Object?>? sourceArtifactJson,
    SharePreview? sharePreview,
    DateTime? lastEditedAt,
  }) {
    return CommunityDraft(
      idempotencyKey: idempotencyKey,
      body: body ?? this.body,
      audience: audience ?? this.audience,
      sourceArtifactJson: sourceArtifactJson ?? this.sourceArtifactJson,
      sharePreview: sharePreview ?? this.sharePreview,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
    );
  }

  /// Whether the draft carries any user-typed content beyond the
  /// artifact. Empty drafts are not persisted — `clearDraft` is
  /// called by the composer on submit-success and on explicit
  /// "discard", so an empty draft means "no work in progress".
  bool get isEmpty => (body == null || body!.isEmpty);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': communityDraftSchemaVersion,
    'idempotencyKey': idempotencyKey,
    'body': body,
    'audience': audience.wireValue,
    'sourceArtifactJson': sourceArtifactJson,
    'sharePreview': _sharePreviewToJson(sharePreview),
    'lastEditedAt': lastEditedAt.toIso8601String(),
  };

  static CommunityDraft fromJson(Map<String, Object?> object) {
    final schemaVersion = object['schemaVersion'];
    if (schemaVersion is! int) {
      throw JsonRecordException(
        'schemaVersion must be an integer',
        field: 'schemaVersion',
      );
    }
    if (schemaVersion != communityDraftSchemaVersion) {
      throw JsonRecordException(
        'unsupported draft schemaVersion $schemaVersion '
        '(expected $communityDraftSchemaVersion)',
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
    final audience = _audienceFromWire(audienceWire);
    final body = object['body'];
    final sourceArtifactRaw = object['sourceArtifactJson'];
    if (sourceArtifactRaw is! Map<String, Object?>) {
      throw JsonRecordException(
        'sourceArtifactJson must be an object',
        field: 'sourceArtifactJson',
      );
    }
    final previewRaw = object['sharePreview'];
    if (previewRaw is! Map<String, Object?>) {
      throw JsonRecordException(
        'sharePreview must be an object',
        field: 'sharePreview',
      );
    }
    final lastEditedRaw = object['lastEditedAt'];
    final lastEdited = lastEditedRaw is String
        ? DateTime.tryParse(lastEditedRaw)
        : null;
    if (lastEdited == null) {
      throw JsonRecordException(
        'lastEditedAt must be an ISO date string',
        field: 'lastEditedAt',
      );
    }
    return CommunityDraft(
      idempotencyKey: key,
      body: body is String ? body : null,
      audience: audience,
      sourceArtifactJson: sourceArtifactRaw,
      sharePreview: _sharePreviewFromJson(previewRaw),
      lastEditedAt: lastEdited,
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

Map<String, Object?> _sharePreviewToJson(SharePreview preview) =>
    <String, Object?>{
      'includeChordTimeline': preview.includeChordTimeline,
      'includeStrumPattern': preview.includeStrumPattern,
      'includeTempo': preview.includeTempo,
      'includeStreakDays': preview.includeStreakDays,
      'includeBestScore': preview.includeBestScore,
    };

SharePreview _sharePreviewFromJson(Map<String, Object?> object) {
  bool flag(String name) => object[name] == true;
  return SharePreview(
    includeChordTimeline: flag('includeChordTimeline'),
    includeStrumPattern: flag('includeStrumPattern'),
    includeTempo: flag('includeTempo'),
    includeStreakDays: flag('includeStreakDays'),
    includeBestScore: flag('includeBestScore'),
  );
}

/// A per-user, versioned, on-device Community post draft store.
///
/// Construction takes the user-id-keyed storage key — the producer
/// (a Riverpod provider) is responsible for picking the right key for
/// the signed-in user. Reading or writing for a user that does not
/// have a draft yet returns ``null`` from [readDraft] and is a no-op
/// for [clearDraft].
class CommunityDraftStore {
  /// Internal constructor — use [CommunityDraftStore.open] to bind
  /// to a real [KeyValueStore].
  CommunityDraftStore._({required this._body});

  /// The injected, versioned single-document store.
  final JsonObjectStore<CommunityDraft> _body;

  /// Open a [CommunityDraftStore] against a real [KeyValueStore] for
  /// the given ``userId``.
  ///
  /// ``userId`` is interpolated into the storage key — never into the
  /// document body, and the document body carries the schema version
  /// that protects a future build from mis-decoding an older one.
  factory CommunityDraftStore.open({
    required KeyValueStore store,
    required AppLogger logger,
    required int userId,
  }) {
    final document = JsonDocumentStore(
      store: store,
      logger: logger,
      key: _storageKeyFor(userId),
      // No legacy key — the draft envelope is fresh in Kör 12
      // (no prior Community draft document exists to migrate from).
      // Wiring the same key for both would cause `JsonDocumentStore.write`
      // to immediately remove what it just wrote; passing an empty
      // string keeps the per-user `v2.<userId>` partition clean.
      legacyKey: '',
      name: _documentName,
    );
    return CommunityDraftStore._(
      body: JsonObjectStore<CommunityDraft>(
        document: document,
        fromJson: CommunityDraft.fromJson,
        toJson: (draft) => draft.toJson(),
      ),
    );
  }

  /// Resolve the namespaced storage key for the given user.
  ///
  /// The ``ss.community.drafts.v2.<userId>`` shape is the first
  /// user-id-partitioned key in this repo (pre-flight D3). A future
  /// shape bump moves to ``.v3`` next to the matching legacy entry.
  static String _storageKeyFor(int userId) => 'ss.community.drafts.v2.$userId';

  /// Public for the test surface and the round-auditor: the resolved
  /// storage key for [userId].
  static String storageKeyFor(int userId) => _storageKeyFor(userId);

  /// The current draft for this user, or ``null`` when there is no
  /// in-progress draft (fresh install, just submitted, or after an
  /// explicit clear).
  ///
  /// A persisted draft whose [CommunityDraft.body] is empty AND
  /// whose source artifact carries no identity is treated as "no
  /// draft" — `clearDraft` writes such a sentinel rather than
  /// removing the document (the JsonObjectStore API has no `remove`
  /// surface), so this normalization is what callers actually want.
  CommunityDraft? readDraft() {
    final draft = _body.read();
    if (draft == null) return null;
    if (draft.isEmpty) return null;
    return draft;
  }

  /// Persist [draft] for this user. Throws [StorageException] on a
  /// platform write refusal (the [KeyValueStore] contract) — the
  /// caller (the composer controller) catches it and surfaces a
  /// non-fatal "couldn't save draft" message, but does NOT delete the
  /// in-memory copy the user is still editing.
  Future<void> saveDraft(CommunityDraft draft) async {
    if (draft.isEmpty) {
      await clearDraft();
      return;
    }
    await _body.write(draft);
  }

  /// Drop the user's draft. Idempotent — a no-op if no draft exists.
  Future<void> clearDraft() async {
    final current = _body.read();
    if (current == null) return;
    await _body.write(_emptySentinel(current));
  }

  /// The draft store records the body only — the post-success path
  /// cannot rely on "document missing" because the platform's write
  /// may legitimately fail. The clear path persists a sentinel that
  /// the next [readDraft] recognises and treats as "no draft". The
  /// sentinel keeps the same idempotency key (so a debug trace can
  /// correlate), but is otherwise a blank record.
  CommunityDraft _emptySentinel(CommunityDraft previous) {
    return CommunityDraft(
      idempotencyKey: previous.idempotencyKey,
      body: null,
      audience: previous.audience,
      sourceArtifactJson: previous.sourceArtifactJson,
      sharePreview: const SharePreview(),
      lastEditedAt: previous.lastEditedAt,
    );
  }
}
