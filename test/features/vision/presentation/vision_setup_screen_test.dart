import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/design_system/components/actions/ss_button.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/vision_setup_controller.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';
import 'package:strumsight/features/vision/presentation/providers/vision_setup_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_setup_screen.dart';
import 'package:strumsight/features/vision/presentation/widgets/camera_permission_panel.dart';
import 'package:strumsight/features/vision/presentation/widgets/vision_setup_frame_guide.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

// R2 (§0.0): the migrated screen's SsCard/SsButton/SsSection now read the
// design-system theme extensions — a themeless MaterialApp null-check
// crashes (L593-class defect).
Widget _host(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _DeniedPermissionGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.denied;

  @override
  Future<CameraPermissionState> request() async => CameraPermissionState.denied;
}

AppConfig _config({required bool visionEnabled, bool? visionSetupEnabled}) =>
    AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: AppConfig.devApiBaseUrl,
      flags: FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: visionEnabled,
        visionSetupEnabled: visionSetupEnabled ?? visionEnabled,
      ),
      diagnosticsToken: AppConfig.devDiagnosticsToken,
      buildMode: 'test',
      appVersion: 'test',
    );

ProviderContainer _setupContainer({
  required bool visionEnabled,
  bool? visionSetupEnabled,
}) {
  final store = InMemoryKeyValueStore({StorageKeys.onboardingSeen: true});
  return ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      appConfigProvider.overrideWithValue(
        _config(
          visionEnabled: visionEnabled,
          visionSetupEnabled: visionSetupEnabled,
        ),
      ),
      cameraPermissionGatewayProvider.overrideWithValue(
        _DeniedPermissionGateway(),
      ),
      cameraSessionCoordinatorProvider.overrideWithValue(
        CameraSessionCoordinator(),
      ),
    ],
  );
}

