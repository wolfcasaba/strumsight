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

/// The single runtime context the editor binds to. Tests override this
/// to inject a fixed `now` and a chosen camera/orientation/zoom.
final guitarCalibrationRuntimeContextProvider =
    Provider<GuitarCalibrationContext>((ref) {
      return GuitarCalibrationContext(
        camera: VisionCameraPreference.back,
        orientation: CameraRotation.degrees0,
        zoom: 0.5,
        setupProfile: VisionSetupProfile.practiceBalanced,
        now: DateTime.now,
      );
    });

/// The controller family — each runtime context produces its own state
/// instance so the editor can navigate between two contexts (e.g. mock vs.
/// live camera) without leaking state.
final guitarCalibrationControllerProvider =
    NotifierProvider.family<
      GuitarCalibrationController,
      GuitarCalibrationState,
      GuitarCalibrationContext
    >(GuitarCalibrationController.new);
