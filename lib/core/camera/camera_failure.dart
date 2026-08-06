import '../foundation/app_failure.dart';

/// Camera operation failures that a platform adapter can report deterministically.
enum CameraFailureKind {
  busy,
  unavailable,
  initialization,
  frame,
  interrupted,
  closed,
}

/// Maps camera-domain failures to the stable application failure contract.
abstract final class CameraFailureMapper {
  static CameraFailure map(
    CameraFailureKind kind, {
    Object? cause,
    StackTrace? stackTrace,
  }) => CameraFailure(
    code: _codeFor(kind),
    retryable: _isRetryable(kind),
    cause: cause,
    stackTrace: stackTrace,
  );

  static String _codeFor(CameraFailureKind kind) => switch (kind) {
    CameraFailureKind.busy => FailureCode.cameraSessionBusy,
    CameraFailureKind.unavailable => FailureCode.cameraUnavailable,
    CameraFailureKind.initialization => FailureCode.cameraInitializationFailed,
    CameraFailureKind.frame => FailureCode.cameraFrameFailed,
    CameraFailureKind.interrupted => FailureCode.cameraInterrupted,
    CameraFailureKind.closed => FailureCode.cameraClosed,
  };

  static bool _isRetryable(CameraFailureKind kind) => switch (kind) {
    CameraFailureKind.closed => false,
    _ => true,
  };
}