Future<void> _pumpSetup(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _host(const VisionSetupScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  group('camera permission panel', () {
    testWidgets('granted shows the continue state', (tester) async {
      await tester.pumpWidget(
        _host(
          const CameraPermissionPanel(
            state: CameraPermissionState.granted,
            onRequest: _noop,
            onOpenSettings: _noop,
          ),
        ),
      );

      expect(
        find.byKey(const Key('vision-permission-granted')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vision-permission-request')), findsNothing);
    });

    testWidgets('denied shows the explicit request action', (tester) async {
      await tester.pumpWidget(
        _host(
          const CameraPermissionPanel(
            state: CameraPermissionState.denied,
            onRequest: _noop,
            onOpenSettings: _noop,
          ),
        ),
      );

      expect(
        find.byKey(const Key('vision-permission-request')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vision-permission-settings')), findsNothing);
    });

    testWidgets('permanently denied sends the user to Settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CameraPermissionPanel(
            state: CameraPermissionState.permanentlyDenied,
            onRequest: _noop,
            onOpenSettings: _noop,
          ),
        ),
      );

      expect(
        find.byKey(const Key('vision-permission-settings')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vision-permission-request')), findsNothing);
    });

    testWidgets('restricted sends the user to Settings', (tester) async {
      await tester.pumpWidget(
        _host(
          const CameraPermissionPanel(
            state: CameraPermissionState.restricted,
            onRequest: _noop,
            onOpenSettings: _noop,
          ),
        ),
      );

      expect(
        find.byKey(const Key('vision-permission-settings')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vision-permission-request')), findsNothing);
    });

    testWidgets('unavailable explains the state without a request action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CameraPermissionPanel(
            state: CameraPermissionState.unavailable,
            onRequest: _noop,
            onOpenSettings: _noop,
          ),
        ),
      );

      expect(
        find.byKey(const Key('vision-permission-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vision-permission-request')), findsNothing);
    });
  });

  testWidgets('each setup profile renders its own frame guide', (tester) async {
    for (final profile in VisionSetupProfile.values) {
      await tester.pumpWidget(_host(VisionSetupFrameGuide(profile: profile)));
      expect(
        find.byKey(Key('vision-setup-guide-${profile.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('skip reaches audio-only continuation from every wizard step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final advanceCount in <int>[0, 1, 2]) {
      final container = _setupContainer(visionEnabled: true);
      addTearDown(container.dispose);
      await _pumpSetup(tester, container);

      for (var index = 0; index < advanceCount; index++) {
        final continueButton = find.byKey(
          Key(
            index == 0
                ? 'vision-setup-profile-continue'
                : 'vision-setup-camera-continue',
          ),
        );
        await tester.tap(continueButton);
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('vision-setup-skip')));
      await tester.pump();

      expect(
        find.byKey(const Key('vision-audio-only-continue')),
        findsOneWidget,
        reason: 'step index $advanceCount',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('Vision route is absent while either setup flag is disabled', () {
    final visionDisabled = _setupContainer(
      visionEnabled: false,
      visionSetupEnabled: true,
    );
    final setupDisabled = _setupContainer(
      visionEnabled: true,
      visionSetupEnabled: false,
    );
    addTearDown(visionDisabled.dispose);
    addTearDown(setupDisabled.dispose);

    expect(
      _containsRoute(visionDisabled.read(routerProvider).configuration.routes),
      isFalse,
    );
    expect(
      _containsRoute(setupDisabled.read(routerProvider).configuration.routes),
      isFalse,
    );
  });

  // A3 (§6/§0.0/R5) — the migrated screen must not overflow at the required
  // 1.5/2.0 textScale threshold pair, in both `en` and `hu`.
  group('A3 — textScale variant matrix (1.5 / 2.0 × en / hu)', () {
    Future<void> pumpVariant(
      WidgetTester tester,
      ProviderContainer container, {
      required double textScale,
      required Locale locale,
    }) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const Scaffold(body: VisionSetupScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final textScale in [1.5, 2.0]) {
      for (final locale in [const Locale('en'), const Locale('hu')]) {
        testWidgets(
          'renders the profile step without overflow at $textScale ($locale)',
          (tester) async {
            final container = _setupContainer(visionEnabled: true);
            addTearDown(container.dispose);
            await pumpVariant(
              tester,
              container,
              textScale: textScale,
              locale: locale,
            );

            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('the profile step uses the design-system SsButton', (
      tester,
    ) async {
      final container = _setupContainer(visionEnabled: true);
      addTearDown(container.dispose);
      await pumpVariant(
        tester,
        container,
        textScale: 1.0,
        locale: const Locale('en'),
      );

      expect(find.byType(SsButton), findsWidgets);
    });
  });

  // -------------------------------------------------------------------
  // WP-D (2026-09-06) — a gitár-geometria belépési pontja.
  //
  // MÉRT hiány: a `/vision/guitar-geometry` útvonalra a szállított
  // felületről SEMMI nem mutatott — a képernyőre csak a legacy
  // `/calibrate` címen lehetett eljutni, magára az útvonalra sehogy.
  // -------------------------------------------------------------------
  group('WP-D — the guitar-geometry entry point', () {
    testWidgets('the ready step opens /vision/guitar-geometry', (tester) async {
      await _pumpReadyStep(tester, visionGuitarGeometryEnabled: true);

      await tester.tap(
        find.byKey(const Key('vision-setup-open-guitar-geometry')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('STUB ${AppRoutes.visionGuitarGeometry}'),
        findsOneWidget,
      );
    });

    testWidgets('the entry is absent when visionGuitarGeometryEnabled is off '
        '(the route is not registered either)', (tester) async {
      await _pumpReadyStep(tester, visionGuitarGeometryEnabled: false);

      expect(
        find.byKey(const Key('vision-setup-open-guitar-geometry')),
        findsNothing,
      );
      // Kontroll: a KÉSZ lépés maga renderelődik — a hiányzó gomb nem
      // azért hiányzik, mert a képernyő máshol tart.
      expect(find.text('Camera setup is ready'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // R18 (audit B8) — a munkamenet belépési pontja.
  //
  // MÉRT hiány: a KÉSZ lépés egyetlen gombja a geometria-kalibráció volt,
  // magára a `/vision/session` címre SEMMI nem vezetett, a Today hub pedig
  // `visionSetupEnabled` mellett mindig a beállításra megy — a munkamenet
  // így a szállított felületről elérhetetlen volt.
  // -------------------------------------------------------------------
  group('R18 — the vision session entry point', () {
    testWidgets('the ready step opens /vision/session', (tester) async {
      await _pumpReadyStep(tester, visionGuitarGeometryEnabled: true);

      expect(
        find.byKey(const Key('vision-setup-start-session')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('vision-setup-start-session')));
      await tester.pumpAndSettle();

      expect(find.text('STUB ${AppRoutes.visionSession}'), findsOneWidget);
    });

    testWidgets('the session CTA is present even when the geometry step is '
        'off — the two are independent doors', (tester) async {
      await _pumpReadyStep(tester, visionGuitarGeometryEnabled: false);

      expect(
        find.byKey(const Key('vision-setup-open-guitar-geometry')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('vision-setup-start-session')));
      await tester.pumpAndSettle();

      expect(find.text('STUB ${AppRoutes.visionSession}'), findsOneWidget);
    });
  });
}

/// WP-D — a beállítás KÉSZ lépését közvetlenül állítja be, hogy a
/// geometria-belépési pont mérhető legyen a teljes engedély- és
/// kamera-lánc lefuttatása nélkül. A `refreshPermissionState` no-op: a
/// képernyő `initState`-je hívja, és a valós változat felülírná az itt
/// beállított állapotot.
final class _ReadyVisionSetupController extends VisionSetupController {
  @override
  VisionSetupState build() => const VisionSetupState(
    step: VisionSetupStep.ready,
    leftHanded: false,
    selectedProfile: VisionSetupProfile.leftHandFocus,
    selectedCamera: VisionCameraPreference.back,
    permissionState: CameraPermissionState.granted,
    cameraSessionActive: true,
  );

  @override
  Future<void> refreshPermissionState() async {}
}

/// WP-D harness — a valós beállítás-képernyő egy MINIMÁLIS go_router
/// alatt; a geometria helyén `STUB <path>` áll.
Future<void> _pumpReadyStep(
  WidgetTester tester, {
  required bool visionGuitarGeometryEnabled,
}) async {
  final store = InMemoryKeyValueStore({StorageKeys.onboardingSeen: true});
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            visionEnabled: true,
            visionSetupEnabled: true,
            visionGuitarGeometryEnabled: visionGuitarGeometryEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      cameraPermissionGatewayProvider.overrideWithValue(
        _DeniedPermissionGateway(),
      ),
      cameraSessionCoordinatorProvider.overrideWithValue(
        CameraSessionCoordinator(),
      ),
      visionSetupControllerProvider.overrideWith(
        _ReadyVisionSetupController.new,
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.visionSetup,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.visionSetup,
        builder: (_, _) => const VisionSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.visionGuitarGeometry,
        builder: (_, state) => Scaffold(body: Text('STUB ${state.uri.path}')),
      ),
      // R18 (audit B8) — the session the whole setup exists to prepare.
      GoRoute(
        path: AppRoutes.visionSession,
        builder: (_, state) => Scaffold(body: Text('STUB ${state.uri.path}')),
      ),
    ],
  );
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
  await tester.pump();
}

void _noop() {}

bool _containsRoute(List<RouteBase> routes) => routes.any((route) {
  if (route is GoRoute && route.path == AppRoutes.visionSetup) return true;
  return _containsRoute(route.routes);
});
