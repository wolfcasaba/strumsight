// E15-R08 — dedicated AchievementDetailScreen coverage. `achievements_screen_test.dart`
// already pins the A2/A4/A6 data-shape cells (evidence, not-found); this file
// closes the §0.0.A/R4 G2 gap: the migrated screen had no dedicated file and
// no phone-viewport A3 measurement. §0.0.A/R5: the cells below use the exact
// 360x640 phone viewport, not the flutter_test 800x600 default — the wider
// default can report "no overflow" on a tree that would clip on a real
// device (L558).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_definition.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_progress.dart';
import 'package:strumsight/features/gamification/presentation/screens/achievement_detail_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

AchievementDefinition _definition({
  required String id,
  String keyStem = 'achievementPracticeStarter',
  AchievementCategory category = AchievementCategory.practice,
  bool hidden = false,
}) => AchievementDefinition(
  id: id,
  category: category,
  titleKey: '${keyStem}Title',
  descriptionKey: '${keyStem}Description',
  accessibilityDescriptionKey: '${keyStem}Semantics',
  objectives: <AchievementObjective>[
    CountAchievementObjective(
      eventKind: AchievementEventKind.practice,
      target: 1,
    ),
  ],
  tierPrerequisiteIds: const [],
  hidden: hidden,
  version: 1,
  deprecated: false,
);

AchievementProgress _progress(String id, num value, {DateTime? completedAt}) =>
    AchievementProgress(
      achievementId: id,
      catalogVersion: 1,
      value: value,
      completedAt: completedAt,
      rewardLedgerEntryId: completedAt == null ? null : 'achievement:$id:1',
    );

Future<void> _pump(
  WidgetTester tester, {
  required String achievementId,
  List<AchievementDefinition>? definitions,
  Map<String, AchievementProgress>? progress,
  AchievementEvidence? evidence,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: AchievementDetailScreen(
        achievementId: achievementId,
        definitions:
            definitions ??
            <AchievementDefinition>[_definition(id: 'practice_starter')],
        progressByAchievement:
            progress ??
            <String, AchievementProgress>{
              'practice_starter': _progress('practice_starter', 0.6),
            },
        evidence: evidence,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — the screen imports the design system for its content card', () {
    testWidgets('the evidence panel renders inside an SsCard surface', (
      tester,
    ) async {
      await _pump(
        tester,
        achievementId: 'practice_starter',
        evidence: AchievementEvidence(
          reason: AchievementEvidenceReasonCode.measuredProgress,
          current: 3,
          target: 5,
        ),
      );

      expect(find.text('Measured progress: 3 of 5.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('A2 — not-found and hidden states are token-styled, not raw text', () {
    testWidgets('unknown id renders the not-found message without a crash', (
      tester,
    ) async {
      await _pump(tester, achievementId: 'missing');
      expect(find.text('Achievement not found'), findsOneWidget);
      expect(find.byIcon(Icons.search_off_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a locked hidden achievement renders the hidden message', (
      tester,
    ) async {
      final hidden = _definition(
        id: 'balanced_practice_week',
        keyStem: 'achievementBalancedPracticeWeek',
        category: AchievementCategory.consistency,
        hidden: true,
      );
      await _pump(
        tester,
        achievementId: hidden.id,
        definitions: <AchievementDefinition>[hidden],
        progress: <String, AchievementProgress>{
          hidden.id: _progress(hidden.id, 0.4),
        },
      );
      expect(find.text('A secret achievement'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('A3 — phone viewport (360x640), textScaler 1.5/2.0/2.5, en+hu', () {
    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          '$scale / ${locale.languageCode} — detail content, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pump(
              tester,
              achievementId: 'practice_starter',
              evidence: AchievementEvidence(
                reason: AchievementEvidenceReasonCode.measuredProgress,
                current: 3,
                target: 5,
              ),
              locale: locale,
              textScale: scale,
            );

            expect(find.byType(ListView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          '$scale / ${locale.languageCode} — not-found state, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pump(
              tester,
              achievementId: 'missing',
              locale: locale,
              textScale: scale,
            );

            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          '$scale / ${locale.languageCode} — hidden state, no overflow '
          '(m1)',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final hidden = _definition(
              id: 'balanced_practice_week',
              keyStem: 'achievementBalancedPracticeWeek',
              category: AchievementCategory.consistency,
              hidden: true,
            );

            await _pump(
              tester,
              achievementId: hidden.id,
              definitions: <AchievementDefinition>[hidden],
              progress: <String, AchievementProgress>{
                hidden.id: _progress(hidden.id, 0.4),
              },
              locale: locale,
              textScale: scale,
            );

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
