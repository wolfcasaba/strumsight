import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/today_plan_repository.dart';
import '../domain/today_plan_snapshot.dart';

/// Production default — overridden in tests with a fake to exercise the
/// ready / offline-cached / sync-pending / day-completed states (brief §5.5).
final todayPlanRepositoryProvider = Provider<TodayPlanRepository>(
  (ref) => const UnavailableTodayPlanRepository(),
);

final todayPlanSnapshotProvider = Provider<TodayPlanSnapshot>(
  (ref) => ref.watch(todayPlanRepositoryProvider).load(),
);
