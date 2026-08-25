import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// E13-R19 migration (brief §5.6): the time signature is now an "advanced"
/// setting behind the app-bar action, presented on a sheet — the main
/// surface keeps only BPM, the beat visualization and the transport.
Widget _app() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MetronomeScreen(),
);

void main() {
  testWidgets('shows the default tempo and transport on the main surface', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.text('100'), findsOneWidget); // default BPM
    expect(find.text('Start'), findsOneWidget);
    // The time signature moved to the advanced-settings sheet — not visible
    // on the main surface.
    expect(find.text('4/4'), findsNothing);
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

  testWidgets('Start toggles to Stop and back (ticker left stopped)', (
    tester,
  ) async {
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

  testWidgets('the advanced-settings sheet shows the time-signature options; '
      'selecting one updates the main surface', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    // The default (4/4) bar renders 4 beat dots on the main surface.
    expect(find.byType(AnimatedContainer), findsNWidgets(4));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);
    expect(find.text('6/4'), findsOneWidget);

    await tester.tap(find.text('6/4'));
    await tester.pumpAndSettle();

    // Close the sheet (tap the barrier) and confirm the selection stuck: the
    // main surface now renders 6 beat dots instead of 4.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('4/4'), findsNothing);
    expect(find.byType(AnimatedContainer), findsNWidgets(6));
  });
}
