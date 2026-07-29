import 'dart:convert';

import '../foundation/json_validation.dart';
import '../logging/app_logger.dart';
import 'key_value_store.dart';
import 'storage_keys.dart';

/// Schema version of the document envelope every complex local document is
/// written in (SDD Ch2 Kör 7 §7.3):
///
/// ```json
/// {"schemaVersion": 1, "items": []}
/// ```
///
/// The envelope is what makes a future shape change survivable: a build that
/// meets a **newer** version than it understands isolates the document instead
/// of decoding it wrongly, and a build that meets an older one can upgrade in a
/// [StorageMigration].
const int documentSchemaVersion = 1;

/// Where new records enter the list, which decides which end the cap evicts.
///
/// Both collections keep the **newest** records: dropping the newest to keep
/// stale ones would make the app look like it lost the user's last action.
enum RecordOrder {
  /// Newest record first (library, songs, setlists) — evict from the tail.
  newestFirst,

  /// Newest record last (the practice log) — evict from the head.
  newestLast,
}

/// Reads and writes ONE versioned JSON document under a [KeyValueStore] key.
///
/// Everything about corruption handling (§7.4) lives here, once:
///
/// * a document that cannot be parsed is **kept**, never overwritten blind —
///   it is copied to a quarantine key on the next write so the user's bytes
///   remain recoverable and the app carries on with a clean document;
/// * a legacy (pre-envelope) blob is still read when the rename migration has
///   not run or could not finish, so a failed migration cannot cost data: the
///   next write moves the content over and drops the legacy key itself;
/// * a platform write refusal is logged, not swallowed, and never thrown at
///   the UI — the in-memory state stays the user's truth for the session.
///
/// It deals in the raw decoded body (a `List` or a `Map`); turning that into
/// domain records is [JsonCollectionStore]'s or the feature repository's job.
class JsonDocumentStore {
  JsonDocumentStore({
    required this.store,
    required this.logger,
    required this.key,
    required this.legacyKey,
    required this.name,
    this.bodyKey = 'items',
  });

  final KeyValueStore store;

  /// Where corruption is reported. Public because the record-level decoders
  /// ([JsonCollectionStore], the lesson-progress repository) log against the
  /// same document.
  final AppLogger logger;

  /// The namespaced key this document lives under.
  final String key;

  /// The pre-envelope key shipped builds wrote. Read-only fallback.
  final String legacyKey;

  /// Short document name for logs (`songs`, `library`, …). Never a value.
  final String name;

  /// Envelope field holding the payload: `items` for a collection, `data` for
  /// a single object.
  final String bodyKey;

  /// The raw content that failed to decode, held until the next write can
  /// quarantine it. Kept in memory only — nothing is deleted meanwhile.
  String? _corrupt;

  /// The document body, or null when there is nothing readable.
  ///
  /// Never throws: a store that cannot be read must not stop the app from
  /// starting with a clean slate.
  Object? readBody() {
    final raw = store.readString(key);
    if (raw != null) return _decodeEnvelope(raw);

    final legacy = store.readString(legacyKey);
    if (legacy == null || legacy.isEmpty) return null;
    // Pre-envelope blob: either the rename migration has not run yet, or it
    // could not finish. Read it rather than report "no data" — the next write
    // completes the move (see [write]).
    logger.info('storage.document.legacy_read', fields: {'document': name});
    return _decode(legacy);
  }

  /// Persist [body], first preserving anything that failed to decode.
  ///
  /// Ordering matters: quarantine copy → new document → drop the legacy key.
  /// A death between any two steps leaves the previous step's data intact.
  Future<void> write(Object body) async {
    try {
      final corrupt = _corrupt;
      if (corrupt != null) {
        await store.writeString(StorageKeys.quarantineOf(key), corrupt);
        _corrupt = null;
        logger.warning(
          'storage.document.quarantined',
          fields: {'document': name, 'key': StorageKeys.quarantineOf(key)},
        );
      }
      await store.writeString(
        key,
        jsonEncode({'schemaVersion': documentSchemaVersion, bodyKey: body}),
      );
      if (store.contains(legacyKey)) await store.remove(legacyKey);
    } on StorageException catch (e, stackTrace) {
      // The platform refused the write. The user's state is still correct in
      // memory for this session; what must not happen is silence.
      logger.error(
        'storage.document.write_failed',
        error: e,
        stackTrace: stackTrace,
        fields: {'document': name},
      );
    }
  }

