import 'dart:async';

import '../../../core/foundation/json_validation.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/key_value_store.dart';
import 'gamification_repository.dart';
import 'gamification_storage_schema.dart';

/// Local implementation backed by four independent versioned documents.
///
/// A profile replacement is one [JsonDocumentStore.write] call. The core
/// store writes its complete envelope in one operation, so a rejected write
/// leaves the earlier profile document readable after restart.
final class LocalGamificationRepository implements GamificationRepository {
  LocalGamificationRepository({
    required KeyValueStore store,
    required AppLogger logger,
  }) : _store = store,
       _profileDocument = _document(
         store: store,
         logger: logger,
         key: GamificationStorageKeys.profileSnapshot,
         legacyKey: GamificationStorageKeys.profileSnapshotLegacy,
         name: 'gamification_profile_snapshot',
         bodyKey: 'data',
       ),
       _catalogDocument = _document(
         store: store,
         logger: logger,
         key: GamificationStorageKeys.catalogVersion,
         legacyKey: GamificationStorageKeys.catalogVersionLegacy,
         name: 'gamification_catalog_version',
         bodyKey: 'data',
       ),
       _inboxDocument = _document(
         store: store,
         logger: logger,
         key: GamificationStorageKeys.rewardInbox,
         legacyKey: GamificationStorageKeys.rewardInboxLegacy,
         name: 'gamification_reward_inbox',
         bodyKey: 'items',
       ),
       _migrationDocument = _document(
         store: store,
         logger: logger,
         key: GamificationStorageKeys.migrationState,
         legacyKey: GamificationStorageKeys.migrationStateLegacy,
         name: 'gamification_migration_state',
         bodyKey: 'data',
       );

  static JsonDocumentStore _document({
    required KeyValueStore store,
    required AppLogger logger,
    required String key,
    required String legacyKey,
    required String name,
    required String bodyKey,
  }) => JsonDocumentStore(
    store: store,
    logger: logger,
    key: key,
    legacyKey: legacyKey,
    name: name,
    bodyKey: bodyKey,
  );

  final KeyValueStore _store;
  final JsonDocumentStore _profileDocument;
  final JsonDocumentStore _catalogDocument;
  final JsonDocumentStore _inboxDocument;
  final JsonDocumentStore _migrationDocument;
  final StreamController<GamificationRead<GamificationProfileSnapshot>>
  _profileChanges =
      StreamController<
        GamificationRead<GamificationProfileSnapshot>
      >.broadcast();
  Future<void> _profileWriteTail = Future<void>.value();

  late final JsonCollectionStore<GamificationInboxItem> _inboxStore =
      JsonCollectionStore<GamificationInboxItem>(
        document: _inboxDocument,
        fromJson: GamificationInboxItem.fromJson,
        toJson: (item) => item.toJson(),
        maxItems: inboxRetentionLimit,
        order: RecordOrder.newestLast,
      );

  @override
  GamificationRead<GamificationProfileSnapshot> readProfileSnapshot() =>
      _readObject(_profileDocument, GamificationProfileSnapshot.fromJson);

  @override
  Future<void> replaceProfileSnapshot(GamificationProfileSnapshot snapshot) {
    final scheduled = _profileWriteTail.then<void>(
      (_) => _replaceProfileSnapshot(snapshot),
    );
    _profileWriteTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<void> _replaceProfileSnapshot(
    GamificationProfileSnapshot snapshot,
  ) async {
    await _profileDocument.write(snapshot.toJson());
    if (!_profileChanges.isClosed) {
      _profileChanges.add(
        GamificationRead<GamificationProfileSnapshot>.available(snapshot),
      );
    }
  }

  @override
  Stream<GamificationRead<GamificationProfileSnapshot>>
  watchProfileSnapshots() => _profileChanges.stream;

  @override
  GamificationRead<GamificationCatalogVersion> readCatalogVersion() =>
      _readObject(_catalogDocument, GamificationCatalogVersion.fromJson);

  @override
  Future<void> replaceCatalogVersion(GamificationCatalogVersion version) =>
      _catalogDocument.write(version.toJson());

  @override
  GamificationRead<List<GamificationInboxItem>> readInbox() {
    final body = _inboxDocument.readBody();
    if (body == null) {
      return _missingOrCorrupt<List<GamificationInboxItem>>(_inboxDocument);
    }
    if (body is! List) {
      return const GamificationRead<List<GamificationInboxItem>>.corrupt();
    }

    return GamificationRead<List<GamificationInboxItem>>.available(
      _inboxStore.read(),
    );
  }

  @override
  Future<GamificationInboxWriteReport> replaceInbox(
    List<GamificationInboxItem> items,
  ) async {
    await _inboxStore.write(items);
    return GamificationInboxWriteReport(
      trimmedCount: items.length > inboxRetentionLimit
          ? items.length - inboxRetentionLimit
          : 0,
    );
  }

  @override
  GamificationRead<GamificationMigrationState> readMigrationState() =>
      _readObject(_migrationDocument, GamificationMigrationState.fromJson);

  @override
  Future<void> replaceMigrationState(GamificationMigrationState state) =>
      _migrationDocument.write(state.toJson());

  @override
  Future<void> dispose() => _profileChanges.close();

  GamificationRead<T> _readObject<T>(
    JsonDocumentStore document,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final body = document.readBody();
    if (body == null) return _missingOrCorrupt<T>(document);
    try {
      return GamificationRead<T>.available(fromJson(requireObject(body)));
    } on Object {
      return GamificationRead<T>.corrupt();
    }
  }

  GamificationRead<T> _missingOrCorrupt<T>(JsonDocumentStore document) =>
      !_store.contains(document.key) && !_store.contains(document.legacyKey)
      ? GamificationRead<T>.missing()
      : GamificationRead<T>.corrupt();
}
