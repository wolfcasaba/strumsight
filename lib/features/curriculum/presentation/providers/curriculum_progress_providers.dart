/// Wiring the curriculum's measured progress into the widget tree.
///
/// The ladder needs a map of [SkillEstimate] by skill id, and it must change
/// when an attempt is recorded — otherwise a learner finishes a rung, returns to
/// the ladder and sees nothing happened, which is the one thing worse than
/// showing no progress at all.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../practice_generator/public.dart'
    show SkillEstimate, practiceEvidenceRepositoryProvider;
import '../../application/curriculum_progress.dart';
import '../../data/beginner_course.dart';
import '../../domain/chord_grading.dart';
import '../../domain/course.dart';
import '../../domain/rhythm_grading.dart';

/// The clock, injected the way every other feature here injects one
/// (`practiceGeneratorClockProvider`, `visionSessionClockProvider`), so a test
/// can place an attempt at a chosen instant instead of racing the wall clock.
final curriculumClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// The shipped course, as one provider, so the ladder and the progress notifier
/// cannot disagree about which course they are talking about.
final curriculumCourseProvider = Provider<Course>((ref) => beginnerCourse());

final curriculumProgressProvider = Provider<CurriculumProgress>(
  (ref) => CurriculumProgress(
    // The PERSISTENT repository, not the never-forgets in-memory fake: progress
    // that vanished on the next launch would be a silent no-op for the one thing
    // the learner cares about most.
    evidenceRepository: ref.watch(practiceEvidenceRepositoryProvider),
  ),
);

/// The learner's measured skills, recomputed from the evidence store.
///
/// The estimates are derived, never stored: the store holds evidence, and the
/// reduction from evidence to a level happens on read. That is what lets a
/// policy change take effect for evidence already earned, instead of leaving a
/// learner with numbers produced by rules the app no longer uses.
class CurriculumEstimates extends Notifier<Map<String, SkillEstimate>> {
  @override
  Map<String, SkillEstimate> build() => _read();

  Map<String, SkillEstimate> _read() => ref
      .read(curriculumProgressProvider)
      .estimatesFor(
        ref.read(curriculumCourseProvider),
        asOf: ref.read(curriculumClockProvider)(),
      );

  /// Records one run — its direction measurement and, when the rung scores a
  /// chord, its chord measurement — and republishes the estimates.
  ///
  /// Returns whether anything was written. False is not a failure — it is the
  /// app declining to judge on too little evidence — and the caller needs to
  /// know which happened so it can say so rather than imply progress.
  bool recordAttempt({
    required CurriculumMission mission,
    required RhythmAttempt rhythm,
    ChordAttempt? chord,
  }) {
    final written = ref
        .read(curriculumProgressProvider)
        .recordAttempt(
          mission: mission,
          rhythm: rhythm,
          chord: chord,
          at: ref.read(curriculumClockProvider)(),
        );
    // Re-read even when nothing was written: a recompute is cheap, and a
    // conditional refresh is the kind of shortcut that later hides a real write
    // behind a stale map.
    state = _read();
    return written.isNotEmpty;
  }

  /// Recomputes from the store — for a surface returning from elsewhere.
  void refresh() => state = _read();
}

final curriculumEstimatesProvider =
    NotifierProvider<CurriculumEstimates, Map<String, SkillEstimate>>(
      CurriculumEstimates.new,
    );
