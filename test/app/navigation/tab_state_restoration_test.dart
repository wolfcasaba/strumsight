// E13-R08 (ADR 0275, D9) — A3.
//
// The selected branch's navigation stack must survive a tab switch and a
// return to that tab: `StatefulShellRoute.indexedStack` + tapping the
// primary-navigation destinations (which call `navigationShell.goBranch`,
// never `context.go`) keeps each branch's Navigator alive in the
// background. Using `context.go` instead would discard the branch stack —
// exactly the regression this test must catch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

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

Future<GoRouter> _pumpCompactAdaptiveRouter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

void main() {
  testWidgets(
    'pushing a sub-route, switching tabs, and switching back keeps the '
    'branch on its sub-route (not reset to the destination root)',
    (tester) async {
      final router = await _pumpCompactAdaptiveRouter(tester);

      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();
      expect(find.byType(PracticeHubScreen), findsOneWidget);

      router.push(AppRoutes.practiceChords);
      await tester.pumpAndSettle();
      expect(find.byType(ChordLibraryScreen), findsOneWidget);
      expect(router.state.uri.path, AppRoutes.practiceChords);

      // Switch away via the real navigation destination (goBranch), not
      // router.go — tapping is what a user does, and it's the path that
      // would break silently if the wiring used context.go instead.
      await tester.tap(find.text('Song library'));
      await tester.pumpAndSettle();
      expect(find.byType(ChordLibraryScreen), findsNothing);

      await tester.tap(find.text('Practice hub'));
      await tester.pumpAndSettle();

      expect(
        find.byType(ChordLibraryScreen),
        findsOneWidget,
        reason:
            'returning to the Practice tab must restore its sub-route, not '
            'reset to the destination root',
      );
      expect(router.state.uri.path, AppRoutes.practiceChords);

      // The preserved stack still pops normally: back to the hub.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PracticeHubScreen), findsOneWidget);
    },
  );
}
