import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/metronome/screens/metronome_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';

Widget _app() => const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MetronomeScreen(),
    );

void main() {
  testWidgets('shows the default tempo and time-signature options',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.text('100'), findsOneWidget); // default BPM
    expect(find.text('4/4'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the ± buttons nudge the BPM', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('101'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('Start toggles to Stop and back (ticker left stopped)',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Stop'), findsOneWidget);
    // Stop again so no ticker is active at teardown.
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Start'), findsOneWidget);
  });
}
