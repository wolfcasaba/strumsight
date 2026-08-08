import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_capture.dart';
import '../../../core/camera/camera_permission.dart';
import '../../../core/camera/camera_providers.dart';
import '../../../core/camera/camera_session_coordinator.dart';
import '../../../core/camera/camera_session_lease.dart';
import '../../../core/foundation/app_result.dart';
import '../domain/feedback/insight_code.dart';
import '../domain/quality/vision_frame_quality.dart';
import '../domain/quality/vision_quality_summary.dart';
import '../domain/vision_session.dart';
import '../domain/vision_session_result.dart';
import 'calibration_loss_machine.dart';
import 'vision_session_state.dart';

typedef VisionSessionIdFactory = VisionSessionId Function();
typedef VisionSessionResultListener = void Function(VisionSessionResult result);

final visionSessionClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final visionSessionIdFactoryProvider = Provider<VisionSessionIdFactory>((_) {
  var sequence = 0;
  return () => VisionSessionId.create('vision-session-${sequence++}');
});

/// Delivers the final aggregate to the composition root without persistence.
final visionSessionResultListenerProvider =
    Provider<VisionSessionResultListener>((_) => (_) {});

final visionSessionControllerProvider =
    NotifierProvider.autoDispose<VisionSessionController, VisionSessionState>(
      VisionSessionController.new,
    );

/// Lifecycle-safe composition root for the camera and Vision feedback pipeline.
///
/// It deliberately does not perform inference. The frame listener only owns
/// the capture lifetime and counts deliveries locally; an inference adapter
/// reports its immutable quality and R23-selected cue through the public
/// methods below.
class VisionSessionController extends Notifier<VisionSessionState> {
  CameraSessionCoordinator? _coordinator;
  CameraCapture? _capture;
  CameraSessionLease? _lease;
  StreamSubscription<Object?>? _frames;
  VisionSession? _session;
  Future<VisionSessionResult?>? _finalization;
  bool _disposed = false;
  int _observedFrameCount = 0;
  VisionQualitySummary? _qualitySummary;
  CalibrationLossState _calibrationState = CalibrationLossState.tracking;
  List<VisionInsight> _sessionSummary = const <VisionInsight>[];
  late DateTime Function() _clock;
  late VisionSessionIdFactory _idFactory;
  late VisionSessionResultListener _resultListener;

  @override
  VisionSessionState build() {
    _coordinator = ref.read(cameraSessionCoordinatorProvider);
    _clock = ref.read(visionSessionClockProvider);
    _idFactory = ref.read(visionSessionIdFactoryProvider);
    _resultListener = ref.read(visionSessionResultListenerProvider);
    ref.onDispose(_dispose);
    return VisionSessionState.idle();
  }

  /// Reads permission without presenting a system dialog and enters setup.
  Future<void> begin() async {
    if (!_allows(<VisionSessionStatus>{
      VisionSessionStatus.idle,
      VisionSessionStatus.completed,
      VisionSessionStatus.cancelled,
    })) {
      return;
    }
    _resetForNewSession();
    final permission = await ref
        .read(cameraPermissionGatewayProvider)
        .currentState();
    if (_disposed) return;
    _applyPermission(permission);
  }

  /// The only action which can show the operating system permission prompt.
  Future<void> requestPermission() async {
    if (!_allows(<VisionSessionStatus>{
      VisionSessionStatus.permissionDenied,
      VisionSessionStatus.permissionPermanentlyDenied,
      VisionSessionStatus.cameraUnavailable,
    })) {
      return;
    }
    final permission = await ref
        .read(cameraPermissionGatewayProvider)
        .request();
    if (_disposed) return;
    _applyPermission(permission);
  }

  /// Marks the setup as accepted. Calibration is explicit and never inferred.
  void beginCalibration() {
    if (!_allows(const <VisionSessionStatus>{VisionSessionStatus.setup})) {
      return;
    }
    _setState(state.copyWith(status: VisionSessionStatus.calibrating));
  }

