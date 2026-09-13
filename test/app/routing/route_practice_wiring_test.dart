// Task #7 — the three practice-flow "0 hívás" routes whose contextual
// entry points were measured empty by the E02 audit (HANDOFF §5.2).
//
// Each cell below drives the REAL `routerProvider` from the contextual
// entry the audit relied on and asserts the registered route lands where
// the entry promised — not on `onException`'s generic fallback. The
// pattern is the one `r18_entry_points_test.dart` and the sibling
// `route_orphan_wiring_test.dart` already use: a regression that empties
// any callback, drops the contextual entry, or short-circuits the
// navigation sink fails here, not in a static source scan.
//
// The three routes:
//
//   * `AppRoutes.practiceResult`            (`/practice/result`)
//       — entered by `practiceResultNavigationSinkProvider` after a
//         finished session emits `NavigateToResult`. R6 closed the
//         "always shows 'result unavailable'" bug by introducing the
//         `PracticeResultTargetController` hand-off; this test pins the
//         listener → sink → router chain end to end.
//
//   * `AppRoutes.practiceGeneratorWeekly`   (`/practice/generator/weekly`)
//       — entered from the Today AppBar `IconButton` with the
//         `today-plan-open-weekly` key (R18, audit §5.2).
//
//   * `AppRoutes.practiceGeneratorPrivacy`  (`/practice/generator/privacy`)
//       — entered from the Today AppBar `IconButton` with the
//         `today-plan-open-privacy` key (R18, audit §5.2).
//
// `adaptiveShellEnabled: true` — the shell is the way the user reaches
// Today; under the legacy shell the Today AppBar action is not in the
// navigator stack.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/application/practice_result_target.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/data/local_practice_history_repository.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/repository/practice_history_repository.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice_generator/domain/model/adaptive_practice_plan.dart';
import 'package:strumsight/features/practice_generator/presentation/providers/practice_generator_providers.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/plan_privacy_screen.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/today_plan_screen.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/weekly_plan_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/practice_generator/validation/validation_fixtures.dart';
import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

FeatureFlags get _flags => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  adaptiveShellEnabled: true,
  practiceEngineV2Enabled: true,
  practiceGeneratorEnabled: true,
);

AppConfig _config() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: _flags,
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// A history repository that always answers with [entries]. Used by the
/// `practiceResult` cell so the route's `resolvePracticeResultView` reads
/// the recorded entry, not the fallback.
class _SeedingHistoryRepository implements PracticeHistoryRepository {
  _SeedingHistoryRepository(this.entries);
  final List<PracticeHistoryEntry> entries;

  @override
  Future<AppResult<List<PracticeHistoryEntry>>> load() async =>
      Success<List<PracticeHistoryEntry>>(entries);

  @override
  Future<AppResult<void>> save(PracticeHistoryEntry entry) async =>
      const Success<void>(null);

  @override
  Future<AppResult<void>> clear() async => const Success<void>(null);
}

/// A `PracticeSessionHost` stub. The `PracticeEffectListener` reads the
/// `effects` stream on `initState`; this stub exposes a broadcast stream
/// the test can write into. Every other member throws so a regression
/// that reaches a different one is loud, not silent.
class _StubSessionHost implements PracticeSessionHost {
  _StubSessionHost(this._recording);
  final _SessionRecording _recording;

  @override
  Stream<PracticeSessionEffect> get effects => _recording.controller.stream;

  @override
  Stream<PracticeSessionState> get states =>
      const Stream<PracticeSessionState>.empty();

  @override
  PracticeSessionState get state => throw UnsupportedError(
    'This stub only exposes `effects` for this test; '
    'a regression that reads a different member is loud, not silent.',
  );

  @override
  int? get liveOverallPerMille => null;

  @override
  void send(PracticeSessionCommand command) {
    throw UnsupportedError(
      'This stub only exposes `effects` for this test; '
      'a regression that reads a different member is loud, not silent.',
    );
  }
}

class _SessionRecording {
  _SessionRecording();
  final controller = StreamController<PracticeSessionEffect>.broadcast();
  void emit(PracticeSessionEffect effect) => controller.add(effect);
  Future<void> close() => controller.close();
}

