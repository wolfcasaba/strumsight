import '../domain/feedback/insight_code.dart';
import '../domain/quality/vision_frame_quality.dart';
import '../domain/quality/vision_quality_summary.dart';
import '../domain/vision_session.dart';
import '../domain/vision_session_result.dart';
import 'calibration_loss_machine.dart';

/// Every user-visible state in the R24 Vision session state machine.
enum VisionSessionStatus {
  idle,
  setup,
  calibrating,
  running,
  paused,
  finalizing,
  completed,
  permissionDenied,
  permissionPermanentlyDenied,
  cameraUnavailable,
  cameraBusy,
  calibrationLost,
  inferenceFailed,
  cancelled,
  disposed,
}

/// A controlled rejection of an invalid state-machine command.
enum VisionSessionIssue { invalidTransition, captureFailure }

/// Quality values rendered by the privacy-preserving preview overlay.
///
/// The values are summaries, never landmarks, frame handles, or pixel data.
final class VisionOverlayQuality {
  const VisionOverlayQuality({
    required this.hand,
    required this.pose,
    required this.guitar,
  });

  const VisionOverlayQuality.unavailable()
    : hand = VisionMetricState.notObservable,
      pose = VisionMetricState.notObservable,
      guitar = CalibrationLossState.lost;

  final VisionMetricState hand;
  final VisionMetricState pose;
  final CalibrationLossState guitar;

  VisionOverlayQuality copyWith({
    VisionMetricState? hand,
    VisionMetricState? pose,
    CalibrationLossState? guitar,
  }) => VisionOverlayQuality(
    hand: hand ?? this.hand,
    pose: pose ?? this.pose,
    guitar: guitar ?? this.guitar,
  );
}

/// Immutable Riverpod state for one Vision session.
///
/// [auditFields] is intentionally a fixed allow-list. The audit test guards
/// that state stays a small summary and never becomes a frame buffer carrier.
final class VisionSessionState {
  const VisionSessionState({
    required this.status,
    required this.qualitySummary,
    required this.overlayQuality,
    required this.calibrationState,
    required this.detailedOverlayEnabled,
    this.session,
    this.realtimeCue,
    this.issue,
    this.result,
  });

  VisionSessionState.idle()
    : status = VisionSessionStatus.idle,
      qualitySummary = VisionQualitySummary.fromFrames(
        const <VisionFrameQuality>[],
      ),
      overlayQuality = const VisionOverlayQuality.unavailable(),
      calibrationState = CalibrationLossState.tracking,
      detailedOverlayEnabled = false,
      session = null,
      realtimeCue = null,
      issue = null,
      result = null;

  final VisionSessionStatus status;
  final VisionQualitySummary qualitySummary;
  final VisionOverlayQuality overlayQuality;
  final CalibrationLossState calibrationState;
  final bool detailedOverlayEnabled;
  final VisionSession? session;
  final VisionInsight? realtimeCue;
  final VisionSessionIssue? issue;
  final VisionSessionResult? result;

  /// Stable primitive-only field names for the no-frame provider-state audit.
  Set<String> get auditFields => const <String>{
    'status',
    'qualitySummary',
    'overlayQuality',
    'calibrationState',
    'detailedOverlayEnabled',
    'session',
    'realtimeCue',
    'issue',
    'result',
  };

  VisionSessionState copyWith({
    VisionSessionStatus? status,
    VisionQualitySummary? qualitySummary,
    VisionOverlayQuality? overlayQuality,
    CalibrationLossState? calibrationState,
    bool? detailedOverlayEnabled,
    VisionSession? session,
    VisionInsight? realtimeCue,
    VisionSessionIssue? issue,
    VisionSessionResult? result,
    bool clearSession = false,
    bool clearCue = false,
    bool clearIssue = false,
    bool clearResult = false,
  }) => VisionSessionState(
    status: status ?? this.status,
    qualitySummary: qualitySummary ?? this.qualitySummary,
    overlayQuality: overlayQuality ?? this.overlayQuality,
    calibrationState: calibrationState ?? this.calibrationState,
    detailedOverlayEnabled:
        detailedOverlayEnabled ?? this.detailedOverlayEnabled,
    session: clearSession ? null : (session ?? this.session),
    realtimeCue: clearCue ? null : (realtimeCue ?? this.realtimeCue),
    issue: clearIssue ? null : (issue ?? this.issue),
    result: clearResult ? null : (result ?? this.result),
  );
}
