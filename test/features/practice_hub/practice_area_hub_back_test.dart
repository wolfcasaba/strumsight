// E18-R01 emulator finding F4 — from the Practice hub's quick tools
// (Metronome, Chord library, Tuner, Live) and from Profile → Library the
// Android system back CLOSED THE APP instead of returning to the hub (4/4
// reproduced), and re-tapping the bottom tab did nothing either. Cause: the
// hubs navigated with `context.go`, which REPLACED the branch stack with the
// tool as its only page. These cells drive the REAL adaptive router the way
// a user does — tap the hub's own button, then the system back (the
// `flutter/navigation` popRoute the OS sends) — and assert the hub is back.
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
import 'package:strumsight/features/library_v2/providers/library_v2_providers.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
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

/// The compact adaptive shell with the Practice hub reachable — the same rig
/// as `tab_state_restoration_test.dart`, plus an empty Library source list
/// so Profile → Library renders without its file repositories.
Future<GoRouter> _pumpShell(WidgetTester tester) async {
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
      libraryV2SourcesProvider.overrideWithValue(const []),
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

/// What the OS sends on Android back: the `popRoute` platform message the
/// binding routes to the Router's back-button dispatcher.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('F4 — system back from a quick tool returns to the Practice hub', () {
    testWidgets('Tuner', (tester) async {
      final router = await _pumpShell(tester);
      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, l10n.liveTuner));
      await tester.pumpAndSettle();
      expect(find.byType(TunerScreen), findsOneWidget);
      expect(router.state.uri.path, AppRoutes.practiceTuner);

      await _systemBack(tester);
      expect(find.byType(TunerScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
      expect(router.state.uri.path, AppRoutes.practiceHub);
    });

    testWidgets('Metronome', (tester) async {
      final router = await _pumpShell(tester);
      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, l10n.metronomeTitle),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeScreen), findsOneWidget);

      await _systemBack(tester);
      expect(find.byType(MetronomeScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    });

    testWidgets('Chord library', (tester) async {
      final router = await _pumpShell(tester);
      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, l10n.chordLibraryTitle),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChordLibraryScreen), findsOneWidget);

      await _systemBack(tester);
      expect(find.byType(ChordLibraryScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    });

    testWidgets('Live (a Stage route outside the shell)', (tester) async {
      final router = await _pumpShell(tester);
      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, l10n.navLive));
      await tester.pumpAndSettle();
      expect(find.byType(LiveScreen), findsOneWidget);

      await _systemBack(tester);
      expect(find.byType(LiveScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    });
  });

  testWidgets(
    'F4 — re-tapping the SELECTED Practice tab from a quick tool returns to '
    'the hub (the branch root)',
    (tester) async {
      final router = await _pumpShell(tester);
      router.go(AppRoutes.practiceHub);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, l10n.liveTuner));
      await tester.pumpAndSettle();
      expect(find.byType(TunerScreen), findsOneWidget);

      await tester.tap(find.text(l10n.practiceHubTitle).last);
      await tester.pumpAndSettle();

      expect(find.byType(TunerScreen), findsNothing);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    },
  );

  testWidgets(
    'F4 — system back from Profile → Library returns to the Profile hub',
    (tester) async {
      final router = await _pumpShell(tester);
      router.go(AppRoutes.profileHome);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileHubScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, l10n.navLibrary));
      await tester.pumpAndSettle();
      expect(find.byType(UnifiedLibraryScreen), findsOneWidget);

      await _systemBack(tester);
      expect(find.byType(UnifiedLibraryScreen), findsNothing);
      expect(find.byType(ProfileHubScreen), findsOneWidget);
    },
  );
}
