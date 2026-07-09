import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/learn/widgets/lesson_highway.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/screens/strum_reel_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';

final _result = AnalyzeResult(
  durationSec: 4,
  bpm: 100,
  chords: const [
    TimelineChord(label: 'C', startSec: 0, endSec: 2),
    TimelineChord(label: 'G', startSec: 2, endSec: 4),
  ],
  strums: [
    for (var i = 0; i < 6; i++)
      TimelineStrum(
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        timeSec: i * 0.5,
        confidence: 1,
      ),
  ],
);

void main() {
  testWidgets('the reel renders branded and animates the recording',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(result: _result),
    ));
    await tester.pump();

    // Branded + shows the chords + the animated highway.
    expect(find.text('StrumSight'), findsOneWidget);
    expect(find.text('C · G'), findsOneWidget);
    expect(find.byType(LessonHighway), findsOneWidget);
    expect(find.textContaining('#StrumSightChallenge'), findsOneWidget);

    // It advances (looping ticker); drive time manually, never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // Tap to pause so no active ticker survives to teardown.
    await tester.tap(find.byType(LessonHighway));
    await tester.pump();
  });
}
