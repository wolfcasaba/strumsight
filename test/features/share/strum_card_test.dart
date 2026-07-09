import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/widgets/strum_card.dart';

AnalyzeResult _result(int nStrums) => AnalyzeResult(
      durationSec: 12,
      bpm: 96,
      chords: const [
        TimelineChord(label: 'C', startSec: 0, endSec: 3),
        TimelineChord(label: 'G', startSec: 3, endSec: 6),
      ],
      strums: [
        for (var i = 0; i < nStrums; i++)
          TimelineStrum(
            direction: i.isEven ? StrumDirection.down : StrumDirection.up,
            timeSec: i.toDouble(),
            confidence: 0.9,
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, AnalyzeResult r, {int capo = 0}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: StrumCard(result: r, capo: capo))),
    ));

void main() {
  testWidgets('renders brand, chords and the strum-direction arrows',
      (tester) async {
    await _pump(tester, _result(4));
    expect(find.text('StrumSight'), findsOneWidget);
    expect(find.text('C · G'), findsOneWidget);
    // The moat visual: one arrow per strum (2 down, 2 up).
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));
    // Stat chips.
    expect(find.text('96'), findsOneWidget); // BPM value
    expect(find.text('DOWN ↓'), findsOneWidget);
    expect(find.text('UP ↑'), findsOneWidget);
  });

  testWidgets('caps the arrow row at 16 and marks truncation', (tester) async {
    await _pump(tester, _result(40));
    // 40 strums alternate down/up → capped at 16 shown (8 down, 8 up) + "…".
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(8));
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(8));
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('capo shifts the chord label on the card', (tester) async {
    await _pump(tester, _result(2), capo: 2);
    expect(find.text('A# · F'), findsOneWidget);
  });

  testWidgets('a strum-less result shows a graceful placeholder',
      (tester) async {
    await _pump(tester, AnalyzeResult.empty);
    expect(find.text('No strums detected'), findsOneWidget);
    expect(find.text('My riff'), findsOneWidget); // no chords → fallback
  });
}
