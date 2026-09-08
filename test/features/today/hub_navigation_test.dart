// E13-R17 — cross-hub navigation. A2 (practice tool reachability depth,
// brief §6.1 three-cell matrix) and A5 (legacy routes stay reachable).
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
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceCatalogProvider;
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/practice/session/practice_session_test_fixtures.dart';
import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

Future<GoRouter> _pumpAdaptiveRouter(WidgetTester tester) async {
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
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Walks [buttonLabels] one tap at a time and returns the 1-based tap index
/// at which [T] first appears — the generic depth-measuring probe the §6.1
/// three-cell matrix (1 accepted, 2 accepted at the threshold, 3 rejected)
/// is built from.
Future<int> _tapsToReach<T extends Widget>(
  WidgetTester tester, {
  required List<String> buttonLabels,
}) async {
  for (var i = 0; i < buttonLabels.length; i++) {
    await tester.tap(find.text(buttonLabels[i]));
    await tester.pumpAndSettle();
    if (find.byType(T).evaluate().isNotEmpty) return i + 1;
  }
  throw StateError(
    '${T.toString()} not reached within ${buttonLabels.length} taps',
  );
}

/// The destination reached only once every `_DepthLevel` button on the
/// chain has been tapped — a distinct type from `_DepthLevel` itself, so a
/// level's own (still-unpressed) button can never satisfy `_tapsToReach`.
class _MetronomeMarker extends StatelessWidget {
  const _MetronomeMarker();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('metronome-marker'));
}

class _DepthLevel extends StatelessWidget {
  const _DepthLevel({required this.label, required this.next});
  final String label;
  final WidgetBuilder next;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: next)),
          child: Text(label),
        ),
      ),
    );
  }
}

const _todayCtaKey = ValueKey('today-hub-primary-cta');

