// E14-R36 (ADR 0546) — the Today hub side of the "10 useful minutes" chain:
// two-tap start, one "what to do next" CTA per step, resume after an
// interruption, and the measured recap. Mirrors the router/override pattern
// of `hub_navigation_test.dart` so the assertions are on the LOCATION the
// CTA navigates to, not on a stubbed screen.
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
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/progress/public.dart';
import 'package:strumsight/features/streak/public.dart';
import 'package:strumsight/features/today/domain/ten_minute_flow.dart';
import 'package:strumsight/features/today/providers/ten_minute_flow_providers.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _ctaKey = ValueKey('today-hub-primary-cta');
const _startKey = ValueKey('today-hub-ten-minute-start');
const _leaveKey = ValueKey('today-hub-ten-minute-leave');

/// The fixed clock every cell renders at, so `startedAt` and the resume
/// window are exact rather than wall-clock dependent.
final _now = DateTime(2026, 8, 25, 18);
final _today = StreakLogic.epochDayOf(_now);

/// A controller that builds with a pre-existing chain — the only way to
/// reach the "app was left mid-chain" states without simulating hours.
class _SeededFlowController extends TenMinuteFlowController {
  _SeededFlowController(this._seed);
  final TenMinuteFlowState? _seed;

  @override
  TenMinuteFlowState? build() => _seed;
}

Override _seedFlow(TenMinuteFlowState seed) =>
    tenMinuteFlowProvider.overrideWith(() => _SeededFlowController(seed));

TenMinuteFlowState _chainAt(
  TenMinuteStep step, {
  DateTime? startedAt,
  int baselineActiveSeconds = 0,
}) => TenMinuteFlowState(
  plan: TenMinutePlan.standard,
  step: step,
  startedAt: startedAt ?? _now,
  baselineActiveSeconds: baselineActiveSeconds,
);

