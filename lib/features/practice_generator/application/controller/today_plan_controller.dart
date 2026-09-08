/// Local-date projection of an active plan for the Today experience.
library;

import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/missed_day_policy.dart';
import '../../domain/policy/scheduling_policy.dart';
import '../port/catch_up_notice_log.dart';

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
    required this.missedDays,
  });

  final LocalDate localDate;
  final TodayPlanMode mode;
  final AdaptivePracticePlan? plan;
  final PracticeDay? day;
  final PracticeBlock? nextBlock;
  final Duration remainingTime;

  /// The missed-day verdict over the WHOLE active plan (ADR 0269), or
  /// `null` when there is no active plan to evaluate.
  ///
  /// This is the honest gate for the catch-up explainer: the Today screen
  /// offers it only when the policy itself counted at least one missed day,
  /// never on a hunch about the calendar. The decision also carries the
  /// unchanged next-day budget, so a consumer that ever tried to grow the
  /// day from missed time would have to ignore a field it was handed
  /// (`MissedDayDecision.nextDayBudget`, the A1 typed invariant).
  final MissedDayDecision? missedDays;

  bool get hasActivePlan => plan != null;
  bool get canStartNextBlock => nextBlock != null;

  /// Whether the plan carries at least one missed day right now — the
  /// condition, and the ONLY condition, under which the catch-up
  /// explainer is offered.
  bool get hasMissedDays => (missedDays?.missedDayCount ?? 0) > 0;
}

/// Resolves the learner's current local date from an injected clock.
///
/// The clock returns the already-local application time. Its calendar fields
/// are copied directly into [LocalDate]: converting it to UTC here would
/// change the learner's planned day around midnight (ADR 0258 §4).
final class TodayPlanController {
  TodayPlanController({
    required this.clock,
    MissedDayPolicy? missedDayPolicy,
    CatchUpNoticeLog? catchUpNoticeLog,
  }) : _missedDayPolicy = missedDayPolicy ?? MissedDayPolicy(),
       _catchUpNoticeLog = catchUpNoticeLog ?? InMemoryCatchUpNoticeLog();

  final DateTime Function() clock;

  /// The REAL policy (ADR 0269), never a re-implementation in the screen:
  /// "was a day missed?" is a domain decision with its own regression
  /// suite (`test/features/practice_generator/continuity/`), and the Today
  /// screen must not be able to disagree with it.
  final MissedDayPolicy _missedDayPolicy;

  /// Where "this revision's catch-up explainer was already offered" lives.
  /// The composition root injects the persistent binding; the default is
  /// process-local (see [InMemoryCatchUpNoticeLog]).
  final CatchUpNoticeLog _catchUpNoticeLog;

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
        missedDays: null,
      );
    }

    final missedDays = _evaluateMissedDays(plan, localDate);

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
        missedDays: missedDays,
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
        missedDays: missedDays,
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
        missedDays: missedDays,
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
        missedDays: missedDays,
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
      missedDays: missedDays,
    );
  }

  /// Feeds the WHOLE plan to [MissedDayPolicy] (ADR 0269).
  ///
  /// Every input is caller-supplied, exactly as the policy's contract
  /// demands: no clock is read here (the resolved local [today] comes in),
  /// and each day contributes its own status, reason codes and whether it
  /// carried a planned primary-focus block. A day whose blocks contain no
  /// [BlockKind.primaryFocus] entry is NOT a missed practice day (A6): the
  /// optional/secondary work never carries over, so it cannot create one.
  MissedDayDecision _evaluateMissedDays(
    AdaptivePracticePlan plan,
    LocalDate today,
  ) {
    return _missedDayPolicy.evaluate(
      MissedDayInput(
        today: today,
        nextDayBudget: _nextDayBudget(plan, today),
        observations: <MissedDayObservation>[
          for (final day in plan.days)
            MissedDayObservation(
              localDate: day.localDate,
              status: day.status,
              reasonCodes: day.reasonCodes,
              hasPrimaryFocus: day.blocks.any(
                (block) => block.kind == BlockKind.primaryFocus,
              ),
            ),
        ],
      ),
    );
  }

  /// The hard ceiling of the first day that is today or later — the frame
  /// ADR 0258 §3 forbids growing. [Duration.zero] when the plan has no such
  /// day left: there is no next frame to protect, and a fabricated budget
  /// would be a claim the plan does not make.
  static Duration _nextDayBudget(AdaptivePracticePlan plan, LocalDate today) {
    PracticeDay? next;
    for (final day in plan.days) {
      if (day.localDate.compareTo(today) < 0) continue;
      if (next == null || day.localDate.compareTo(next.localDate) < 0) {
        next = day;
      }
    }
    return next?.timeBudget ?? Duration.zero;
  }

  /// The scope of ONE catch-up offer: the plan and the revision it is on.
  ///
  /// A revision is a new plan state (ADR 0256 — the past is immutable, a
  /// change makes a new revision), so an offer acknowledged on the old
  /// revision does not silence the new one.
  static String catchUpOfferKey(AdaptivePracticePlan plan) =>
      '${plan.id.value}/${plan.activeRevisionId.value}';

  /// Whether this plan revision's catch-up explainer was already offered.
  bool hasOfferedCatchUp(AdaptivePracticePlan plan) =>
      _catchUpNoticeLog.wasAcknowledged(catchUpOfferKey(plan));

  /// Records that the offer was taken up or dismissed — the "once, not
  /// nagged" half of ADR 0269 §5.
  Future<void> markCatchUpOffered(AdaptivePracticePlan plan) =>
      _catchUpNoticeLog.acknowledge(catchUpOfferKey(plan));

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