  /// Acquires the exclusive camera lease and starts exactly one frame stream.
  Future<void> start() async {
    if (!_allows(const <VisionSessionStatus>{
      VisionSessionStatus.calibrating,
    })) {
      return;
    }
    final coordinator = _coordinator;
    if (coordinator == null) {
      _captureFailed();
      return;
    }

    var capture = _capture;
    if (capture == null) {
      capture = ref.read(cameraCaptureFactoryProvider)();
      final acquired = await coordinator.acquire(
        CameraOwner.visionPractice,
        onRevoke: () => _finalize(VisionSessionEndReason.appBackground),
      );
      if (_disposed) {
        await capture.close();
        if (acquired case Success<CameraSessionLease>(:final value)) {
          await value.release();
        }
        return;
      }
      switch (acquired) {
        case Failure<CameraSessionLease>():
          await capture.close();
          _setState(state.copyWith(status: VisionSessionStatus.cameraBusy));
          return;
        case Success<CameraSessionLease>(:final value):
          _capture = capture;
          _lease = value;
      }
    }

    final started = await capture.start();
    if (_disposed) return;
    if (started case Failure<void>()) {
      await _closeCapture(releaseLease: true);
      _captureFailed();
      return;
    }

    _session ??= VisionSession(id: _idFactory(), startedAt: _clock());
    _frames ??= capture.frames.listen(_onFrame, onError: _onFrameError);
    _setState(
      state.copyWith(
        status: VisionSessionStatus.running,
        session: _session,
        clearIssue: true,
      ),
    );
  }

  Future<void> pause() async {
    if (!_allows(const <VisionSessionStatus>{VisionSessionStatus.running})) {
      return;
    }
    final capture = _capture;
    if (capture == null) {
      _captureFailed();
      return;
    }
    final stopped = await capture.stop();
    if (_disposed) return;
    if (stopped case Failure<void>()) {
      _captureFailed();
      return;
    }
    _setState(state.copyWith(status: VisionSessionStatus.paused));
  }

  Future<void> resume() async {
    if (!_allows(const <VisionSessionStatus>{VisionSessionStatus.paused})) {
      return;
    }
    final capture = _capture;
    final lease = _lease;
    if (capture == null || lease == null || !lease.isActive) {
      _captureFailed();
      return;
    }
    final started = await capture.start();
    if (_disposed) return;
    if (started case Failure<void>()) {
      _captureFailed();
      return;
    }
    _setState(state.copyWith(status: VisionSessionStatus.running));
  }

  /// Re-enters the explicit calibration step without taking a second lease.
  Future<void> recalibrate() async {
    if (!_allows(const <VisionSessionStatus>{
      VisionSessionStatus.running,
      VisionSessionStatus.paused,
      VisionSessionStatus.calibrationLost,
    })) {
      return;
    }
    final capture = _capture;
    if (capture != null && state.status == VisionSessionStatus.running) {
      final stopped = await capture.stop();
      if (_disposed || stopped.isFailure) {
        if (!_disposed) _captureFailed();
        return;
      }
    }
    _calibrationState = CalibrationLossState.tracking;
    _setState(
      state.copyWith(
        status: VisionSessionStatus.calibrating,
        calibrationState: _calibrationState,
        overlayQuality: state.overlayQuality.copyWith(
          guitar: _calibrationState,
        ),
        clearCue: true,
      ),
    );
  }

  Future<VisionSessionResult?> stop() =>
      _finalize(VisionSessionEndReason.explicitStop);

  Future<VisionSessionResult?> leaveRoute() =>
      _finalize(VisionSessionEndReason.routeLeave);

  /// Accepts a summary produced outside the UI/frame callback.
  void reportQuality({
    required VisionQualitySummary summary,
    required VisionMetricState hand,
    required VisionMetricState pose,
    required CalibrationLossState guitar,
  }) {
    if (!_allows(const <VisionSessionStatus>{
      VisionSessionStatus.running,
      VisionSessionStatus.paused,
    })) {
      return;
    }
    _qualitySummary = summary;
    _calibrationState = guitar;
    final status = guitar == CalibrationLossState.lost
        ? VisionSessionStatus.calibrationLost
        : state.status;
    _setState(
      state.copyWith(
        status: status,
        qualitySummary: summary,
        overlayQuality: VisionOverlayQuality(
          hand: hand,
          pose: pose,
          guitar: guitar,
        ),
        calibrationState: guitar,
      ),
    );
  }

