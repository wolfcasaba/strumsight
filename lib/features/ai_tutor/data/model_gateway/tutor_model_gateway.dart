import '../../../../core/foundation/app_result.dart';
import 'tutor_model_event.dart';
import 'tutor_model_request.dart';

/// Provider-independent streaming contract for tutor model interactions.
///
/// The gateway accepts a request and returns a stream of events representing
/// the model's response. It supports cancellation and health checks.
///
/// No Flutter UI types or provider SDK dependencies (ADR 0131).
abstract interface class TutorModelGateway {
  /// Starts streaming events for the given [request].
  ///
  /// Returns a stream of [TutorModelEvent] representing the model's response.
  /// The stream emits events in order and closes when the response is complete.
  ///
  /// Returns a failed [AppResult] if the gateway cannot start (e.g., disposed,
  /// already running, or capability unavailable).
  Future<AppResult<Stream<TutorModelEvent>>> start(TutorModelRequest request);

  /// Cancels the active streaming session, if any.
  ///
  /// After cancellation, the event stream closes. Calling cancel when no
  /// session is active is a no-op.
  void cancel();

  /// Checks whether the gateway is operational.
  ///
  /// Returns [Success] if the gateway can accept requests, [Failure] otherwise.
  Future<AppResult<void>> health();
}
