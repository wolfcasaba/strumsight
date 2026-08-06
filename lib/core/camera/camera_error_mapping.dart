import 'package:camera/camera.dart' as plugin;

import '../foundation/app_failure.dart';
import 'camera_failure.dart';

/// Maps camera-plugin exception codes without exposing plugin types elsewhere.
abstract final class CameraErrorMapping {
  static CameraFailure map(Object error, [StackTrace? stackTrace]) {
    final code = error is plugin.CameraException ? error.code : '';
    final kind = switch (code.toLowerCase()) {
      'cameradisconnected' => CameraFailureKind.interrupted,
      'camerainuse' => CameraFailureKind.busy,
      'cameramaxcamerasinuse' => CameraFailureKind.unavailable,
      'cameradeviceerror' => CameraFailureKind.initialization,
      _ => CameraFailureKind.frame,
    };
    return CameraFailureMapper.map(kind, cause: error, stackTrace: stackTrace);
  }
}
