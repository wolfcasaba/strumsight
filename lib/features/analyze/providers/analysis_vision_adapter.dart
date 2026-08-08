import 'package:strumsight/features/vision/domain/integration/public.dart';

import '../model/analyze_result.dart';
import '../model/analysis_vision_reference.dart';

/// Maps clip-relative analysis times onto the shared Vision session timeline.
final class AnalysisVisionAdapter {
  const AnalysisVisionAdapter();

  SessionTimestamp toSessionTimestamp({
    required SessionTimestamp clipStart,
    required double clipRelativeSeconds,
  }) {
    if (!clipRelativeSeconds.isFinite || clipRelativeSeconds < 0) {
      throw ArgumentError.value(
        clipRelativeSeconds,
        'clipRelativeSeconds',
        'Must be finite and non-negative.',
      );
    }
    return SessionTimestamp(
      clipStart.microseconds +
          (clipRelativeSeconds * Duration.microsecondsPerSecond).round(),
    );
  }

  double toClipRelativeSeconds({
    required SessionTimestamp clipStart,
    required SessionTimestamp sessionTimestamp,
  }) {
    final offsetUs = sessionTimestamp.microseconds - clipStart.microseconds;
    if (offsetUs < 0) {
      throw ArgumentError.value(
        sessionTimestamp,
        'sessionTimestamp',
        'Must not precede the clip start.',
      );
    }
    return offsetUs / Duration.microsecondsPerSecond;
  }

  AnalysisVisionReference adapt({
    required String analysisEvidenceId,
    required String visionEvidenceId,
    required SessionTimestamp clipStart,
    required double clipRelativeSeconds,
  }) => AnalysisVisionReference(
    analysisEvidenceId: analysisEvidenceId,
    visionEvidenceId: visionEvidenceId,
    sessionTimestamp: toSessionTimestamp(
      clipStart: clipStart,
      clipRelativeSeconds: clipRelativeSeconds,
    ),
  );

  /// Links a chord's clip-relative start to the shared session timeline.
  AnalysisVisionReference forChord({
    required String analysisEvidenceId,
    required String visionEvidenceId,
    required SessionTimestamp clipStart,
    required TimelineChord chord,
  }) => adapt(
    analysisEvidenceId: analysisEvidenceId,
    visionEvidenceId: visionEvidenceId,
    clipStart: clipStart,
    clipRelativeSeconds: chord.startSec,
  );

  /// Links a strum's clip-relative instant to the shared session timeline.
  AnalysisVisionReference forStrum({
    required String analysisEvidenceId,
    required String visionEvidenceId,
    required SessionTimestamp clipStart,
    required TimelineStrum strum,
  }) => adapt(
    analysisEvidenceId: analysisEvidenceId,
    visionEvidenceId: visionEvidenceId,
    clipStart: clipStart,
    clipRelativeSeconds: strum.timeSec,
  );
}
