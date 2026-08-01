import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/model/practice_history_entry.dart';
import '../domain/repository/practice_history_repository.dart';
import 'practice_history_serializer.dart';

/// Local, versioned, capped, idempotent Practice History V2 repository.
///
/// Backed by a single [JsonCollectionStore] under [StorageKeys.practiceHistoryV2].
/// One record per session — saving with the same `id` updates the existing
/// record instead of appending (ADR 0084 §Döntés 4).
class LocalPracticeHistoryRepository implements PracticeHistoryRepository {
  LocalPracticeHistoryRepository({required this.store, required this.logger});

  final JsonCollectionStore<PracticeHistoryEntry> store;
  final AppLogger logger;

  @override
  Future<AppResult<List<PracticeHistoryEntry>>> load() async {
    try {
      final records = store.read();
      return Success<List<PracticeHistoryEntry>>(
        List<PracticeHistoryEntry>.unmodifiable(records),
      );
    } on StorageException catch (e, stackTrace) {
      logger.error(
        'practice_history.load_failed',
        error: e,
        stackTrace: stackTrace,
      );
      return Failure<List<PracticeHistoryEntry>>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      logger.error(
        'practice_history.load_failed',
        error: e,
        stackTrace: stackTrace,
      );
      return Failure<List<PracticeHistoryEntry>>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> save(PracticeHistoryEntry entry) async {
    try {
      final existing = store.read();
      // Newest-first ordering: new entries go at index 0 so the
      // [RecordOrder.newestFirst] cap evicts the oldest, not the just-saved.
      final next = <PracticeHistoryEntry>[
        entry,
        for (final record in existing)
          if (record.id != entry.id) record,
      ];
      await store.write(next);
      return const Success<void>(null);
    } on StorageException catch (e, stackTrace) {
      logger.error(
        'practice_history.save_failed',
        error: e,
        stackTrace: stackTrace,
        fields: <String, Object?>{'sessionId': entry.id},
      );
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      logger.error(
        'practice_history.save_failed',
        error: e,
        stackTrace: stackTrace,
        fields: <String, Object?>{'sessionId': entry.id},
      );
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> clear() async {
    try {
      await store.write(const <PracticeHistoryEntry>[]);
      return const Success<void>(null);
    } on StorageException catch (e, stackTrace) {
      logger.error(
        'practice_history.clear_failed',
        error: e,
        stackTrace: stackTrace,
      );
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Riverpod binding for the production repository.
///
/// Wired to the [JsonDocumentStore] under [StorageKeys.practiceHistoryV2].
/// The document has no legacy key — the V2 store is a clean slate.
final practiceHistoryRepositoryProvider = Provider<PracticeHistoryRepository>((
  ref,
) {
  final store = ref.watch(keyValueStoreProvider);
  final logger = ref.watch(appLoggerProvider);
  return LocalPracticeHistoryRepository(
    store: JsonCollectionStore<PracticeHistoryEntry>(
      document: JsonDocumentStore(
        store: store,
        logger: logger,
        key: StorageKeys.practiceHistoryV2,
        legacyKey: _noLegacyKey,
        name: 'practice_history_v2',
      ),
      fromJson: _decode,
      toJson: _encode,
      maxItems: PracticeHistoryRepository.maxSessions,
    ),
    logger: logger,
  );
});

// Helpers used by [practiceHistoryRepositoryProvider]. Kept as top-level
// functions so the `JsonCollectionStore` sees simple `T Function(...)`
// callables (it does not own the serializer object).

PracticeHistoryEntry _decode(Map<String, dynamic> json) {
  return const PracticeHistorySerializer().fromJson(json);
}

Map<String, dynamic> _encode(PracticeHistoryEntry entry) {
  return const PracticeHistorySerializer().toJson(entry);
}

// `JsonDocumentStore` requires a legacy key for read-fallback. The V2
// history has no legacy data — any pre-envelope bytes under this key would
// have come from a build that never shipped, so the read just returns null.
const String _noLegacyKey = 'ss.practice.history_v2.legacy';

// Re-export the [JsonCollectionStore] type so test files do not need
// to import the storage layer directly.
typedef PracticeHistoryCollectionStore<T> = JsonCollectionStore<T>;
