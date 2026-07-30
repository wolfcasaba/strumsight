import 'package:meta/meta.dart';

import 'practice_metrics.dart';
import 'practice_validation.dart';
import 'practice_value_equality.dart';
import 'practice_verdict.dart';
import 'tempo.dart';

/// Completion state of one practice attempt.
enum PracticeAttemptOutcome {
  passed('passed'),
  failed('failed'),
  incomplete('incomplete'),
  notScored('notScored');

  const PracticeAttemptOutcome(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable attempt-outcome code without guessing a fallback.
PracticeAttemptOutcome? practiceAttemptOutcomeFromCode(String code) {
  for (final value in PracticeAttemptOutcome.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Result of one fixed-tempo playthrough or loop group.
///
/// [verdicts] must be immutable; use a const list or [List.unmodifiable].
@immutable
final class PracticeAttemptResult {
  const PracticeAttemptResult({
    required this.index,
    required this.tempo,
    required this.metrics,
    required this.verdicts,
    required this.outcome,
  });

  final int index;
  final Tempo tempo;
  final PracticeMetrics metrics;

  /// Read-only verdicts in target evaluation order.
  final List<PracticeVerdict> verdicts;

  final PracticeAttemptOutcome outcome;

  /// Returns every nested and aggregate validation problem.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (index < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.attemptIndexNegative,
          message: 'Attempt index cannot be negative.',
        ),
      );
    }
    failures.addAll(tempo.validate());
    failures.addAll(metrics.validate());

    final targetIds = <String>{};
    var hasDuplicateTarget = false;
    for (final verdict in verdicts) {
      failures.addAll(verdict.validate());
      if (!targetIds.add(verdict.targetEventId)) {
        hasDuplicateTarget = true;
      }
    }
    if (hasDuplicateTarget) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.attemptVerdictsTargetDuplicate,
          message: 'Attempt verdict target IDs must be unique.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeAttemptResult &&
          other.index == index &&
          other.tempo == tempo &&
          other.metrics == metrics &&
          listEquals(other.verdicts, verdicts) &&
          other.outcome == outcome;

  @override
  int get hashCode =>
      Object.hash(index, tempo, metrics, listHash(verdicts), outcome);
}
