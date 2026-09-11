/// Which chords a rung asks for, bar by bar.
///
/// ## Why it is derived from the skills rather than stored on the assignment
///
/// `RhythmAssignment` deliberately names no chord — its own doc says so — because
/// which chord a rung practises follows from what the rung TRAINS. Putting the
/// chord on the assignment as well would give one decision two homes that can
/// disagree, and the one that disagreed would be the one a learner was scored
/// against.
///
/// ## Why a cycle rather than a single chord
///
/// A change rung is a change: `chord.emToAm` alternates bar by bar, and that
/// alternation is the whole exercise. It is also what makes the chord measurement
/// a measurement OF THE CHANGE — both bars cannot be confirmed without the
/// learner actually changing between them. A single-chord rung gets a cycle of
/// one, so every bar asks the same shape and the exercise is "find it and keep
/// it".
///
/// ## What it deliberately does not do
///
/// It names only chords the app can both SHOW (a shipped `ChordShapes`
/// fingering) and RECOGNISE (in the decoder's vocabulary, measured 7/7 on
/// modelled audio and 7/7 on the labelled real-guitar naturals). No simplified
/// stepping-stone voicing appears here, for the reason `beginner_course.dart`
/// already measured: `G6` is not in the decoder's vocabulary at all and reads as
/// `G`, and `Cmaj7` does not reliably confirm. A learner must never play
/// something correctly and be told nothing happened.
/// `test/features/curriculum/mission_chords_test.dart` checks both properties
/// against the shipped data rather than trusting this comment.
///
/// Pure Dart: no Flutter, no clock, and no dependency on the chord feature — the
/// labels are plain strings here and the guard test is what ties them to the
/// shipped fingerings (AGENTS.md §6).
library;

import 'course.dart';
import 'skill_metrics.dart';

/// The chords [mission] asks for, one per bar, repeating.
///
/// Empty when the rung asks for no chord at all — a damped rung, or one whose
/// exercise does not score a chord. Empty is meaningful: the lane shows no shape
/// rather than a shape the learner is not meant to fret.
List<String> missionChordCycle(CurriculumMission mission) {
  final assignment = mission.rhythm;
  if (assignment == null || !assignment.mode.scoresChord) {
    return const <String>[];
  }
  for (final skillId in mission.trainedSkillIds) {
    if (curriculumSkillMetric(skillId) != CurriculumSkillMetric.chordShape) {
      continue;
    }
    final cycle = _chordSkillCycle(skillId);
    if (cycle != null) return cycle;
  }
  // A chord-scoring rung that trains no chord skill: the pattern rung, whose
  // skill is the strumming pattern. It still needs a shape to play it over, and
  // the course's own reasoning is that it runs on the two chords already known
  // rather than waiting for the whole chord set.
  return const ['Em', 'Am'];
}

/// The bar cycle one chord skill is practised as, or null when [skillId] is not a
/// chord skill this function knows.
///
/// Null rather than a guess: a chord skill with no cycle here must surface as a
/// guard-test failure, not as a learner being asked to play `Em` because it was
/// the nearest default.
List<String>? _chordSkillCycle(String skillId) => switch (skillId) {
  'chord.eMinor' => const ['Em'],
  'chord.aMinor' => const ['Am'],
  'chord.dMajor' => const ['D'],
  'chord.gMajor' => const ['G'],
  'chord.cMajor' => const ['C'],
  'chord.emToAm' => const ['Em', 'Am'],
  'chord.amToD' => const ['Am', 'D'],
  'chord.dToG' => const ['D', 'G'],
  'chord.gToC' => const ['G', 'C'],
  _ => null,
};

/// Every chord label this file can ask a learner to play.
///
/// Exposed so the guard test can check each one against the shipped fingerings
/// and the decoder's vocabulary without having to re-enumerate the table.
Set<String> get curriculumChordLabels => {
  for (final skillId in const [
    'chord.eMinor',
    'chord.aMinor',
    'chord.dMajor',
    'chord.gMajor',
    'chord.cMajor',
    'chord.emToAm',
    'chord.amToD',
    'chord.dToG',
    'chord.gToC',
  ])
    ..._chordSkillCycle(skillId)!,
  'Em',
  'Am',
};
