import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/widgets/lesson_highway.dart';
import 'package:music_theory/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Lesson lesson, double playhead) =>
    tester.pumpWidget(MaterialApp(
      // LessonHighway reads AppLocalizations for its a11y semantics label, so
      // the delegates must be present (production always has them via the app
      // shell) — otherwise AppLocalizations.of(context) is null.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: LessonHighway(lesson: lesson, playheadBeat: playhead),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('renders the chord + a direction arrow for a visible event',
      (tester) async {
    // downUpGroove: first event is beat 0, chord C, downstroke.
    await _pump(tester, Lessons.downUpGroove, 0);
    expect(find.text('C'), findsWidgets); // the chord card at/near the strike
    expect(find.byIcon(Icons.arrow_downward), findsWidgets);
  });

  testWidgets('far-future events are not laid out (windowed)', (tester) async {
    // At playhead 0 the last-bar F chord (beat 12+) is off-screen.
    await _pump(tester, Lessons.downUpGroove, 0);
    expect(find.text('F'), findsNothing);

    // Scrub to the last bar → F becomes visible, early C gone.
    await _pump(tester, Lessons.downUpGroove, 12);
    expect(find.text('F'), findsWidgets);
  });

  testWidgets('a mid-play playhead shows up-stroke arrows too', (tester) async {
    await _pump(tester, Lessons.downUpGroove, 1.5);
    expect(find.byIcon(Icons.arrow_upward), findsWidgets);
  });

  test('background painter repaints only when the playhead/geometry changes',
      () {
    HighwayBackgroundPainter p(double playhead) => HighwayBackgroundPainter(
          playheadBeat: playhead,
          pxPerBeat: 40,
          strikeX: 68,
          beatsVisibleAhead: 4,
          beatsPerBar: 4,
        );
    expect(p(1).shouldRepaint(p(1)), isFalse);
    expect(p(1).shouldRepaint(p(1.5)), isTrue);
  });
}
