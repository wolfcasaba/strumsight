/// What kind of measurement a curriculum skill is actually made of.
///
/// ## Why this exists
///
/// A rhythm attempt measures direction; a chord attempt measures the shape. Both
/// come out of the SAME run of the same exercise, so without this the obvious
/// wiring writes both measurements against every skill the rung trains — and
/// `mission.eMinor` would have its chord skill credited from a direction
/// accuracy, which says nothing whatever about whether the learner's fingers were
/// on the right frets. A number in the right field measuring the wrong thing is
/// worse than no number, because nothing downstream can tell.
///
/// The classification lives here rather than being inferred at each call site,
/// and `test/features/curriculum/skill_metrics_test.dart` holds the part that
/// matters: every skill the shipped course trains must classify, and every rung
/// must be able to PRODUCE the measurement its own skills need.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6).
library;

import 'course.dart';
import 'rhythm_assignment.dart';

/// The kind of evidence a skill is measured by.
enum CurriculumSkillMetric {
  /// Which way the hand travelled at each notated slot — `gradeRhythm`.
  strumDirection('strumDirection'),

  /// Whether the asked chord was confirmed while it was being asked for —
  /// `gradeChords`.
  chordShape('chordShape'),

  /// Nothing this app measures yet. NOT a gap to be filled with the nearest
  /// available number: a skill here earns no evidence at all, which is the
  /// honest state of something unmeasured.
  notMeasuredHere('notMeasuredHere');

  const CurriculumSkillMetric(this.code);

  final String code;

  @override
  String toString() => code;
}

/// How [skillId] is measured.
///
/// Classified by the skill id's namespace, which is how the course already names
/// things (`rhythm.*`, `chord.*`, `strumPattern.*`, `songPerformance.*`). The
/// namespaces are part of the persisted vocabulary and the guard test walks the
/// shipped course, so a new skill in an unknown namespace classifies as
/// [CurriculumSkillMetric.notMeasuredHere] — earning nothing, rather than
/// borrowing whichever measurement happens to be nearby.
CurriculumSkillMetric curriculumSkillMetric(String skillId) {
  if (skillId.startsWith('rhythm.') || skillId.startsWith('strumPattern.')) {
    return CurriculumSkillMetric.strumDirection;
  }
  if (skillId.startsWith('chord.')) return CurriculumSkillMetric.chordShape;
  // `songPerformance.*` lands here on purpose: playing a song through is not a
  // direction accuracy and not a chord accuracy, and calling it either would be
  // scoring something other than what the rung asked for.
  return CurriculumSkillMetric.notMeasuredHere;
}

/// Which measurements [assignment] can actually produce.
///
/// Every rhythm assignment produces a direction measurement — that is what the
/// grid is. Only a chord-scoring mode produces a chord measurement, because a
/// damped grid has no chord to name.
Set<CurriculumSkillMetric> assignmentMetrics(RhythmAssignment assignment) => {
  CurriculumSkillMetric.strumDirection,
  if (assignment.mode.scoresChord) CurriculumSkillMetric.chordShape,
};

/// The skills of [mission] that its own exercise cannot measure.
///
/// Empty is the only acceptable answer for a shipped measured rung, and the guard
/// test is what keeps it that way. A non-empty result means the rung claims
/// progress in something its exercise does not produce — so finishing it would
/// either write the wrong measurement or write nothing while looking like it
/// counted.
Set<String> unmeasurableSkillsOf(CurriculumMission mission) {
  final assignment = mission.rhythm;
  if (assignment == null) return mission.trainedSkillIds;
  final available = assignmentMetrics(assignment);
  return {
    for (final skillId in mission.trainedSkillIds)
      if (!available.contains(curriculumSkillMetric(skillId))) skillId,
  };
}
