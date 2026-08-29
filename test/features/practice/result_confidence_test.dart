// E13-R22 — A1 (confidence gate, three-cell mátrix), A2 (partial session),
// A7 (executable, correctly-parameterized next step), A8 (minimal share
// projection).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/presentation/practice_route_args.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

AppLocalizations l10n() => AppLocalizationsEn();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpResult(
    WidgetTester tester,
    PracticeHistoryEntry entry,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PracticeResultScreen(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder anyPercentText() => find.byWidgetPredicate(
    (w) => w is Text && w.data != null && w.data!.contains('%'),
  );

  group(
    'A1 — the confidence three-cell mátrix (§6.1, threshold 0.60 inclusive)',
    () {
      testWidgets(
        'below threshold — 9/20 = 0.45 — no categorical percentage anywhere',
        (tester) async {
          final entry = _entry(resolvedTargets: 9, totalTargets: 20);
          await pumpResult(tester, entry);

          expect(
            find.text(l10n().practiceResultConfidenceLowTitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n().practiceResultConfidenceLowBody(9, 20)),
            findsOneWidget,
          );
          expect(find.text(l10n().practiceResultBreakdownTitle), findsNothing);
          expect(anyPercentText(), findsNothing);
        },
      );

      testWidgets(
        'AT threshold — 12/20 = 0.60 — categorical, inclusive boundary '
        '(falsification edge: a strict ">" would fail this cell)',
        (tester) async {
          final entry = _entry(resolvedTargets: 12, totalTargets: 20);
          await pumpResult(tester, entry);

          expect(
            find.text(l10n().practiceResultConfidenceLowTitle),
            findsNothing,
          );
          expect(
            find.text(l10n().practiceResultBreakdownTitle),
            findsOneWidget,
          );
          expect(anyPercentText(), findsWidgets);
        },
      );

      testWidgets('above threshold — 17/20 = 0.85 — categorical', (
        tester,
      ) async {
        final entry = _entry(resolvedTargets: 17, totalTargets: 20);
        await pumpResult(tester, entry);

        expect(
          find.text(l10n().practiceResultConfidenceLowTitle),
          findsNothing,
        );
        expect(find.text(l10n().practiceResultBreakdownTitle), findsOneWidget);
        expect(anyPercentText(), findsWidgets);
      });
    },
  );

  group('A2 — partial vs. full session, derived from finishReasonCode', () {
    testWidgets('completedAllTargets — no partial badge', (tester) async {
      final entry = _entry(
        resolvedTargets: 20,
        totalTargets: 20,
        finishReasonCode: 'completedAllTargets',
      );
      await pumpResult(tester, entry);

      expect(find.text(l10n().practiceResultPartialBadge), findsNothing);
    });

    testWidgets('interrupted — the partial badge renders', (tester) async {
      final entry = _entry(
        resolvedTargets: 12,
        totalTargets: 20,
        finishReasonCode: 'interrupted',
      );
      await pumpResult(tester, entry);

      expect(find.text(l10n().practiceResultPartialBadge), findsOneWidget);
    });

    testWidgets('userFinished — also partial (ended before every target)', (
      tester,
    ) async {
      final entry = _entry(
        resolvedTargets: 20,
        totalTargets: 20,
        finishReasonCode: 'userFinished',
      );
      await pumpResult(tester, entry);

      expect(find.text(l10n().practiceResultPartialBadge), findsOneWidget);
    });
  });

  group('A7 — the next step is a button, correctly parameterized', () {
    testWidgets(
      'tapping "Practice again" pushes Setup pre-loaded with the SAME '
      'definitionId',
      (tester) async {
        final entry = _entry(
          resolvedTargets: 17,
          totalTargets: 20,
          definitionId: 'def-xyz',
        );
        await pumpResult(tester, entry);

        final cta = find.text(l10n().practiceResultNextStepCta);
        expect(cta, findsOneWidget);
        await tester.tap(cta);
        await tester.pumpAndSettle();

        final setupFinder = find.byType(PracticeSetupScreen);
        expect(setupFinder, findsOneWidget);
        final setup = tester.widget<PracticeSetupScreen>(setupFinder);
        expect(setup.argsOverride, isNotNull);
        expect(setup.argsOverride!.request, PracticeSetupRequest.hasId);
        expect(setup.argsOverride!.definitionId, 'def-xyz');
      },
    );
  });

  group('A8 — the share action carries only the minimal projection', () {
    testWidgets(
      'the revealed summary shows the session id/title/mode/date/result, '
      'and never the raw skill tags (a field the projection excludes)',
      (tester) async {
        final entry = _entry(
          resolvedTargets: 17,
          totalTargets: 20,
          id: 'share-session-9',
          skillTags: const ['unexported-secret-skill-tag'],
        );
        await pumpResult(tester, entry);

        expect(
          find.text('unexported-secret-skill-tag'),
          findsNothing,
          reason: 'skill tags are never rendered on this screen at all',
        );

        final shareCta = find.text(l10n().practiceResultShareCta);
        expect(shareCta, findsOneWidget);
        await tester.tap(shareCta);
        await tester.pumpAndSettle();

        expect(
          find.text(l10n().practiceResultShareSessionId('share-session-9')),
          findsOneWidget,
        );
        expect(
          find.text(l10n().practiceResultShareResult('17/20')),
          findsOneWidget,
        );
        // Still never leaked, even with the summary card open.
        expect(find.text('unexported-secret-skill-tag'), findsNothing);
      },
    );
  });
}

PracticeHistoryEntry _entry({
  required int resolvedTargets,
  required int totalTargets,
  String finishReasonCode = 'completedAllTargets',
  String id = 'confidence-fixture',
  String definitionId = 'd-confidence-fixture',
  List<String> skillTags = const ['smoke'],
}) {
  return PracticeHistoryEntry(
    id: id,
    modeCode: PracticeMode.chordProgression.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime.utc(2026, 8, 1, 12, 0),
    definitionId: definitionId,
    displayTitle: 'fixture-$id',
    finishReasonCode: finishReasonCode,
    activeDuration: const Duration(seconds: 40),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.9),
      rhythm: PracticeMetricDimensionAvailable(0.85),
      direction: PracticeMetricDimensionAvailable(0.95),
      chord: PracticeMetricDimensionAvailable(0.9),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: totalTargets,
    resolvedTargets: resolvedTargets,
    scorePoints: 800,
    maxCombo: 12,
    meanAbsoluteOffset: const Duration(milliseconds: 18),
    timingBias: const Duration(milliseconds: -2),
    coachingSummary: const [],
    skillTags: skillTags,
    highestStableTempoBpm: null,
  );
}
