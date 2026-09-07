// R18 (audit B1/B2/B3/B4, M6) — the shipped adaptive shell's missing entry
// points, measured through the REAL router.
//
// Every cell below covers a hole in the shipped dev APK
// (`adaptiveShellEnabled == true`):
//
//   B1 — the five category chips on the Practice Area Hub all navigated to
//        `/practice/setup` with NO `?id=`, so each of them rendered the Setup
//        screen's route-error branch ("this practice is not available").
//   B2 — the catalog listing screen was registered only under
//        `!adaptiveShellEnabled`, so nine of the ten built-in practices had
//        no on-screen entry point at all.
//   B3/B4 — nothing anywhere in `lib/` navigated to `/practice/analyze` or
//        `/practice/learn`, the only doors into the Audio Analysis V2 capture
//        flow and the Song Trainer V2 lesson library.
//   M6 — three route builders read `AsyncValue.value` directly, so LOADING
//        and ERROR both rendered as the screens' measured "you have nothing
//        here" state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/domain/model/practice_category.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_mode_card.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceCatalogProvider;
import 'package:strumsight/features/practice_generator/domain/model/adaptive_practice_plan.dart';
import 'package:strumsight/features/practice_generator/presentation/providers/practice_generator_providers.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/today_plan_screen.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A compact phone, so the shell renders its bottom navigation (not a rail)
/// and the hub's list scrolls the way the shipped build scrolls it.
const _compactPortrait = Size(412, 915);

/// The corrupt active-plan pointer `practice_generator_providers_test.dart`'s
/// M4 cell uses — a REAL read failure through the real repository, not a
/// hand-made `AsyncError`.
const _corruptPlanPointer = <String, Object>{
  'ss.practice_generator.plan.active_pointer': 'not-json-at-all{{{',
};

/// A plan read that never completes — the router must render its loading
/// frame, never the screen's "no active plan" state.
Future<AdaptivePracticePlan?> _pendingPlan(Ref ref) =>
    Completer<AdaptivePracticePlan?>().future;

Future<List<AnalysisSummary>> _pendingAnalyses(Ref ref) =>
    Completer<List<AnalysisSummary>>().future;

Future<List<AnalysisSummary>> _failingAnalyses(Ref ref) async {
  throw StateError('the analysis index could not be read');
}

