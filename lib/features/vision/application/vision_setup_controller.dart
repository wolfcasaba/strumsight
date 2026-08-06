import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_capture.dart';
import '../../../core/camera/camera_permission.dart';
import '../../../core/camera/camera_providers.dart';
import '../../../core/camera/camera_session_coordinator.dart';
import '../../../core/camera/camera_session_lease.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/vision_setup_profile.dart';

/// The user-visible positions in the optional Vision setup flow.
enum VisionSetupStep { profile, camera, permission, ready, audioOnly }

/// Immutable state for the guided, optional camera setup.
final class VisionSetupState {
  const VisionSetupState({
    required this.step,
    required this.leftHanded,
    required this.selectedProfile,
    required this.selectedCamera,
    required this.permissionState,
    required this.cameraSessionActive,
  });

  final VisionSetupStep step;
  final bool leftHanded;
  final VisionSetupProfile selectedProfile;
  final VisionCameraPreference selectedCamera;
  final CameraPermissionState permissionState;
  final bool cameraSessionActive;

  VisionSetupProfile get recommendedProfile =>
      VisionSetupProfile.recommendedFor(leftHanded: leftHanded);

  VisionSetupState copyWith({
    VisionSetupStep? step,
    VisionSetupProfile? selectedProfile,
    VisionCameraPreference? selectedCamera,
    CameraPermissionState? permissionState,
    bool? cameraSessionActive,
  }) => VisionSetupState(
    step: step ?? this.step,
    leftHanded: leftHanded,
    selectedProfile: selectedProfile ?? this.selectedProfile,
    selectedCamera: selectedCamera ?? this.selectedCamera,
    permissionState: permissionState ?? this.permissionState,
    cameraSessionActive: cameraSessionActive ?? this.cameraSessionActive,
  );
}

/// Coordinates explicit permission, one camera lease, and the two setup
/// preferences. It never stores raw camera data and never asks permission
/// during provider construction.
class VisionSetupController extends Notifier<VisionSetupState> {
  CameraSessionCoordinator? _coordinator;
  CameraSessionLease? _lease;
  CameraCapture? _capture;

  @override
  VisionSetupState build() {
    final store = ref.read(keyValueStoreProvider);
    final leftHanded = store.readBool(StorageKeys.leftHanded) ?? false;
    final recommended = VisionSetupProfile.recommendedFor(
      leftHanded: leftHanded,
    );
    _coordinator = ref.read(cameraSessionCoordinatorProvider);
    ref.onDispose(_disposeCameraSession);
    return VisionSetupState(
      step: VisionSetupStep.profile,
      leftHanded: leftHanded,
      selectedProfile: _storedProfile(
        store.readString(StorageKeys.visionSetupProfile),
        recommended,
      ),
      selectedCamera: VisionCameraPreference.fromStorage(
        store.readString(StorageKeys.visionCamera),
      ),
      permissionState: CameraPermissionState.denied,
      cameraSessionActive: false,
    );
  }

  VisionSetupProfile _storedProfile(
    String? stored,
    VisionSetupProfile fallback,
  ) {
    if (stored == null) return fallback;
    return VisionSetupProfile.values.firstWhere(
      (profile) => profile.storageValue == stored,
      orElse: () => fallback,
    );
  }

  void selectProfile(VisionSetupProfile profile) {
    state = state.copyWith(selectedProfile: profile);
  }

  /// Persists only the two permitted setup preferences.
  Future<void> persistSelections() async {
    final store = ref.read(keyValueStoreProvider);
    await store.writeString(
      StorageKeys.visionSetupProfile,
      state.selectedProfile.storageValue,
    );
    await store.writeString(
      StorageKeys.visionCamera,
      state.selectedCamera.storageValue,
    );
  }

  /// Changes the future-camera preference. An active setup session is closed
  /// before a new lease and capture are opened, so there is never overlap.
  Future<void> selectCamera(VisionCameraPreference camera) async {
    if (state.selectedCamera == camera) return;
    final restart = state.cameraSessionActive;
    if (restart) await _closeCameraSession();
    state = state.copyWith(selectedCamera: camera);
    if (restart) await _openCameraSession();
  }

  void continueToCamera() {
    state = state.copyWith(step: VisionSetupStep.camera);
  }

  Future<void> continueToPermission() async {
    await persistSelections();
    state = state.copyWith(step: VisionSetupStep.permission);
  }

  /// Reads the platform status without showing a system permission dialog.
  Future<void> refreshPermissionState() async {
    final permission = await ref
        .read(cameraPermissionGatewayProvider)
        .currentState();
    state = state.copyWith(permissionState: permission);
  }

  /// The only explicit system permission request in this flow.
  Future<void> requestCameraPermission() async {
    final permission = await ref
        .read(cameraPermissionGatewayProvider)
        .request();
    state = state.copyWith(permissionState: permission);
    if (permission.isGranted) await _openCameraSession();
  }

  /// Leaves the setup through the fully supported audio-only path.
  Future<void> skip() async {
    await _closeCameraSession();
    state = state.copyWith(step: VisionSetupStep.audioOnly);
  }

  Future<void> _openCameraSession() async {
    if (state.cameraSessionActive) return;
    final coordinator = _coordinator;
    if (coordinator == null) return;

    final capture = ref.read(cameraCaptureFactoryProvider).call();
    final acquired = await coordinator.acquire(
      CameraOwner.visionSetup,
      onRevoke: () async {
        await capture.close();
        if (identical(_capture, capture)) {
          _capture = null;
          _lease = null;
          state = state.copyWith(cameraSessionActive: false);
        }
      },
    );
    switch (acquired) {
      case Failure<CameraSessionLease>():
        await capture.close();
        return;
      case Success<CameraSessionLease>(:final value):
        _capture = capture;
        _lease = value;
    }

    final started = await capture.start();
    if (started.isFailure) {
      await capture.close();
      await _lease?.release();
      _capture = null;
      _lease = null;
      return;
    }
    state = state.copyWith(
      step: VisionSetupStep.ready,
      cameraSessionActive: true,
    );
  }

  Future<void> _closeCameraSession() async {
    final capture = _capture;
    final lease = _lease;
    _capture = null;
    _lease = null;
    if (capture != null) await capture.close();
    if (lease != null) await lease.release();
    if (state.cameraSessionActive) {
      state = state.copyWith(cameraSessionActive: false);
    }
  }

  void _disposeCameraSession() {
    final capture = _capture;
    final lease = _lease;
    _capture = null;
    _lease = null;
    if (capture != null) unawaited(capture.close());
    if (lease != null) unawaited(lease.release());
  }
}
