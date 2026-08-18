/// Caller-fed normalization for Practice Engine terminal outcomes.
library;

import 'package:strumsight/features/practice/public.dart' as practice;

import '../../domain/id/planner_ids.dart';

/// Normalized terminal states from SDD Ch8 §26.2.
enum PracticeCompletionState {
  completed,
  partial,
  skipped,
  cancelled,
  failedTechnical,
  unavailable,
}

/// Stable source code for normalized Practice Engine outcomes.
abstract final class PracticeOutcomeSource {
  static const String practiceEngine = 'practiceEngine';
}

/// Optional structured feedback; raw user text is intentionally out of scope.
enum PracticeUserFeedback {
  tooEasy,
  rightLevel,
  tooHard,
  uncomfortable,
  notEnjoyable,
  technicalProblem,
}

/// Caller-provided immutable context for one normalized outcome.
final class PracticeOutcomeContext {
  PracticeOutcomeContext({
    required this.id,
    required this.planId,
    required this.revisionId,
    required this.dayId,
    required this.blockId,
    required DateTime startedAt,
    required DateTime completedAt,
    required this.activeDuration,
    Iterable<PracticeUserFeedback> userFeedback =
        const <PracticeUserFeedback>[],
  }) : startedAt = startedAt.toUtc(),
       completedAt = completedAt.toUtc(),
       userFeedback = List<PracticeUserFeedback>.unmodifiable(userFeedback) {
    if (this.completedAt.isBefore(this.startedAt)) {
      throw ArgumentError.value(
        completedAt,
        'completedAt',
        'must not be before startedAt',
      );
    }
    if (activeDuration.isNegative) {
      throw ArgumentError.value(
        activeDuration,
        'activeDuration',
        'must not be negative',
      );
    }
  }

  final OutcomeId id;
  final PlanId planId;
  final RevisionId revisionId;
  final DayId dayId;
  final BlockId blockId;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration activeDuration;
  final List<PracticeUserFeedback> userFeedback;
}

/// The externally supplied terminal fact. Cancelled and technical failures
/// have their own variants because Practice Engine does not create a result
/// object on those terminal branches.
sealed class PracticeOutcomeInput {
  const PracticeOutcomeInput();
}

final class CompletedPracticeSessionOutcome extends PracticeOutcomeInput {
  CompletedPracticeSessionOutcome({
    required this.sessionResult,
    required Map<String, double> metricEvidence,
  }) : metricEvidence = _metricEvidence(metricEvidence);

  final practice.PracticeSessionResult sessionResult;
  final Map<String, double> metricEvidence;
}

final class CancelledPracticeOutcome extends PracticeOutcomeInput {
  const CancelledPracticeOutcome();
}

final class TechnicalFailurePracticeOutcome extends PracticeOutcomeInput {
  TechnicalFailurePracticeOutcome({required String failureCode})
    : failureCode = _requiredText(failureCode, 'failureCode');

  final String failureCode;
}

final class SkippedPracticeOutcome extends PracticeOutcomeInput {
  const SkippedPracticeOutcome();
}

final class UnavailablePracticeOutcome extends PracticeOutcomeInput {
  const UnavailablePracticeOutcome();
}

/// Immutable normalized outcome. Technical and cancelled inputs cannot carry
/// metric evidence, preventing their accidental conversion into skill data.
final class PracticeOutcome {
  PracticeOutcome({
    required this.id,
    required this.planId,
    required this.revisionId,
    required this.dayId,
    required this.blockId,
    required this.source,
    required this.startedAt,
    required this.completedAt,
    required this.activeDuration,
    required this.completionState,
    required Map<String, double> metricEvidence,
    required Iterable<PracticeUserFeedback> userFeedback,
  }) : metricEvidence = _metricEvidence(metricEvidence),
       userFeedback = List<PracticeUserFeedback>.unmodifiable(userFeedback);

  final OutcomeId id;
  final PlanId planId;
  final RevisionId revisionId;
  final DayId dayId;
  final BlockId blockId;
  final String source;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration activeDuration;
  final PracticeCompletionState completionState;
  final Map<String, double> metricEvidence;
  final List<PracticeUserFeedback> userFeedback;
}

/// Normalizes caller-fed Practice Engine terminal inputs without reading any
/// feature-internal controller, provider, or repository.
final class PracticeOutcomeAdapter {
  const PracticeOutcomeAdapter();

  PracticeOutcome adapt({
    required PracticeOutcomeContext context,
    required PracticeOutcomeInput input,
  }) {
    final state = _completionStateFor(input);
    final metrics = switch (input) {
      CompletedPracticeSessionOutcome() => input.metricEvidence,
      _ => const <String, double>{},
    };
    return PracticeOutcome(
      id: context.id,
      planId: context.planId,
      revisionId: context.revisionId,
      dayId: context.dayId,
      blockId: context.blockId,
      source: PracticeOutcomeSource.practiceEngine,
      startedAt: context.startedAt,
      completedAt: context.completedAt,
      activeDuration: context.activeDuration,
      completionState: state,
      metricEvidence: metrics,
      userFeedback: context.userFeedback,
    );
  }

  PracticeCompletionState _completionStateFor(PracticeOutcomeInput input) =>
      switch (input) {
        CompletedPracticeSessionOutcome(:final sessionResult) =>
          _completionStateForFinishReason(sessionResult.finishReason),
        CancelledPracticeOutcome() => PracticeCompletionState.cancelled,
        TechnicalFailurePracticeOutcome() =>
          PracticeCompletionState.failedTechnical,
        SkippedPracticeOutcome() => PracticeCompletionState.skipped,
        UnavailablePracticeOutcome() => PracticeCompletionState.unavailable,
      };

  PracticeCompletionState _completionStateForFinishReason(
    practice.PracticeFinishReason finishReason,
  ) => switch (finishReason) {
    practice.PracticeFinishReason.completedAllTargets =>
      PracticeCompletionState.completed,
    practice.PracticeFinishReason.userFinished ||
    practice.PracticeFinishReason.timedOut ||
    practice.PracticeFinishReason.interrupted =>
      PracticeCompletionState.partial,
    // Defensive branches: the current engine does not emit a result for
    // cancelled/failed terminal states, but future callers must not turn
    // either one into a learner-performance failure.
    practice.PracticeFinishReason.cancelled =>
      PracticeCompletionState.cancelled,
    practice.PracticeFinishReason.failed =>
      PracticeCompletionState.failedTechnical,
  };
}

Map<String, double> _metricEvidence(Map<String, double> values) {
  for (final entry in values.entries) {
    _requiredText(entry.key, 'metricEvidence key');
    if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
      throw ArgumentError.value(
        entry.value,
        'metricEvidence',
        'values must be finite and within 0..1',
      );
    }
  }
  return Map<String, double>.unmodifiable(values);
}

String _requiredText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
