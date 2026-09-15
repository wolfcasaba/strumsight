import '../model/next_practice_recommendation.dart';
import '../model/practice_definition.dart';
import '../model/practice_difficulty.dart';
import '../model/practice_history_entry.dart';

/// Target coverage (resolved / total) at or above which a session counts as
/// "cleared"; below it the same definition is recommended once more.
const double nextPracticeConsolidationCoverage = 0.7;

/// Picks the next practice from [catalog] given the learner's [history]
/// (any order) and, optionally, the [latest] entry that may not be in the
/// persisted history yet (the result screen holds the session it just
/// finished before the history list reloads).
///
/// Pure and deterministic: no clock, no I/O, no randomness. Returns `null`
/// only for an empty catalog. A history entry whose definition is no longer
/// in the catalog never yields a recommendation for it — the catalog is the
/// only source of playable definitions.
NextPracticeRecommendation? recommendNextPractice({
  required List<PracticeDefinition> catalog,
  required List<PracticeHistoryEntry> history,
  PracticeHistoryEntry? latest,
}) {
  if (catalog.isEmpty) return null;
  final ordered = _easiestFirst(catalog);
  final byId = {for (final definition in catalog) definition.id: definition};

  final entries = <PracticeHistoryEntry>[
    ...history,
    if (latest != null && !history.any((e) => e.id == latest.id)) latest,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  if (entries.isEmpty) {
    return NextPracticeRecommendation(
      definition: ordered.first,
      reason: NextPracticeReason.firstSession,
    );
  }

  final last = entries.first;
  final lastDefinition = byId[last.definitionId];
  final lastCoverage = _coverage(last);
  if (lastDefinition != null &&
      lastCoverage != null &&
      lastCoverage < nextPracticeConsolidationCoverage) {
    return NextPracticeRecommendation(
      definition: lastDefinition,
      reason: NextPracticeReason.repeatToConsolidate,
      basedOn: last,
    );
  }

  final played = {for (final entry in entries) entry.definitionId};
  for (final definition in ordered) {
    if (!played.contains(definition.id)) {
      return NextPracticeRecommendation(
        definition: definition,
        reason: NextPracticeReason.advance,
        basedOn: last,
      );
    }
  }

  // Everything played at least once: the weakest most-recent coverage.
  // Entries are newest-first, so the first hit per definition is its
  // latest session.
  PracticeDefinition? weakest;
  PracticeHistoryEntry? weakestEntry;
  double? weakestCoverage;
  final seen = <String>{};
  for (final entry in entries) {
    if (!seen.add(entry.definitionId)) continue;
    final definition = byId[entry.definitionId];
    if (definition == null) continue;
    final coverage = _coverage(entry) ?? 1.0;
    if (weakestCoverage == null || coverage < weakestCoverage) {
      weakest = definition;
      weakestEntry = entry;
      weakestCoverage = coverage;
    }
  }
  return NextPracticeRecommendation(
    definition: weakest ?? ordered.first,
    reason: NextPracticeReason.revisitWeakest,
    basedOn: weakestEntry ?? last,
  );
}

/// `null` when the session scored no targets at all (free practice, or an
/// aborted session) — such a session neither passes nor fails.
double? _coverage(PracticeHistoryEntry entry) {
  if (entry.totalTargets <= 0) return null;
  return entry.resolvedTargets / entry.totalTargets;
}

/// Stable sort by difficulty (beginner first), catalog order within a tier.
List<PracticeDefinition> _easiestFirst(List<PracticeDefinition> catalog) {
  final indexed = catalog.asMap().entries.toList()
    ..sort((a, b) {
      final byDifficulty = _rank(
        a.value.difficulty,
      ).compareTo(_rank(b.value.difficulty));
      if (byDifficulty != 0) return byDifficulty;
      return a.key.compareTo(b.key);
    });
  return [for (final entry in indexed) entry.value];
}

int _rank(PracticeDifficulty difficulty) => switch (difficulty) {
  PracticeDifficulty.beginner => 0,
  PracticeDifficulty.intermediate => 1,
  PracticeDifficulty.advanced => 2,
};
