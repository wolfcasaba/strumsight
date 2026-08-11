/// Named, versioned signal-quality thresholds (ADR 0223,
/// `docs/rag/chunks/019-signal-quality-metrics.md` is the canonical source
/// for every formula and value below — retune there, not with a magic
/// number in the math).
///
/// Provisional until the real-audio evaluation in E06-R29.
abstract final class QualityThresholds {
  /// Matches [SignalQualityStage.version] so the existing R04 pipeline
  /// `stageVersions` provenance also records this threshold policy's
  /// version, without a new provenance field (ADR 0223 §4).
  static const int version = 1;

  /// dBFS floor for any measurement that would otherwise be `-Infinity`.
  static const double silenceFloorDbfs = -120.0;

  /// dBFS ceiling — small headroom above full scale for measurement noise.
  static const double maxDbfs = 6.0;

  /// Inclusive absolute-sample threshold above which a sample is clipped.
  static const double clippedSampleThreshold = 0.999;

  /// Inclusive clipped-sample-ratio threshold that raises a warning.
  static const double clippedRatioWarning = 0.001;

  /// Inclusive per-frame RMS dBFS threshold at/below which a frame is silent.
  static const double silentFrameDbfs = -60.0;

  /// Frame size (samples) shared by noise-floor, silence and tonalness framing.
  static const int frameSize = 2048;

  /// Frame hop (samples) — 50% overlap.
  static const int hopSize = 1024;

  /// Percentile (0..1) of the per-frame RMS distribution used as noise floor.
  static const double noiseFloorPercentile = 0.10;

  /// Silent-frame ratio at/above which a `mostly_silent` warning fires.
  static const double mostlySilentRatioWarning = 0.95;

  /// Below this clip duration, the tonalness/noise-floor reading gets a
  /// stable `inputQuality` warning instead of a new "degraded" field.
  static const double minReliableDurationSeconds = 1.0;

  /// Composite `overall` grade weights — sum to 1.0.
  static const double weightClipping = 0.25;
  static const double weightSilence = 0.25;
  static const double weightDynamicRange = 0.25;
  static const double weightTonalness = 0.25;

  /// Clipped-ratio at/above which the clipping sub-score bottoms out at 0.
  static const double clippingFullPenaltyRatio = 0.05;

  /// Dynamic range (rmsDbfs - noiseFloorDbfs) at/above which the dynamic
  /// range sub-score maxes out at 1.
  static const double fullDynamicRangeDb = 40.0;
}