/// Pumps the Today hub on a minimal router whose Practice destinations are
/// inert markers — the assertion is the LOCATION the CTA navigates to, so the
/// real setup screen (and its providers) is deliberately not involved. Mirror
/// of `test/features/practice_hub/practice_area_hub_cta_test.dart`'s helper.
Future<GoRouter> _pumpTodayHub(
  WidgetTester tester, {
  List<Override> overrides = const [],
  bool practiceEngineEnabled = true,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.today,
    routes: [
      GoRoute(
        path: AppRoutes.today,
        builder: (_, _) => TodayHubScreen(now: DateTime(2026, 8, 25)),
      ),
      GoRoute(
        path: AppRoutes.practiceSetup,
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: AppEnvironment.development,
            apiBaseUrl: AppConfig.devApiBaseUrl,
            flags: FeatureFlags(
              accountEnabled: false,
              diagnosticsEnabled: false,
              labModeAvailable: false,
              practiceEngineV2Enabled: practiceEngineEnabled,
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
  group(
    'A2 — the metronome quick tool is reachable within the 2-touch cap',
    () {
      testWidgets('production Practice Hub: Metronome is 1 tap from the root '
          '(under the threshold)', (tester) async {
        final router = await _pumpAdaptiveRouter(tester);
        router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();
        expect(find.byType(PracticeAreaHubScreen), findsOneWidget);

        await tester.tap(find.text('Metronome'));
        await tester.pumpAndSettle();

        expect(find.byType(MetronomeScreen), findsOneWidget);
      });

      testWidgets('production Practice Hub: Tuner is 1 tap from the root', (
        tester,
      ) async {
        final router = await _pumpAdaptiveRouter(tester);
        router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tuner'));
        await tester.pumpAndSettle();

        expect(find.byType(TunerScreen), findsOneWidget);
      });

      testWidgets('the depth probe: exactly at the 2-touch threshold is '
          'accepted', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: _DepthLevel(
              label: 'More tools',
              next: (_) => _DepthLevel(
                label: 'Metronome',
                next: (_) => const _MetronomeMarker(),
              ),
            ),
          ),
        );

        final taps = await _tapsToReach<_MetronomeMarker>(
          tester,
          buttonLabels: const ['More tools', 'Metronome'],
        );

        expect(taps, 2);
        expect(taps <= 2, isTrue, reason: '2 taps is the inclusive threshold');
      });

      testWidgets(
        'valódi-sértés próba (§10) — the metronome nested a THIRD level deep '
        'fails the 2-touch cap; this probe stays red by construction so the '
        'gate cannot silently start ignoring a real violation',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: _DepthLevel(
                label: 'More tools',
                next: (_) => _DepthLevel(
                  label: 'Advanced',
                  next: (_) => _DepthLevel(
                    label: 'Metronome',
                    next: (_) => const _MetronomeMarker(),
                  ),
                ),
              ),
            ),
          );

          final taps = await _tapsToReach<_MetronomeMarker>(
            tester,
            buttonLabels: const ['More tools', 'Advanced', 'Metronome'],
          );

          expect(taps, 3);
          expect(
            taps <= 2,
            isFalse,
            reason:
                'a metronome nested a third level deep must fail the A2 gate — '
                'this is the falsification probe documented in §10, distinct '
                'from the two passing cells above',
          );
        },
      );
    },
  );

  // Audit L1 — "Start your first practice" (the first CTA a new user ever
  // sees) used to land on the Practice HUB, one more decision away from
  // playing. The same URI matrix the Practice hub's own recommended CTA is
  // measured with (`practice_area_hub_cta_test.dart`): the shipped catalog,
  // an OVERRIDDEN catalog (so a hardcoded id literal fails), and the empty
  // catalog — the only case that may still fall back to the hub.
  group('audit L1 — the Today CTA starts the recommended practice', () {
    testWidgets(
      'the shipped catalog: the CTA lands on the practice SETUP route '
      "carrying the recommendation's id, not on the hub",
      (tester) async {
        final router = await _pumpTodayHub(tester);

        await tester.tap(find.byKey(_todayCtaKey));
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/practice/setup?id=builtin.quarterDownstrokes.v1',
        );
        expect(router.state.uri.path, isNot(AppRoutes.practiceHub));
      },
    );

    testWidgets(
      'an overridden catalog: the CTA carries the OVERRIDDEN first id, so a '
      'hardcoded literal cannot satisfy this cell',
      (tester) async {
        final router = await _pumpTodayHub(
          tester,
          overrides: [
            practiceCatalogProvider.overrideWithValue([
              practiceSessionFixtureDefinition(id: 'test.first.v1'),
            ]),
          ],
        );

        await tester.tap(find.byKey(_todayCtaKey));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/practice/setup?id=test.first.v1');
      },
    );

    testWidgets(
      'an EMPTY catalog: no recommendation exists, so the CTA falls back to '
      'the hub instead of opening a setup screen with no definition id',
      (tester) async {
        final router = await _pumpTodayHub(
          tester,
          overrides: [practiceCatalogProvider.overrideWithValue(const [])],
        );

        await tester.tap(find.byKey(_todayCtaKey));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), AppRoutes.practiceHub);
      },
    );

    testWidgets(
      'practiceEngineV2Enabled off: `/practice/setup` is not registered in '
      'that build, so the CTA keeps the hub destination',
      (tester) async {
        final router = await _pumpTodayHub(
          tester,
          practiceEngineEnabled: false,
        );

        await tester.tap(find.byKey(_todayCtaKey));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), AppRoutes.practiceHub);
      },
    );
  });

  group('A5 — legacy routes stay reachable after the hub swap', () {
    testWidgets('legacy /live still redirects to its adaptive-shell target', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);
      router.go(AppRoutes.live);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LiveScreen), findsOneWidget);
    });

    testWidgets('legacy /settings still redirects to SettingsScreen', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);
      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('legacy /progress still redirects to ProgressScreen', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);
      router.go(AppRoutes.progress);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // E16-R02 (ADR 0500) — the redirect now lands on the real Progress V2
      // dashboard, not the legacy ProgressScreen adapter.
      expect(find.byType(ProgressDashboardScreen), findsOneWidget);
    });

    testWidgets('legacy /streak still redirects to StreakScreen', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);
      router.go(AppRoutes.streak);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(StreakScreen), findsOneWidget);
    });
  });
}
