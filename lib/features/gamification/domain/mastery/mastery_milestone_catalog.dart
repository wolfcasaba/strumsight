import 'mastery_milestone.dart';

/// The v1 mastery-milestone catalog (ADR 0500 §5.4) — the only measured
/// source for the Progress V2 dashboard's skill rows.
///
/// `final` + [List.unmodifiable], NOT `const`: [MasteryMilestone] and
/// [MasteryTempoRange] validate their arguments through a factory
/// constructor, and a factory cannot be invoked in a `const` context (their
/// `const` constructors are private).
///
/// Three beginner milestones, one per measurable [MasteryMilestone.skill] in
/// [PracticeMetricSnapshot]: `chordTransition` (`.chord`), `rhythmAccuracy`
/// (`.rhythm`), `strumConsistency` (`.direction`). `tempoStability` has NO
/// milestone in v1 — the fan has no measured `tempoAdherence` source (the
/// history only retains the Speed Builder's peak stable tempo, not an
/// adherence ratio); adding one here would be a fabricated measurement.
///
/// `difficulty` is `MasteryDifficulty.beginner` on all three, not a free
/// choice: the builtin practice catalog is 8 `beginner` / 2 `intermediate`
/// definitions (`builtin_practice_catalog.dart`), and
/// `MasteryEvaluator._qualifyingSessions` drops evidence whose difficulty
/// does not match the milestone's — an `intermediate` milestone here would
/// silently discard the 8 `beginner` sessions that are the catalog's actual
/// measured majority.
///
/// `tempoRange` is `40..240` BPM: every builtin definition's `defaultTempo`
/// falls inside `60..90`, so this range excludes no measured evidence while
/// staying a real (not degenerate) bound.
final List<MasteryMilestone> masteryMilestoneCatalogV1 =
    List.unmodifiable(<MasteryMilestone>[
      MasteryMilestone(
        id: 'mastery_chord_transition_v1',
        catalogVersion: 1,
        skill: MasterySkill.chordTransition,
        metric: MasteryMetric.accuracy,
        minimumThreshold: 0.8,
        difficulty: MasteryDifficulty.beginner,
        tempoRange: MasteryTempoRange(minBpm: 40, maxBpm: 240),
        minEvidenceSessions: 3,
        titleKey: 'masteryChordTransitionTitle',
        descriptionKey: 'masteryChordTransitionDescription',
      ),
      MasteryMilestone(
        id: 'mastery_rhythm_accuracy_v1',
        catalogVersion: 1,
        skill: MasterySkill.rhythmAccuracy,
        metric: MasteryMetric.accuracy,
        minimumThreshold: 0.8,
        difficulty: MasteryDifficulty.beginner,
        tempoRange: MasteryTempoRange(minBpm: 40, maxBpm: 240),
        minEvidenceSessions: 3,
        titleKey: 'masteryRhythmAccuracyTitle',
        descriptionKey: 'masteryRhythmAccuracyDescription',
      ),
      MasteryMilestone(
        id: 'mastery_strum_consistency_v1',
        catalogVersion: 1,
        skill: MasterySkill.strumConsistency,
        metric: MasteryMetric.accuracy,
        minimumThreshold: 0.8,
        difficulty: MasteryDifficulty.beginner,
        tempoRange: MasteryTempoRange(minBpm: 40, maxBpm: 240),
        minEvidenceSessions: 3,
        titleKey: 'masteryStrumConsistencyTitle',
        descriptionKey: 'masteryStrumConsistencyDescription',
      ),
    ]);
