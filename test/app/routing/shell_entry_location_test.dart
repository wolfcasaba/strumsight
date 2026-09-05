import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/adaptive_shell_routes.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/first_win_stage_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A strong strum reading — drives the Stage's production engine
/// (`LiveFirstWinEngine`, ADR 0534 D3) to its success branch via the SAME
/// `strumEngineProvider` override this file already installs.
LiveFrame _strongStrumFrame() => const LiveFrame(
  current: null,
  next: null,
  latestStrum: Strum(direction: StrumDirection.down, confidence: 0.85),
  bar: [],
  bpm: 0,
  inputLevel: 0.5,
  tuningHz: 440,
  listening: true,
);

/// ADR 0508 D1/D2 — the belépési 2×2 mátrix (brief §6 A2):
/// `adaptiveShellEnabled` × completion branch (Skip/finish, first-win), on a
/// REAL router — the flag is read via `appConfigProvider`, exactly like
/// `app_router.dart` and `OnboardingScreen` both do (`entryLocationFor`, the
/// single source both call). Every cell asserts the SETTLED
/// (`pumpAndSettle`) `router.state.uri`, not the value passed to `router.go`
/// at the tap — the redirect table's second evaluation is what actually
/// decided the old L2 defect (brief §6.1).
void main() {
  Future<(GoRouter, FakeStrumEngine)> pumpOnboarding(
    WidgetTester tester, {
    required bool adaptiveShellEnabled,
  }) async {
    final engine = FakeStrumEngine();
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        onboardingSeenProvider.overrideWith(() => OnboardingController(false)),
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: AppEnvironment.development,
            apiBaseUrl: AppConfig.devApiBaseUrl,
            flags: FeatureFlags(
              accountEnabled: false,
              diagnosticsEnabled: true,
              labModeAvailable: true,
              adaptiveShellEnabled: adaptiveShellEnabled,
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
      await engine.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.welcome);
    return (router, engine);
  }

  Future<void> tapThroughToLastPage(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  /// E17-R01 (ADR 0534 D1): the Stage now sits between the first-win CTA and
  /// the scored mini-lesson — pin-guard retype (brief §4): drives a strong
  /// reading through the SAME `strumEngineProvider` override already in
  /// play and continues, landing on `LearnScreen` exactly as before.
  Future<void> passThroughFirstWinStage(
    WidgetTester tester,
    FakeStrumEngine engine,
  ) async {
    expect(find.byType(FirstWinStageScreen), findsOneWidget);
    engine.emit(_strongStrumFrame());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboard-first-win-continue')));
    await tester.pumpAndSettle();
  }

  group('A2 — the belépési 2×2 mátrix (settled router URI)', () {
    testWidgets('shell BE × Skip/finish settles on /today', (tester) async {
      final (router, _) = await pumpOnboarding(
        tester,
        adaptiveShellEnabled: true,
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.today);
    });

    testWidgets('shell BE × first-win settles on /today', (tester) async {
      final (router, engine) = await pumpOnboarding(
        tester,
        adaptiveShellEnabled: true,
      );

      await tapThroughToLastPage(tester);
      await tester.tap(find.text('Try your first win — 30 seconds'));
      await tester.pumpAndSettle();
      await passThroughFirstWinStage(tester, engine);

      expect(router.state.uri.path, AppRoutes.today);
      expect(find.byType(LearnScreen), findsOneWidget);
      expect(
        tester.widget<LearnScreen>(find.byType(LearnScreen)).lesson.id,
        Lessons.firstWin.id,
      );
    });

    testWidgets(
      'shell BE × first-win Stage "Not now" ALSO settles on /today — A3, no '
      'literal route in either branch',
      (tester) async {
        final (router, _) = await pumpOnboarding(
          tester,
          adaptiveShellEnabled: true,
        );

        await tapThroughToLastPage(tester);
        await tester.tap(find.text('Try your first win — 30 seconds'));
        await tester.pumpAndSettle();
        expect(find.byType(FirstWinStageScreen), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('onboard-first-win-skip')));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, AppRoutes.today);
        expect(
          find.byType(LearnScreen),
          findsNothing,
          reason: '"Not now" abandons the attempt — no mini-lesson push',
        );
      },
    );

    testWidgets('shell KI × Skip/finish settles on /live (non-redirected)', (
      tester,
    ) async {
      final (router, _) = await pumpOnboarding(
        tester,
        adaptiveShellEnabled: false,
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.live);
    });

    testWidgets('shell KI × first-win settles on /live (non-redirected)', (
      tester,
    ) async {
      final (router, engine) = await pumpOnboarding(
        tester,
        adaptiveShellEnabled: false,
      );

      await tapThroughToLastPage(tester);
      await tester.tap(find.text('Try your first win — 30 seconds'));
      await tester.pumpAndSettle();
      await passThroughFirstWinStage(tester, engine);

      expect(router.state.uri.path, AppRoutes.live);
      expect(find.byType(LearnScreen), findsOneWidget);
      expect(
        tester.widget<LearnScreen>(find.byType(LearnScreen)).lesson.id,
        Lessons.firstWin.id,
      );
    });
  });

  group(
    'A2 — isolated onboarding-only rig (review MAJOR-1, falszifikáció)',
    () {
      // The `pumpOnboarding` cells above run under the REAL `routerProvider`,
      // which has two guard rails unrelated to this round's D1/D2 contract:
      // (1) `onboardingRedirect`'s reactive redirect, which fires the instant
      // `onboardingSeenProvider` flips true and lands on the router's OWN
      // (unmutated) `entryLocation`; (2) `app_router.dart`'s
      // `onException: (_, _, router) => router.go(entryLocation)`, which
      // catches the `GoException` a mutated `router.go('/today')` throws when
      // `/today` isn't registered under the current flag (shell KI) and
      // redirects to the correct target anyway. Both converge on the
      // CORRECT entry location regardless of what the onboarding screen's
      // OWN navigation call targets, so a flag-blind regression in
      // `_completeFinish`/`_completeFirstWin` (the D1/D2 duplicate-source
      // ban's most likely future break) stays green through the real router
      // (brief §7.1 pont 2, review MAJOR-1). This rig removes BOTH nets on
      // purpose — a bare `GoRouter` with NEITHER `redirect` NOR `onException`
      // wired, and BOTH `/today` and `/live` registered under every flag
      // state so a mutated call never throws — so the only thing left
      // deciding the settled URI is the onboarding screen's own
      // `entryLocationFor(...)` call.
      Future<GoRouter> pumpBareOnboarding(
        WidgetTester tester, {
        required bool adaptiveShellEnabled,
      }) async {
        final container = ProviderContainer(
          overrides: [
            ...preferenceOverrides(),
            onboardingSeenProvider.overrideWith(
              () => OnboardingController(false),
            ),
            appConfigProvider.overrideWithValue(
              AppConfig(
                environment: AppEnvironment.development,
                apiBaseUrl: AppConfig.devApiBaseUrl,
                flags: FeatureFlags(
                  accountEnabled: false,
                  diagnosticsEnabled: true,
                  labModeAvailable: true,
                  adaptiveShellEnabled: adaptiveShellEnabled,
                ),
                diagnosticsToken: AppConfig.devDiagnosticsToken,
                buildMode: 'test',
                appVersion: 'test',
              ),
            ),
          ],
        );
        final router = GoRouter(
          initialLocation: AppRoutes.welcome,
          routes: [
            GoRoute(
              path: AppRoutes.welcome,
              builder: (_, _) => const OnboardingScreen(),
            ),
            GoRoute(
              path: AppRoutes.today,
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: AppRoutes.live,
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
        });

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.welcome);
        return router;
      }

      testWidgets('shell BE × Skip/finish: bare rig settles on /today', (
        tester,
      ) async {
        final router = await pumpBareOnboarding(
          tester,
          adaptiveShellEnabled: true,
        );

        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, entryLocationFor(true));
      });

      testWidgets('shell KI × Skip/finish: bare rig settles on /live', (
        tester,
      ) async {
        final router = await pumpBareOnboarding(
          tester,
          adaptiveShellEnabled: false,
        );

        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, entryLocationFor(false));
      });
    },
  );
}
