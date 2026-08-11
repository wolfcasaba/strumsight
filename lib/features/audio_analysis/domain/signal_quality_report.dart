import 'analysis_warning.dart';

/// Raw signal quality facts. No claim is derived here; R07 computes them.
final class SignalQualityReport {
  SignalQualityReport({
    required this.overall,
    required this.peakDbfs,
    required this.rmsDbfs,
    required this.noiseFloorDbfs,
    required this.clippedSampleRatio,
    required this.silentRatio,
    required this.tonalness,
    List<AnalysisWarning> warnings = const <AnalysisWarning>[],
  }) : warnings = List<AnalysisWarning>.unmodifiable(warnings) {
    if (![
      overall,
      peakDbfs,
      rmsDbfs,
      noiseFloorDbfs,
      tonalness,
    ].every((value) => value.isFinite)) {
      throw ArgumentError('Signal measurements must be finite.');
    }
    if (clippedSampleRatio < 0 ||
        clippedSampleRatio > 1 ||
        silentRatio < 0 ||
        silentRatio > 1) {
      throw ArgumentError('Signal ratios must be in [0, 1].');
    }
  }
  final double overall;
  final double peakDbfs;
  final double rmsDbfs;
  final double noiseFloorDbfs;
  final double clippedSampleRatio;
  final double silentRatio;
  final double tonalness;
  final List<AnalysisWarning> warnings;
}
