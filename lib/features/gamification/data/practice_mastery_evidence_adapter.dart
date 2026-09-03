import '../../practice/public.dart';
import '../domain/mastery/mastery_milestone.dart';
import '../domain/mastery/mastery_progress.dart';

/// Pure `PracticeHistoryEntry` → `MasteryEvidence` mapping (ADR 0500 §5.5).
///
/// No clock, no `Random`, no repository read — every value is derived from
/// [entry], [milestone] and [practiceCatalog] alone. Returns `null` (NOT a
/// zero-filled or "beginner-assumed" [MasteryEvidence]) whenever a value
/// this milestone needs is not measurable:
///
/// * the [milestone]'s skill has no available `PracticeMetricSnapshot`
///   dimension on this [entry] (`notApplicable`/`insufficientData`, or the
///   skill itself has no mapped dimension at all — `tempoStability`);
/// * [entry].definitionId does not resolve against [practiceCatalog] (an
///   unknown/removed definition — its difficulty cannot be measured).
///
/// [tempoBpm] is the resolved definition's `defaultTempo.bpm`, not the
/// tempo actually played: `PracticeHistoryEntry` does not retain that
/// (`highestStableTempoBpm` is Speed Builder's own peak-tempo field, not an
/// adherence measurement — §2). The v1 catalog's tempo ranges are wide
/// enough that this substitution excludes no evidence (§5.4).
MasteryEvidence? masteryEvidenceFromPracticeHistoryEntry({
  required PracticeHistoryEntry entry,
  required MasteryMilestone milestone,
  required List<PracticeDefinition> practiceCatalog,
}) {
  final dimension = _dimensionForSkill(
    milestone.skill,
    entry.finalMetricSnapshot,
  );
  if (dimension is! PracticeMetricDimensionAvailable) return null;

  final definition = _definitionById(practiceCatalog, entry.definitionId);
  if (definition == null) return null;

  return MasteryEvidence(
    sessionId: entry.id,
    origin: MasteryEvidenceOrigin.device,
    difficulty: _toMasteryDifficulty(definition.difficulty),
    tempoBpm: definition.defaultTempo.bpm,
    metricValue: dimension.value,
    observedAt: entry.createdAt.toUtc(),
  );
}

/// Maps every entry in [history] against [milestone], keeping only the
/// entries that produce measurable evidence (§5.5). Dedup across sessions
/// and monotonic progress are [MasteryEvaluator]'s responsibility, not
/// this adapter's — this function's only job is entry-to-evidence mapping.
List<MasteryEvidence> masteryEvidenceFromPracticeHistory({
  required Iterable<PracticeHistoryEntry> history,
  required MasteryMilestone milestone,
  required List<PracticeDefinition> practiceCatalog,
}) {
  final evidence = <MasteryEvidence>[];
  for (final entry in history) {
    final sample = masteryEvidenceFromPracticeHistoryEntry(
      entry: entry,
      milestone: milestone,
      practiceCatalog: practiceCatalog,
    );
    if (sample != null) evidence.add(sample);
  }
  return List.unmodifiable(evidence);
}

/// The `PracticeMetricSnapshot` dimension a milestone's skill measures
/// against, per the §5.4 table. `tempoStability` has none — the v1 catalog
/// ships no milestone for it (§5.4), and this mapping stays exhaustive
/// rather than guessing a dimension for a skill with no measured source.
PracticeMetricDimension? _dimensionForSkill(
  MasterySkill skill,
  PracticeMetricSnapshot snapshot,
) => switch (skill) {
  MasterySkill.chordTransition => snapshot.chord,
  MasterySkill.rhythmAccuracy => snapshot.rhythm,
  MasterySkill.strumConsistency => snapshot.direction,
  MasterySkill.tempoStability => null,
};

PracticeDefinition? _definitionById(
  List<PracticeDefinition> catalog,
  String definitionId,
) {
  for (final definition in catalog) {
    if (definition.id == definitionId) return definition;
  }
  return null;
}

/// 1:1 code mapping between the practice feature's authored difficulty and
/// the gamification domain's mastery difficulty — both enums share the same
/// stable `beginner`/`intermediate`/`advanced` codes by design.
MasteryDifficulty _toMasteryDifficulty(PracticeDifficulty difficulty) {
  for (final value in MasteryDifficulty.values) {
    if (value.code == difficulty.code) return value;
  }
  throw StateError('unmapped PracticeDifficulty code: ${difficulty.code}');
}
