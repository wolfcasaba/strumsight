import 'today_plan_snapshot.dart';

/// Reads today's practice plan for the Today Hub.
///
/// The seam is this repository interface (brief §5.5): tests supply a fake
/// to exercise the ready/offline/sync-pending/day-completed states, and
/// `todayPlanRepositoryProvider` picks the production implementation from
/// the state of the Practice Generator's active plan — the projection
/// (`ActivePlanTodayPlanRepository`) when a plan is active,
/// [UnavailableTodayPlanRepository] when there is none, and
/// [UnreadableTodayPlanRepository] when the plan store answered with a
/// failure.
abstract class TodayPlanRepository {
  TodayPlanSnapshot load();
}

/// No plan to show: the learner has not activated one (the honest "no data"
/// answer — never an invented plan, A8).
final class UnavailableTodayPlanRepository implements TodayPlanRepository {
  const UnavailableTodayPlanRepository();

  @override
  TodayPlanSnapshot load() =>
      const TodayPlanSnapshot(availability: TodayPlanAvailability.unavailable);
}

/// The plan store answered with a failure (R19, audit M4/M6). Kept distinct
/// from [UnavailableTodayPlanRepository]: mapping a read error to "no plan"
/// would tell a learner whose plan is present-but-unreadable that they have
/// none, and quietly invite them to start over.
final class UnreadableTodayPlanRepository implements TodayPlanRepository {
  const UnreadableTodayPlanRepository();

  @override
  TodayPlanSnapshot load() =>
      const TodayPlanSnapshot(availability: TodayPlanAvailability.unreadable);
}
