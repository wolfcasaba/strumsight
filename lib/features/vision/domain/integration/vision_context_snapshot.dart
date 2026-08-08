import '../evidence/vision_evidence.dart';
import '../feedback/insight_code.dart';
import '../sync/vision_clock.dart';
import '../vision_session.dart';

export '../evidence/vision_evidence.dart' show ObservationState;
export '../feedback/insight_code.dart' show InsightCode;
export '../sync/vision_clock.dart' show SessionTimestamp;

/// Minimal, structured Vision evidence safe for cross-feature context.
final class VisionContextSnapshot {
  VisionContextSnapshot({
    required this.sessionId,
    required this.sessionTimestamp,
    required this.insightCode,
    required this.confidence,
    required this.observationState,
  }) {
    if (sessionId.value.trim().isEmpty ||
        !(confidence.isFinite && confidence >= 0 && confidence <= 1)) {
      throw ArgumentError(
        'A session ID and finite [0, 1] confidence are required.',
      );
    }
  }

  final VisionSessionId sessionId;
  final SessionTimestamp sessionTimestamp;
  final InsightCode insightCode;
  final double confidence;
  final ObservationState observationState;

  /// Stable, pinned representation for minimal Tutor context projection.
  Map<String, Object> toJson() => <String, Object>{
    'sessionId': sessionId.value,
    'sessionTimestampUs': sessionTimestamp.microseconds,
    'insightCode': insightCode.name,
    'confidence': confidence,
    'observationState': observationState.name,
  };
}
