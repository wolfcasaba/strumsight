import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LearnScreen(lesson: Lessons.firstStrums),
    ));

void main() {
  testWidgets('starts paused and toggles play/pause without settling',
      (tester) async {
    await _pump(tester);

    // Starts paused → the Play control is shown, plus the lesson header.
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Chords'), findsOneWidget);
    expect(find.textContaining('BPM'), findsOneWidget);

    // Play → ticker runs; advance time manually (never pumpAndSettle a ticker).
    await tester.tap(find.text('Play'));
    await tester.pump(); // apply setState(_playing = true)
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    // Pause again to leave no active ticker at teardown.
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
  });
}
