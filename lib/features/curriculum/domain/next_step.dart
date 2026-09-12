/// Which rung is the learner's next step.
///
/// ## One definition, because two would disagree in front of the learner
///
/// Two surfaces need this answer: the Today hub, whose primary button continues
/// "today's step", and the ladder, which marks that step so the button does not
/// drop someone onto an undifferentiated list of fourteen rows. Two
/// implementations would eventually name different rungs, and the learner would
/// see the hub promise one thing and the ladder point at another — the same class
/// of duplication `docs/LESSONS.md` L269 records for matching helpers.
///
/// ## The definition
///
/// **The first rung, in ladder order, that is unlocked and has not yet unlocked
/// what comes after it.** Formally: the first mission whose skill gate is satisfied
/// and which trains a skill some still-locked later mission needs.
///
/// It needs no threshold of its own, which is why it was chosen. Both obvious
/// alternatives fail:
///
/// - *"the furthest unlocked rung"* skips the teaching order. Once the right-hand
///   rung is earned, E minor (rung 3) and down-up eighths (rung 6) both unlock; the
///   furthest is rung 6, while the course's researched order puts the shape first.
/// - *"the first unlocked rung with no recorded attempt"* stops recommending a rung
///   after ONE attempt, when the measured gate needs two
///   (`curriculum_progress_test.dart`).
///
/// At the top of the ladder nothing later is locked, so the last unlocked rung is
/// the answer: there is nothing beyond it to aim at.
///
/// ## What it deliberately ignores
///
/// Device capability. `curriculumDeviceCapabilities` answers "what can be measured
/// while audio is arriving", which is a property of a practice session rather than
/// of the learner's position on the ladder — and the surfaces that CAN know it (the
/// ladder, the practice screen) already say so in words. Consulting it here would
/// mean a hub with no live engine recommending "tune up" forever.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6).
library;

import '../../practice_generator/public.dart' show SkillEstimate;
import 'course.dart';

/// The rung to practise next, or null when the course offers none.
///
/// Null is not a failure: a course whose first rung is gated on evidence nobody has
/// would legitimately have no next step, and the honest answer is to say so rather
/// than to offer the first rung regardless.
CurriculumMission? curriculumNextStep(
  Course course, {
  required Map<String, SkillEstimate> estimates,
}) {
  final missions = course.missionsInOrder.toList(growable: false);
  final unlocked = [
    for (final mission in missions)
      if (mission.unlock.isSatisfiedBy(estimates)) mission,
  ];
  if (unlocked.isEmpty) return null;

  final lockedSkillsNeeded = <String>{
    for (final mission in missions)
      if (!mission.unlock.isSatisfiedBy(estimates))
        ...mission.unlock.prerequisiteSkillIds,
  };
  for (final mission in unlocked) {
    if (mission.trainedSkillIds.any(lockedSkillsNeeded.contains)) {
      return mission;
    }
  }
  return unlocked.last;
}
