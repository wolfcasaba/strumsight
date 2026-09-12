import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../curriculum/public.dart'
    show
        curriculumClockProvider,
        curriculumCourseProvider,
        curriculumProgressProvider;
import '../data/curriculum_today_plan_repository.dart';
import '../domain/today_plan_repository.dart';
import '../domain/today_plan_snapshot.dart';

/// Production reads the COURSE: the ladder knows which rung the learner is on, and
/// until this was bound the hub told a learner halfway up it that they had no plan.
///
/// `UnavailableTodayPlanRepository` remains the honest fallback and is still what
/// tests use alongside fakes for the offline-cached / sync-pending states — states
/// the curriculum source never produces, because shipped data and local evidence
/// have nothing to sync.
final todayPlanRepositoryProvider = Provider<TodayPlanRepository>(
  (ref) => CurriculumTodayPlanRepository(
    course: ref.watch(curriculumCourseProvider),
    progress: ref.watch(curriculumProgressProvider),
    asOf: ref.watch(curriculumClockProvider)(),
  ),
);

final todayPlanSnapshotProvider = Provider<TodayPlanSnapshot>(
  (ref) => ref.watch(todayPlanRepositoryProvider).load(),
);