  Object? _decodeEnvelope(String raw) {
    if (raw.isEmpty) return null;
    final decoded = _decode(raw);
    if (decoded == null) return null;
    if (decoded is! Map<String, dynamic>) {
      return _markCorrupt(raw, 'not_a_document');
    }
    final version = decoded['schemaVersion'];
    if (version is! int) return _markCorrupt(raw, 'missing_version');
    if (version > documentSchemaVersion) {
      // Written by a newer build (a downgrade). Guessing at an unknown shape
      // is how data gets mangled — isolate it instead.
      return _markCorrupt(raw, 'future_version');
    }
    final body = decoded[bodyKey];
    if (body == null) return _markCorrupt(raw, 'missing_body');
    return body;
  }

  Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (e) {
      return _markCorrupt(raw, 'unparsable', error: e);
    }
  }

  Object? _markCorrupt(String raw, String reason, {Object? error}) {
    _corrupt = raw;
    logger.warning(
      'storage.document.corrupt',
      error: error,
      fields: {'document': name, 'reason': reason},
    );
    return null;
  }
}

/// A list document decoded **record by record**, so one bad record costs the
/// user that record and nothing else (§7.4).
///
/// [maxItems] is the documented storage bound for the collection (§7.5); it is
/// enforced on both read and write, so a blob that grew past it in an older
/// build is trimmed rather than carried forever.
class JsonCollectionStore<T> {
  const JsonCollectionStore({
    required this.document,
    required this.fromJson,
    required this.toJson,
    required this.maxItems,
    this.order = RecordOrder.newestFirst,
  });

  final JsonDocumentStore document;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  /// Documented maximum number of persisted records.
  final int maxItems;

  final RecordOrder order;

  /// Every valid record, newest-preserving-capped. Never throws.
  ///
  /// The empty results are `<T>[]`, deliberately not `const []`: a const empty
  /// literal is a `List<Never>` at runtime, and callers that pass a typed
  /// closure to it (`firstWhere(orElse: () => session)`) fail with a cast error
  /// on a fresh install — a crash the user meets before they have any data.
  List<T> read() {
    final body = document.readBody();
    if (body == null) return <T>[];
    if (body is! List) {
      document.logger.warning(
        'storage.document.body_not_a_list',
        fields: {'document': document.name},
      );
      return <T>[];
    }

    final items = <T>[];
    var skipped = 0;
    for (var i = 0; i < body.length; i++) {
      try {
        items.add(fromJson(requireObject(body[i])));
      } on JsonRecordException catch (e) {
        skipped++;
        document.logger.warning(
          'storage.document.record_skipped',
          fields: {
            'document': document.name,
            'index': i,
            'reason': e.reason,
            if (e.field != null) 'field': e.field,
          },
        );
      } catch (e) {
        skipped++;
        document.logger.warning(
          'storage.document.record_skipped',
          error: e,
          fields: {'document': document.name, 'index': i, 'reason': 'invalid'},
        );
      }
    }
    if (skipped > 0) {
      document.logger.warning(
        'storage.document.records_skipped',
        fields: {
          'document': document.name,
          'skipped': skipped,
          'kept': items.length,
        },
      );
    }
    return capRecords(items, maxItems, order);
  }

  Future<void> write(List<T> items) => document.write([
    for (final i in capRecords(items, maxItems, order)) toJson(i),
  ]);
}

/// A single-object document (streak state, …). A corrupt object yields null —
/// the caller falls back to its default and the bytes stay quarantined.
class JsonObjectStore<T> {
  const JsonObjectStore({
    required this.document,
    required this.fromJson,
    required this.toJson,
  });

  final JsonDocumentStore document;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  T? read() {
    final body = document.readBody();
    if (body == null) return null;
    try {
      return fromJson(requireObject(body));
    } on JsonRecordException catch (e) {
      document.logger.warning(
        'storage.document.record_skipped',
        fields: {
          'document': document.name,
          'reason': e.reason,
          if (e.field != null) 'field': e.field,
        },
      );
      return null;
    } catch (e) {
      document.logger.warning(
        'storage.document.record_skipped',
        error: e,
        fields: {'document': document.name, 'reason': 'invalid'},
      );
      return null;
    }
  }

  Future<void> write(T value) => document.write(toJson(value));
}

/// Trim [items] to [maxItems], dropping the oldest end for [order].
List<T> capRecords<T>(List<T> items, int maxItems, RecordOrder order) {
  if (items.length <= maxItems) return items;
  return order == RecordOrder.newestFirst
      ? items.sublist(0, maxItems)
      : items.sublist(items.length - maxItems);
}
