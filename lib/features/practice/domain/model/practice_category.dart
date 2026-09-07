import 'practice_definition.dart';

/// A goal-shaped grouping over the practice catalog.
///
/// This is a PRESENTATION category derived from a definition's own declared
/// [PracticeDefinition.skillTags] — not a pedagogical claim about the
/// exercise, and not a new field on the catalog. It mirrors the same
/// tag-driven mapping the tutor already uses for its plan blocks
/// (`tutor_practice_plan_producer.dart`'s `tutorBlockTypeFor`), so a
/// retagged definition moves category by itself and the two surfaces cannot
/// drift into two different meanings of "chords".
///
/// [scales] currently matches NO built-in definition: the shipped catalog
/// has no scale content. That is deliberately expressed as an empty
/// [filter] result — the catalog list then renders its own "nothing here"
/// copy — rather than as a category that navigates into a route error.
enum PracticeCategory {
  warmup('warmup'),
  chords('chords'),
  rhythm('rhythm'),
  scales('scales'),
  technique('technique');

  const PracticeCategory(this.code);

  /// Stable identifier used in the `?category=` query parameter of the
  /// catalog route, independent of enum order.
  final String code;

  /// The skill tags that place a definition in this category.
  Set<String> get skillTags => switch (this) {
    PracticeCategory.warmup => const {'downstrokes'},
    PracticeCategory.chords => const {'chordChanges', 'chordProgression'},
    PracticeCategory.rhythm => const {
      'rhythm',
      'quarterNotes',
      'eighthNotes',
      'rhythmOnly',
    },
    PracticeCategory.scales => const {'scales'},
    PracticeCategory.technique => const {
      'upstrokes',
      'syncopation',
      'freePlay',
    },
  };

  /// Whether [definition] belongs to this category.
  ///
  /// Categories deliberately OVERLAP (a quarter-note downstroke exercise is
  /// both a warm-up and a rhythm exercise); the union of every category
  /// except [scales] covers the whole built-in catalog, which is pinned by
  /// `practice_category_test.dart`.
  bool matches(PracticeDefinition definition) {
    final tags = skillTags;
    for (final tag in definition.skillTags) {
      if (tags.contains(tag)) return true;
    }
    return false;
  }

  /// The definitions of [definitions] that belong to this category, in the
  /// catalog's own declaration order.
  List<PracticeDefinition> filter(List<PracticeDefinition> definitions) {
    return List<PracticeDefinition>.unmodifiable([
      for (final definition in definitions)
        if (matches(definition)) definition,
    ]);
  }
}

/// Resolves a stable code without guessing a fallback — an unknown or
/// missing code means "no category filter", never a silently wrong one.
PracticeCategory? practiceCategoryFromCode(String? code) {
  if (code == null) return null;
  for (final value in PracticeCategory.values) {
    if (value.code == code) return value;
  }
  return null;
}
