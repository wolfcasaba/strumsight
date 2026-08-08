import 'package:strumsight/features/vision/domain/integration/public.dart';

/// Inferred link between one audio-analysis result and Vision evidence.
final class AnalysisVisionReference {
  AnalysisVisionReference({
    required this.analysisEvidenceId,
    required this.visionEvidenceId,
    required this.sessionTimestamp,
  }) {
    if (analysisEvidenceId.trim().isEmpty || visionEvidenceId.trim().isEmpty) {
      throw ArgumentError('Analysis and Vision evidence IDs are required.');
    }
  }

  final String analysisEvidenceId;
  final String visionEvidenceId;
  final SessionTimestamp sessionTimestamp;

  /// Cross-modal links are derived from two sources, never directly observed.
  ObservationState get observationState => ObservationState.inferred;
}