final class _Rig {
  const _Rig(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;
}

Future<_Rig> _pumpShell(
  WidgetTester tester, {
  List<Override> extraOverrides = const [],
  Map<String, Object>? seed,
  bool practiceGeneratorEnabled = false,
  bool audioAnalysisV2Enabled = false,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(seed),
      ...fakeAudioOverrides(wakelock: FakeScreenWakelock()),
      ...extraOverrides,
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            adaptiveShellEnabled: true,
            practiceEngineV2Enabled: true,
            practiceGeneratorEnabled: practiceGeneratorEnabled,
            audioAnalysisV2Enabled: audioAnalysisV2Enabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Rig(container, router);
}

/// The OUTER scrollable of [screen]. Depth-first order puts the screen's own
/// `ListView` ahead of any nested horizontal scroller (the catalog's mode
/// filter row), so `.first` is always the vertical list.
Finder _scrollableOf(Type screen) {
  final matches = find.descendant(
    of: find.byType(screen),
    matching: find.byType(Scrollable),
  );
  return matches.first;
}

Future<void> _tapOnHub(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: _scrollableOf(PracticeAreaHubScreen),
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<_Rig> _openHub(WidgetTester tester) async {
  final rig = await _pumpShell(tester);
  rig.router.go(AppRoutes.practiceHub);
  await tester.pumpAndSettle();
  expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
  return rig;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('B1 — every category chip leads to a real screen, never the Setup '
      'route-error branch', () {
    for (final category in PracticeCategory.values) {
      testWidgets('the "${category.code}" chip opens the filtered catalog', (
        tester,
      ) async {
        await _openHub(tester);

        await _tapOnHub(
          tester,
          find.byKey(ValueKey('practice-hub-category-${category.code}')),
        );

        expect(find.byType(PracticeHubScreen), findsOneWidget);
        final screen = tester.widget<PracticeHubScreen>(
          find.byType(PracticeHubScreen),
        );
        expect(screen.category, category);
        // The measured defect: Setup's route-error branch. Neither the
        // screen nor its error copy may appear.
        expect(find.byType(PracticeSetupScreen), findsNothing);
        expect(find.text(l10n.practiceRouteErrorTitle), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the empty "scales" category shows the catalog\'s own empty '
        'copy — an honest listing, not a failure', (tester) async {
      await _openHub(tester);

      await _tapOnHub(
        tester,
        find.byKey(const ValueKey('practice-hub-category-scales')),
      );

      expect(find.byType(PracticeHubScreen), findsOneWidget);
      expect(find.byType(PracticeModeCard), findsNothing);
      expect(find.text(l10n.practiceHubEmptyCatalogSubtitle), findsOneWidget);
      expect(find.text(l10n.practiceRouteErrorTitle), findsNothing);
    });
  });

  group('B2 — the whole catalog is reachable from the hub', () {
    testWidgets('"All practices" lists every built-in definition, and the '
        'last one opens Setup with a real definition', (tester) async {
      final rig = await _openHub(tester);

      await _tapOnHub(
        tester,
        find.byKey(const ValueKey('practice-hub-all-practices')),
      );

      expect(find.byType(PracticeHubScreen), findsOneWidget);
      final screen = tester.widget<PracticeHubScreen>(
        find.byType(PracticeHubScreen),
      );
      expect(
        screen.category,
        isNull,
        reason: '"All practices" must not carry a category filter',
      );

      final catalog = rig.container.read(practiceCatalogProvider);
      expect(catalog, hasLength(10));
      final list = _scrollableOf(PracticeHubScreen);
      var lastTitle = '';
      for (final definition in catalog) {
        lastTitle = practiceDefinitionDisplayTitle(l10n, definition);
        final title = find.text(lastTitle);
        await tester.scrollUntilVisible(title, 160, scrollable: list);
        expect(
          title,
          findsOneWidget,
          reason: '${definition.id} is not listed by the catalog screen',
        );
      }

      await tester.tap(find.text(lastTitle));
      await tester.pumpAndSettle();

      expect(find.byType(PracticeSetupScreen), findsOneWidget);
      expect(find.text(l10n.practiceRouteErrorTitle), findsNothing);
    });
  });

  group('B3/B4 — the Analyze and Learn tools have an entry point again', () {
    testWidgets('the Analyze tile opens AnalyzeScreen and pops back', (
      tester,
    ) async {
      final rig = await _openHub(tester);

      await _tapOnHub(
        tester,
        find.byKey(const ValueKey('practice-hub-analyze')),
      );

      expect(find.byType(AnalyzeScreen), findsOneWidget);
      expect(rig.router.canPop(), isTrue);

      rig.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AnalyzeScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    });

    testWidgets('the Learn tile opens LessonListScreen and pops back', (
      tester,
    ) async {
      final rig = await _openHub(tester);

      await _tapOnHub(tester, find.byKey(const ValueKey('practice-hub-learn')));

      expect(find.byType(LessonListScreen), findsOneWidget);
      expect(rig.router.canPop(), isTrue);

      rig.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(LessonListScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    });
  });

  group('M6 — loading and error are distinct from "you have nothing"', () {
    testWidgets('/practice/generator/today shows a loading frame, not the '
        '"no active plan" screen', (tester) async {
      final rig = await _pumpShell(
        tester,
        practiceGeneratorEnabled: true,
        extraOverrides: [activePracticePlanProvider.overrideWith(_pendingPlan)],
      );
      rig.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(const Key('today-plan-route-loading')), findsOneWidget);
      expect(find.byType(TodayPlanScreen), findsNothing);
    });

    testWidgets('/practice/generator/today shows a retryable error frame for '
        'a plan the store cannot read', (tester) async {
      final rig = await _pumpShell(
        tester,
        practiceGeneratorEnabled: true,
        seed: _corruptPlanPointer,
      );
      rig.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-plan-route-error')), findsOneWidget);
      expect(find.text(l10n.shellDataErrorMessage), findsOneWidget);
      expect(find.text(l10n.shellDataRetry), findsOneWidget);
      expect(
        find.byType(TodayPlanScreen),
        findsNothing,
        reason:
            'an unreadable plan must never render as "you have no plan yet"',
      );
    });

    testWidgets('/practice/generator/weekly separates loading from "no plan"', (
      tester,
    ) async {
      final rig = await _pumpShell(
        tester,
        practiceGeneratorEnabled: true,
        extraOverrides: [activePracticePlanProvider.overrideWith(_pendingPlan)],
      );
      rig.router.go(AppRoutes.practiceGeneratorWeekly);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        find.byKey(const Key('weekly-plan-route-loading')),
        findsOneWidget,
      );
    });

    testWidgets('/practice/generator/weekly renders the error frame for an '
        'unreadable plan', (tester) async {
      final rig = await _pumpShell(
        tester,
        practiceGeneratorEnabled: true,
        seed: _corruptPlanPointer,
      );
      rig.router.go(AppRoutes.practiceGeneratorWeekly);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weekly-plan-route-error')), findsOneWidget);
      expect(find.text(l10n.shellDataErrorMessage), findsOneWidget);
    });

    testWidgets('/analysis/capture shows a loading frame, not "no earlier '
        'analyses"', (tester) async {
      final rig = await _pumpShell(
        tester,
        audioAnalysisV2Enabled: true,
        extraOverrides: [
          analysisRecentSummariesProvider.overrideWith(_pendingAnalyses),
        ],
      );
      rig.router.go(AppRoutes.analysisCapture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        find.byKey(const Key('analysis-home-route-loading')),
        findsOneWidget,
      );
      expect(find.byType(AnalysisHomeScreen), findsNothing);
    });

    testWidgets('/analysis/capture shows the error frame when the index read '
        'fails, never an empty recent list', (tester) async {
      final rig = await _pumpShell(
        tester,
        audioAnalysisV2Enabled: true,
        extraOverrides: [
          analysisRecentSummariesProvider.overrideWith(_failingAnalyses),
        ],
      );
      rig.router.go(AppRoutes.analysisCapture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        find.byKey(const Key('analysis-home-route-error')),
        findsOneWidget,
      );
      expect(
        find.byType(AnalysisHomeScreen),
        findsNothing,
        reason: 'a failed read must not look like "no earlier analyses"',
      );
      // Riverpod 3 auto-retries a `FutureProvider` that throws; tearing the
      // tree down inside the cell disposes the autoDispose provider (and its
      // pending retry) before the binding checks for leftover timers.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