  /// R23 has already selected this one cue. This controller never ranks cues.
  void reportRealtimeCue(
    VisionInsight? cue, {
    Iterable<VisionInsight>? summary,
  }) {
    if (!_allows(const <VisionSessionStatus>{
      VisionSessionStatus.running,
      VisionSessionStatus.paused,
      VisionSessionStatus.calibrationLost,
    })) {
      return;
    }
    if (summary != null) {
      _sessionSummary = List<VisionInsight>.unmodifiable(summary.take(2));
    }
    _setState(state.copyWith(realtimeCue: cue, clearCue: cue == null));
  }

  void setDetailedOverlayEnabled(bool enabled) {
    _setState(state.copyWith(detailedOverlayEnabled: enabled));
  }

  bool _allows(Set<VisionSessionStatus> allowed) {
    if (_disposed || allowed.contains(state.status)) return !_disposed;
    _setState(
      state.copyWith(
        issue: VisionSessionIssue.invalidTransition,
        clearIssue: false,
      ),
    );
    return false;
  }

  void _applyPermission(CameraPermissionState permission) {
    final status = switch (permission) {
      CameraPermissionState.granted => VisionSessionStatus.setup,
      CameraPermissionState.denied => VisionSessionStatus.permissionDenied,
      CameraPermissionState.permanentlyDenied ||
      CameraPermissionState.restricted =>
        VisionSessionStatus.permissionPermanentlyDenied,
      CameraPermissionState.unavailable =>
        VisionSessionStatus.cameraUnavailable,
    };
    _setState(state.copyWith(status: status, clearIssue: true));
  }

  void _onFrame(Object? _) {
    // A frame is borrowed by the capture adapter. Do not inspect, copy, or put
    // it in state here; a future pipeline owns inference off the UI thread.
    if (_disposed || state.status != VisionSessionStatus.running) return;
    _observedFrameCount += 1;
  }

  void _onFrameError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    unawaited(_finalize(VisionSessionEndReason.failure));
  }

  void _captureFailed() {
    _setState(
      state.copyWith(
        status: VisionSessionStatus.inferenceFailed,
        issue: VisionSessionIssue.captureFailure,
      ),
    );
    unawaited(_finalize(VisionSessionEndReason.failure));
  }

  Future<VisionSessionResult?> _finalize(VisionSessionEndReason reason) {
    final inFlight = _finalization;
    if (inFlight != null) return inFlight;
    final operation = _finalizeOnce(reason);
    _finalization = operation;
    return operation;
  }

  Future<VisionSessionResult?> _finalizeOnce(
    VisionSessionEndReason reason,
  ) async {
    final session = _session;
    if (session == null) return null;
    if (!_disposed) {
      _setState(state.copyWith(status: VisionSessionStatus.finalizing));
    }
    await _closeCapture(releaseLease: true);
    final result = VisionSessionResult(
      session: session,
      endedAt: _clock(),
      endReason: reason,
      qualitySummary:
          _qualitySummary ?? VisionQualitySummary.fromFrames(const []),
      calibrationState: _calibrationState,
      sessionSummary: _sessionSummary,
      observedFrameCount: _observedFrameCount,
    );
    _session = null;
    _resultListener(result);
    if (!_disposed) {
      _setState(
        state.copyWith(
          status: VisionSessionStatus.completed,
          result: result,
          clearSession: true,
        ),
      );
    }
    return result;
  }

  Future<void> _closeCapture({required bool releaseLease}) async {
    final subscription = _frames;
    _frames = null;
    if (subscription != null) await subscription.cancel();
    final capture = _capture;
    _capture = null;
    if (capture != null) await capture.close();
    final lease = _lease;
    _lease = null;
    if (releaseLease && lease != null) await lease.release();
  }

  void _resetForNewSession() {
    _finalization = null;
    _session = null;
    _observedFrameCount = 0;
    _qualitySummary = null;
    _calibrationState = CalibrationLossState.tracking;
    _sessionSummary = const <VisionInsight>[];
    _setState(VisionSessionState.idle());
  }

  void _dispose() {
    _disposed = true;
    unawaited(_finalize(VisionSessionEndReason.disposed));
  }

  void _setState(VisionSessionState next) {
    if (!_disposed) state = next;
  }
}
