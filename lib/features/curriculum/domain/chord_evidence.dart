/// Turning one graded chord attempt into skill evidence.
///
/// The sibling of `rhythm_evidence.dart`, and a separate file for the reason the
/// previous round stated when it deferred this: a chord-scored attempt gets its
/// OWN metric code rather than borrowing the direction one, because the two
/// measure different things and a borrowed number would be undetectable later.
///
/// ## What is measured, and what is therefore not claimed
///
/// [gradeChords] measures whether the asked chord was confirmed during the bar
/// that asked for it. It does not measure tone, clean ringing of individual
/// strings, or that a change landed ON the beat — each of those would need its own
/// measurement and would get its own metric code. The continuity half of a change
/// rung (keep the strumming hand moving) is measured as DIRECTION on the same run,
/// by the rhythm translator.
///
/// ## The refusals, and the one extra one this file has
///
/// Same four as the rhythm side — not a chord-scoring rung, an unmeasured mission,
/// below the coverage floor, nothing heard — plus: a rung whose exercise does not
/// score a chord writes nothing, however well it was played. A damped grid has no
/// chord to name, so a chord score from one would be a score of a label the engine
/// cannot produce.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6). Both instants are passed in.
library;

import '../../practice_generator/public.dart'
    show EvidenceSource, OutcomeId, PerformanceEvidence, SkillEvidence;
import 'chord_grading.dart';
import 'course.dart';
import 'skill_metrics.dart';

/// What the chord attempt actually measures, named so it can never be mistaken for
/// a direction, timing or tone measurement.
const String chordShapeAccuracyMetric = 'chord.shapeAccuracy';

/// Version of this translator. Bump it when the arithmetic changes, so an older
/// record stays identifiable as having been produced by older rules.
const int curriculumChordMeasurementVersion = 1;

/// The dedup key for one attempt's chord evidence about one skill.
///
/// Distinct from the rhythm translator's key even for the same run and the same
/// instant: one run produces two different measurements, and they are two records.
/// The repository stores exactly one record per id, so sharing a key would make
/// whichever was written second erase the other.
OutcomeId chordAttemptOutcomeId({
  required String missionId,
  required String skillId,
  required DateTime measuredAt,
}) => OutcomeId(
  'curriculum.chord:$missionId:'
  '${measuredAt.toUtc().microsecondsSinceEpoch}:$skillId',
);

/// Evidence for every chord skill [mission] trains, or empty when this attempt may
/// claim nothing.
List<SkillEvidence> chordAttemptEvidence({
  required CurriculumMission mission,
  required ChordAttempt attempt,
  required DateTime measuredAt,
  required DateTime capturedAt,
}) {
  final assignment = mission.rhythm;
  if (assignment == null || !assignment.mode.scoresChord) {
    return const <SkillEvidence>[];
  }
  if (!mission.isOutcomeMeasured) return const <SkillEvidence>[];
  if (!attempt.isReportable) return const <SkillEvidence>[];
  final accuracy = attempt.accuracy;
  if (accuracy == null) return const <SkillEvidence>[];

  final skillIds =
      mission.trainedSkillIds
          .where(
            (skillId) =>
                curriculumSkillMetric(skillId) ==
                CurriculumSkillMetric.chordShape,
          )
          .toList(growable: false)
        ..sort();
  if (skillIds.isEmpty) return const <SkillEvidence>[];

  return [
    for (final skillId in skillIds)
      SkillEvidence(
        skillId: skillId,
        source: EvidenceSource.curriculum,
        sourceOutcomeId: chordAttemptOutcomeId(
          missionId: mission.missionId,
          skillId: skillId,
          measuredAt: measuredAt,
        ),
        measurementVersion: curriculumChordMeasurementVersion,
        measuredAt: measuredAt,
        capturedAt: capturedAt,
        // Coverage as confidence, never folded into the value — the same split,
        // and for the same reason, as the rhythm translator's: "I could not hear
        // that bar" and "you held the wrong shape" call for opposite responses.
        confidence: attempt.coverage.clamp(0.0, 1.0),
        performance: PerformanceEvidence(
          metricCode: chordShapeAccuracyMetric,
          value: accuracy,
          // Bars that produced confirmed evidence, not bars asked for.
          sampleCount: attempt.heard,
        ),
      ),
  ];
}
