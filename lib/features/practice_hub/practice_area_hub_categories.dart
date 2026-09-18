import '../practice/public.dart'
    show PracticeDefinition, PracticeDifficulty, PracticeMode;

/// The "Browse by goal" groups the Practice Area Hub (UI-06) shows.
///
/// A goal is derived from the definition itself (its [PracticeMode] and
/// [PracticeDefinition.skillTags]) — the hub never carries a hand-written
/// id → goal table, so a new catalog entry lands in a group without a hub
/// edit. A group with no definition is simply not rendered: a tappable
/// heading that leads nowhere is the dead end this file replaces.
enum PracticeAreaHubCategory { warmup, chords, rhythm, scales, technique }

/// Skill tags that pull a definition into a goal ahead of its mode. The
/// built-in catalog has no scale/technique entries yet; these tags are the
/// contract a future entry uses to land in those groups.
const _scaleTags = <String>{'scale', 'scales', 'pentatonic', 'fretboard'};
const _techniqueTags = <String>{
  'technique',
  'hammerOn',
  'pullOff',
  'slide',
  'bend',
  'fingerpicking',
  'muting',
};

/// The goal group [definition] belongs to.
PracticeAreaHubCategory practiceAreaHubCategoryOf(
  PracticeDefinition definition,
) {
  final tags = definition.skillTags;
  if (tags.any(_scaleTags.contains)) return PracticeAreaHubCategory.scales;
  if (tags.any(_techniqueTags.contains)) {
    return PracticeAreaHubCategory.technique;
  }
  switch (definition.mode) {
    case PracticeMode.rhythmOnly:
    case PracticeMode.freePractice:
      return PracticeAreaHubCategory.warmup;
    case PracticeMode.chordChanges:
    case PracticeMode.chordProgression:
      return PracticeAreaHubCategory.chords;
    case PracticeMode.strumPattern:
      return PracticeAreaHubCategory.rhythm;
  }
}

/// The catalog split into goal groups, in [PracticeAreaHubCategory] order,
/// each group keeping the catalog's own order and sorted beginner-first so
/// the easiest entry of a goal is the first thing a learner sees. Empty
/// groups are omitted.
List<MapEntry<PracticeAreaHubCategory, List<PracticeDefinition>>>
practiceAreaHubGroups(List<PracticeDefinition> catalog) {
  final groups = <PracticeAreaHubCategory, List<PracticeDefinition>>{};
  for (final definition in catalog) {
    groups
        .putIfAbsent(
          practiceAreaHubCategoryOf(definition),
          () => <PracticeDefinition>[],
        )
        .add(definition);
  }
  return [
    for (final category in PracticeAreaHubCategory.values)
      if (groups[category] case final definitions?)
        MapEntry(category, _stableSortedByDifficulty(definitions)),
  ];
}

List<PracticeDefinition> _stableSortedByDifficulty(
  List<PracticeDefinition> definitions,
) {
  final indexed = definitions.asMap().entries.toList()
    ..sort((a, b) {
      final byDifficulty = _difficultyRank(
        a.value.difficulty,
      ).compareTo(_difficultyRank(b.value.difficulty));
      if (byDifficulty != 0) return byDifficulty;
      return a.key.compareTo(b.key);
    });
  return [for (final entry in indexed) entry.value];
}

int _difficultyRank(PracticeDifficulty difficulty) => switch (difficulty) {
  PracticeDifficulty.beginner => 0,
  PracticeDifficulty.intermediate => 1,
  PracticeDifficulty.advanced => 2,
};
