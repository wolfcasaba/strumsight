// 2026-09-13 — task #7 sub-round. Three routes measured as "registered but
// unreachable" in the audit, each in a different shape:
//
//   - AppRoutes.settings (/settings): the legacy HomeShell's fifth tab —
//     `HomeShell.onDestinationSelected` reads `AppRoutes.shellTabs[4]` and
//     calls `context.go(AppRoutes.settings)`. Already proven reachable by
//     the `legacy_route_redirect_test.dart` A2 sweep (which asserts the
//     redirect target `/profile/settings` renders SettingsScreen), but the
//     LEGACY shell tab-tap path itself was never pinned. The first cell
//     below exercises that path explicitly: the user taps the Settings tab
//     on a `HomeShell` (NOT an adaptive shell) and the route lands on
//     `/settings` rendering SettingsScreen.
//
//   - AppRoutes.setlists (/setlists): the legacy `GoRoute` registers
//     `SetlistListScreen` at `/setlists` (app_router.dart line ~604), and
//     `legacyRedirects[setlists] → /songs/setlists` aliases the same screen
//     under the Songs destination when the adaptive shell is on. The two
//     cells below prove both reach the right widget.
//
//   - AppRoutes.recovery (/recovery): the safe-mode surface (ADR 0281 §3).
//     No shipped UI calls `context.push/go/replace(recovery)` — it is the
//     in-app degraded state the `BootstrapFailureApp` pre-first-frame
//     counterpart pairs with. The only navigation available is the explicit
//     `router.go(AppRoutes.recovery)` — that IS the reach contract for this
//     route, so the third cell pins it: a deep link must render
//     RecoveryScreen with the empty-problems fallback.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/bootstrap/recovery_screen.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/home_shell.dart';
import 'package:strumsight/app/routing/adaptive_shell_routes.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: SsLightTheme.data(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

Future<({ProviderContainer container, GoRouter router})> _pumpRouter(
  WidgetTester tester, {
  required bool seen,
  bool adaptiveShellEnabled = false,
}) async {
  final liveEngine = FakeStrumEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(liveEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(seen)),
      accountEnabledProvider.overrideWithValue(false),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
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
    await liveEngine.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

void main() {
  group('AppRoutes.settings — legacy shell tab reach (task #7 #1)', () {
    testWidgets(
      'HomeShell.onDestinationSelected(4) navigates to /settings and renders '
      'SettingsScreen (proves the legacy shell tab is a live entry point)',
      (tester) async {
        // Adaptive shell OFF → the legacy `HomeShell` is the only bottom-nav
        // surface and `AppRoutes.shellTabs[4]` IS `AppRoutes.settings`.
        final harness = await _pumpRouter(
          tester,
          seen: true,
          adaptiveShellEnabled: false,
        );

        // Sanity-pin: the catalog the shell reads really names settings.
        expect(AppRoutes.shellTabs[4], AppRoutes.settings);

        // Land on /live first (default for a seen onboarding, adaptive off),
        // then tap the Settings tab through the shell's own callback — the
        // SAME callback the bottom `NavigationBar` invokes in production.
        harness.router.go(AppRoutes.live);
        await tester.pumpAndSettle();
        final homeShellContext = tester.element(find.byType(HomeShell));
        GoRouter.of(homeShellContext).go(AppRoutes.shellTabs[4]);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(harness.router.state.uri.path, AppRoutes.settings);
        expect(find.byType(SettingsScreen), findsOneWidget);
      },
    );
  });

  group(
    'AppRoutes.setlists — legacy route + adaptive redirect (task #7 #2)',
    () {
      testWidgets(
        'adaptive shell OFF: /setlists renders SetlistListScreen directly',
        (tester) async {
          final harness = await _pumpRouter(
            tester,
            seen: true,
            adaptiveShellEnabled: false,
          );

          harness.router.go(AppRoutes.setlists);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(harness.router.state.uri.path, AppRoutes.setlists);
          expect(find.byType(SetlistListScreen), findsOneWidget);
        },
      );

      testWidgets(
        'adaptive shell ON: /setlists is a legacy-redirect source, lands on '
        '/songs/setlists and renders SetlistListScreen',
        (tester) async {
          final harness = await _pumpRouter(
            tester,
            seen: true,
            adaptiveShellEnabled: true,
          );

          harness.router.go(AppRoutes.setlists);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          // The redirect target is the SAME widget under a different path.
          expect(harness.router.state.uri.path, AppRoutes.songsSetlists);
          expect(
            legacyRedirects[AppRoutes.setlists],
            AppRoutes.songsSetlists,
            reason:
                'pinned: /setlists must alias /songs/setlists under the '
                'adaptive shell (E13-R08 D5)',
          );
          expect(find.byType(SetlistListScreen), findsOneWidget);
        },
      );
    },
  );

  group('AppRoutes.recovery — registered route is reachable by deep link '
      '(task #7 #3 — no contextual reach in production UI by design)', () {
    testWidgets(
      'a direct /recovery deep link renders RecoveryScreen with the empty-'
      'problems fallback (matches the in-app safe-mode contract, ADR 0281 '
      '§3/§6)',
      (tester) async {
        final harness = await _pumpRouter(
          tester,
          seen: true,
          adaptiveShellEnabled: false,
        );

        harness.router.go(AppRoutes.recovery);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(harness.router.state.uri.path, AppRoutes.recovery);
        final screen = tester.widget<RecoveryScreen>(
          find.byType(RecoveryScreen),
        );
        // No `extra` carried in the deep-link case: the route's own
        // builder falls back to `const <String>[]`.
        expect(screen.problems, isEmpty);
        // `onRetry` defaults to null — the deep link carries nothing to
        // retry, and the recovery screen hides the button in that case.
        expect(screen.onRetry, isNull);
      },
    );

    testWidgets(
      'a /recovery deep link carrying problems renders the RecoveryScreen '
      'verbatim (the route builder\'s `state.extra as List<String>?` '
      'cast survives a non-null payload)',
      (tester) async {
        final harness = await _pumpRouter(
          tester,
          seen: true,
          adaptiveShellEnabled: false,
        );

        const redactedProblems = <String>[
          'audio.capture.failed',
          'settings.persistence.read_failed',
        ];
        harness.router.go(AppRoutes.recovery, extra: redactedProblems);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(harness.router.state.uri.path, AppRoutes.recovery);
        final screen = tester.widget<RecoveryScreen>(
          find.byType(RecoveryScreen),
        );
        expect(screen.problems, redactedProblems);
      },
    );
  });
}
