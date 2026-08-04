// Boundary that turns duplicate Song Trainer terminals (finalize + a late
// finish tick, or two re-entry navigations) into a single persisted progress
// commit. The boundary is the ONE place that may write session progress — the
// controller, the re-entry navigator, and the result callback all funnel
// through the idempotency key.
//
// E03-R21 brief §5.4 / §6 acceptance "duplicate finalize/re-entry egyszer
// commitol".

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_progress_committer.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';

void main() {
  group('SongProgressCommitter', () {
    test(
      'commits the result exactly once even when finish fires twice',
      () async {
        final sink = _CountingSink();
        final committer = SongProgressCommitter(
          sessionRecorder: _RecorderSink(sink),
        );

        final outcome = _result();
        final first = await committer.commit(
          idempotencyKey: 'song|song|attempt|1',
          sessionResult: outcome.sessionResult,
        );
        final second = await committer.commit(
          idempotencyKey: 'song|song|attempt|1',
          sessionResult: outcome.sessionResult,
        );

        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);
        expect(sink.recordCalls, 1);
      },
    );

    test('different idempotency keys commit independently', () async {
      final sink = _CountingSink();
      final committer = SongProgressCommitter(
        sessionRecorder: _RecorderSink(sink),
      );

      final outcome = _result();
      final first = await committer.commit(
        idempotencyKey: 'song|song|attempt|1',
        sessionResult: outcome.sessionResult,
      );
      final second = await committer.commit(
        idempotencyKey: 'song|song|attempt|2',
        sessionResult: outcome.sessionResult,
      );

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isTrue);
      expect(sink.recordCalls, 2);
    });

    test(
      'concurrent commits with the same key collapse to one write',
      () async {
        final sink = _CountingSink();
        final committer = SongProgressCommitter(
          sessionRecorder: _RecorderSink(sink),
        );

        final outcome = _result();
        final futures = <Future<AppResult<void>>>[
          committer.commit(
            idempotencyKey: 'song|song|attempt|race',
            sessionResult: outcome.sessionResult,
          ),
          committer.commit(
            idempotencyKey: 'song|song|attempt|race',
            sessionResult: outcome.sessionResult,
          ),
          committer.commit(
            idempotencyKey: 'song|song|attempt|race',
            sessionResult: outcome.sessionResult,
          ),
        ];
        final outcomes = await Future.wait(futures);

        for (final entry in outcomes) {
          expect(entry.isSuccess, isTrue);
        }
        expect(sink.recordCalls, 1);
      },
    );

    test(
      'recorder failure is propagated and the key remains unfired',
      () async {
        final sink = _CountingSink();
        final committer = SongProgressCommitter(
          sessionRecorder: _RecorderSink(sink),
        );

        sink.shouldFail = FailureCode.storageWrite;
        final first = await committer.commit(
          idempotencyKey: 'song|song|attempt|fail',
          sessionResult: _result().sessionResult,
        );

        expect(first.isFailure, isTrue);
        expect(sink.recordCalls, 1);

        // A retry should be allowed — the key has not been marked as committed.
        sink.shouldFail = null;
        final retry = await committer.commit(
          idempotencyKey: 'song|song|attempt|fail',
          sessionResult: _result().sessionResult,
        );
        expect(retry.isSuccess, isTrue);
        expect(sink.recordCalls, 2);
      },
    );

    test('a disposed committer refuses further commits', () async {
      final committer = SongProgressCommitter(
        sessionRecorder: _RecorderSink(_CountingSink()),
      );
      await committer.dispose();
      final outcome = await committer.commit(
        idempotencyKey: 'song|song|attempt|disposed',
        sessionResult: _result().sessionResult,
      );
      expect(outcome.isFailure, isTrue);
    });
  });
}

SongTrainerResult _result() => SongTrainerResult(
  sessionResult: PracticeSessionResult(
    id: 'practice-result',
    activeDuration: const Duration(seconds: 4),
    pausedDuration: Duration.zero,
    attempts: const <PracticeAttemptResult>[],
    finishReason: PracticeFinishReason.completedAllTargets,
    highestStableTempo: null,
    coachingSummary: const <String>[],
  ),
  verdicts: const <SongTrainerVerdict>[],
  measureResults: const <SongMeasureTrainerResult>[],
  sectionResults: const <SongSectionTrainerResult>[],
);

final class _CountingSink {
  int recordCalls = 0;
  String? shouldFail;
}

class _RecorderSink implements PracticeSessionRecorder {
  _RecorderSink(this._sink);

  final _CountingSink _sink;

  @override
  Future<AppResult<void>> record(PracticeSessionResult sessionResult) async {
    _sink.recordCalls++;
    final failureCode = _sink.shouldFail;
    if (failureCode != null) {
      return AppResult<void>.failure(StorageFailure(code: failureCode));
    }
    return const AppResult<void>.success(null);
  }
}
