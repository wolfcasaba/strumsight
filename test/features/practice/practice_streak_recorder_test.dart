// Learner-loop round 4: a saved, eligible Practice V2 session credits the
// streak the Today/Profile hubs read — once per day, through the canonical
// eligibility predicate; cancelled, failed and too-short sessions never do.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/practice/application/practice_streak_recorder.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_session_recorder.dart';
import 'package:strumsight/features/practice/domain/service/practice_session_eligibility.dart';
import 'package:strumsight/features/streak/public.dart';

import '../../support/preference_store.dart';

const PracticeMetrics _metrics = PracticeMetrics(
  completion: MetricAvailable(0.9),
  rhythm: MetricAvailable(0.85),
  direction: MetricAvailable(0.95),
  chord: MetricNotApplicable(),
  overall: MetricAvailable(0.9),
  totalTargets: 16,
  resolvedTargets: 14,
  maxCombo: 8,
  scorePoints: 800,
  meanAbsoluteOffset: Duration(milliseconds: 18),
  timingBias: Duration.zero,
);

PracticeSessionResult _result({
  Duration activeDuration = const Duration(minutes: 2),
  PracticeFinishReason finishReason = PracticeFinishReason.completedAllTargets,
  bool scored = true,
}) => PracticeSessionResult(
  id: 'session',
  activeDuration: activeDuration,
  pausedDuration: Duration.zero,
  attempts: scored
      ? <PracticeAttemptResult>[
          PracticeAttemptResult(
            index: 0,
            tempo: const Tempo(90),
            metrics: _metrics,
            verdicts: const <PracticeVerdict>[],
            outcome: PracticeAttemptOutcome.passed,
          ),
        ]
      : const <PracticeAttemptResult>[],
  finishReason: finishReason,
  highestStableTempo: const Tempo(90),
  coachingSummary: const <String>[],
);

final class _FailingRecorder implements PracticeSessionRecorder {
  const _FailingRecorder();
  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async =>
      const Failure<void>(StorageFailure());
}

final _now = DateTime(2026, 9, 15, 10, 30);

({ProviderContainer container, StreakCreditingPracticeSessionRecorder recorder})
_harness({
  PracticeSessionRecorder inner = const NoopPracticeSessionRecorder(),
}) {
  final container = ProviderContainer(overrides: preferenceOverrides());
  addTearDown(container.dispose);
  final recorder = StreakCreditingPracticeSessionRecorder(
    inner: inner,
    streak: container.read(streakProvider.notifier),
    eligibility: const PracticeSessionEligibility(),
    now: () => _now,
    logger: const NoopAppLogger(),
  );
  return (container: container, recorder: recorder);
}

void main() {
  test('an eligible saved session credits the streak, once per day', () async {
    final h = _harness();
    expect(h.container.read(streakProvider).current, 0);

    await h.recorder.record(_result());
    expect(h.container.read(streakProvider).current, 1);

    await h.recorder.record(_result());
    expect(h.container.read(streakProvider).current, 1);
  });

  test('a session below every threshold does not credit', () async {
    final h = _harness();
    await h.recorder.record(
      _result(activeDuration: const Duration(seconds: 5), scored: false),
    );
    expect(h.container.read(streakProvider).current, 0);
  });

  test('a cancelled session never credits, even when long', () async {
    final h = _harness();
    await h.recorder.record(
      _result(finishReason: PracticeFinishReason.cancelled),
    );
    expect(h.container.read(streakProvider).current, 0);
  });

  test('a failed history save returns the failure, no credit', () async {
    final h = _harness(inner: const _FailingRecorder());
    final saved = await h.recorder.record(_result());
    expect(saved, isA<Failure<void>>());
    expect(h.container.read(streakProvider).current, 0);
  });

  test('the predicate is pure: active time OR resolved targets carry it', () {
    const eligibility = PracticeSessionEligibility();
    expect(
      practiceSessionCreditsStreak(
        _result(activeDuration: const Duration(seconds: 25), scored: false),
        eligibility,
      ),
      isTrue,
    );
    expect(
      practiceSessionCreditsStreak(
        _result(activeDuration: const Duration(seconds: 5)),
        eligibility,
      ),
      isTrue,
      reason: '14 resolved targets clear the target threshold',
    );
    expect(
      practiceSessionCreditsStreak(
        _result(finishReason: PracticeFinishReason.failed),
        eligibility,
      ),
      isFalse,
    );
  });
}
