import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/chord_shape.dart';
import 'package:music_theory/features/chords/screens/chord_library_screen.dart';
import 'package:music_theory/features/chords/widgets/chord_diagram.dart';
import 'package:music_theory/l10n/app_localizations.dart';

void main() {
  test('allLabels exposes the full catalogue', () {
    final labels = ChordShapes.allLabels;
    expect(labels, containsAll(['C', 'Am', 'G7', 'Asus4']));
    expect(labels.length, greaterThan(15));
  });

  testWidgets('the library groups shapes by type and renders diagrams',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChordLibraryScreen(),
      ),
    ));
    await tester.pump();

    expect(find.text('MAJOR'), findsOneWidget);
    expect(find.text('MINOR'), findsOneWidget);
    expect(find.byType(ChordDiagram), findsWidgets);
  });

  testWidgets('the search box filters the catalogue', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChordLibraryScreen(),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sus');
    await tester.pump();

    // Only the Suspended group survives the filter.
    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(find.text('MAJOR'), findsNothing);
    expect(find.text('MINOR'), findsNothing);
  });
}
