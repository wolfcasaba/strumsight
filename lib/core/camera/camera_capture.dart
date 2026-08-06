import '../foundation/app_result.dart';
import 'camera_frame.dart';

/// Platform-neutral owner of one camera capture session.
///
/// A frame is valid only during the synchronous body of a [frames] listener.
/// [close] releases the session permanently and is idempotent; all later
/// capture operations must return a failure rather than silently doing nothing.
abstract interface class CameraCapture {
  /// Borrowed frame delivery for the active session.
  Stream<CameraFrame> get frames;

  /// Starts the session and frame delivery.
  Future<AppResult<void>> start();

  /// Stops delivery while retaining this session for a later [start].
  Future<AppResult<void>> stop();

  /// Releases the session permanently. Calling it more than once is safe.
  Future<AppResult<void>> close();
}
