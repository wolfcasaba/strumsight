import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// ADR 0508 D1/D2 — the belépési 2×2 mátrix (brief §6 A2):
/// `adaptiveShellEnabled` × completion branch (Skip/finish, first-win), on a
/// REAL router — the flag is read via `appConfigProvider`, exactly like
/// `app_router.dart` and `OnboardingScreen` both do (`entryLocationFor`, the
/// single source both call). Every cell asserts the SETTLED
/// (`pumpAndSettle`) `router.state.uri`, not the value passed to `router.go`
/// at the tap — the redirect table's second evaluation is what actually
/// decided the old L2 defect (brief §6.1).
void main() {
  Future<GoRouter> pumpOnboarding(
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
    return router;
  }

  Future<void> tapThroughToLastPage(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  group('A2 — the belépési 2×2 mátrix (settled router URI)', () {
    testWidgets('shell BE × Skip/finish settles on /today', (tester) async {
      final router = await pumpOnboarding(tester, adaptiveShellEnabled: true);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.today);
    });

    testWidgets('shell BE × first-win settles on /today', (tester) async {
      final router = await pumpOnboarding(tester, adaptiveShellEnabled: true);

      await tapThroughToLastPage(tester);
      await tester.tap(find.text('Try your first win — 30 seconds'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.today);
    });

    testWidgets('shell KI × Skip/finish settles on /live (non-redirected)', (
      tester,
    ) async {
      final router = await pumpOnboarding(tester, adaptiveShellEnabled: false);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.live);
    });

    testWidgets('shell KI × first-win settles on /live (non-redirected)', (
      tester,
    ) async {
      final router = await pumpOnboarding(tester, adaptiveShellEnabled: false);

      await tapThroughToLastPage(tester);
      await tester.tap(find.text('Try your first win — 30 seconds'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.live);
    });
  });
}
