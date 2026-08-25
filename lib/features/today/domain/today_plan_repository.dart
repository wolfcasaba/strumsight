import 'today_plan_snapshot.dart';

/// Reads today's practice plan for the Today Hub.
///
/// §0.0/R6.1 measured that the Chapter 8 Practice Generator has no
/// presentation-layer provider yet — `TodayPlanController` exists but
/// nothing in `lib/features/practice_generator/presentation/` publishes it
/// to a Riverpod provider. Per brief §5.5, the seam is this repository
/// interface: production reads [UnavailableTodayPlanRepository] (the honest
/// "no data" default — never an invented plan, A8), and tests supply a fake
/// to exercise the ready/offline/sync-pending/day-completed states.
abstract class TodayPlanRepository {
  TodayPlanSnapshot load();
}

/// The production default until a future round wires the real plan source.
final class UnavailableTodayPlanRepository implements TodayPlanRepository {
  const UnavailableTodayPlanRepository();

  @override
  TodayPlanSnapshot load() =>
      const TodayPlanSnapshot(availability: TodayPlanAvailability.unavailable);
}
