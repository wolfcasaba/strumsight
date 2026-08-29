import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/chords/chord_shape.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/chords/widgets/chord_diagram.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

void main() {
  test('allLabels exposes the full catalogue', () {
    final labels = ChordShapes.allLabels;
    expect(labels, containsAll(['C', 'Am', 'G7', 'Asus4']));
    expect(labels.length, greaterThan(15));
  });

  testWidgets('the library groups shapes by type and renders diagrams', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChordLibraryScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MAJOR'), findsOneWidget);
    expect(find.text('MINOR'), findsOneWidget);
    expect(find.byType(ChordDiagram), findsWidgets);
  });

  testWidgets('the search box filters the catalogue', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChordLibraryScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sus');
    await tester.pump();

    // Only the Suspended group survives the filter.
    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(find.text('MAJOR'), findsNothing);
    expect(find.text('MINOR'), findsNothing);
  });

  testWidgets('a search with no matches shows an empty state, not a blank '
      'screen (round 133)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChordLibraryScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();

    expect(find.textContaining('No chords match'), findsOneWidget);
    expect(find.byType(ChordDiagram), findsNothing);
    // No stray group headers either.
    expect(find.text('MAJOR'), findsNothing);
  });

  // A6 (ADR 0282 §6, §0.0/R10) — the practice action must start with the
  // OPENED chord, never the library's first entry.
  testWidgets('the practice action from a chord\'s detail view opens a '
      'lesson built around THAT chord', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChordLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chord-open-detail-G')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chord-detail-practice-action')));
    await tester.pumpAndSettle();

    final learnScreen = tester.widget<LearnScreen>(find.byType(LearnScreen));
    expect(learnScreen.lesson.chordSequence, ['G']);
  });

  // A7 (§3/§5.6) — opening and closing a chord's detail view must not reset
  // the library's search/filter state underneath it.
  testWidgets('the search query survives opening and closing a chord\'s '
      'detail view', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChordLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sus');
    await tester.pump();
    expect(find.text('SUSPENDED'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chord-open-detail-Asus4')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('sus'), findsOneWidget); // the TextField kept its value
    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(find.text('MAJOR'), findsNothing);
  });
}
