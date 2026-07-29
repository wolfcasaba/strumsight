import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../model/streak_data.dart';

/// The practice streak, persisted locally as a single versioned document
/// (Kör 7 §7.2). Not a collection — there is exactly one streak.
abstract interface class StreakRepository {
  /// The stored streak, or null when there is none (or the stored one could not
  /// be decoded — the caller falls back to a fresh [StreakData] and the corrupt
  /// bytes stay isolated, never silently rewritten).
  StreakData? load();

  Future<void> save(StreakData streak);
}

class KeyValueStreakRepository implements StreakRepository {
  const KeyValueStreakRepository(this._streak);

  final JsonObjectStore<StreakData> _streak;

  @override
  StreakData? load() => _streak.read();

  @override
  Future<void> save(StreakData streak) => _streak.write(streak);
}

final streakRepositoryProvider = Provider<StreakRepository>((ref) {
  return KeyValueStreakRepository(
    JsonObjectStore<StreakData>(
      document: JsonDocumentStore(
        store: ref.watch(keyValueStoreProvider),
        logger: ref.watch(appLoggerProvider),
        key: StorageKeys.streak,
        legacyKey: LegacyStorageKeys.streak,
        name: 'streak',
        bodyKey: 'data',
      ),
      fromJson: StreakData.fromJson,
      toJson: (s) => s.toJson(),
    ),
  );
});
