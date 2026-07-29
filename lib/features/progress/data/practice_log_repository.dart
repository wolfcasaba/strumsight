import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../model/practice_entry.dart';

/// The raw practice history, persisted locally (Kör 7 §7.2).
///
/// The log is kept **newest-last**, so the documented cap evicts from the front
/// — the dashboard needs recent history and totals, and the oldest moments are
/// the least interesting.
abstract interface class PracticeLogRepository {
  List<PracticeEntry> load();
  Future<void> save(List<PracticeEntry> entries);

  /// Documented storage bound (§7.5): a heavy user's log stays bounded instead
  /// of growing without limit in a single preference value.
  static const int maxEntries = 400;
}

class KeyValuePracticeLogRepository implements PracticeLogRepository {
  const KeyValuePracticeLogRepository(this._entries);

  final JsonCollectionStore<PracticeEntry> _entries;

  @override
  List<PracticeEntry> load() => _entries.read();

  @override
  Future<void> save(List<PracticeEntry> entries) => _entries.write(entries);
}

final practiceLogRepositoryProvider = Provider<PracticeLogRepository>((ref) {
  return KeyValuePracticeLogRepository(
    JsonCollectionStore<PracticeEntry>(
      document: JsonDocumentStore(
        store: ref.watch(keyValueStoreProvider),
        logger: ref.watch(appLoggerProvider),
        key: StorageKeys.practiceLog,
        legacyKey: LegacyStorageKeys.practiceLog,
        name: 'practice_log',
      ),
      fromJson: PracticeEntry.fromJson,
      toJson: (e) => e.toJson(),
      maxItems: PracticeLogRepository.maxEntries,
      order: RecordOrder.newestLast,
    ),
  );
});
