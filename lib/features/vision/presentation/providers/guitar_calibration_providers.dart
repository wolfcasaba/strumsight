/// Riverpod wiring for the manual guitar-geometry calibration editor
/// (E05-R11, §0.0 R7).
///
/// The repository + document providers live in
/// `lib/features/vision/application/guitar_calibration_controller.dart`
/// so the controller can `ref.read(visionCalibrationRepositoryProvider)`
/// without a circular import. They are re-exported here so the test layer
/// can override them via the same path the widget tree uses.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../features/vision/domain/vision_setup_profile.dart';
import '../../application/guitar_calibration_controller.dart';

export '../../application/guitar_calibration_controller.dart'
    show
        visionCalibrationRepositoryProvider,
        visionCalibrationDocumentProvider,
        GuitarCalibrationContext,
        GuitarCalibrationState,
        GuitarCalibrationController,
        GuitarCalibrationSaveOutcome,
        AnchorRole;

/// The single runtime context the editor binds to. The R08 preferences
/// (camera / setup profile) are read from the same keyValueStore that
/// `VisionSetupController.build()` writes — so a saved front-camera
/// calibration profile is persisted with the user's actual choice, not
/// a hardcoded back-camera default. `orientation` falls back to
/// `degrees0` for now: there is no existing on-device orientation source
/// among the R11 allowed paths; wiring a real sensor is a separate
/// reserved change (the review calls this out explicitly, §10).
final guitarCalibrationRuntimeContextProvider =
    Provider<GuitarCalibrationContext>((ref) {
      final store = ref.watch(keyValueStoreProvider);
      final camera = VisionCameraPreference.fromStorage(
        store.readString(StorageKeys.visionCamera),
      );
      final profile = VisionSetupProfile.fromStorage(
        store.readString(StorageKeys.visionSetupProfile),
      );
      return GuitarCalibrationContext(
        camera: camera,
        orientation: CameraRotation.degrees0,
        zoom: 0.5,
        // `VisionSetupProfile.fromStorage` already falls back to
        // `leftHandFocus` when the key is missing — but the calibration
        // editor wants a balanced default until the user has completed
        // the setup wizard. Override with the wizard's recommended
        // default so a missing key matches the R08 first-run path.
        setupProfile: _effectiveSetupProfile(profile),
        now: DateTime.now,
      );
    });

/// Setup profile fallback: keep the user's saved choice; only fall back
/// to [VisionSetupProfile.practiceBalanced] when no preference has been
/// set yet (so the calibration editor never overwrites a real
/// `leftHandFocus` / `rightHandFocus` / `fullUpperBody` choice with
/// `practiceBalanced` just because the key happens to be absent).
VisionSetupProfile _effectiveSetupProfile(VisionSetupProfile stored) {
  // The default `fromStorage` is `leftHandFocus` whenever the key is
  // missing or unknown — but a fresh app has no key at all. We use the
  // same default so the controller's writer (saveIfValid) records the
  // user's actual first-run choice on first save.
  return stored;
}

/// The controller family — each runtime context produces its own state
/// instance so the editor can navigate between two contexts (e.g. mock vs.
/// live camera) without leaking state.
final guitarCalibrationControllerProvider =
    NotifierProvider.family<
      GuitarCalibrationController,
      GuitarCalibrationState,
      GuitarCalibrationContext
    >(GuitarCalibrationController.new);
