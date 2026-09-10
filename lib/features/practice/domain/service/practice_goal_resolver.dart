import '../model/practice_definition.dart';
import '../model/practice_difficulty.dart';
import '../model/practice_mode.dart';

/// The Practice hub's "Browse by goal" categories (SDD Ch13 §UI-06).
enum PracticeGoal { warmup, chords, rhythm, scales, technique }

/// A goal the catalogue can actually serve, with the definition it opens.
final class PracticeGoalEntry {
  const PracticeGoalEntry({required this.goal, required this.definitionId});

  final PracticeGoal goal;
  final String definitionId;
}

/// Which built-in practice each hub goal opens — a pure lookup over the
/// catalogue (E18-R01 emulator finding F6).
///
/// The hub's goal chips used to navigate to the bare `/practice/setup` route
/// with no definition id, so every chip landed on "Practice unavailable".
/// There is no goal concept in the catalogue itself; the mapping is by
/// [PracticeMode] first (the catalogue's own taxonomy), by skill tag where a
/// mode does not exist (scales, technique). A goal with NO matching
/// definition is simply absent from the result — the hub then shows no chip
/// for it rather than a dead end.
///
/// Within a goal the easiest definition wins (beginner before intermediate
/// before advanced), catalogue order breaking ties — the same "first entry is
/// the recommendation" convention the hub's CTA relies on (ADR 0508 D3).
List<PracticeGoalEntry> resolvePracticeGoals(List<PracticeDefinition> catalog) {
  final entries = <PracticeGoalEntry>[];
  for (final goal in PracticeGoal.values) {
    final match = _easiest(catalog.where((d) => _serves(d, goal)));
    if (match != null) {
      entries.add(PracticeGoalEntry(goal: goal, definitionId: match.id));
    }
  }
  return List.unmodifiable(entries);
}

bool _serves(PracticeDefinition definition, PracticeGoal goal) {
  switch (goal) {
    case PracticeGoal.warmup:
      return definition.mode == PracticeMode.strumPattern &&
          definition.difficulty == PracticeDifficulty.beginner;
    case PracticeGoal.chords:
      return definition.mode == PracticeMode.chordChanges ||
          definition.mode == PracticeMode.chordProgression;
    case PracticeGoal.rhythm:
      return definition.mode == PracticeMode.rhythmOnly ||
          definition.skillTags.contains(_rhythmTag);
    case PracticeGoal.scales:
      return definition.skillTags.contains(_scalesTag);
    case PracticeGoal.technique:
      return definition.skillTags.contains(_techniqueTag);
  }
}

const String _rhythmTag = 'rhythm';
const String _scalesTag = 'scales';
const String _techniqueTag = 'technique';

PracticeDefinition? _easiest(Iterable<PracticeDefinition> candidates) {
  PracticeDefinition? best;
  for (final candidate in candidates) {
    if (best == null || candidate.difficulty.index < best.difficulty.index) {
      best = candidate;
    }
  }
  return best;
}
