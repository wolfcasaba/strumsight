import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_failure.dart';
import 'package:strumsight/core/camera/camera_format.dart';
import 'package:strumsight/core/camera/camera_frame.dart';
import 'package:strumsight/core/camera/camera_timestamp.dart';
import 'package:strumsight/core/foundation/app_failure.dart';

void main() {
  test(
    'camera timestamp is non-negative, ordered, and advances monotonically',
    () {
      const first = CameraTimestamp(10);
      final second = first.advanceBy(const Duration(microseconds: 5));

      expect(second, const CameraTimestamp(15));
      expect(second.compareTo(first), greaterThan(0));
      expect(() => CameraTimestamp(-1), throwsAssertionError);
    },
  );

  test('camera formats and orientation are platform-neutral enums', () {
    expect(CameraPixelFormat.values, contains(CameraPixelFormat.yuv420));
    expect(CameraOrientation.values, contains(CameraOrientation.portraitUp));
  });

  test('camera failures map every controlled failure to a stable code', () {
    final expectedCodes = <CameraFailureKind, String>{
      CameraFailureKind.busy: FailureCode.cameraSessionBusy,
      CameraFailureKind.unavailable: FailureCode.cameraUnavailable,
      CameraFailureKind.initialization: FailureCode.cameraInitializationFailed,
      CameraFailureKind.frame: FailureCode.cameraFrameFailed,
      CameraFailureKind.interrupted: FailureCode.cameraInterrupted,
      CameraFailureKind.closed: FailureCode.cameraClosed,
    };

    for (final entry in expectedCodes.entries) {
      final failure = CameraFailureMapper.map(entry.key);
      expect(failure.code, entry.value);
      expect(failure.toString(), isNot(contains('Uint8List')));
    }
  });

  test(
    'a frame is invalidated after delivery and a synchronous copy survives',
    () {
      final frame = CameraFrame(
        bytes: Uint8List.fromList(<int>[1, 2]),
        frameId: 7,
        timestamp: const CameraTimestamp(0),
        width: 1,
        height: 2,
        format: CameraPixelFormat.yuv420,
        orientation: CameraOrientation.portraitUp,
      );

      final retainedCopy = frame.copyBytes();
      frame.invalidate();

      expect(retainedCopy, orderedEquals(<int>[1, 2]));
      expect(frame.isValid, isFalse);
      expect(frame.assertValid, throwsStateError);
      expect(() => frame.byteAt(0), throwsStateError);
      expect(frame.copyBytes, throwsStateError);
    },
  );
}
