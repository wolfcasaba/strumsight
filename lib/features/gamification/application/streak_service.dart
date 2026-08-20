import '../domain/activity/learning_activity_event.dart';
import '../domain/streak/streak_policy.dart';
import '../domain/streak/streak_state.dart';
import '../domain/streak/streak_transition.dart';
import '../infrastructure/default_streak_policy.dart';
import 'package:strumsight/features/practice_generator/public.dart';

/// Typed application-level explanation for a qualified-day evaluation.
enum StreakEvaluationReason {
  qualified,
  recoveryQualified,
  insufficientActivity,
  plannedRest,
  grace,
  freezeCovered,
  broken,
  alreadyQualified,
  clockAnomaly,
}

/// Immutable caller-supplied inputs for one deterministic day evaluation.
final class StreakEvaluationRequest {
  StreakEvaluationRequest({
    required this.previous,
    required this.epochDay,
    this.activity,
    this.weeklySchedule,
    this.recoveryEligible = false,
  }) {
    if (epochDay < 0) {
      throw ArgumentError.value(epochDay, 'epochDay', 'must not be negative');
    }
    if (activity != null && activity!.epochDay != epochDay) {
      throw ArgumentError.value(
        activity!.epochDay,
        'activity.epochDay',
        'must equal epochDay',
      );
    }
    if (recoveryEligible && activity == null) {
      throw ArgumentError.value(
        recoveryEligible,
        'recoveryEligible',
        'requires a canonical activity',
      );
    }
  }

  /// State from the caller; this service never reads a repository.
  final StreakState previous;

  /// Local epoch day under evaluation, supplied explicitly by the caller.
  final int epochDay;

  /// Optional canonical activity measured for [epochDay].
  final LearningActivityEvent? activity;

  /// Optional public Practice Generator decision containing planned rest days.
  final WeeklyScheduleDecision? weeklySchedule;

  /// Enables the shorter threshold only when the caller explicitly grants it.
  final bool recoveryEligible;
}

/// Immutable state and typed reason produced by [StreakService.evaluate].
final class StreakEvaluation {
  const StreakEvaluation({required this.state, required this.reason});

  /// The next state; no XP, reward ledger, clock, or storage is touched.
  final StreakState state;

  /// The complete application-level explanation for this evaluation.
  final StreakEvaluationReason reason;
}

/// Pure application service for qualified days, planned rest, and recovery.
final class StreakService {
  StreakService({
    StreakPolicy? streakPolicy,
    DefaultStreakPolicy? qualificationPolicy,
  }) : _streakPolicy = streakPolicy ?? const StreakPolicy(),
       _qualificationPolicy = qualificationPolicy ?? DefaultStreakPolicy();

  final StreakPolicy _streakPolicy;
  final DefaultStreakPolicy _qualificationPolicy;

  /// Evaluates one supplied epoch day without querying a clock or persistence.
  StreakEvaluation evaluate(StreakEvaluationRequest request) {
    final scheduledRestDays = _qualificationPolicy.plannedRestEpochDays(
      request.weeklySchedule,
    );
    final plannedRestDays = <int>{
      ...request.previous.plannedRestDays,
      ...scheduledRestDays,
    };
    final state = scheduledRestDays.isEmpty
        ? request.previous
        : request.previous.copyWith(plannedRestDays: plannedRestDays);
    final lastQualifiedDay = state.lastQualifiedDay;

    if (lastQualifiedDay >= 0 && request.epochDay < lastQualifiedDay) {
      return StreakEvaluation(
        state: state,
        reason: StreakEvaluationReason.clockAnomaly,
      );
    }
    if (plannedRestDays.contains(request.epochDay)) {
      return StreakEvaluation(
        state: state,
        reason: StreakEvaluationReason.plannedRest,
      );
    }
    if (!_qualificationPolicy.qualifies(
      request.activity,
      recoveryEligible: request.recoveryEligible,
    )) {
      return _unqualifiedEvaluation(state, request.epochDay);
    }

    final transition = _streakPolicy.applyQualifiedDay(
      state,
      _projectedQualifiedDay(
        currentDay: request.epochDay,
        previousDay: lastQualifiedDay,
        plannedRestDays: plannedRestDays,
      ),
    );
    final next = identical(transition.state, state)
        ? state
        : transition.state.copyWith(
            lastQualifiedDay: request.epochDay,
            plannedRestDays: plannedRestDays,
          );
    return StreakEvaluation(
      state: next,
      reason: _reasonFor(transition, request.recoveryEligible),
    );
  }

  /// Counts unique caller-supplied qualified days in the inclusive last week.
  int weeklyConsistency({
    required int endingEpochDay,
    required Iterable<int> qualifiedDayHistory,
  }) {
    if (endingEpochDay < 0) {
      throw ArgumentError.value(
        endingEpochDay,
        'endingEpochDay',
        'must not be negative',
      );
    }
    final windowStart = endingEpochDay - 6;
    return {
      for (final day in qualifiedDayHistory)
        if (day >= windowStart && day <= endingEpochDay) day,
    }.length;
  }

  StreakEvaluation _unqualifiedEvaluation(StreakState state, int epochDay) {
    if (state.lastQualifiedDay < 0) {
      return StreakEvaluation(
        state: state,
        reason: StreakEvaluationReason.insufficientActivity,
      );
    }
    final gap = epochDay - state.lastQualifiedDay;
    return StreakEvaluation(
      state: state,
      reason: gap <= _qualificationPolicy.config.graceDays
          ? StreakEvaluationReason.grace
          : StreakEvaluationReason.broken,
    );
  }

  static int _projectedQualifiedDay({
    required int currentDay,
    required int previousDay,
    required Set<int> plannedRestDays,
  }) {
    if (previousDay < 0) return currentDay;
    final protectedDays = plannedRestDays.where(
      (day) => day > previousDay && day < currentDay,
    );
    return currentDay - protectedDays.length;
  }

  static StreakEvaluationReason _reasonFor(
    StreakTransition transition,
    bool recoveryEligible,
  ) => switch (transition.reason) {
    StreakTransitionReason.firstQualifiedDay ||
    StreakTransitionReason.consecutiveQualifiedDay =>
      recoveryEligible
          ? StreakEvaluationReason.recoveryQualified
          : StreakEvaluationReason.qualified,
    StreakTransitionReason.freezeCoveredMissedDay =>
      StreakEvaluationReason.freezeCovered,
    StreakTransitionReason.resetAfterMissedDays =>
      StreakEvaluationReason.broken,
    StreakTransitionReason.alreadyQualifiedToday =>
      StreakEvaluationReason.alreadyQualified,
    StreakTransitionReason.clockMovedBackwards =>
      StreakEvaluationReason.clockAnomaly,
  };
}
