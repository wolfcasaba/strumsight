import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../model/setlist.dart';

/// The user's saved setlists, persisted locally (Kör 7 §7.2). Synchronous
/// [load] for the same reason as [SongsRepository]: no async gap, no race.
abstract interface class SetlistsRepository {
  List<Setlist> load();
  Future<void> save(List<Setlist> setlists);

  /// Documented storage bound (§7.5); the oldest set is evicted at the limit.
  /// A setlist holds song *ids* only, so the document stays small — the per-set
  /// entry bound is `maxSetlistEntries` on the model.
  static const int maxSetlists = 100;
}

class KeyValueSetlistsRepository implements SetlistsRepository {
  const KeyValueSetlistsRepository(this._setlists);

  final JsonCollectionStore<Setlist> _setlists;

  @override
  List<Setlist> load() => _setlists.read();

  @override
  Future<void> save(List<Setlist> setlists) => _setlists.write(setlists);
}

final setlistsRepositoryProvider = Provider<SetlistsRepository>((ref) {
  return KeyValueSetlistsRepository(
    JsonCollectionStore<Setlist>(
      document: JsonDocumentStore(
        store: ref.watch(keyValueStoreProvider),
        logger: ref.watch(appLoggerProvider),
        key: StorageKeys.setlists,
        legacyKey: LegacyStorageKeys.setlists,
        name: 'setlists',
      ),
      fromJson: Setlist.fromJson,
      toJson: (s) => s.toJson(),
      maxItems: SetlistsRepository.maxSetlists,
    ),
  );
});
