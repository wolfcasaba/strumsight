import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/theme/app_colors.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/lesson_score_preview_screen.dart';
import 'package:music_theory/features/learn/widgets/lesson_score_card.dart';
import 'package:music_theory/features/share/share_content.dart';
import 'package:music_theory/features/share/share_service.dart';
import 'package:music_theory/l10n/app_localizations.dart';

class _FakeShareService extends ShareService {
  const _FakeShareService(this.log);
  final List<String> log;

  @override
  Future<void> shareImage({
    required GlobalKey boundaryKey,
    required String caption,
    required String fileName,
    String? fallbackText,
    Rect? sharePositionOrigin,
  }) async =>
      log.add('$fileName::$caption');
}

void main() {
  test('lessonCaption carries score, stars, moat and install link', () {
    final c = ShareContent.lessonCaption(
      lessonName: 'Down-Up Groove',
      accuracy: 0.92,
      stars: 3,
      maxCombo: 14,
    );
    expect(c, contains('Down-Up Groove'));
    expect(c, contains('92%'));
    expect(c, contains('⭐⭐⭐'));
    expect(c, contains('14'));
    expect(c, contains(ShareContent.installUrl));
    expect(c, contains('#StrumSightChallenge'));
  });

  testWidgets('score card shows the lesson, accuracy, stars and stats',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: LessonScoreCard(
            lessonName: 'Funk Chop',
            accuracy: 0.8,
            stars: 2,
            maxCombo: 9,
            hits: 12,
            total: 15,
          ),
        ),
      ),
    ));
    expect(find.text('Funk Chop'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('12/15'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(2)); // 2 filled stars
  });

  testWidgets('score % colour follows the confidence ramp, not always green',
      (tester) async {
    Color scoreColor(WidgetTester t) => t
        .widget<Text>(find.textContaining('%').first)
        .style!
        .color!;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LessonScoreCard(
          lessonName: 'L',
          accuracy: 0.0,
          stars: 0,
          maxCombo: 0,
          hits: 0,
          total: 16,
        ),
      ),
    ));
    expect(scoreColor(tester), AppColors.confidence(0.0),
        reason: 'a failing score must not render in the success green');

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LessonScoreCard(
          lessonName: 'L',
          accuracy: 0.9,
          stars: 3,
          maxCombo: 9,
          hits: 14,
          total: 16,
        ),
      ),
    ));
    expect(scoreColor(tester), AppColors.confidence(0.9));
  });

  testWidgets('preview shares the score card image on tap', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LessonScorePreviewScreen(
        lesson: Lessons.downUpGroove,
        accuracy: 0.85,
        maxCombo: 11,
        hits: 10,
        total: 12,
        shareService: _FakeShareService(log),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LessonScoreCard), findsOneWidget);
    await tester.tap(find.text('Share card'));
    await tester.pumpAndSettle();
    expect(log, hasLength(1));
    expect(log.first, contains('strumsight-score-down-up-groove.png'));
    expect(log.first, contains('85%'));
  });
}
