import 'vision_frame_quality.dart';

/// A deterministic setup-only roll-up over a frame-quality window.
///
/// The fixed ordering makes one actionable cue available at a time and avoids
/// converting weak or unavailable evidence into technical-playing feedback.
final class VisionQualitySummary {
  VisionQualitySummary._({
    required this.frameCount,
    required this.framing,
    required this.lighting,
    required this.blur,
    required this.stability,
    required this.roiCoverage,
    required this.overall,
    required this.setupCue,
  });

  factory VisionQualitySummary.fromFrames(List<VisionFrameQuality> frames) {
    if (frames.isEmpty) {
      return VisionQualitySummary._(
        frameCount: 0,
        framing: VisionMetricState.notObservable,
        lighting: VisionLighting.notObservable,
        blur: VisionMetricState.notObservable,
        stability: VisionMetricState.notObservable,
        roiCoverage: VisionMetricState.notObservable,
        overall: VisionMetricState.notObservable,
        setupCue: VisionSetupCue.notObservable,
      );
    }

    final framing = _metric(frames.map((frame) => frame.framing));
    final lighting = _lighting(frames.map((frame) => frame.lighting));
    final blur = _metric(frames.map((frame) => frame.blur));
    final stability = _metric(frames.map((frame) => frame.stability));
    final roiCoverage = _metric(frames.map((frame) => frame.roiCoverage));
    final overall = _metric(frames.map((frame) => frame.overall));
    final setupCue = _cue(
      framing: framing,
      lighting: lighting,
      blur: blur,
      stability: stability,
      roiCoverage: roiCoverage,
      overall: overall,
    );

    return VisionQualitySummary._(
      frameCount: frames.length,
      framing: framing,
      lighting: lighting,
      blur: blur,
      stability: stability,
      roiCoverage: roiCoverage,
      overall: overall,
      setupCue: setupCue,
    );
  }

  final int frameCount;
  final VisionMetricState framing;
  final VisionLighting lighting;
  final VisionMetricState blur;
  final VisionMetricState stability;
  final VisionMetricState roiCoverage;
  final VisionMetricState overall;
  final VisionSetupCue setupCue;

  int get activeCueCount => setupCue == VisionSetupCue.none ? 0 : 1;

  static VisionMetricState _metric(Iterable<VisionMetricState> states) {
    final values = states.toList(growable: false);
    if (values.any((state) => state == VisionMetricState.needsImprovement)) {
      return VisionMetricState.needsImprovement;
    }
    if (values.every((state) => state == VisionMetricState.good)) {
      return VisionMetricState.good;
    }
    return VisionMetricState.notObservable;
  }

  static VisionLighting _lighting(Iterable<VisionLighting> states) {
    final values = states.toList(growable: false);
    if (values.any((state) => state == VisionLighting.tooDark)) {
      return VisionLighting.tooDark;
    }
    if (values.any((state) => state == VisionLighting.overexposed)) {
      return VisionLighting.overexposed;
    }
    if (values.every((state) => state == VisionLighting.good)) {
      return VisionLighting.good;
    }
    return VisionLighting.notObservable;
  }

  static VisionSetupCue _cue({
    required VisionMetricState framing,
    required VisionLighting lighting,
    required VisionMetricState blur,
    required VisionMetricState stability,
    required VisionMetricState roiCoverage,
    required VisionMetricState overall,
  }) {
    if (framing == VisionMetricState.needsImprovement) {
      return VisionSetupCue.adjustFraming;
    }
    if (lighting == VisionLighting.tooDark ||
        lighting == VisionLighting.overexposed) {
      return VisionSetupCue.improveLighting;
    }
    if (blur == VisionMetricState.needsImprovement) {
      return VisionSetupCue.reduceBlur;
    }
    if (stability == VisionMetricState.needsImprovement) {
      return VisionSetupCue.stabilizeCamera;
    }
    if (roiCoverage == VisionMetricState.needsImprovement) {
      return VisionSetupCue.increaseRoiCoverage;
    }
    if (overall == VisionMetricState.notObservable) {
      return VisionSetupCue.notObservable;
    }
    return VisionSetupCue.none;
  }
}
