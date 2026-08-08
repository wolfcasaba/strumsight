import '../quality/vision_frame_quality.dart';
import '../sync/sync_quality.dart';

/// The independently measured confidence components of a fused evidence item.
final class ConfidenceComponents {
  const ConfidenceComponents({
    required this.model,
    required this.quality,
    required this.geometry,
    required this.sync,
  }) : assert(model >= 0 && model <= 1),
       assert(quality >= 0 && quality <= 1),
       assert(geometry >= 0 && geometry <= 1),
       assert(sync >= 0 && sync <= 1);

  final double model;
  final double quality;
  final double geometry;
  final double sync;

  ConfidenceComponents copyWith({
    double? model,
    double? quality,
    double? geometry,
    double? sync,
  }) => ConfidenceComponents(
    model: model ?? this.model,
    quality: quality ?? this.quality,
    geometry: geometry ?? this.geometry,
    sync: sync ?? this.sync,
  );
}

/// Monotonic confidence policy: fusion is the minimum of its components.
///
/// A weak component is therefore never hidden by stronger inputs, unlike an
/// arithmetic average. The categorical mappings are deliberately ordered and
/// versioned by their source contracts.
final class ConfidenceModel {
  const ConfidenceModel();

  double combine(ConfidenceComponents components) => <double>[
    components.model,
    components.quality,
    components.geometry,
    components.sync,
  ].reduce((lowest, value) => value < lowest ? value : lowest);

  double syncContribution(SyncQuality quality) => switch (quality) {
    SyncQuality.excellent => 1,
    SyncQuality.good => 0.8,
    SyncQuality.acceptable => 0.5,
    SyncQuality.poor => 0.25,
  };

  /// Computes a signal directly from the raw per-frame quality result, never
  /// from [VisionQualitySummary]'s UI cue-prioritization output.
  double qualityContribution(VisionFrameQuality frame) => <double>[
    _metricContribution(frame.framing),
    _lightingContribution(frame.lighting),
    _metricContribution(frame.blur),
    _metricContribution(frame.stability),
    _metricContribution(frame.roiCoverage),
  ].reduce((lowest, value) => value < lowest ? value : lowest);

  double _metricContribution(VisionMetricState state) => switch (state) {
    VisionMetricState.good => 1,
    VisionMetricState.needsImprovement => 0.5,
    VisionMetricState.notObservable => 0,
  };

  double _lightingContribution(VisionLighting lighting) => switch (lighting) {
    VisionLighting.good => 1,
    VisionLighting.tooDark => 0.5,
    VisionLighting.overexposed => 0.5,
    VisionLighting.notObservable => 0,
  };
}
