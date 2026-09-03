// E13-R30 acceptance: A1 (explicit-action-only camera), A2 (no default frame
// retention + a visible status) and A6 (unsupported-device audio-only
// alternative). See docs/rounds/e13-r30-vision-ui.md §6/§6.1.
//
// Actions that reach `VisionSessionController._finalizeOnce` (stop,
// leaveRoute, disposal) close the `FakeCameraCapture`'s broadcast stream
// controller — under `testWidgets`'s fake clock that resolution needs a real
// event-loop turn, so those calls are wrapped in `tester.runAsync` (measured;
// without it the awaited `stop()` never settles even though the identical
// call resolves instantly in a plain `test()`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/presentation/providers/vision_capability_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

final class _PermissionGateway implements CameraPermissionGateway {
  _PermissionGateway(this.state);

  final CameraPermissionState state;

  @override
  Future<CameraPermissionState> currentState() async => state;

  @override
  Future<CameraPermissionState> request() async => state;
}

// R2 (§0.0, extended measurement): VisionSessionScreen/VisionSetupScreen now
// read the design-system theme extensions via their migrated SsButton/
// SsCard/SsSection/SsSwitchRow — a themeless MaterialApp null-check crashes
// (L593-class defect).
Widget _host(Widget child) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

ProviderContainer _sessionContainer(FakeCameraCapture capture) {
  final container = ProviderContainer(
    overrides: [
      cameraPermissionGatewayProvider.overrideWithValue(
        _PermissionGateway(CameraPermissionState.granted),
      ),
      cameraCaptureFactoryProvider.overrideWithValue(() => capture),
      cameraSessionCoordinatorProvider.overrideWithValue(
        CameraSessionCoordinator(),
      ),
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      visionSessionClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 27, 12),
      ),
      visionSessionIdFactoryProvider.overrideWithValue(
        () => VisionSessionId.create('permission-test-session'),
      ),
    ],
  );
  container.listen(visionSessionControllerProvider, (_, _) {});
  return container;
}

void main() {
  group('A1 — the camera opens only after an explicit user action', () {
    testWidgets(
      'mounting, granting permission, and entering calibration never start '
      'capture; only the explicit Start tap does',
      (tester) async {
        final capture = FakeCameraCapture();
        final container = _sessionContainer(capture);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _host(const VisionSessionScreen()),
          ),
        );
        await tester.pump();
        expect(
          capture.startCalls,
          0,
          reason: 'mounting must not open the camera',
        );

        await tester.tap(find.byKey(const Key('vision-session-begin')));
        await tester.pumpAndSettle();
        expect(
          capture.startCalls,
          0,
          reason: 'begin() only reads permission state, never starts capture',
        );

        await tester.tap(find.byKey(const Key('vision-session-calibrate')));
        await tester.pump();
        expect(
          capture.startCalls,
          0,
          reason: 'entering calibration is a confirmed step, not capture start',
        );

        await tester.tap(find.byKey(const Key('vision-session-start')));
        await tester.pumpAndSettle();
        expect(
          capture.startCalls,
          1,
          reason: 'only the explicit Start action opens the camera',
        );
      },
    );
  });

  group('A2 — the frame is not saved by default and the retention status is '
      'visible', () {
    testWidgets('setup always shows the on-device / not-recorded notice', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          cameraPermissionGatewayProvider.overrideWithValue(
            _PermissionGateway(CameraPermissionState.denied),
          ),
          cameraSessionCoordinatorProvider.overrideWithValue(
            CameraSessionCoordinator(),
          ),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const VisionSetupScreen()),
        ),
      );
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(VisionSetupScreen)),
      );
      expect(find.text(l10n.visionSetupPrivacyBody), findsOneWidget);
    });

    testWidgets(
      'a completed session states plainly that frames were not saved',
      (tester) async {
        final capture = FakeCameraCapture();
        final container = _sessionContainer(capture);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _host(const VisionSessionScreen()),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('vision-session-begin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('vision-session-calibrate')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('vision-session-start')));
        await tester.pumpAndSettle();

        await tester.runAsync(
          () => container.read(visionSessionControllerProvider.notifier).stop(),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(VisionSessionScreen)),
        );
        expect(
          find.byKey(const Key('vision-result-frame-retention')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.visionResultFrameRetentionNotSaved),
          findsOneWidget,
        );
      },
    );
  });

  group('A6 — an unsupported device gets an audio-only alternative', () {
    testWidgets('the setup screen skips the wizard steps entirely', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          visionDeviceCapabilityProvider.overrideWithValue(
            VisionDeviceCapability.unsupported,
          ),
          cameraPermissionGatewayProvider.overrideWithValue(
            _PermissionGateway(CameraPermissionState.unavailable),
          ),
          cameraSessionCoordinatorProvider.overrideWithValue(
            CameraSessionCoordinator(),
          ),
          keyValueStoreProvider.overrideWithValue(
            InMemoryKeyValueStore(<String, Object>{
              StorageKeys.onboardingSeen: true,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const VisionSetupScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('vision-audio-only-continue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vision-setup-unsupported-notice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vision-setup-profile-continue')),
        findsNothing,
      );
      expect(find.byKey(const Key('vision-setup-skip')), findsNothing);
    });

    testWidgets('a supported device still gets the full wizard', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          cameraPermissionGatewayProvider.overrideWithValue(
            _PermissionGateway(CameraPermissionState.denied),
          ),
          cameraSessionCoordinatorProvider.overrideWithValue(
            CameraSessionCoordinator(),
          ),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(const VisionSetupScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('vision-setup-profile-continue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vision-setup-unsupported-notice')),
        findsNothing,
      );
    });
  });
}
