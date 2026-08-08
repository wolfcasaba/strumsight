import '../application/calibration_loss_machine.dart';
import 'feedback/insight_code.dart';
import 'quality/vision_quality_summary.dart';
import 'vision_session.dart';

/// The controlled way a Vision session reached its final result.
enum VisionSessionEndReason {
  explicitStop,
  routeLeave,
  appBackground,
  failure,
  disposed,
}

/// A raw-media-free aggregate created exactly once when a session ends.
///
/// Persistence is intentionally outside this round. This value only contains
/// immutable summaries that later persistence and Practice integrations may
/// consume through the public Vision contract.
final class VisionSessionResult {
  VisionSessionResult({
    required this.session,
    required DateTime endedAt,
    required this.endReason,
    required this.qualitySummary,
    required this.calibrationState,
    required List<VisionInsight> sessionSummary,
    required this.observedFrameCount,
  }) : endedAt = endedAt.toUtc(),
       sessionSummary = List<VisionInsight>.unmodifiable(sessionSummary) {
    if (observedFrameCount < 0) {
      throw ArgumentError.value(
        observedFrameCount,
        'observedFrameCount',
        'Must not be negative.',
      );
    }
  }

  final VisionSession session;
  final DateTime endedAt;
  final VisionSessionEndReason endReason;
  final VisionQualitySummary qualitySummary;
  final CalibrationLossState calibrationState;
  final List<VisionInsight> sessionSummary;
  final int observedFrameCount;

  Duration get duration => endedAt.difference(session.startedAt);
}
