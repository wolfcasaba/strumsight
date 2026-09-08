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

import '../../../../core/storage/storage_providers.dart';
import '../../application/guitar_calibration_controller.dart';

export '../../application/guitar_calibration_controller.dart'
    show
        visionCalibrationRepositoryProvider,
        visionCalibrationDocumentProvider,
        GuitarCalibrationContext,
        GuitarCalibrationState,
        GuitarCalibrationController,
        GuitarCalibrationSaveOutcome,
        guitarCalibrationContextFrom,
        AnchorRole;

/// The single runtime context the editor binds to. The R08 preferences
/// (camera / setup profile) are read from the same keyValueStore that
/// `VisionSetupController.build()` writes — so a saved front-camera
/// calibration profile is persisted with the user's actual choice, not
/// a hardcoded back-camera default. `orientation` falls back to
/// `degrees0` for now: there is no existing on-device orientation source
/// among the R11 allowed paths; wiring a real sensor is a separate
/// reserved change (the review calls this out explicitly, §10).
///
/// It delegates to [guitarCalibrationContextFrom] so the running Vision
/// session (E09-R28a) evaluates a persisted bundle against exactly the
/// camera / orientation / zoom the editor saved it with.
final guitarCalibrationRuntimeContextProvider =
    Provider<GuitarCalibrationContext>(
      (ref) => guitarCalibrationContextFrom(
        store: ref.watch(keyValueStoreProvider),
        now: DateTime.now,
      ),
    );

/// The controller family — each runtime context produces its own state
/// instance so the editor can navigate between two contexts (e.g. mock vs.
/// live camera) without leaking state.
final guitarCalibrationControllerProvider =
    NotifierProvider.family<
      GuitarCalibrationController,
      GuitarCalibrationState,
      GuitarCalibrationContext
    >(GuitarCalibrationController.new);
