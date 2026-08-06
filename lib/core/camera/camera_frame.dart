import 'dart:typed_data';

import 'camera_format.dart';
import 'camera_timestamp.dart';

/// One camera image delivered by [CameraCapture.frames].
///
/// The buffer is borrowed from the capture adapter. Read it only while the
/// stream listener callback is executing. After that callback returns, the
/// adapter invalidates this frame and [assertValid], [byteAt], and [copyBytes]
/// throw. Copy bytes synchronously when a later stage needs to retain them.
final class CameraFrame {
  CameraFrame({
    required Uint8List bytes,
    required this.frameId,
    required this.timestamp,
    required this.width,
    required this.height,
    required this.format,
    required this.orientation,
    this.mirror = false,
    this.crop,
  }) : _bytes = Uint8List.fromList(bytes) {
    if (frameId < 0) {
      throw ArgumentError.value(frameId, 'frameId', 'Must not be negative.');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame dimensions must be positive.');
    }
  }

  final Uint8List _bytes;
  final int frameId;
  final CameraTimestamp timestamp;
  final int width;
  final int height;
  final CameraPixelFormat format;
  final CameraOrientation orientation;

  /// Whether the source camera mirrored this frame horizontally.
  final bool mirror;

  /// Raw pixel-space crop reported by the platform, or `null` for full frame.
  final CameraCrop? crop;
  bool _isValid = true;

  /// Whether the borrowed buffer may still be read.
  bool get isValid => _isValid;

  /// Throws when code tries to use the borrowed buffer after delivery.
  void assertValid() {
    if (!_isValid) {
      throw StateError(
        'CameraFrame $frameId is no longer valid outside its stream callback.',
      );
    }
  }

  /// Number of bytes in the currently valid borrowed buffer.
  int get byteLength {
    assertValid();
    return _bytes.length;
  }

  /// Reads one byte while this frame is still valid.
  int byteAt(int index) {
    assertValid();
    return _bytes[index];
  }

  /// Copies the buffer so the caller can safely retain the returned data.
  Uint8List copyBytes() {
    assertValid();
    return Uint8List.fromList(_bytes);
  }

  /// Called by a capture adapter immediately after synchronous delivery.
  ///
  /// This is public only because adapters live in separate Dart libraries;
  /// application code must never call it.
  void invalidate() {
    _isValid = false;
  }
}

/// An unnormalised crop rectangle in source-frame pixels.
///
/// Coordinate transforms belong to the later frame-transform round; this type
/// only preserves what a platform adapter reported.
final class CameraCrop {
  const CameraCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0),
       assert(top >= 0),
       assert(width > 0),
       assert(height > 0);

  final int left;
  final int top;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CameraCrop &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}
