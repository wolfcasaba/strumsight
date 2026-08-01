import 'dart:async';
import 'dart:convert';

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
///
/// The repository writes the JSON document envelope directly through the
/// [KeyValueStore] instead of going through [JsonDocumentStore.write]: the
/// latter swallows [StorageException] after logging it, which would silently
/// report a `Success` for a real platform-write refusal (the project's measured
/// "silent data loss" class, ADR 0084 §Döntés 5 / brief B1). Reads still flow
/// through [JsonCollectionStore] / [JsonDocumentStore] so corruption isolation,
/// the `schemaVersion` envelope check, and the cap-on-read behaviour are
/// preserved.
class LocalPracticeHistoryRepository implements PracticeHistoryRepository {
  LocalPracticeHistoryRepository({
    required this.store,
    required this.keyValueStore,
    required this.logger,
  });

  /// Read-side collection (decode + cap-on-read + record-skip on corruption).
  final JsonCollectionStore<PracticeHistoryEntry> store;

  /// Write-side backing store. Writes go through here directly so a real
  /// [StorageException] bubbles up to the repository's try/catch and surfaces
  /// as `AppResult.failure(StorageFailure)`.
  final KeyValueStore keyValueStore;

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
      // Strip per-attempt detail from older sessions: only the newest
      // [practiceHistoryDetailLimit] sessions keep detail attempts (ADR 0084
      // §Döntés 3, SDD §20.2). The session-summary is preserved for every
      // record, so the result screen still has data to render.
      final trimmed = _stripOldDetailAttempts(next);
      // Write the JSON envelope directly through the KeyValueStore so a real
      // platform-write refusal propagates as `StorageException` (the
      // JsonDocumentStore.write path would swallow it).
      await keyValueStore.writeString(
        _documentKey,
        jsonEncode(<String, Object?>{
          'schemaVersion': _documentSchemaVersion,
          'items': <Map<String, dynamic>>[
            for (final record in trimmed) _encode(record),
          ],
        }),
      );
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
      await keyValueStore.writeString(
        _documentKey,
        jsonEncode(<String, Object?>{
          'schemaVersion': _documentSchemaVersion,
          'items': <Object?>[],
        }),
      );
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

  /// Trim per-attempt detail on every entry outside the newest
  /// [practiceHistoryDetailLimit] sessions. The newest N sessions are returned
  /// unchanged; older ones lose their `detailAttempts` but keep every
  /// summary field. The entry's own attempt-cap invariant
  /// (`detailAttempts.length <= practiceHistoryDetailLimit`) still holds
  /// because the trim only shrinks.
  static List<PracticeHistoryEntry> _stripOldDetailAttempts(
    List<PracticeHistoryEntry> entries,
  ) {
    if (entries.length <= practiceHistoryDetailLimit) return entries;
    return <PracticeHistoryEntry>[
      for (var i = 0; i < entries.length; i++)
        if (i < practiceHistoryDetailLimit)
          entries[i]
        else
          entries[i]._withoutDetailAttempts(),
    ];
  }
}

/// The document key the repository writes through. Mirrors the key the
/// read-side [JsonDocumentStore] uses under the hood; it must stay in sync
/// with [StorageKeys.practiceHistoryV2].
const String _documentKey = StorageKeys.practiceHistoryV2;
const int _documentSchemaVersion = 1;

extension on PracticeHistoryEntry {
  /// Returns a copy of this entry with its per-attempt detail stripped.
  /// The session-summary fields are unchanged.
  PracticeHistoryEntry _withoutDetailAttempts() {
    return PracticeHistoryEntry(
      id: id,
      modeCode: modeCode,
      sourceCode: sourceCode,
      createdAt: createdAt,
      definitionId: definitionId,
      displayTitle: displayTitle,
      finishReasonCode: finishReasonCode,
      activeDuration: activeDuration,
      pausedDuration: pausedDuration,
      attemptsCount: attemptsCount,
      finalMetricSnapshot: finalMetricSnapshot,
      totalTargets: totalTargets,
      resolvedTargets: resolvedTargets,
      scorePoints: scorePoints,
      maxCombo: maxCombo,
      meanAbsoluteOffset: meanAbsoluteOffset,
      timingBias: timingBias,
      coachingSummary: coachingSummary,
      skillTags: skillTags,
      highestStableTempoBpm: highestStableTempoBpm,
      // Empty detail list; the assertion that `attemptsCount >=
      // detailAttempts.length` is satisfied by passing 0.
      detailAttempts: const <PracticeAttemptDetail>[],
    );
  }
}

Map<String, dynamic> _encode(PracticeHistoryEntry entry) =>
    const PracticeHistorySerializer().toJson(entry);

/// Riverpod binding for the production repository.
///
/// Wired to the [JsonDocumentStore] under [StorageKeys.practiceHistoryV2] for
/// reads, and to the raw [KeyValueStore] for writes (so the document store's
/// swallowed `StorageException` never reaches the repository's `save()`
/// result — see brief B1).
final practiceHistoryRepositoryProvider = Provider<PracticeHistoryRepository>((
  ref,
) {
  final keyValueStore = ref.watch(keyValueStoreProvider);
  final logger = ref.watch(appLoggerProvider);
  return LocalPracticeHistoryRepository(
    store: JsonCollectionStore<PracticeHistoryEntry>(
      document: JsonDocumentStore(
        store: keyValueStore,
        logger: logger,
        key: StorageKeys.practiceHistoryV2,
        legacyKey: _noLegacyKey,
        name: 'practice_history_v2',
      ),
      fromJson: _decode,
      toJson: _encode,
      maxItems: PracticeHistoryRepository.maxSessions,
    ),
    keyValueStore: keyValueStore,
    logger: logger,
  );
});

// Helpers used by [practiceHistoryRepositoryProvider]. Kept as top-level
// functions so the `JsonCollectionStore` sees simple `T Function(...)`
// callables (it does not own the serializer object).

PracticeHistoryEntry _decode(Map<String, dynamic> json) {
  return const PracticeHistorySerializer().fromJson(json);
}

// `JsonDocumentStore` requires a legacy key for read-fallback. The V2
// history has no legacy data — any pre-envelope bytes under this key would
// have come from a build that never shipped, so the read just returns null.
const String _noLegacyKey = 'ss.practice.history_v2.legacy';

// Re-export the [JsonCollectionStore] type so test files do not need
// to import the storage layer directly.
typedef PracticeHistoryCollectionStore<T> = JsonCollectionStore<T>;
