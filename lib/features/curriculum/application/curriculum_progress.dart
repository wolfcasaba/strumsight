/// Recording what a learner played, and reading back what it says about them.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2.
/// The ladder's gate is [UnlockRule.isSatisfiedBy], which takes a map of
/// [SkillEstimate] by skill id. Until this existed the only caller handed it an
/// empty map, so every gated rung read "not yet reached" permanently. This class
/// is the whole join: attempt in, evidence persisted, estimates out.
///
/// ## It owns no policy
///
/// Every judgement here already existed and is reused rather than re-decided:
/// what an attempt measures ([rhythmAttemptEvidence]), how much one observation
/// is worth ([EvidenceWeightPolicy]), how evidence becomes a level and a state
/// ([SkillEstimateReducer]), and when a rung opens ([UnlockRule]). A second
/// opinion on any of those would be a second answer to the same question.
///
/// ## Every skill the course names, including the ones with nothing behind them
///
/// [estimatesFor] returns an entry for every skill trained anywhere in the
/// course, including [SkillEstimate.unknown] ones. That is deliberate: the gate
/// treats a missing entry and an `unknown` entry identically, so the map can be
/// complete without changing any verdict, and a surface that wants to say "no
/// evidence yet" can read it from the estimate instead of inferring it from a
/// key's absence.
///
/// No clock is read here (AGENTS.md §6): `at` / `asOf` are supplied.
library;

import '../../practice_generator/public.dart'
    show
        PracticeEvidenceRepository,
        SkillEstimate,
        SkillEstimateReducer,
        SkillEvidence;
import '../domain/chord_evidence.dart';
import '../domain/chord_grading.dart';
import '../domain/course.dart';
import '../domain/rhythm_evidence.dart';
import '../domain/rhythm_grading.dart';
import '../domain/unlock_rule.dart';

final class CurriculumProgress {
  CurriculumProgress({
    required this.evidenceRepository,
    SkillEstimateReducer? reducer,
  }) : reducer = reducer ?? SkillEstimateReducer();

  final PracticeEvidenceRepository evidenceRepository;
  final SkillEstimateReducer reducer;

  /// Persists what one run says about [mission]'s skills, and returns the records
  /// actually written — empty when nothing may be claimed.
  ///
  /// Returning the records rather than void is what lets a caller tell "saved
  /// nothing because there was not enough evidence" apart from "saved", without
  /// re-deriving the refusal rules that [rhythmAttemptEvidence] and
  /// [chordAttemptEvidence] own.
  ///
  /// Writing the same attempt twice is harmless: the outcome id is derived from
  /// the mission and [at], so a repeat save replaces the identical record
  /// instead of counting the attempt twice. That matters because a Flutter
  /// widget can rebuild for reasons that have nothing to do with the learner.
  List<SkillEvidence> recordAttempt({
    required CurriculumMission mission,
    required RhythmAttempt rhythm,
    ChordAttempt? chord,
    required DateTime at,
  }) {
    final evidence = [
      ...rhythmAttemptEvidence(
        mission: mission,
        attempt: rhythm,
        measuredAt: at,
        capturedAt: at,
      ),
      // ONE run, TWO measurements. They are separate records with separate metric
      // codes and separate dedup keys, because direction accuracy and chord
      // accuracy say different things about the player — and a rung's skills are
      // credited only from the measurement they are actually made of
      // (`skill_metrics.dart`).
      if (chord != null)
        ...chordAttemptEvidence(
          mission: mission,
          attempt: chord,
          measuredAt: at,
          // The attempt was graded the instant it ended, so it was measured and
          // captured at the same time. They are separate fields because an
          // adapter importing older measurements needs them apart; here they
          // coincide, and saying so is more honest than back-dating one of them.
          capturedAt: at,
        ),
    ];
    for (final record in evidence) {
      // No `sourcePlanId`: this evidence belongs to no generated practice plan,
      // and claiming one would hand `deleteForPlan` a record it does not own.
      // The repository records that as ownership-unknown and therefore never
      // deletes it on a plan's behalf, which is the correct outcome.
      evidenceRepository.save(record);
    }
    return evidence;
  }

  /// The learner's estimate for every skill [course] trains, as of [asOf].
  Map<String, SkillEstimate> estimatesFor(
    Course course, {
    required DateTime asOf,
  }) {
    final skillIds = <String>{
      for (final mission in course.missionsInOrder) ...mission.trainedSkillIds,
    }.toList(growable: false)..sort();
    return <String, SkillEstimate>{
      for (final skillId in skillIds)
        skillId: reducer.reduce(
          skillId: skillId,
          // `allForSkill`, not `query`: the reducer's own job is to tell current
          // evidence from stale, and it needs to see both to do it. Filtering
          // expired records out here would turn "old data" into "no data" —
          // the exact distinction ADR 0260 §5 keeps the store immutable for.
          evidence: evidenceRepository.allForSkill(skillId),
          asOf: asOf,
        ),
    };
  }

  /// How many attempts the estimate for [skillId] rests on, for a surface that
  /// wants to say what a verdict is based on.
  ///
  /// Counted from the evidence ids the reducer actually used, not from the store:
  /// an id the reducer discarded (a duplicate, or a record carrying no
  /// performance) did not contribute, and counting it would overstate the
  /// evidence behind the number shown.
  int attemptsBehind(SkillEstimate estimate) => estimate.evidenceIds.length;
}
