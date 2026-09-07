// R18 (audit B1/B2) — the goal categories the Practice Area Hub's chips
// navigate on. The chips used to open `/practice/setup` with NO `?id=`, so
// every one of them rendered the Setup screen's route-error branch. They now
// open the catalog filtered by these categories, which makes two properties
// load-bearing and therefore measured here:
//
//   * every built-in definition belongs to at least one category — otherwise
//     a definition would be listed by NO chip;
//   * `scales` is the one empty category, and that emptiness is a measured
//     fact about the shipped catalog, not an accident of the mapping.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/practice_category.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';

void main() {
  const catalog = BuiltinPracticeCatalog();

  test('the built-in catalog still has exactly ten definitions', () {
    expect(catalog.all(), hasLength(10));
  });

  test('every built-in definition is listed by at least one category', () {
    final uncovered = <String>[];
    for (final definition in catalog.all()) {
      final covered = PracticeCategory.values.any(
        (category) => category.matches(definition),
      );
      if (!covered) uncovered.add(definition.id);
    }
    expect(
      uncovered,
      isEmpty,
      reason:
          'these definitions would be reachable from no category chip: '
          '$uncovered',
    );
  });

  test('the union of every category is the whole catalog', () {
    final union = <String>{};
    for (final category in PracticeCategory.values) {
      for (final definition in category.filter(catalog.all())) {
        union.add(definition.id);
      }
    }
    expect(union, catalog.all().map((d) => d.id).toSet());
  });

  test('scales is the ONE empty category in the shipped catalog', () {
    final empty = <PracticeCategory>[];
    for (final category in PracticeCategory.values) {
      if (category.filter(catalog.all()).isEmpty) empty.add(category);
    }
    expect(empty, <PracticeCategory>[PracticeCategory.scales]);
  });

  test('filter keeps the catalog declaration order', () {
    final chords = PracticeCategory.chords.filter(catalog.all());
    expect(chords.map((d) => d.id).toList(), <String>[
      'builtin.gToDChanges.v1',
      'builtin.emToCChanges.v1',
      'builtin.cGAmFProgression.v1',
    ]);
  });

  test('filter returns an unmodifiable list', () {
    final rhythm = PracticeCategory.rhythm.filter(catalog.all());
    expect(() => rhythm.add(catalog.all().first), throwsUnsupportedError);
  });

  test('practiceCategoryFromCode round-trips every code and refuses to '
      'guess for anything else', () {
    for (final category in PracticeCategory.values) {
      expect(practiceCategoryFromCode(category.code), category);
    }
    expect(practiceCategoryFromCode(null), isNull);
    expect(practiceCategoryFromCode(''), isNull);
    expect(practiceCategoryFromCode('Chords'), isNull);
    expect(practiceCategoryFromCode('not-a-category'), isNull);
  });

  test('a definition with no known tag belongs to no category (the mapping '
      'never falls back to a catch-all)', () {
    final definition = catalog.all().first;
    final untagged = PracticeDefinition(
      id: 'test.untagged.v1',
      schemaVersion: definition.schemaVersion,
      titleKey: definition.titleKey,
      descriptionKey: definition.descriptionKey,
      mode: definition.mode,
      source: definition.source,
      meter: definition.meter,
      defaultTempo: definition.defaultTempo,
      totalBeats: definition.totalBeats,
      events: definition.events,
      scoringProfile: definition.scoringProfile,
      skillTags: const <String>['somethingNobodyMapped'],
    );
    for (final category in PracticeCategory.values) {
      expect(category.matches(untagged), isFalse, reason: category.name);
    }
  });
}
