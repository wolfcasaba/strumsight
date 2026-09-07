import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppLocalizations l10n() => AppLocalizationsEn();

  Future<void> pumpResult(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
  }

  group('A1 — visibility matrix', () {
    testWidgets('Strum Pattern: chord block is NOT in the tree', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.strumPattern);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      // Chord is not applicable to strum-pattern; the card never renders it.
      expect(find.text(l10n().practiceResultChord), findsNothing);
    });

    testWidgets('Chord Changes: direction is hidden', (tester) async {
      final entry = _entry(PracticeMode.chordChanges);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(l10n().practiceResultDirection), findsNothing);
    });

    testWidgets('Chord Progression: all four dimensions render', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.chordProgression);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(l10n().practiceResultOverall), findsOneWidget);
      expect(find.text(l10n().practiceResultRhythm), findsOneWidget);
      expect(find.text(l10n().practiceResultDirection), findsOneWidget);
      expect(find.text(l10n().practiceResultChord), findsOneWidget);
    });

    testWidgets('Free Practice: NO overall/rhythm/direction/chord cards', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.freePractice);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(l10n().practiceResultOverall), findsNothing);
      expect(find.text(l10n().practiceResultRhythm), findsNothing);
      expect(find.text(l10n().practiceResultDirection), findsNothing);
      expect(find.text(l10n().practiceResultChord), findsNothing);
    });
  });

  group('A2 — InsufficientData is NOT rendered as a percentage', () {
    testWidgets(
      'a dimension in InsufficientData shows the "not enough data" string',
      (tester) async {
        final entry = _entry(PracticeMode.chordProgression).copyWith(
          finalMetricSnapshot: const PracticeMetricSnapshot(
            completion: PracticeMetricDimensionAvailable(0.9),
            rhythm: PracticeMetricDimensionAvailable(0.85),
            direction: PracticeMetricDimensionInsufficientData(
              'practice.metric.insufficient_samples',
            ),
            chord: PracticeMetricDimensionAvailable(0.95),
            overall: PracticeMetricDimensionAvailable(0.9),
          ),
        );
        await pumpResult(tester, PracticeResultScreen(entry: entry));
        // The "not enough data" cell renders once for direction.
        expect(
          find.text(l10n().practiceResultInsufficientData),
          findsOneWidget,
        );
        // No percentage is rendered for the direction row.
        final directionLabel = find.text(l10n().practiceResultDirection);
        final percentRendered = find.descendant(
          of: directionLabel,
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.contains('%'),
          ),
        );
        expect(percentRendered, findsNothing);
      },
    );
  });

  group('A3 — Free Practice result is score-free', () {
    testWidgets(
      'no overall / pass-fail / accuracy / combo tiles, but the fact tiles render',
      (tester) async {
        final entry = _entry(PracticeMode.freePractice).copyWith(
          attemptsCount: 12,
          activeDuration: const Duration(minutes: 2, seconds: 30),
        );
        await pumpResult(tester, PracticeResultScreen(entry: entry));
        // No overall / pass-fail / accuracy tiles are rendered.
        expect(find.text(l10n().practiceResultOverall), findsNothing);
        // The two fact tiles are present.
        expect(
          find.text(l10n().practiceFreePracticeActiveDuration),
          findsOneWidget,
        );
        expect(
          find.text(l10n().practiceFreePracticeStrumCount),
          findsOneWidget,
        );
        // Active duration renders as "2m 30s".
        expect(find.text('2m 30s'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
      },
    );
  });

  group('E15-R04 — design-system migration', () {
    testWidgets(
      'PracticeResultFallback (no entry) renders the informational state, '
      'no action and no navigation (E15-R04 review MAJOR-3b: this fallback '
      'never navigated pre-migration; adding one would be a behaviour '
      'change in an appearance-only round)',
      (tester) async {
        await pumpResult(tester, const PracticeResultFallback());
        expect(
          find.text(l10n().practiceResultUnavailableTitle),
          findsOneWidget,
        );
        expect(find.text(l10n().practiceResultUnavailableBody), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ss-empty-state-action')),
          findsNothing,
        );
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
      },
    );

    for (final locale in [const Locale('en'), const Locale('hu')]) {
      testWidgets('textScaler 2.0 renders without overflow — Chord Progression '
          '(${locale.languageCode})', (tester) async {
        tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(
          tester.view.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PracticeResultScreen(
                entry: _entry(PracticeMode.chordProgression),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'textScaler 2.0 renders the PracticeResultFallback without overflow '
        '(${locale.languageCode})',
        (tester) async {
          tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(
            tester.view.platformDispatcher.clearTextScaleFactorTestValue,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const PracticeResultFallback(),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // -------------------------------------------------------------------
  // R17 (2026-09-07 audit) — a way OUT of the result screen.
  //
  // MÉRT hiba: a `/practice/result` útvonalra a hatás-figyelő
  // `router.go`-val érkezik (szándékosan: a befejezett munkamenet
  // képernyője így eltűnik), tehát az érkező oldal az EGYETLEN a
  // stacken — `canPop == false`, az AppBar nem rajzol vissza-nyilat, és
  // a képernyő végén sem volt semmilyen záró CTA. A kör a KIVEZETŐ utat
  // javítja, a `go`-t nem.
  // -------------------------------------------------------------------
  group('R17 — a way out of the result screen', () {
    testWidgets('the back leading returns to the hub', (tester) async {
      final router = await _pumpRouted(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.chordProgression)),
      );
      expect(router.canPop(), isFalse);

      await tester.tap(find.byKey(const Key('practiceResultBack')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.practiceHub);
    });

    testWidgets('the Done CTA returns to the hub', (tester) async {
      final router = await _pumpRouted(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.chordProgression)),
      );

      final cta = find.byKey(const Key('practiceResultDoneCta'));
      await tester.scrollUntilVisible(
        cta,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.practiceHub);
    });

    // The fallback is shown exactly when the result could NOT be resolved
    // — the one state where being stranded is most likely.
    testWidgets('the fallback offers the same way out', (tester) async {
      final router = await _pumpRouted(tester, const PracticeResultFallback());

      await tester.tap(find.byKey(const Key('practiceResultDoneCta')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.practiceHub);
    });

    testWidgets('a PUSHED result keeps the plain AppBar', (tester) async {
      final router = await _pumpRouted(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.chordProgression)),
        pushed: true,
      );

      // Nothing is added where `AppBar` already draws a working back
      // button, so the pushed frame is unchanged by this round.
      expect(find.byKey(const Key('practiceResultBack')), findsNothing);
      expect(find.byKey(const Key('practiceResultDoneCta')), findsNothing);
      expect(router.canPop(), isTrue);
    });

    // The frame the E13-R22 pixel goldens pump: no router above the
    // screen at all, so there is no hub route to leave for and NOTHING is
    // added — which is why those goldens stay byte-identical.
    testWidgets('no router: no exit affordance is added', (tester) async {
      await pumpResult(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.chordProgression)),
      );

      expect(find.byKey(const Key('practiceResultBack')), findsNothing);
      expect(find.byKey(const Key('practiceResultDoneCta')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// R17 (2026-09-07 audit) — the result screen under a real router
// ---------------------------------------------------------------------------

/// `/practice/result` with the practice hub behind it. [pushed] chooses the
/// two ways the screen is entered: the shipped one is a stack-replacing
/// `go` (nothing to pop), the other a push (the AppBar's own back arrow).
GoRouter _resultRouter(Widget screen, {required bool pushed}) => GoRouter(
  initialLocation: pushed ? AppRoutes.practiceHub : AppRoutes.practiceResult,
  routes: <RouteBase>[
    GoRoute(path: AppRoutes.practiceResult, builder: (_, _) => screen),
    GoRoute(path: AppRoutes.practiceHub, builder: _stub),
  ],
);

Widget _stub(BuildContext _, GoRouterState state) =>
    Scaffold(body: Text('STUB ${state.uri.path}'));

Future<GoRouter> _pumpRouted(
  WidgetTester tester,
  Widget screen, {
  bool pushed = false,
}) async {
  final router = _resultRouter(screen, pushed: pushed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: preferenceOverrides(),
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    router.push(AppRoutes.practiceResult);
    await tester.pumpAndSettle();
  }
  return router;
}

PracticeHistoryEntry _entry(PracticeMode mode) {
  return PracticeHistoryEntry(
    id: 'result-${mode.code}',
    modeCode: mode.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime(2026, 8, 1, 12, 0),
    definitionId: 'd-${mode.code}',
    displayTitle: 'fixture-${mode.code}',
    finishReasonCode: 'userFinished',
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.9),
      rhythm: PracticeMetricDimensionAvailable(0.85),
      direction: PracticeMetricDimensionAvailable(0.95),
      chord: PracticeMetricDimensionAvailable(0.92),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: 16,
    resolvedTargets: 14,
    scorePoints: 800,
    maxCombo: 12,
    meanAbsoluteOffset: const Duration(milliseconds: 18),
    timingBias: const Duration(milliseconds: -2),
    coachingSummary: const ['practice.coach.late'],
    skillTags: const ['smoke'],
    highestStableTempoBpm: 100.0,
  );
}

extension on PracticeHistoryEntry {
  PracticeHistoryEntry copyWith({
    String? id,
    PracticeMetricSnapshot? finalMetricSnapshot,
    int? attemptsCount,
    Duration? activeDuration,
  }) {
    return PracticeHistoryEntry(
      id: id ?? this.id,
      modeCode: modeCode,
      sourceCode: sourceCode,
      createdAt: createdAt,
      definitionId: definitionId,
      displayTitle: displayTitle,
      finishReasonCode: finishReasonCode,
      activeDuration: activeDuration ?? this.activeDuration,
      pausedDuration: pausedDuration,
      attemptsCount: attemptsCount ?? this.attemptsCount,
      finalMetricSnapshot: finalMetricSnapshot ?? this.finalMetricSnapshot,
      totalTargets: totalTargets,
      resolvedTargets: resolvedTargets,
      scorePoints: scorePoints,
      maxCombo: maxCombo,
      meanAbsoluteOffset: meanAbsoluteOffset,
      timingBias: timingBias,
      coachingSummary: coachingSummary,
      skillTags: skillTags,
      highestStableTempoBpm: highestStableTempoBpm,
      detailAttempts: detailAttempts,
    );
  }
}
