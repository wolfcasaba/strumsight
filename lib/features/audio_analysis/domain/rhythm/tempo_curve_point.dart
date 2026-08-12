/// One point of the R12 tempo curve (SDD Ch7 §14.1, §14.3).
///
/// Deliberately not `AnalysisTimeline.TempoPoint` — that type is already
/// exported and used by the V1 migration adapter and codec (ADR 0230 §1).
final class TempoCurvePoint {
  TempoCurvePoint({
    required this.time,
    required this.bpm,
    required this.confidence,
  }) {
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (!bpm.isFinite || bpm <= 0 || bpm > 400) {
      throw ArgumentError.value(bpm, 'bpm', 'must be finite and in (0, 400]');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final Duration time;
  final double bpm;
  final double confidence;
}
