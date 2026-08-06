import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_error_mapping.dart';
import 'package:strumsight/core/foundation/app_failure.dart';

void main() {
  test('maps every documented camera platform error to a distinct failure', () {
    final expectedCodes = <String, String>{
      'CameraDisconnected': FailureCode.cameraInterrupted,
      'CameraInUse': FailureCode.cameraSessionBusy,
      'CameraMaxCamerasInUse': FailureCode.cameraUnavailable,
      'CameraDeviceError': FailureCode.cameraInitializationFailed,
      'unexpected-platform-code': FailureCode.cameraFrameFailed,
    };

    for (final entry in expectedCodes.entries) {
      final failure = CameraErrorMapping.map(
        CameraException(entry.key, 'test platform error'),
      );

      expect(failure.code, entry.value, reason: entry.key);
    }
  });
}
