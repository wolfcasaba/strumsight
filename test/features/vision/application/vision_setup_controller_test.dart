import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/core/camera/fake_camera_capture.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/vision/application/vision_setup_controller.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';
import 'package:strumsight/features/vision/presentation/providers/vision_setup_providers.dart';

import '../../../support/preference_store.dart';

final class _FakePermissionGateway implements CameraPermissionGateway {
  _FakePermissionGateway({
    this.current = CameraPermissionState.denied,
    this.requestResult = CameraPermissionState.denied,
  });

  CameraPermissionState current;
  CameraPermissionState requestResult;
  int requestCalls = 0;

  @override
  Future<CameraPermissionState> currentState() async => current;

  @override
  Future<CameraPermissionState> request() async {
    requestCalls += 1;
    return requestResult;
  }
}

AppConfig _config() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    visionEnabled: true,
    visionSetupEnabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

ProviderContainer _container({
  required InMemoryKeyValueStore store,
  required _FakePermissionGateway permissions,
  required CameraSessionCoordinator coordinator,
  required List<FakeCameraCapture> captures,
}) => ProviderContainer(
  overrides: [
    preferenceStoreOverride(store),
    appConfigProvider.overrideWithValue(_config()),
    cameraPermissionGatewayProvider.overrideWithValue(permissions),
    cameraSessionCoordinatorProvider.overrideWithValue(coordinator),
    cameraCaptureFactoryProvider.overrideWithValue(() {
      final capture = FakeCameraCapture();
      captures.add(capture);
      return capture;
    }),
  ],
);

void main() {
  group('VisionSetupController', () {
    test(
      'left-handed preference changes the recommendation but not selection',
      () {
        final store = InMemoryKeyValueStore({StorageKeys.leftHanded: true});
        final permissions = _FakePermissionGateway();
        final container = _container(
          store: store,
          permissions: permissions,
          coordinator: CameraSessionCoordinator(),
          captures: <FakeCameraCapture>[],
        );
        addTearDown(container.dispose);

        final state = container.read(visionSetupControllerProvider);
        expect(state.recommendedProfile, VisionSetupProfile.rightHandFocus);
        expect(state.selectedProfile, VisionSetupProfile.rightHandFocus);

        container
            .read(visionSetupControllerProvider.notifier)
            .selectProfile(VisionSetupProfile.leftHandFocus);

        expect(
          container.read(visionSetupControllerProvider).selectedProfile,
          VisionSetupProfile.leftHandFocus,
        );
      },
    );

    test('persists exactly the profile and camera preference keys', () async {
      final store = InMemoryKeyValueStore();
      final container = _container(
        store: store,
        permissions: _FakePermissionGateway(),
        coordinator: CameraSessionCoordinator(),
        captures: <FakeCameraCapture>[],
      );
      addTearDown(container.dispose);
      final controller = container.read(visionSetupControllerProvider.notifier);

      controller.selectProfile(VisionSetupProfile.fullUpperBody);
      await controller.selectCamera(VisionCameraPreference.front);
      await controller.persistSelections();

      expect(store.values, {
        StorageKeys.visionSetupProfile: 'fullUpperBody',
        StorageKeys.visionCamera: 'front',
      });
    });

    test('permission request happens only from the explicit action', () async {
      final permissions = _FakePermissionGateway(
        current: CameraPermissionState.denied,
        requestResult: CameraPermissionState.denied,
      );
      final container = _container(
        store: InMemoryKeyValueStore(),
        permissions: permissions,
        coordinator: CameraSessionCoordinator(),
        captures: <FakeCameraCapture>[],
      );
      addTearDown(container.dispose);
      final controller = container.read(visionSetupControllerProvider.notifier);

      await controller.refreshPermissionState();
      expect(permissions.requestCalls, 0);

      await controller.requestCameraPermission();
      expect(permissions.requestCalls, 1);
    });

    test(
      'camera preference switch closes its lease before opening another',
      () async {
        final coordinator = CameraSessionCoordinator();
        final captures = <FakeCameraCapture>[];
        final container = _container(
          store: InMemoryKeyValueStore(),
          permissions: _FakePermissionGateway(
            requestResult: CameraPermissionState.granted,
          ),
          coordinator: coordinator,
          captures: captures,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          visionSetupControllerProvider.notifier,
        );

        await controller.requestCameraPermission();
        expect(coordinator.activeOwner, isNotNull);
        expect(captures, hasLength(1));
        expect(captures.single.startCalls, 1);

        await controller.selectCamera(VisionCameraPreference.front);

        expect(captures, hasLength(2));
        expect(captures.first.closeCalls, 1);
        expect(captures.last.startCalls, 1);
        expect(coordinator.activeOwner, isNotNull);
      },
    );

    test('skip never constructs or starts a camera capture', () async {
      final captures = <FakeCameraCapture>[];
      final container = _container(
        store: InMemoryKeyValueStore(),
        permissions: _FakePermissionGateway(),
        coordinator: CameraSessionCoordinator(),
        captures: captures,
      );
      addTearDown(container.dispose);

      await container.read(visionSetupControllerProvider.notifier).skip();

      expect(
        container.read(visionSetupControllerProvider).step,
        VisionSetupStep.audioOnly,
      );
      expect(captures, isEmpty);
    });
  });
}
