/// Local-date projection of an active plan for the Today experience.
library;

import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/scheduling_policy.dart';

/// The distinct, non-punitive presentation states for a local plan day.
enum TodayPlanMode {
  noActivePlan,
  notScheduled,
  restDay,
  unavailableDay,
  completedDay,
  plannedDay,
}

/// Immutable data for a single Today-screen render.
final class TodayPlanState {
  const TodayPlanState({
    required this.localDate,
    required this.mode,
    required this.plan,
    required this.day,
    required this.nextBlock,
    required this.remainingTime,
  });

  final LocalDate localDate;
  final TodayPlanMode mode;
  final AdaptivePracticePlan? plan;
  final PracticeDay? day;
  final PracticeBlock? nextBlock;
  final Duration remainingTime;

  bool get hasActivePlan => plan != null;
  bool get canStartNextBlock => nextBlock != null;
}

/// Resolves the learner's current local date from an injected clock.
///
/// The clock returns the already-local application time. Its calendar fields
/// are copied directly into [LocalDate]: converting it to UTC here would
/// change the learner's planned day around midnight (ADR 0258 §4).
final class TodayPlanController {
  TodayPlanController({required this.clock});

  final DateTime Function() clock;

  TodayPlanState resolve(AdaptivePracticePlan? plan) {
    final now = clock();
    final localDate = LocalDate(now.year, now.month, now.day);
    if (plan == null || plan.status != PlanStatus.active) {
      return TodayPlanState(
        localDate: localDate,
        mode: TodayPlanMode.noActivePlan,
        plan: null,
        day: null,
        nextBlock: null,
        remainingTime: Duration.zero,
      );
    }

    PracticeDay? day;
    for (final candidate in plan.days) {
      if (candidate.localDate == localDate) {
        day = candidate;
        break;
      }
    }
    if (day == null) {
      return TodayPlanState(
        localDate: localDate,
        mode: TodayPlanMode.notScheduled,
        plan: plan,
        day: null,
        nextBlock: null,
        remainingTime: Duration.zero,
      );
    }

    if (day.reasonCodes.contains(ScheduleDecisionReason.restDay.code)) {
      return TodayPlanState(
        localDate: localDate,
        mode: TodayPlanMode.restDay,
        plan: plan,
        day: day,
        nextBlock: null,
        remainingTime: Duration.zero,
      );
    }
    if (day.reasonCodes.contains(ScheduleDecisionReason.dayUnavailable.code)) {
      return TodayPlanState(
        localDate: localDate,
        mode: TodayPlanMode.unavailableDay,
        plan: plan,
        day: day,
        nextBlock: null,
        remainingTime: Duration.zero,
      );
    }
    if (day.status == PracticeItemStatus.completed) {
      return TodayPlanState(
        localDate: localDate,
        mode: TodayPlanMode.completedDay,
        plan: plan,
        day: day,
        nextBlock: null,
        remainingTime: Duration.zero,
      );
    }

    final remaining =
        day.blocks
            .where((block) => !_isTerminal(block.status))
            .toList(growable: false)
          ..sort((left, right) => left.order.compareTo(right.order));
    return TodayPlanState(
      localDate: localDate,
      mode: TodayPlanMode.plannedDay,
      plan: plan,
      day: day,
      nextBlock: remaining.isEmpty ? null : remaining.first,
      remainingTime: remaining.fold<Duration>(
        Duration.zero,
        (total, block) => total + block.estimatedElapsed,
      ),
    );
  }

  static bool _isTerminal(PracticeItemStatus status) => switch (status) {
    PracticeItemStatus.completed ||
    PracticeItemStatus.skipped ||
    PracticeItemStatus.substituted ||
    PracticeItemStatus.unavailable ||
    PracticeItemStatus.expired => true,
    PracticeItemStatus.planned ||
    PracticeItemStatus.ready ||
    PracticeItemStatus.inProgress => false,
  };
}

/// Typed, pre-parsed request for the Today destination.
///
/// Routing code may call [tryParse] with a resolved map. Raw URIs deliberately
/// do not reach this type; malformed or unknown external values become null.
final class TodayPlanRouteRequest {
  const TodayPlanRouteRequest._();

  static const String _destinationKey = 'destination';
  static const String _todayDestination = 'today';

  static TodayPlanRouteRequest? tryParse(Object? extra) {
    if (extra is! Map || extra.length != 1) {
      return null;
    }

    try {
      for (final entry in extra.entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            entry.key != _destinationKey ||
            entry.value != _todayDestination) {
          return null;
        }
      }
    } on TypeError {
      return null;
    }

    return const TodayPlanRouteRequest._();
  }

  /// A notification only opens this destination for an enabled active plan.
  bool permits({
    required AdaptivePracticePlan? activePlan,
    required bool isFeatureEnabled,
  }) => isFeatureEnabled && activePlan?.status == PlanStatus.active;
}
