import 'package:flutter/widgets.dart';

/// Optional capability of a `CameraCapture` adapter that owns a live platform
/// preview surface.
///
/// It is deliberately a separate interface, not a member of `CameraCapture`:
/// only the plugin adapter can hand out a platform texture, and every test
/// double stays a plain `CameraCapture`. `capture is CameraPreviewSource` is
/// then the honest question "is there a real camera behind this session?" —
/// so a fake can never accidentally answer it with a fabricated surface.
abstract interface class CameraPreviewSource {
  /// The live preview for the running session, or `null` while the platform
  /// controller is not initialized (or the session is already closed).
  Widget? buildPreview();

  /// Whether the preview must be mirrored horizontally.
  ///
  /// True for a front lens, whose sensor image is the mirror of what the
  /// player sees. The adapter owns this because the adapter picks the lens.
  bool get previewMirror;
}
