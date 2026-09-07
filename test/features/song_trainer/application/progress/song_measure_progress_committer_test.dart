// Javító sáv 2026-09-06 (R8, audit §5.2 "Dal-tréner ütemenkénti
// haladás-commit").
//
// B1 — one durable record per measure, addressed by the session's
//      idempotency key, so `SongProgressAggregator` finally has records.
// B2 — a replayed terminal tick writes nothing twice.
// B3 — the per-measure active durations sum back to the session total; no
//      minute is invented.
// B4 — a measure with a missed target is NOT marked completed.
// B5 — a repository failure is returned, never swallowed.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_measure_progress_committer.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_progress_repository.dart';

void main() {
  group('SongMeasureProgressCommitter', () {
    test('B1 — writes one record per measure', () async {
      final repository = _RecordingProgressRepository();
      final committer = _committer(repository);

      final committed = await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(),
        activeDuration: const Duration(seconds: 12),
      );

      expect(committed.valueOrNull, 2);
      expect(repository.saved, hasLength(2));
      expect(repository.saved.map((record) => record.source.measureIndex), [
        0,
        1,
      ]);
      expect(repository.saved.first.songId, SongId('song'));
      expect(repository.saved.first.songRevision, 3);
      expect(repository.saved.first.source.measureId, 'measure-0');
      expect(repository.saved.first.source.sectionId, 'verse');
      expect(repository.saved.first.score, 1);
    });

    test('B1 — the records aggregate into a measure projection', () async {
      final repository = _RecordingProgressRepository();
      final committer = _committer(repository);
      await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(),
        activeDuration: const Duration(seconds: 12),
      );

      final aggregate = SongProgressAggregator.aggregate(repository.saved);

      expect(aggregate.songId, SongId('song'));
      expect(aggregate.measures, hasLength(2));
      expect(aggregate.measures.first.measureId, 'measure-0');
      expect(aggregate.measures.first.attempts, 1);
    });

    test('B2 — a replayed terminal tick writes nothing twice', () async {
      final repository = _RecordingProgressRepository();
      final committer = _committer(repository);
      final result = _result();

      await committer.commit(
        attemptKey: 'attempt-1',
        result: result,
        activeDuration: const Duration(seconds: 12),
      );
      final replay = await committer.commit(
        attemptKey: 'attempt-1',
        result: result,
        activeDuration: const Duration(seconds: 12),
      );

      expect(replay.valueOrNull, 0);
      expect(repository.saved, hasLength(2));
    });

    test('B3 — measure durations sum back to the session total', () async {
      final repository = _RecordingProgressRepository();
      final committer = _committer(repository);

      await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(),
        activeDuration: const Duration(seconds: 12),
      );

      var total = Duration.zero;
      for (final record in repository.saved) {
        total += record.activeDuration;
      }
      expect(total, const Duration(seconds: 12));
    });

    test('B4 — a missed target keeps the measure incomplete', () async {
      final repository = _RecordingProgressRepository();
      final committer = _committer(repository);

      await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(missReasonForMeasureOne: 'practice.miss.no_signal'),
        activeDuration: const Duration(seconds: 12),
      );

      expect(repository.saved.first.completed, isTrue);
      expect(repository.saved.last.completed, isFalse);
    });

    test('B5 — a repository failure is returned, not swallowed', () async {
      final repository = _RecordingProgressRepository(failing: true);
      final committer = _committer(repository);

      final committed = await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(),
        activeDuration: const Duration(seconds: 12),
      );

      expect(committed.isFailure, isTrue);
      expect(committed.failureOrNull!.code, FailureCode.storageWrite);
      expect(repository.saved, isEmpty);
    });

    test('B5 — a failed measure can be retried after the fix', () async {
      final repository = _RecordingProgressRepository(failing: true);
      final committer = _committer(repository);
      await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(),
        activeDuration: const Duration(seconds: 12),
      );

      repository.failing = false;
      final retried = await committer.commit(
        attemptKey: 'attempt-1',
        result: _result(),
        activeDuration: const Duration(seconds: 12),
      );

      expect(retried.valueOrNull, 2);
    });
  });
}

SongMeasureProgressCommitter _committer(SongProgressRepository repository) =>
    SongMeasureProgressCommitter(
      repository: repository,
      clock: () => DateTime.utc(2026, 9, 7),
    );

/// Two measures, one target event each. The second one can be made a miss.
SongTrainerResult _result({String? missReasonForMeasureOne}) {
  final first = _verdict(measureIndex: 0, eventId: 'e0');
  final second = _verdict(
    measureIndex: 1,
    eventId: 'e1',
    missReasonCode: missReasonForMeasureOne,
  );
  return SongTrainerResult(
    sessionResult: const PracticeSessionResult(
      id: 'practice-result',
      activeDuration: Duration(seconds: 12),
      pausedDuration: Duration.zero,
      attempts: <PracticeAttemptResult>[],
      finishReason: PracticeFinishReason.completedAllTargets,
      highestStableTempo: null,
      coachingSummary: <String>[],
    ),
    verdicts: <SongTrainerVerdict>[first, second],
    measureResults: <SongMeasureTrainerResult>[
      SongMeasureTrainerResult(
        measureIndex: 0,
        verdicts: <SongTrainerVerdict>[first],
        averageEventScore: 1,
      ),
      SongMeasureTrainerResult(
        measureIndex: 1,
        verdicts: <SongTrainerVerdict>[second],
        averageEventScore: 0.5,
      ),
    ],
    sectionResults: const <SongSectionTrainerResult>[],
  );
}

SongTrainerVerdict _verdict({
  required int measureIndex,
  required String eventId,
  String? missReasonCode,
}) => SongTrainerVerdict(
  verdict: PracticeVerdict(
    targetEventId: eventId,
    matchedObservationSequence: missReasonCode == null ? 1 : null,
    targetAt: Duration.zero,
    observedAt: missReasonCode == null ? Duration.zero : null,
    timingOffset: missReasonCode == null ? Duration.zero : null,
    timingGrade: missReasonCode == null
        ? TimingGrade.perfect
        : TimingGrade.missed,
    expectedDirection: StrumDirection.down,
    observedDirection: missReasonCode == null ? StrumDirection.down : null,
    directionOutcome: missReasonCode == null
        ? DirectionOutcome.correct
        : DirectionOutcome.notApplicable,
    expectedChord: null,
    observedChord: null,
    chordOutcome: ChordOutcome.notApplicable,
    eventScore: missReasonCode == null ? 1 : 0.5,
    missReasonCode: missReasonCode,
    coachingCode: null,
  ),
  reference: SongEventReference(
    songId: SongId('song'),
    songRevision: 3,
    trackId: SongTrackId('strums'),
    eventId: SongEventId(eventId),
    measureIndex: measureIndex,
    sectionId: SongSectionId('verse'),
  ),
);

final class _RecordingProgressRepository implements SongProgressRepository {
  _RecordingProgressRepository({this.failing = false});

  bool failing;
  final List<SongPracticeRecord> saved = <SongPracticeRecord>[];

  @override
  Future<AppResult<List<SongPracticeRecord>>> load({
    SongId? songId,
    int? revision,
  }) async => Success<List<SongPracticeRecord>>(saved);

  @override
  Future<AppResult<void>> save(SongPracticeRecord record) async {
    if (failing) {
      return const Failure<void>(
        StorageFailure(code: FailureCode.storageWrite),
      );
    }
    saved.add(record);
    return const Success<void>(null);
  }
}
