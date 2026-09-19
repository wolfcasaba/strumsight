/// Riverpod wiring for the Vision frame pipeline (E09-R28a).
///
/// It lives in `application/` next to the session controller so the controller
/// can read it without importing the presentation layer — the same reason
/// `visionCalibrationRepositoryProvider` lives there.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../data/pipeline/vision_frame_pipeline.dart';
import '../data/pipeline/vision_session_geometry.dart';
import 'guitar_calibration_controller.dart';
import 'vision_session_controller.dart';

/// Builds one processor for one session start.
typedef VisionFrameProcessorFactory = VisionFrameProcessor Function();

/// The factory the session controller calls when capture starts.
///
/// The persisted calibration is read inside the returned closure, not while
/// this provider builds: after the user recalibrates mid-session, the next
/// start must see the bundle they just saved, not the one cached at route
/// entry.
final visionFrameProcessorFactoryProvider =
    Provider<VisionFrameProcessorFactory>((ref) {
      final repository = ref.watch(visionCalibrationRepositoryProvider);
      final store = ref.watch(keyValueStoreProvider);
      final clock = ref.watch(visionSessionClockProvider);
      return () {
        final context = guitarCalibrationContextFrom(store: store, now: clock);
        return FrameQualityPipeline(
          geometry: VisionSessionGeometry.resolve(
            record: repository.read(),
            context: VisionGeometryContext(
              camera: context.camera,
              orientation: context.orientation,
              zoom: context.zoom,
              now: context.now(),
            ),
          ),
          profile: context.setupProfile,
          now: clock,
        );
      };
    });