/// Pumps the Today hub on a minimal router whose destinations are inert
/// markers — every assertion below is about the LOCATION, so the real
/// Practice/Tuner screens (and their providers) stay out of it.
Future<GoRouter> _pumpTodayHub(
  WidgetTester tester, {
  List<Override> overrides = const [],
  int activeSecondsToday = 0,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.today,
    routes: [
      GoRoute(
        path: AppRoutes.today,
        builder: (_, _) => TodayHubScreen(now: _now),
      ),
      GoRoute(
        path: AppRoutes.practiceSetup,
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.practiceTuner,
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        dailyGoalActiveSecondsProvider(
          _today,
        ).overrideWithValue(activeSecondsToday),
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: AppEnvironment.development,
            apiBaseUrl: AppConfig.devApiBaseUrl,
            flags: const FeatureFlags(
              accountEnabled: false,
              diagnosticsEnabled: false,
              labModeAvailable: false,
              practiceEngineV2Enabled: true,
            ),
            diagnosticsToken: AppConfig.devDiagnosticsToken,
            buildMode: 'test',
            appVersion: 'test',
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('the chain is opt-in and never regresses the audit-L1 CTA', () {
    testWidgets(
      'with no chain running the ONE primary CTA still lands on the '
      'recommended practice, and the chain is offered as a SECONDARY action',
      (tester) async {
        final router = await _pumpTodayHub(tester);

        expect(find.byKey(_startKey), findsOneWidget);
        expect(
          find.byType(FilledButton),
          findsOneWidget,
          reason: 'A1 — the chain must not add a second primary button',
        );

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/practice/setup?id=builtin.quarterDownstrokes.v1',
        );
      },
    );
  });

  group('two taps put the player in the first link of the chain', () {
    testWidgets('start → the hub shows step 1 of 3 and its own next action', (
      tester,
    ) async {
      await _pumpTodayHub(tester);

      await tester.tap(find.byKey(_startKey));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Tune up'), findsOneWidget);
      expect(
        find.byType(FilledButton),
        findsOneWidget,
        reason: 'still exactly one primary action while the chain runs',
      );
      expect(
        find.byKey(_startKey),
        findsNothing,
        reason: 'a running chain cannot be started a second time',
      );
    });

    testWidgets('start + next action = 2 taps to the tuner route', (
      tester,
    ) async {
      final router = await _pumpTodayHub(tester);

      await tester.tap(find.byKey(_startKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_ctaKey));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), AppRoutes.practiceTuner);
    });

    testWidgets(
      'the chain survives leaving the hub — coming back resumes the SAME '
      'step instead of starting over',
      (tester) async {
        final router = await _pumpTodayHub(tester);

        await tester.tap(find.byKey(_startKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();
        router.go(AppRoutes.today);
        await tester.pumpAndSettle();

        expect(find.text('Step 1 of 3'), findsOneWidget);
        expect(find.text('Tune up'), findsOneWidget);
      },
    );
  });

  group('interruption', () {
    testWidgets(
      'a chain left behind hours ago is NOT resurrected — the hub goes back '
      'to its ordinary single CTA',
      (tester) async {
        final router = await _pumpTodayHub(
          tester,
          overrides: [
            _seedFlow(
              _chainAt(
                TenMinuteStep.play,
                startedAt: _now.subtract(const Duration(hours: 5)),
              ),
            ),
          ],
        );

        expect(find.text('Step 2 of 3'), findsNothing);
        expect(find.byKey(_startKey), findsOneWidget);

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/practice/setup?id=builtin.quarterDownstrokes.v1',
        );
      },
    );

    testWidgets('"leave the session" drops a running chain', (tester) async {
      await _pumpTodayHub(
        tester,
        overrides: [_seedFlow(_chainAt(TenMinuteStep.tune))],
      );

      expect(find.byKey(_leaveKey), findsOneWidget);

      await tester.tap(find.byKey(_leaveKey));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 3'), findsNothing);
      expect(find.byKey(_startKey), findsOneWidget);
    });
  });

  group('the play step and its measured recap', () {
    testWidgets(
      'the play step opens the SAME recommended exercise the ordinary CTA '
      'would — the chain never invents a second destination',
      (tester) async {
        final router = await _pumpTodayHub(
          tester,
          overrides: [
            _seedFlow(_chainAt(TenMinuteStep.play, baselineActiveSeconds: 120)),
          ],
          activeSecondsToday: 120,
        );

        expect(find.text('Step 2 of 3'), findsOneWidget);

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/practice/setup?id=builtin.quarterDownstrokes.v1',
        );
      },
    );

    testWidgets(
      'MEASURED practice time — not having opened the setup screen — is what '
      'promotes the chain to its recap, and Finish closes it',
      (tester) async {
        await _pumpTodayHub(
          tester,
          overrides: [
            _seedFlow(_chainAt(TenMinuteStep.play, baselineActiveSeconds: 120)),
          ],
          activeSecondsToday: 540,
        );

        expect(find.text('Step 3 of 3'), findsOneWidget);
        expect(find.text('Finish'), findsOneWidget);

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();

        expect(find.text('Step 3 of 3'), findsNothing);
        expect(
          find.byKey(_startKey),
          findsOneWidget,
          reason: 'a finished chain leaves the hub in its ordinary state',
        );
      },
    );
  });

  // The light router above proves the LOCATION; this cell proves the location
  // is a route the real application actually registers, and that the whole
  // hand-off works on the composition root (§6 — "every CTA points at a real
  // route", the placeholder-wiring guard's rule applied to the chain).
  group('the chain runs on the real router', () {
    testWidgets('two taps from Today land on the real TunerScreen', (
      tester,
    ) async {
      final liveEngine = FakeStrumEngine();
      final tunerEngine = FakeTunerEngine();
      final container = ProviderContainer(
        overrides: [
          ...preferenceOverrides(),
          ...fakeAudioOverrides(),
          strumEngineProvider.overrideWithValue(liveEngine),
          tunerEngineProvider.overrideWithValue(tunerEngine),
          onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: AppEnvironment.development,
              apiBaseUrl: AppConfig.devApiBaseUrl,
              flags: const FeatureFlags(
                accountEnabled: false,
                diagnosticsEnabled: true,
                labModeAvailable: true,
                practiceEngineV2Enabled: true,
                adaptiveShellEnabled: true,
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
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: ref.watch(routerProvider),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go(AppRoutes.today);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_startKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_ctaKey));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TunerScreen), findsOneWidget);
    });
  });
}
