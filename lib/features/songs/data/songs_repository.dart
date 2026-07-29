import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../model/song.dart';

/// The user's songbook, persisted locally (Kör 7 §7.2).
///
/// [load] is **synchronous**: the key-value store is opened during bootstrap,
/// before the first frame, so the controller can build its initial state
/// without an async gap — which is what removed the r149/r150 race class (a
/// mutation racing an unfinished load used to persist the empty default over
/// the songbook on disk).
abstract interface class SongsRepository {
  List<Song> load();
  Future<void> save(List<Song> songs);

  /// Documented storage bound (§7.5). Songs are hand-authored, so this is far
  /// above any realistic songbook; at the limit the OLDEST song is evicted,
  /// the same policy the library has always used.
  static const int maxSongs = 200;
}

class KeyValueSongsRepository implements SongsRepository {
  const KeyValueSongsRepository(this._songs);

  final JsonCollectionStore<Song> _songs;

  @override
  List<Song> load() => _songs.read();

  @override
  Future<void> save(List<Song> songs) => _songs.write(songs);
}

final songsRepositoryProvider = Provider<SongsRepository>((ref) {
  return KeyValueSongsRepository(
    JsonCollectionStore<Song>(
      document: JsonDocumentStore(
        store: ref.watch(keyValueStoreProvider),
        logger: ref.watch(appLoggerProvider),
        key: StorageKeys.songs,
        legacyKey: LegacyStorageKeys.songs,
        name: 'songs',
      ),
      fromJson: Song.fromJson,
      toJson: (s) => s.toJson(),
      maxItems: SongsRepository.maxSongs,
    ),
  );
});