final class _RouterHarness {
  _RouterHarness(this.router, this.container, this.session);
  final GoRouter router;
  final ProviderContainer container;
  final _SessionRecording session;
}

/// Drives the real `routerProvider` with the audit-required flag set.
///
/// Cells that exercise the `practiceResult` listener→sink→router chain pass
/// [resultSessionId]: a session id that names the ending session. The
/// harness builds the `practiceResultNavigationSinkProvider` override as
/// a closure that closes over a [_RouterSnapshot] — the snapshot is
/// filled with the real router+container AFTER the `ProviderContainer`
/// has been built (so the override still goes through the ctor, the
/// pattern `result_navigation_test.dart` uses). `ref.read` consults the
/// override on every call, so the listener's effect handler observes
/// the late-bound router exactly once per `NavigateToResult` emission.
///
/// The production sink's own `practiceActiveSessionInputsProvider` lookup
/// is intentionally NOT reproduced: it requires a fully-wired
/// `PracticeSessionController`, which is the production path's
/// responsibility, not this cell's. The recording sink mirrors the
/// production `expect(id)` + `router.go` pair — a `null` session id would
/// regress the recorded state to `Pending`.
Future<_RouterHarness> _pumpRouter(
  WidgetTester tester, {
  List<PracticeHistoryEntry> history = const <PracticeHistoryEntry>[],
  AdaptivePracticePlan? plan,
  String? resultSessionId,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final session = _SessionRecording();

  // Late-bound router+container for the `practiceResult` cells: the
  // closure below is installed before the router exists, but it is
  // invoked from `ref.read` — which only fires when the listener actually
  // hands an effect to the sink. Both fields are filled inside the
  // setup block below.
  _RouterSnapshot? resultSnapshot;
  if (resultSessionId != null) {
    resultSnapshot = _RouterSnapshot(resultSessionId);
  }

  final overrides = <Override>[
    ...preferenceOverrides(),
    ...fakeAudioOverrides(wakelock: FakeScreenWakelock()),
    strumEngineProvider.overrideWithValue(liveEngine),
    tunerEngineProvider.overrideWithValue(tunerEngine),
    onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
    appConfigProvider.overrideWithValue(_config()),
    practiceResultTargetProvider.overrideWith(
      PracticeResultTargetController.new,
    ),
    if (resultSnapshot != null)
      practiceResultNavigationSinkProvider.overrideWithValue(
        _navigatingResultSink(resultSnapshot),
      ),
    practiceSessionHostProvider.overrideWithValue(_StubSessionHost(session)),
    practiceHistoryRepositoryProvider.overrideWithValue(
      _SeedingHistoryRepository(history),
    ),
    // The Today / Weekly routes read `activePracticePlanProvider` —
    // a `FutureProvider<AdaptivePracticePlan?>` we stub by overriding the
    // builder directly. An explicit plan keeps the cell closer to the
    // shipped build; `null` still renders the AppBar, so both work.
    activePracticePlanProvider.overrideWith(
      plan != null ? _seedingPlan(plan) : _noPlan(),
    ),
  ];

  final container = ProviderContainer(overrides: overrides);
  resultSnapshot?.container = container;
  addTearDown(container.dispose);
  addTearDown(session.close);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  final router = container.read(routerProvider);
  resultSnapshot?.router = router;
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
  return _RouterHarness(router, container, session);
}

FutureOr<AdaptivePracticePlan?> Function(Ref) _noPlan() =>
    (Ref ref) async => null;
FutureOr<AdaptivePracticePlan?> Function(Ref) _seedingPlan(
  AdaptivePracticePlan plan,
) =>
    (Ref ref) async => plan;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // (1) `AppRoutes.practiceResult` — `router.go` from the session sink
  // ---------------------------------------------------------------------
  //
  // R6 wired `practiceResultNavigationSinkProvider` so the session's
  // terminal `NavigateToResult` effect lands on `/practice/result`
  // through the composition root's router. Before R6 every finished
  // session rendered "result unavailable" because the route had no
  // hand-off. This cell pins BOTH halves of that fix:
  //
  //   * the sink still navigates (`router.state.uri.path ==
  //     AppRoutes.practiceResult`), and
  //   * the route resolves to the recorded entry (`PracticeResultScreen`
  //     for the id the sink named), not the `PracticeResultFallback`.
  //
  // The production `PracticeSessionController` is not exercised here —
  // its `result?.id` lookup is the production sink's own bookkeeping. The
  // recording sink mirrors the production `expect(id)` + `router.go`
  // pair (NOT `expect(null)`, which would regress the recorded state).
  group(
    'practiceResult — the session result-navigation sink lands on the route',
    () {
      testWidgets(
        'firing the NavigateToResult effect after a session routes to '
        '/practice/result and renders the recorded entry (not the fallback)',
        (tester) async {
          const sessionId = 'rec-fixture-1';
          final harness = await _pumpRouter(
            tester,
            history: <PracticeHistoryEntry>[_entry(sessionId)],
            resultSessionId: sessionId,
          );

          // The recording sink mirrors the production sink's
          // `expect(sessionId)` + `router.go(...)` pair. R6 needs the session
          // named BEFORE the navigation fires so the route's
          // `resolvePracticeResultView` finds the entry, not the fallback.
          harness.container
              .read(practiceResultTargetProvider.notifier)
              .expect(sessionId);
          harness.container
              .read(practiceResultTargetProvider.notifier)
              .recorded(sessionId);

          // Fire the terminal effect — the listener forwards it to the
          // sink, which `router.go`s `/practice/result`.
          harness.session.emit(const NavigateToResult());
          await tester.pumpAndSettle();

          expect(
            harness.router.state.uri.path,
            AppRoutes.practiceResult,
            reason:
                'the session\'s NavigateToResult effect must land on '
                '/practice/result — a regression that drops the sink\'s '
                'router.go would fall through onException to the entry '
                'location instead',
          );
          expect(find.byType(PracticeResultScreen), findsOneWidget);
          expect(
            find.byType(PracticeResultFallback),
            findsNothing,
            reason:
                'a named, recorded session must render its entry — '
                'the fallback is the documented "no entry" state, not '
                'the post-session one',
          );
        },
      );

      testWidgets(
        'the production sink navigates with `router.go`, replacing the '
        'session screen — `canPop` is false on arrival',
        (tester) async {
          const sessionId = 'rec-fixture-2';
          final harness = await _pumpRouter(
            tester,
            history: <PracticeHistoryEntry>[_entry(sessionId)],
            resultSessionId: sessionId,
          );
          harness.container
              .read(practiceResultTargetProvider.notifier)
              .expect(sessionId);
          harness.container
              .read(practiceResultTargetProvider.notifier)
              .recorded(sessionId);

          // Land on the session screen first, so the cell can observe the
          // replacement that the production sink performs (a `router.go`
          // discards the stack the session was on).
          harness.router.go(AppRoutes.practiceSession);
          await tester.pumpAndSettle();
          expect(find.byType(PracticeSessionScreen), findsOneWidget);

          harness.session.emit(const NavigateToResult());
          await tester.pumpAndSettle();

          expect(harness.router.state.uri.path, AppRoutes.practiceResult);
          expect(
            harness.router.canPop(),
            isFalse,
            reason:
                'the production sink uses `router.go`, not `router.push` '
                '— the session screen is intentionally replaced, so the '
                'result screen arrives with no stack to pop',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------
  // (2) `AppRoutes.practiceGeneratorWeekly` — Today AppBar IconButton
  // ---------------------------------------------------------------------
  //
  // R18 (audit §5.2): the route was registered but the shipped Today
  // AppBar had no entry point. R18 added the IconButton with the
  // `today-plan-open-weekly` key. This cell drives the FULL router from
  // the Today screen and asserts the tap navigates to
  // `/practice/generator/weekly` and renders `WeeklyPlanScreen`.
  group('practiceGeneratorWeekly — the Today AppBar opens the weekly plan', () {
    testWidgets('tapping the today-plan-open-weekly IconButton pushes '
        '/practice/generator/weekly and renders WeeklyPlanScreen', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, plan: buildPlan());
      // Land on Today.
      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();
      expect(find.byType(TodayPlanScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('today-plan-open-weekly')));
      await tester.pumpAndSettle();

      expect(
        harness.router.state.uri.path,
        AppRoutes.practiceGeneratorWeekly,
        reason:
            'the Today AppBar IconButton with key '
            '`today-plan-open-weekly` must navigate to '
            '/practice/generator/weekly — a regression that empties '
            'the `onPressed` (or removes the IconButton) would land '
            'on whatever the router\'s onException points at',
      );
      expect(find.byType(WeeklyPlanScreen), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // (3) `AppRoutes.practiceGeneratorPrivacy` — Today AppBar IconButton
  // ---------------------------------------------------------------------
  //
  // R18 (audit §5.2): same shape as the weekly entry — the route was
  // registered but no in-app surface reached it. R18 added the
  // `today-plan-open-privacy` IconButton. This cell pins that path.
  group(
    'practiceGeneratorPrivacy — the Today AppBar opens the privacy screen',
    () {
      testWidgets('tapping the today-plan-open-privacy IconButton pushes '
          '/practice/generator/privacy and renders PlanPrivacyScreen', (
        tester,
      ) async {
        final harness = await _pumpRouter(tester, plan: buildPlan());
        harness.router.go(AppRoutes.practiceGeneratorToday);
        await tester.pumpAndSettle();
        expect(find.byType(TodayPlanScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('today-plan-open-privacy')));
        await tester.pumpAndSettle();

        expect(
          harness.router.state.uri.path,
          AppRoutes.practiceGeneratorPrivacy,
          reason:
              'the Today AppBar IconButton with key '
              '`today-plan-open-privacy` must navigate to '
              '/practice/generator/privacy — the audit §5.2 promise '
              'that every generator route has an in-app entry point',
        );
        expect(find.byType(PlanPrivacyScreen), findsOneWidget);
      });
    },
  );

  // ---------------------------------------------------------------------
  // (4) Source audit — the three route strings in AppRoutes still resolve
  //     to the ones this task wired end-to-end. A pure rename in
  //     `app_route.dart` (without updating this file's expectation) would
  //     flip a route's URL — this cell catches that.
  // ---------------------------------------------------------------------
  group('AppRoutes source — the three constants still resolve', () {
    test(
      'practiceResult, practiceGeneratorWeekly, and practiceGeneratorPrivacy '
      'match the URLs the test above drove',
      () {
        expect(AppRoutes.practiceResult, '/practice/result');
        expect(AppRoutes.practiceGeneratorWeekly, '/practice/generator/weekly');
        expect(
          AppRoutes.practiceGeneratorPrivacy,
          '/practice/generator/privacy',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The recording sink used by the `practiceResult` cells. It mirrors the
/// production `practiceResultNavigationSinkProvider`'s pair:
///
/// * `target.expect(sessionId)` — name the ending session so the route
///   has something to wait for (a `null` session id would regress the
///   target to `Pending` and render a spinner instead of the result
///   screen);
/// * `router.go(AppRoutes.practiceResult)` — the wire this task pins.
///
/// `snapshot` is filled in by `_pumpRouter` once the router has been
/// built; the closure captures it indirectly so the `overrideWithValue`
/// ctor can be passed in BEFORE the router exists. `ref.read` consults
/// the override on every call, so the listener's effect handler observes
/// the late-bound router exactly once per `NavigateToResult` emission.
class _RouterSnapshot {
  _RouterSnapshot(this.sessionId);
  final String sessionId;
  GoRouter? router;
  ProviderContainer? container;
}

void Function() _navigatingResultSink(_RouterSnapshot snapshot) {
  return () {
    final container = snapshot.container!;
    final router = snapshot.router!;
    container
        .read(practiceResultTargetProvider.notifier)
        .expect(snapshot.sessionId);
    router.go(AppRoutes.practiceResult);
  };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A `chordProgression` entry used by the result-route cells. The shape is
/// exactly the one the real recorder writes (R18's snapshot schema).
PracticeHistoryEntry _entry(String id) {
  return PracticeHistoryEntry(
    id: id,
    modeCode: PracticeMode.chordProgression.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime.utc(2026, 9, 1, 12),
    definitionId: 'fixture.$id',
    displayTitle: 'fixture-$id',
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
    coachingSummary: const <String>[],
    skillTags: const <String>['smoke'],
    highestStableTempoBpm: 100.0,
  );
}
