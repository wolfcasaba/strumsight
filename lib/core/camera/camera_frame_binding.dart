import 'dart:typed_data';

import 'camera_format.dart';
import 'camera_frame.dart';
import 'camera_timestamp.dart';

/// A platform-owned frame plus the one-time action that relinquishes it.
///
/// The adapter must call [release] on every path. The binding is deliberately
/// platform-neutral so its ownership rules can be tested without device code.
final class PlatformCameraFrame {
  factory PlatformCameraFrame({
    required Uint8List bytes,
    required CameraTimestamp timestamp,
    required int width,
    required int height,
    required CameraPixelFormat format,
    required CameraOrientation orientation,
    required bool mirror,
    required CameraCrop? crop,
    required void Function() release,
  }) => PlatformCameraFrame._(
    bytes: bytes,
    timestamp: timestamp,
    width: width,
    height: height,
    format: format,
    orientation: orientation,
    mirror: mirror,
    crop: crop,
    release: release,
  );

  PlatformCameraFrame._({
    required this.bytes,
    required this.timestamp,
    required this.width,
    required this.height,
    required this.format,
    required this.orientation,
    required this.mirror,
    required this.crop,
    required this._release,
  });

  final Uint8List bytes;
  final CameraTimestamp timestamp;
  final int width;
  final int height;
  final CameraPixelFormat format;
  final CameraOrientation orientation;
  final bool mirror;
  final CameraCrop? crop;
  final void Function() _release;
  bool _released = false;

  /// Releases the platform buffer at most once.
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _release();
  }
}

/// Converts one platform frame to the stable [CameraFrame] contract.
abstract final class CameraFrameBinding {
  static CameraFrame bind(PlatformCameraFrame frame, {required int frameId}) =>
      CameraFrame(
        bytes: frame.bytes,
        frameId: frameId,
        timestamp: frame.timestamp,
        width: frame.width,
        height: frame.height,
        format: frame.format,
        orientation: frame.orientation,
        mirror: frame.mirror,
        crop: frame.crop,
      );
}
