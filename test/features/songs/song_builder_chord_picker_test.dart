// Audit U5 — the Song Builder's "add a chord" picker was one unstructured
// grid of every shape the app has a diagram for (33 chips, no order a player
// could reason about, no way to look one up). It is grouped by quality with
// localized headers now, behind a case-insensitive label filter — the same
// structure the Chord library already uses.
//
// The grouping must stay TOTAL: every label in `ChordShapes.allLabels` lands
// in exactly one group, so the picker never needs an "other" bucket and no
// chord can silently disappear from the builder. Chip labels are unchanged,
// which is what keeps `song_flow_test.dart`'s chip finders working.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:strumsight/features/chords/chord_shape.dart';
import 'package:strumsight/features/songs/screens/song_builder_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _filterKey = Key('song-builder-chord-filter');

/// A viewport tall enough for the whole builder to be laid out at once — the
/// picker lives inside a `ListView`, which only builds what is near the
/// viewport, and these cells assert over ALL of its chips.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SongBuilderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The chord chips currently rendered by the picker. Filtered against
/// `ChordShapes.allLabels` so the builder's other `ActionChip`s (the strum
/// pattern presets) never leak into the assertion.
List<String> _chordChipLabels(WidgetTester tester) {
  final labels = <String>[];
  for (final chip in tester.widgetList<ActionChip>(find.byType(ActionChip))) {
    final label = chip.label;
    if (label is! Text) continue;
    final data = label.data;
    if (data == null || !ChordShapes.allLabels.contains(data)) continue;
    labels.add(data);
  }
  return labels;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the picker renders a header per quality group and every chord '
      'exactly once under one of them', (tester) async {
    await _pump(tester);

    for (final header in const ['MAJOR', 'MINOR', 'SEVENTHS', 'SUSPENDED']) {
      expect(
        find.text(header),
        findsOneWidget,
        reason: '$header group header must render above its chips',
      );
    }

    final labels = _chordChipLabels(tester);
    expect(
      labels..sort(),
      equals([...ChordShapes.allLabels]..sort()),
      reason:
          'the grouping is total: no chord may be dropped, and none may be '
          'rendered twice',
    );
  });

  testWidgets('typing in the filter narrows the picker to matching labels', (
    tester,
  ) async {
    await _pump(tester);
    final all = _chordChipLabels(tester);
    final expected = all.where((l) => l.toLowerCase().contains('m')).toList();
    expect(expected, isNotEmpty);
    expect(
      expected.length,
      lessThan(all.length),
      reason: 'the fixture must actually be narrowed by this query',
    );

    await tester.enterText(find.byKey(_filterKey), 'm');
    await tester.pumpAndSettle();

    final shown = _chordChipLabels(tester);
    expect(shown..sort(), equals([...expected]..sort()));
    // Case-insensitive: an upper-case query narrows to the same set.
    await tester.enterText(find.byKey(_filterKey), 'M');
    await tester.pumpAndSettle();
    expect(_chordChipLabels(tester)..sort(), equals([...expected]..sort()));
  });

  testWidgets('a query that matches nothing says so instead of going blank', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(_filterKey), 'zzz');
    await tester.pumpAndSettle();

    expect(_chordChipLabels(tester), isEmpty);
    // The message names the query — `textContaining('No chords match')`
    // rather than the query itself, which the filter field also renders.
    expect(find.textContaining('No chords match'), findsOneWidget);
  });

  testWidgets('a grouped chip still adds its chord to the progression', (
    tester,
  ) async {
    await _pump(tester);
    // Filter first so the tapped chip is unambiguous and on screen.
    await tester.enterText(find.byKey(_filterKey), 'Am7');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Am7'));
    await tester.pumpAndSettle();

    // The added chord appears as a removable InputChip in the progression.
    expect(find.widgetWithText(InputChip, 'Am7'), findsOneWidget);
  });
}
