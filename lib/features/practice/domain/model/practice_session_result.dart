import 'package:meta/meta.dart';

import 'practice_attempt_result.dart';
import 'practice_metrics.dart';
import 'practice_validation.dart';
import 'practice_value_equality.dart';
import 'practice_verdict.dart';
import 'tempo.dart';

/// Reason a practice session reached its terminal result.
enum PracticeFinishReason {
  completedAllTargets('completedAllTargets'),
  userFinished('userFinished'),
  cancelled('cancelled'),
  timedOut('timedOut'),
  interrupted('interrupted'),
  failed('failed');

  const PracticeFinishReason(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable finish-reason code without guessing a fallback.
PracticeFinishReason? practiceFinishReasonFromCode(String code) {
  for (final value in PracticeFinishReason.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Immutable result of one complete user practice session.
///
/// [attempts] and [coachingSummary] must be immutable; use const lists or
/// [List.unmodifiable].
@immutable
final class PracticeSessionResult {
  const PracticeSessionResult({
    required this.id,
    required this.activeDuration,
    required this.pausedDuration,
    required this.attempts,
    required this.finishReason,
    required this.highestStableTempo,
    required this.coachingSummary,
  });

  final String id;
  final Duration activeDuration;
  final Duration pausedDuration;

  /// Read-only attempts in strictly increasing [PracticeAttemptResult.index]
  /// order.
  final List<PracticeAttemptResult> attempts;

  final PracticeFinishReason finishReason;
  final Tempo? highestStableTempo;

  /// Read-only canonical coaching codes summarizing the session.
  final List<String> coachingSummary;

  /// The attempt with the greatest index, or null when there are no attempts.
  PracticeAttemptResult? get finalAttempt {
    PracticeAttemptResult? result;
    for (final attempt in attempts) {
      if (result == null || attempt.index > result.index) {
        result = attempt;
      }
    }
    return result;
  }

  /// The greatest valid available overall score, or null when none exists.
  ///
  /// Equal scores prefer the smaller attempt index.
  PracticeAttemptResult? get bestAttempt {
    PracticeAttemptResult? result;
    double? resultScore;
    for (final attempt in attempts) {
      final overall = attempt.metrics.overall;
      if (overall is! MetricAvailable) continue;

      final score = overall.value;
      if (!score.isFinite || score < 0 || score > 1) continue;
      if (result == null ||
          score > resultScore! ||
          (score == resultScore && attempt.index < result.index)) {
        result = attempt;
        resultScore = score;
      }
    }
    return result;
  }

  /// Returns every nested and aggregate validation problem.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (id.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.sessionIdEmpty,
          message: 'Practice session ID cannot be empty.',
        ),
      );
    }
    if (attempts.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.sessionAttemptsEmpty,
          message: 'Practice session must contain at least one attempt.',
        ),
      );
    }
    var attemptsUnordered = false;
    for (var index = 0; index < attempts.length; index++) {
      failures.addAll(attempts[index].validate());
      if (index > 0 && attempts[index].index <= attempts[index - 1].index) {
        attemptsUnordered = true;
      }
    }
    if (attemptsUnordered) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.sessionAttemptsUnordered,
          message: 'Attempt indexes must be strictly increasing.',
        ),
      );
    }
    if (activeDuration < Duration.zero || pausedDuration < Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.sessionDurationNegative,
          message: 'Session durations cannot be negative.',
        ),
      );
    }
    if (highestStableTempo != null) {
      failures.addAll(highestStableTempo!.validate());
    }
    if (coachingSummary.any(
      (code) => !PracticeCoachingCode.values.contains(code),
    )) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.sessionCoachingSummaryUnknownCode,
          message: 'Session coaching summary contains an unknown code.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionResult &&
          other.id == id &&
          other.activeDuration == activeDuration &&
          other.pausedDuration == pausedDuration &&
          listEquals(other.attempts, attempts) &&
          other.finishReason == finishReason &&
          other.highestStableTempo == highestStableTempo &&
          listEquals(other.coachingSummary, coachingSummary);

  @override
  int get hashCode => Object.hash(
    id,
    activeDuration,
    pausedDuration,
    listHash(attempts),
    finishReason,
    highestStableTempo,
    listHash(coachingSummary),
  );
}
