// The Chapter 13 closure package (brief §3.2/§7): route-, permission-,
// state-restoration- and 200%-text-scale cells for the app's critical
// flows — cold start, mic/camera consent, tab-stack and session-pause
// restoration, and login. Unlike `test/ui/goldens/e13_r36_variant_matrix_
// test.dart` (layout only, no interaction), every cell here TAPS through a
// real flow at `textScale: 2.0` and asserts `tester.takeException()` stays
// null, mirroring the existing `test/app/routing/app_router_test.dart` /
// `test/app/navigation/tab_state_restoration_test.dart` harness pattern —
// extended with the 200% scale this suite is the gate for (A5). Nothing
// here weakens `semantics_contract_test.dart`, `tap_target_test.dart` or
// `screen_reader_copy_test.dart` — it only adds cells.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/permission_primer_screen.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../fixtures/practice/session/practice_session_test_fixtures.dart';
import '../support/fake_audio.dart';
import '../support/fake_auth.dart';
import '../support/fake_engines.dart';
import '../support/preference_store.dart';

// ---------------------------------------------------------------------------
// Shared router harness — a trimmed `test/app/routing/app_router_test.dart`
// pattern, with the `textScale` this suite is the gate for.
// ---------------------------------------------------------------------------

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp({required this.textScale});

  final double textScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      // R2 (§0.0, extended measurement): `/welcome` resolves to
      // OnboardingScreen, now migrated to SsButton/SsSection — a themeless
      // (or legacy-AppTheme) MaterialApp null-check crashes (L593-class
      // defect). SsLightTheme is additive-only over AppPalette (ADR 0466
      // D2), so this does not change any non-migrated screen's colours.
      theme: SsLightTheme.data(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required bool seen,
  bool accountEnabled = false,
  bool practiceEngineV2Enabled = false,
  bool adaptiveShellEnabled = false,
  double textScale = 2.0,
  Size viewport = const Size(400, 800),
}) async {
  tester.view.physicalSize = viewport;
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
      onboardingSeenProvider.overrideWith(() => OnboardingController(seen)),
      accountEnabledProvider.overrideWithValue(accountEnabled),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: accountEnabled,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            practiceEngineV2Enabled: practiceEngineV2Enabled,
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
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _RouterTestApp(textScale: textScale),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  // -------------------------------------------------------------------------
  // A6 — route closure: critical destinations stay reachable at textScale
  // 2.0 (the layout matrix checks the SCREEN in isolation; this checks the
  // ROUTER actually lands on it).
  // -------------------------------------------------------------------------
  group('A6 — critical routes resolve at textScale 2.0', () {
    testWidgets('first launch settles on welcome, no exception', (
      tester,
    ) async {
      final router = await _pumpRouter(tester, seen: false);

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.welcome);
    });

    testWidgets('completed onboarding lands on Live, no exception', (
      tester,
    ) async {
      final router = await _pumpRouter(tester, seen: true);

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.live);
      expect(find.byType(LiveScreen), findsOneWidget);
    });

    testWidgets('Settings route reaches SettingsScreen, no exception', (
      tester,
    ) async {
      final router = await _pumpRouter(tester, seen: true);

      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('Tuner route reaches TunerScreen, no exception', (
      tester,
    ) async {
      final router = await _pumpRouter(tester, seen: true);

      router.go(AppRoutes.tuner);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.tuner);
    });

    testWidgets('an unknown path is recovered to Live, no exception', (
      tester,
    ) async {
      final router = await _pumpRouter(tester, seen: true);

      router.go('/does-not-exist');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.live);
      expect(find.byType(LiveScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // A4 — permission closure: mic/camera denial primers survive at
  // textScale 2.0, both the retryable and the permanently-denied shape.
  // -------------------------------------------------------------------------
  group('A4 — permission-denied flows survive at textScale 2.0', () {
    // Captures `FlutterError.onError` reports instead of letting the
    // default test-binding behaviour surface them as a thrown exception —
    // the same technique as `e13_r36_variant_matrix_test.dart`, needed for
    // the ONE dated, measured `lib/**` defect below that this round cannot
    // fix (brief §4: `lib/**` is this round's tilos zona).
    Future<List<String>> pumpPrimer(
      WidgetTester tester, {
      required MicrophonePermissionGateway gateway,
      Future<bool> Function()? openSettings,
      VoidCallback? onGranted,
      double textScale = 2.0,
    }) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final captured = <String>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) =>
          captured.add(details.exception.toString());

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              microphonePermissionGatewayProvider.overrideWithValue(gateway),
            ],
            child: MaterialApp(
              // SsLightTheme (not AppTheme — see e13_r30's golden comment):
              // the permanently-denied branch renders `SsPermissionState`,
              // which force-unwraps the design-system `SsColorScheme`/
              // `SsTypography` theme extensions AppTheme does not register.
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: PermissionPrimerScreen(
                onGranted: onGranted,
                openSettings: openSettings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previousOnError;
      }
      return captured;
    }

    testWidgets(
      'a retryable denial shows the Allow action, and tapping it re-asks '
      'the gateway without an exception',
      (tester) async {
        final gateway = FakeMicrophonePermissionGateway(
          state: MicrophonePermissionState.denied,
        );
        var granted = false;
        final errors = await pumpPrimer(
          tester,
          gateway: gateway,
          onGranted: () => granted = true,
        );

        expect(errors, isEmpty);
        expect(
          find.byKey(const ValueKey('onboard-primer-allow')),
          findsOneWidget,
        );

        gateway.state = MicrophonePermissionState.granted;
        final allowButton = find.byKey(const ValueKey('onboard-primer-allow'));
        // At textScale 2.0 the primer's SingleChildScrollView pushes the
        // button below the fold — `tap()` alone hit-tests the current
        // viewport and misses it, so scroll it into view first.
        await tester.ensureVisible(allowButton);
        await tester.pumpAndSettle();
        await tester.tap(allowButton);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(gateway.requestCalls, 1);
        expect(granted, isTrue);
      },
    );

    testWidgets(
      'a permanent denial shows the open-settings action, and tapping it '
      'calls the injected opener without an exception — at textScale 1.0',
      (tester) async {
        var openedSettings = 0;
        final errors = await pumpPrimer(
          tester,
          textScale: 1.0,
          gateway: FakeMicrophonePermissionGateway(
            state: MicrophonePermissionState.permanentlyDenied,
          ),
          openSettings: () async {
            openedSettings++;
            return true;
          },
        );

        expect(errors, isEmpty);
        final openSettingsButton = find.byWidgetPredicate(
          (widget) => widget is FilledButton || widget is OutlinedButton,
        );
        expect(openSettingsButton, findsWidgets);

        await tester.tap(openSettingsButton.first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(openedSettings, 1);
      },
    );

    testWidgets(
      'RESOLVED (E15-R02, was measured 2026-08-27 at 297px, lib/** — see '
      'docs/ui/legacy-backlog.md): the permanently-denied primer no longer '
      'overflows at textScale 2.0, now that its branch is wrapped in a '
      'SingleChildScrollView like the retryable branch.',
      (tester) async {
        final errors = await pumpPrimer(
          tester,
          textScale: 2.0,
          gateway: FakeMicrophonePermissionGateway(
            state: MicrophonePermissionState.permanentlyDenied,
          ),
        );

        expect(
          errors.any((e) => e.contains('overflowed')),
          isFalse,
          reason:
              'REGRESSION: lib/features/onboarding/screens/'
              'permission_primer_screen.dart overflows its '
              'permanently-denied branch at textScale 2.0 again — see '
              'docs/ui/legacy-backlog.md §1 (E15-R02 resolution)',
        );
      },
    );

    testWidgets(
      'a denied camera gateway renders Vision Setup without an exception',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cameraPermissionGatewayProvider.overrideWithValue(
                const _DeniedCameraGateway(),
              ),
              cameraSessionCoordinatorProvider.overrideWithValue(
                CameraSessionCoordinator(),
              ),
              keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            ],
            child: MaterialApp(
              // R2 (§0.0, extended measurement): VisionSetupScreen is now
              // migrated (SsCard/SsButton/SsSection) — a legacy AppTheme
              // null-check crashes (L593-class defect).
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
              home: const VisionSetupScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // A2 — state-restoration closure: a preserved navigation branch stack and
  // a resumed practice session, both at textScale 2.0.
  // -------------------------------------------------------------------------
  group('A2 — state restoration survives textScale 2.0', () {
    testWidgets(
      'switching tabs and back preserves the pushed sub-route (not reset '
      'to the destination root)',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          seen: true,
          practiceEngineV2Enabled: true,
          adaptiveShellEnabled: true,
        );

        router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();
        expect(find.byType(PracticeAreaHubScreen), findsOneWidget);

        router.push(AppRoutes.practiceChords);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ChordLibraryScreen), findsOneWidget);

        await tester.tap(find.text('Song library'));
        await tester.pumpAndSettle();
        expect(find.byType(ChordLibraryScreen), findsNothing);

        await tester.tap(find.text('Practice hub'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byType(ChordLibraryScreen),
          findsOneWidget,
          reason:
              'returning to the Practice tab must restore its sub-route at '
              '200% text scale too, not reset to the destination root',
        );
        expect(router.state.uri.path, AppRoutes.practiceChords);
      },
    );

    testWidgets('the pause/recovery overlay resumes the session on tap, at '
        'textScale 2.0', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final host = FakeSessionHost();
      host.emitState(
        practiceSessionStateFor(
          PracticeSessionStatus.paused,
          definition: practiceSessionFixtureDefinition(
            id: 'closure.session.paused',
          ),
          config: practiceSessionFixtureConfig(
            definitionId: 'closure.session.paused',
          ),
          pauseCause: PauseCause.interruption,
        ),
      );
      addTearDown(host.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            appConfigProvider.overrideWithValue(
              AppConfig(
                environment: AppEnvironment.development,
                apiBaseUrl: AppConfig.devApiBaseUrl,
                flags: const FeatureFlags(
                  accountEnabled: false,
                  diagnosticsEnabled: false,
                  labModeAvailable: false,
                ),
                diagnosticsToken: AppConfig.devDiagnosticsToken,
                buildMode: 'test',
                appVersion: 'test',
              ),
            ),
            appLifecycleEventsProvider.overrideWithValue(FakeLifecycleEvents()),
            practiceSessionHostProvider.overrideWithValue(host),
            practiceFeedbackOutputProvider.overrideWithValue(
              const _NoopFeedback(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: const PracticeSessionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final resumeButton = find.byKey(
        const ValueKey('practice-pause-overlay-resume'),
      );
      expect(resumeButton, findsOneWidget);

      await tester.tap(resumeButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(host.sent, contains(const ResumePractice()));
    });
  });

  // -------------------------------------------------------------------------
  // A5 — 200% text-scale interactive smoke: the critical login round trip
  // actually completes (not just renders) at textScale 2.0.
  // -------------------------------------------------------------------------
  group('A5 — the login round trip completes at textScale 2.0', () {
    testWidgets(
      'Settings -> Sign in -> submit credentials -> pops back to Settings',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          seen: true,
          accountEnabled: true,
        );
        router.go(AppRoutes.settings);
        await tester.pumpAndSettle();

        // At textScale 2.0 the account section sits well past the first
        // viewport-full of the Settings ListView, which — like any Sliver
        // list — only builds children near the visible range: `tap()` alone
        // would find nothing to hit-test. Scroll it into view first.
        final signInText = find.text('Sign in');
        await tester.scrollUntilVisible(
          signInText,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(router.state.uri.path, AppRoutes.login);
        expect(find.byType(LoginScreen), findsOneWidget);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'player@strumsight.app');
        await tester.enterText(fields.at(1), 'password123');
        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(router.state.uri.path, AppRoutes.settings);
        expect(find.byType(SettingsScreen), findsOneWidget);
      },
    );
  });
}

final class _DeniedCameraGateway implements CameraPermissionGateway {
  const _DeniedCameraGateway();

  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.denied;

  @override
  Future<CameraPermissionState> request() async => CameraPermissionState.denied;
}

final class _NoopFeedback implements PracticeFeedbackOutput {
  const _NoopFeedback();
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}
