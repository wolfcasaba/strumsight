/// Turning one graded rhythm attempt into skill evidence.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2.
/// This is the join the ladder was missing: without it `missionAvailability` is
/// handed an empty estimate map forever, so no rung the course gates can ever
/// open and the curriculum is a map of a path nobody can walk.
///
/// ## What is measured, and what is therefore NOT claimed
///
/// [gradeRhythm] measures ONE thing: which way the hand travelled at each
/// notated slot. It does not grade the chord, the tone, or the fingering — so
/// the metric code says `rhythm.directionAccuracy` and nothing here ever pretends
/// otherwise. A future chord-scored attempt gets its own metric code and its own
/// translator rather than borrowing this one's number.
///
/// ## Only the skills this measurement is ABOUT
///
/// A rung's exercise produces both a direction measurement and (when it scores a
/// chord) a chord measurement, from the same run. So this writes records only for
/// the trained skills [curriculumSkillMetric] classifies as
/// [CurriculumSkillMetric.strumDirection]; the chord skills of the same rung are
/// `chord_evidence.dart`'s to write. Without that split, `mission.eMinor` would
/// have its chord skill credited from a direction accuracy — a number in the right
/// field measuring the wrong thing, which nothing downstream could detect.
///
/// ## The four refusals
///
/// Each returns NO evidence, which is a different thing from evidence of a low
/// level — and the whole reason [SkillEstimate] keeps `unknown` separate from a
/// low `level` (design §2 rule 1: only confirmed evidence counts).
///
/// 1. **Not a rhythm mission.** Nothing else here was graded by [gradeRhythm].
/// 2. **An unmeasured mission, or one that names no skill.** A rung that says it
///    measures nothing must not quietly write a measurement.
/// 3. **Below the coverage floor** ([RhythmAttempt.isReportable]). "I could not
///    hear enough of that" is not a score, and writing one would make a quiet
///    room look like bad playing.
/// 4. **Nothing heard at all** (a null [RhythmAttempt.directionAccuracy]).
///
/// ## Where coverage goes, and where it deliberately does not
///
/// Coverage is the share of notated strokes that produced confirmed evidence. It
/// is recorded as the record's [SkillEvidence.confidence] and as
/// [PerformanceEvidence.sampleCount] — never folded into the measured value.
/// Folding it in would average "I could not hear you" together with "you
/// strummed the wrong way", and those call for opposite responses: another
/// repetition versus a correction. §3 states the same rule from the other side —
/// a missed slot subtracts nothing.
///
/// Said plainly, because the number is easy to over-read: with the shipped
/// [EvidenceWeightPolicy] the confidence figure currently changes NOTHING. The
/// per-record influence cap (0.25) binds for every attempt that clears the
/// coverage floor, so a 60%-coverage attempt and a 100%-coverage one carry
/// identical weight. It is written down because it is true of the measurement,
/// not because it tunes the estimate — and
/// `test/features/curriculum/curriculum_progress_test.dart` measures that the cap
/// binds, so nobody later believes this field is doing work it is not.
///
/// ## No self-expiry
///
/// [SkillEvidence.validUntil] is left null. The policy already discounts age
/// continuously through its measured 30-day recency half-life; adding a hard
/// expiry cliff on top would be a second, invented decay, and it would push
/// evidence into [SkillEstimateState.stale], which no gate accepts — a rung
/// would slam shut on a date rather than fade. The gradual fade is measured in
/// the progress test rather than assumed.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6). Both instants are passed in.
library;

import '../../practice_generator/public.dart'
    show
        EvidenceSource,
        OutcomeId,
        PerformanceEvidence,
        PracticeEvidenceRepository,
        SkillEvidence;
import 'course.dart';
import 'rhythm_grading.dart';
import 'skill_metrics.dart';

/// What the rhythm attempt actually measures, named so it can never be mistaken
/// for a chord, tone or timing measurement later.
const String rhythmDirectionAccuracyMetric = 'rhythm.directionAccuracy';

/// Version of this translator. Bump it when the arithmetic above changes, so an
/// older record stays identifiable as having been produced by older rules.
const int curriculumRhythmMeasurementVersion = 1;

/// The dedup key for one attempt's evidence about one skill (ADR 0260 §3).
///
/// Two adapters reporting the same attempt must agree on this, so it is derived
/// from the attempt's identity — its mission and the instant it was measured —
/// and never from a counter or a random id.
///
/// [skillId] is part of the key, and has to be: [PracticeEvidenceRepository]
/// stores strictly one record per `sourceOutcomeId`, so one attempt that trains
/// two skills and shares a single id would have its second record silently
/// overwrite the first — one skill's evidence would simply vanish. The existing
/// `analysis_evidence_adapter` carries its skill hint in the id for the same
/// reason.
OutcomeId rhythmAttemptOutcomeId({
  required String missionId,
  required String skillId,
  required DateTime measuredAt,
}) => OutcomeId(
  'curriculum.rhythm:$missionId:'
  '${measuredAt.toUtc().microsecondsSinceEpoch}:$skillId',
);

/// Evidence for every skill [mission] trains, or empty when this attempt may
/// claim nothing.
///
/// One record per trained DIRECTION skill. Chord skills of the same rung get
/// nothing here: they are measured by `gradeChords` on the same run and written by
/// `chordAttemptEvidence`.
List<SkillEvidence> rhythmAttemptEvidence({
  required CurriculumMission mission,
  required RhythmAttempt attempt,
  required DateTime measuredAt,
  required DateTime capturedAt,
}) {
  if (mission.rhythm == null) return const <SkillEvidence>[];
  if (!mission.isOutcomeMeasured) return const <SkillEvidence>[];
  if (mission.trainedSkillIds.isEmpty) return const <SkillEvidence>[];
  if (!attempt.isReportable) return const <SkillEvidence>[];
  final accuracy = attempt.directionAccuracy;
  if (accuracy == null) return const <SkillEvidence>[];

  // Sorted so the records come out in one order whatever order the set iterates
  // in — the reducer is order-independent, but a test that compares lists should
  // not have to be.
  final skillIds =
      mission.trainedSkillIds
          .where(
            (skillId) =>
                curriculumSkillMetric(skillId) ==
                CurriculumSkillMetric.strumDirection,
          )
          .toList(growable: false)
        ..sort();
  return [
    for (final skillId in skillIds)
      SkillEvidence(
        skillId: skillId,
        source: EvidenceSource.curriculum,
        sourceOutcomeId: rhythmAttemptOutcomeId(
          missionId: mission.missionId,
          skillId: skillId,
          measuredAt: measuredAt,
        ),
        measurementVersion: curriculumRhythmMeasurementVersion,
        measuredAt: measuredAt,
        capturedAt: capturedAt,
        confidence: attempt.coverage.clamp(0.0, 1.0),
        performance: PerformanceEvidence(
          metricCode: rhythmDirectionAccuracyMetric,
          value: accuracy,
          // How many observations this value summarises: the strokes that
          // produced confirmed evidence, not the strokes that were notated.
          sampleCount: attempt.heard,
        ),
      ),
  ];
}
