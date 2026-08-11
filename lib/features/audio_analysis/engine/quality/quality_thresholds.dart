/// Versioned, named thresholds for the deterministic signal-quality stage.
///
/// The values are intentionally provisional until E06-R29 calibrates them on
/// real recordings. Keeping them here makes that future calibration explicit
/// and prevents formula-local tuning.
final class QualityThresholds {
  const QualityThresholds({
    required this.version,
    required this.silenceFloorDbfs,
    required this.maximumReportDbfs,
    required this.clippedSampleThreshold,
    required this.clippedRatioWarning,
    required this.silentSampleDbfs,
    required this.silentRatioWarning,
    required this.analysisFrameSize,
    required this.analysisFrameHop,
    required this.shortClipDuration,
    required this.spectralMagnitudeFloor,
    required this.silentOverall,
    required this.lowLevelOverall,
    required this.clippedOverallMultiplier,
    required this.shortClipOverallMultiplier,
  });

  static const QualityThresholds standard = QualityThresholds(
    version: 'signal-quality-v1',
    silenceFloorDbfs: -120.0,
    maximumReportDbfs: 6.0,
    clippedSampleThreshold: 0.999,
    clippedRatioWarning: 0.001,
    silentSampleDbfs: -60.0,
    silentRatioWarning: 0.95,
    analysisFrameSize: 2048,
    analysisFrameHop: 1024,
    shortClipDuration: Duration(milliseconds: 250),
    spectralMagnitudeFloor: 1e-12,
    silentOverall: 0.25,
    lowLevelOverall: 0.65,
    clippedOverallMultiplier: 0.5,
    shortClipOverallMultiplier: 0.85,
  );

  final String version;
  final double silenceFloorDbfs;
  final double maximumReportDbfs;
  final double clippedSampleThreshold;
  final double clippedRatioWarning;
  final double silentSampleDbfs;
  final double silentRatioWarning;
  final int analysisFrameSize;
  final int analysisFrameHop;
  final Duration shortClipDuration;
  final double spectralMagnitudeFloor;
  final double silentOverall;
  final double lowLevelOverall;
  final double clippedOverallMultiplier;
  final double shortClipOverallMultiplier;
}
