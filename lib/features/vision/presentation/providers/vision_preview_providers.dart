/// The live camera preview behind the Vision overlay (E09-R28a).
///
/// Before this round the app had no camera preview at all: the session screen
/// wrapped its overlay in a flat `surfaceSunken` box, so the camera really
/// opened and the player saw nothing of what it saw. `grep CameraPreview` had
/// zero hits in `lib/`.
///
/// The surface is exposed as a nullable provider that resolves to `null`
/// unless the running session's capture adapter really owns a platform
/// texture. Every test double is a plain `CameraCapture`, so under test this
/// stays `null` and the session screen keeps rendering the identical inert
/// box — which is what keeps the six pinned Vision goldens byte-identical.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/camera/camera_preview_source.dart';
import '../../application/vision_session_controller.dart';
import '../../application/vision_session_state.dart';

/// Builds the live preview widget, or returns `null` when there is none yet.
typedef VisionPreviewBuilder = Widget? Function();

/// The statuses in which a live preview may be shown.
///
/// Anything earlier means the camera permission gateway has not granted
/// access and no lease has been acquired, so there is nothing to render and
/// nothing to imply to the player.
const Set<VisionSessionStatus> visionPreviewStatuses = <VisionSessionStatus>{
  VisionSessionStatus.running,
  VisionSessionStatus.paused,
  VisionSessionStatus.calibrationLost,
};

/// Wraps a raw platform preview so a front lens reads as a mirror.
///
/// A front sensor delivers the scene reversed; showing it unmirrored makes
/// the player's own fretting hand appear on the wrong side of the neck.
Widget mirrorVisionPreview(Widget preview, {required bool mirror}) =>
    mirror ? Transform.scale(scaleX: -1, child: preview) : preview;

/// The preview for the current session, or `null` when there is none.
///
/// Overridden by tests that want a deterministic stand-in; left alone it asks
/// the running session's own capture adapter, which is the only object that
/// can answer honestly.
///
/// It is auto-disposing like the session controller it watches: a keep-alive
/// provider would hold that controller past route exit and defeat the camera
/// release the cleanup matrix pins.
final visionPreviewBuilderProvider =
    Provider.autoDispose<VisionPreviewBuilder?>((ref) {
      final status = ref.watch(
        visionSessionControllerProvider.select((state) => state.status),
      );
      if (!visionPreviewStatuses.contains(status)) return null;
      final CameraPreviewSource? source = ref
          .read(visionSessionControllerProvider.notifier)
          .previewSource;
      if (source == null) return null;
      return () {
        final preview = source.buildPreview();
        if (preview == null) return null;
        return mirrorVisionPreview(preview, mirror: source.previewMirror);
      };
    });
