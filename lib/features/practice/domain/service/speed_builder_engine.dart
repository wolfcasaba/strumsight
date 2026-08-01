import '../model/practice_attempt_result.dart';
import '../model/practice_metrics.dart';
import '../model/speed_builder_state.dart';
import '../model/tempo.dart';

/// Pure transition engine for Speed Builder attempts.
final class SpeedBuilderEngine {
  const SpeedBuilderEngine();

  // SDD §16.7 step-up policy. These are intentionally independent from the
  // plain scored-practice outcome thresholds.
  static const double completionThreshold = 0.95;
  static const double overallThreshold = 0.85;
  static const double rhythmThreshold = 0.80;

  bool isStepUpPass(PracticeAttemptResult result) {
    final completion = result.metrics.completion;
    final overall = result.metrics.overall;
    final rhythm = result.metrics.rhythm;
    if (completion is! MetricAvailable ||
        completion.value < completionThreshold) {
      return false;
    }
    if (overall is! MetricAvailable || overall.value < overallThreshold) {
      return false;
    }
    return switch (rhythm) {
      MetricAvailable(:final value) => value >= rhythmThreshold,
      MetricNotApplicable() => true,
      MetricInsufficientData() => false,
    };
  }

  SpeedBuilderState record(
    SpeedBuilderState state,
    PracticeAttemptResult result,
  ) {
    if (state.isClosed || state.attempts.length >= state.policy.maxAttempts) {
      return state;
    }

    final attempts = List<PracticeAttemptResult>.of(state.attempts)
      ..add(result);
    final passed = isStepUpPass(result);
    var currentBpm = state.currentTempo.bpm;
    var successStreak = passed ? state.successStreak + 1 : 0;
    var failStreak = passed ? 0 : state.failStreak + 1;
    var status = SpeedBuilderStatus.active;

    if (passed && successStreak >= state.policy.requiredConsecutivePasses) {
      if (currentBpm >= state.policy.targetBpm.bpm) {
        status = SpeedBuilderStatus.completed;
      } else {
        currentBpm = (currentBpm + state.policy.stepBpm).clamp(
          state.policy.startBpm.bpm,
          state.policy.targetBpm.bpm,
        );
      }
      successStreak = 0;
    } else if (!passed &&
        failStreak >= state.policy.reduceAfterConsecutiveFails) {
      currentBpm = (currentBpm - state.policy.stepBpm).clamp(
        state.policy.startBpm.bpm,
        state.policy.targetBpm.bpm,
      );
      failStreak = 0;
    }

    if (status == SpeedBuilderStatus.active &&
        attempts.length >= state.policy.maxAttempts) {
      status = SpeedBuilderStatus.maxAttemptsReached;
    }

    final highestStable = _highestStableTempo(
      attempts,
      state.policy.requiredConsecutivePasses,
    );
    return state.copyWith(
      currentTempo: Tempo(currentBpm),
      successStreak: successStreak,
      failStreak: failStreak,
      attempts: attempts,
      highestStableTempo: highestStable,
      clearHighestStableTempo: highestStable == null,
      status: status,
    );
  }

  SpeedBuilderState finish(SpeedBuilderState state) {
    if (state.isClosed) return state;
    final highestStable = _highestStableTempo(
      state.attempts,
      state.policy.requiredConsecutivePasses,
    );
    return state.copyWith(
      highestStableTempo: highestStable,
      clearHighestStableTempo: highestStable == null,
      status: SpeedBuilderStatus.userFinished,
    );
  }

  Tempo? _highestStableTempo(
    List<PracticeAttemptResult> attempts,
    int requiredConsecutivePasses,
  ) {
    if (requiredConsecutivePasses < 1) return null;
    Tempo? highest;
    Tempo? streakTempo;
    var streak = 0;
    for (final attempt in attempts) {
      if (isStepUpPass(attempt)) {
        if (attempt.tempo == streakTempo) {
          streak++;
        } else {
          streakTempo = attempt.tempo;
          streak = 1;
        }
        if (streak >= requiredConsecutivePasses &&
            (highest == null || attempt.tempo.bpm > highest.bpm)) {
          highest = attempt.tempo;
        }
      } else {
        streakTempo = null;
        streak = 0;
      }
    }
    return highest;
  }
}
