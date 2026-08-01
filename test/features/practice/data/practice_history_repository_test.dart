import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/shared_preferences_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice/data/local_practice_history_repository.dart';
import 'package:strumsight/features/practice/data/practice_history_serializer.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/repository/practice_history_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A6 — round-trip', () {
    test('an entry round-trips through save → load', () async {
      final repo = _buildRepo(await _openStore());
      final entry = _entry('e-1');

      final saveResult = await repo.save(entry);
      expect(saveResult, isA<Success<void>>());

      final loadResult = await repo.load();
      expect(loadResult, isA<Success<List<PracticeHistoryEntry>>>());
      final list = (loadResult as Success<List<PracticeHistoryEntry>>).value;
      expect(list.single, entry);
    });

    test('every persisted enum decodes via stable code', () async {
      final repo = _buildRepo(await _openStore());
      final entry = _entry('e-2');
      await repo.save(entry);
      final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
      expect(list.value.single.modeCode, entry.modeCode);
      expect(list.value.single.sourceCode, entry.sourceCode);
      expect(list.value.single.finishReasonCode, entry.finishReasonCode);
    });

    test('duration fields round-trip with microsecond precision', () async {
      final repo = _buildRepo(await _openStore());
      final entry = _entry('e-3');
      await repo.save(entry);
      final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
      expect(list.value.single.activeDuration, entry.activeDuration);
      expect(list.value.single.pausedDuration, entry.pausedDuration);
    });

    test('every persisted enum code round-trips through the serializer', () {
      final entry = _entry('e-serializer');
      final json = const PracticeHistorySerializer().toJson(entry);
      final decoded = const PracticeHistorySerializer().fromJson(json);
      expect(decoded.modeCode, entry.modeCode);
      expect(decoded.sourceCode, entry.sourceCode);
      expect(decoded.finishReasonCode, entry.finishReasonCode);
      expect(decoded.skillTags, entry.skillTags);
      expect(decoded.coachingSummary, entry.coachingSummary);
    });

    test('unknown enum code fails without fallback', () {
      final json = const PracticeHistorySerializer().toJson(_entry('e-x'));
      json['mode'] = 'practice.mode.never-heard-of-this';
      expect(
        () => const PracticeHistorySerializer().fromJson(json),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('A7 — corruption, future version, cap', () {
    test('a corrupt record is skipped; the rest still loads', () async {
      final store = await _openStore();
      // Write a valid envelope containing one good record + one record that
      // fails decoding — the [JsonCollectionStore] is supposed to skip the
      // bad record and keep the rest.
      final goodJson = const PracticeHistorySerializer().toJson(
        _entry('good-1'),
      );
      await store.writeString(
        StorageKeys.practiceHistoryV2,
        '{"schemaVersion":1,"items":['
        '${const JsonEncoder().convert(goodJson)},'
        '{"v":1,"id":"bad","mode":"__never_heard__","source":"builtin",'
        '"createdAt":"2026-08-01T12:00:00.000Z","definitionId":"d",'
        '"displayTitle":"t","finishReason":"userFinished",'
        '"activeMs":0,"pausedMs":0,"attemptsCount":1,'
        '"final":{"completion":{"kind":"available","value":1.0},'
        '"rhythm":{"kind":"notApplicable"},"direction":{"kind":"notApplicable"},'
        '"chord":{"kind":"notApplicable"},"overall":{"kind":"notApplicable"}},'
        '"totalTargets":0,"resolvedTargets":0,"scorePoints":0,"maxCombo":0,'
        '"meanOffsetMicros":0,"timingBiasMicros":0,"coachingSummary":[],'
        '"skillTags":[],"details":[]}'
        ']}',
      );

      final repo = _buildRepo(store);
      final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
      // `good-1` survives, the record with the unknown mode is skipped.
      expect(list.value.length, 1);
      expect(list.value.single.id, 'good-1');
    });

    test('a record with future schemaVersion is skipped', () async {
      final store = await _openStore();
      await store.writeString(
        StorageKeys.practiceHistoryV2,
        '{"schemaVersion":1,"items":[{"v":999,"id":"future","mode":"strumPattern",'
        '"source":"builtin","createdAt":"2026-08-01T12:00:00.000Z",'
        '"definitionId":"d","displayTitle":"t","finishReason":"userFinished",'
        '"activeMs":0,"pausedMs":0,"attemptsCount":1,'
        '"final":{"completion":{"kind":"available","value":1.0},'
        '"rhythm":{"kind":"notApplicable"},"direction":{"kind":"notApplicable"},'
        '"chord":{"kind":"notApplicable"},"overall":{"kind":"notApplicable"}},'
        '"totalTargets":0,"resolvedTargets":0,"scorePoints":0,"maxCombo":0,'
        '"meanOffsetMicros":0,"timingBiasMicros":0,"coachingSummary":[],'
        '"skillTags":[],"details":[]}]}',
      );
      final repo = _buildRepo(store);
      final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
      expect(list.value, isEmpty);
    });

    test('cap evicts the oldest record past maxSessions', () async {
      final repo = _buildRepo(await _openStore());
      final total = PracticeHistoryRepository.maxSessions + 5;
      for (var i = 0; i < total; i++) {
        final saveResult = await repo.save(_entry('cap-$i'));
        expect(saveResult, isA<Success<void>>());
      }
      final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
      expect(list.value.length, PracticeHistoryRepository.maxSessions);
      expect(list.value.first.id, 'cap-${total - 1}');
      expect(
        list.value.last.id,
        'cap-${total - PracticeHistoryRepository.maxSessions}',
      );
    });
  });

  group('A8 — idempotent save', () {
    test(
      'the same sessionId saved twice produces one record (last-wins)',
      () async {
        final repo = _buildRepo(await _openStore());
        final first = _entry('dup')._withCoaching(const ['x']);
        final second = _entry('dup')._withCoaching(const ['y']);
        expect(await repo.save(first), isA<Success<void>>());
        expect(await repo.save(second), isA<Success<void>>());
        final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
        expect(list.value.length, 1);
        expect(list.value.single.coachingSummary, ['y']);
      },
    );

    test('two distinct sessionIds produce two records', () async {
      final repo = _buildRepo(await _openStore());
      expect(await repo.save(_entry('a')), isA<Success<void>>());
      expect(await repo.save(_entry('b')), isA<Success<void>>());
      final list = (await repo.load()) as Success<List<PracticeHistoryEntry>>;
      expect(list.value.length, 2);
    });
  });

  group('A9 — storage failure bubbles up as AppResult.failure', () {
    test(
      'a refused write surfaces StorageFailure and does NOT silently succeed',
      () async {
        final repo = _buildRepo(_RejectingKeyValueStore());
        final result = await repo.save(_entry('e-fail'));
        expect(result, isA<Failure<void>>());
        expect((result as Failure<void>).error.code, FailureCode.storageWrite);
      },
    );

    test('a refused read surfaces StorageFailure', () async {
      final repo = _buildRepo(_RejectingKeyValueStore());
      final result = await repo.load();
      expect(result, isA<Failure<List<PracticeHistoryEntry>>>());
      expect(
        (result as Failure<List<PracticeHistoryEntry>>).error.code,
        FailureCode.storageRead,
      );
    });
  });

  group('A10 — V1 storage untouched', () {
    test('writing V2 leaves the V1 practiceLog bytes identical', () async {
      final prefs = await SharedPreferences.getInstance();
      const v1Bytes = '{"schemaVersion":1,"items":[]}';
      await prefs.setString(StorageKeys.practiceLog, v1Bytes);
      final store = SharedPreferencesStore(prefs);
      final repo = _buildRepo(store);

      expect(await repo.save(_entry('e-v2')), isA<Success<void>>());

      expect(prefs.getString(StorageKeys.practiceLog), v1Bytes);
      expect(prefs.getString(StorageKeys.practiceHistoryV2), isNotNull);
    });
  });
}

// --- helpers ----------------------------------------------------------------

Future<KeyValueStore> _openStore() async {
  final result = await SharedPreferencesStore.open();
  return (result as Success<SharedPreferencesStore>).value;
}

PracticeHistoryRepository _buildRepo(KeyValueStore store) {
  return LocalPracticeHistoryRepository(
    store: JsonCollectionStore<PracticeHistoryEntry>(
      document: JsonDocumentStore(
        store: store,
        logger: _SilentLogger(),
        key: StorageKeys.practiceHistoryV2,
        legacyKey: 'ss.practice.history_v2.legacy',
        name: 'practice_history_v2',
      ),
      fromJson: _decode,
      toJson: _encode,
      maxItems: PracticeHistoryRepository.maxSessions,
    ),
    logger: _SilentLogger(),
  );
}

PracticeHistoryEntry _entry(String id) {
  return PracticeHistoryEntry(
    id: id,
    modeCode: 'strumPattern',
    sourceCode: 'builtin',
    createdAt: DateTime(2026, 8, 1, 12, 0),
    definitionId: 'd-$id',
    displayTitle: 'fixture-$id',
    finishReasonCode: 'userFinished',
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.9),
      rhythm: PracticeMetricDimensionAvailable(0.85),
      direction: PracticeMetricDimensionAvailable(0.95),
      chord: PracticeMetricDimensionNotApplicable(),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: 16,
    resolvedTargets: 14,
    scorePoints: 800,
    maxCombo: 12,
    meanAbsoluteOffset: const Duration(milliseconds: 18),
    timingBias: const Duration(milliseconds: -2),
    coachingSummary: const ['practice.coach.late'],
    skillTags: const ['smoke'],
    highestStableTempoBpm: 100.0,
  );
}

extension on PracticeHistoryEntry {
  PracticeHistoryEntry _withCoaching(List<String> codes) {
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
      coachingSummary: codes,
      skillTags: skillTags,
      highestStableTempoBpm: highestStableTempoBpm,
      detailAttempts: detailAttempts,
    );
  }
}

PracticeHistoryEntry _decode(Map<String, dynamic> json) =>
    const PracticeHistorySerializer().fromJson(json);

Map<String, dynamic> _encode(PracticeHistoryEntry entry) =>
    const PracticeHistorySerializer().toJson(entry);

class _SilentLogger implements AppLogger {
  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {}
  @override
  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {}
  @override
  void info(
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {}
  @override
  void debug(
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {}
}

class _RejectingKeyValueStore implements KeyValueStore {
  @override
  String? readString(String key) {
    throw StateError('rejected');
  }

  @override
  int? readInt(String key) => null;
  @override
  double? readDouble(String key) => null;
  @override
  bool? readBool(String key) => null;
  @override
  List<String>? readStringList(String key) => null;

  @override
  Future<void> writeString(String key, String value) async {
    // Throw a non-StorageException so the [JsonDocumentStore.write] catch
    // does NOT swallow it — the exception bubbles up to the repository,
    // which must surface it as `AppResult.failure` (A9).
    throw StateError('rejected');
  }

  @override
  Future<void> writeInt(String key, int value) async {
    throw StateError('rejected');
  }

  @override
  Future<void> writeDouble(String key, double value) async {
    throw StateError('rejected');
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    throw StateError('rejected');
  }

  @override
  Future<void> writeStringList(String key, List<String> value) async {
    throw StateError('rejected');
  }

  @override
  Future<void> remove(String key) async {
    throw StateError('rejected');
  }

  @override
  bool contains(String key) => false;
}
