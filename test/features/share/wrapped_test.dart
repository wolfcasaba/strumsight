import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_entry.dart';
import 'package:music_theory/features/share/model/weekly_recap.dart';
import 'package:music_theory/features/share/share_content.dart';
import 'package:music_theory/features/share/widgets/wrapped_card.dart';

/// Round 151 — "Strum Wrapped" weekly recap (chunk 017 rec #5: the
/// Wrapped-style recap is the category's strongest install hook).
PracticeEntry _e(int day, int seconds,
        {int strokes = 0, double? accuracy}) =>
    PracticeEntry(
      day: day,
      source: PracticeSource.learn,
      seconds: seconds,
      strokes: strokes,
      directionAccuracy: accuracy,
    );

void main() {
  group('WeeklyRecap.fromEntries', () {
    test('rolls up exactly the trailing 7 days', () {
      final recap = WeeklyRecap.fromEntries([
        _e(93, 600), // 8 days ago — outside the window
        _e(94, 300, strokes: 40), // exactly 6 days back — inside
        _e(98, 240, strokes: 30, accuracy: 0.8),
        _e(100, 60, strokes: 10, accuracy: 0.6), // today
        _e(100, 120, strokes: 20),
      ], today: 100, streak: 4);

      expect(recap.minutes, 12); // (300+240+60+120)/60
      expect(recap.sessions, 4);
      expect(recap.strokes, 100);
      expect(recap.daysPracticed, 3);
      expect(recap.bestDay, 94, reason: '300 s is the biggest single day');
      expect(recap.averageAccuracy, closeTo(0.7, 1e-9));
      expect(recap.streak, 4);
      expect(recap.isEmpty, isFalse);
    });

    test('an empty week reports empty with null accuracy/bestDay', () {
      final recap = WeeklyRecap.fromEntries([_e(50, 600)], today: 100);
      expect(recap.isEmpty, isTrue);
      expect(recap.averageAccuracy, isNull);
      expect(recap.bestDay, isNull);
      expect(recap.minutes, 0);
    });
  });

  test('the caption carries the stats, moat and install link', () {
    final caption = ShareContent.wrappedCaption(
      minutes: 42,
      daysPracticed: 5,
      strokes: 980,
      streak: 6,
      averageAccuracy: 0.87,
    );
    expect(caption, contains('42 min'));
    expect(caption, contains('5/7 days'));
    expect(caption, contains('87%'));
    expect(caption, contains('6-day streak'));
    expect(caption, contains(ShareContent.installUrl));
    expect(caption, contains('#StrumSightChallenge'));
  });

  testWidgets('the card renders the recap values', (tester) async {
    const recap = WeeklyRecap(
      minutes: 42,
      sessions: 9,
      strokes: 980,
      daysPracticed: 5,
      bestDay: 100,
      averageAccuracy: 0.87,
      streak: 6,
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WrappedCard(recap: recap, weekLabel: 'Jul 6 – Jul 12'),
      ),
    ));
    expect(find.text('42'), findsOneWidget);
    expect(find.text('5/7'), findsOneWidget);
    expect(find.text('980'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.textContaining('6-day streak'), findsOneWidget);
    expect(find.text('Jul 6 – Jul 12'), findsOneWidget);
  });
}
