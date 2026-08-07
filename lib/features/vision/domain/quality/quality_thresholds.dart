import '../vision_setup_profile.dart';

/// Versioned limits for the model-free frame-quality checks.
///
/// A recorded [thresholdsVersion] lets later tuning distinguish a changed
/// threshold from a changed camera scene. Values are deliberately explicit:
/// callers must supply a newer version when they change one.
final class QualityThresholds {
  const QualityThresholds({
    required this.thresholdsVersion,
    required this.downsampleFactor,
    required this.minimumMeanLuminance,
    required this.maximumMeanLuminance,
    required this.maximumShadowClippingRatio,
    required this.maximumHighlightClippingRatio,
    required this.minimumSharpness,
    required this.maximumCameraMotion,
    required this.minimumRoiCoverage,
    this.shadowClipLuminance = 16,
    this.highlightClipLuminance = 240,
  }) : assert(thresholdsVersion != ''),
       assert(downsampleFactor > 0),
       assert(minimumMeanLuminance >= 0),
       assert(maximumMeanLuminance <= 255),
       assert(minimumMeanLuminance <= maximumMeanLuminance),
       assert(maximumShadowClippingRatio >= 0),
       assert(maximumShadowClippingRatio <= 1),
       assert(maximumHighlightClippingRatio >= 0),
       assert(maximumHighlightClippingRatio <= 1),
       assert(minimumSharpness >= 0),
       assert(maximumCameraMotion >= 0),
       assert(minimumRoiCoverage >= 0),
       assert(minimumRoiCoverage <= 1);

  const QualityThresholds.defaultV1()
    : this(
        thresholdsVersion: 'vision-frame-quality-v1',
        downsampleFactor: 4,
        minimumMeanLuminance: 40,
        maximumMeanLuminance: 215,
        maximumShadowClippingRatio: 0.20,
        maximumHighlightClippingRatio: 0.20,
        minimumSharpness: 10,
        maximumCameraMotion: 12,
        minimumRoiCoverage: 0.20,
      );

  final String thresholdsVersion;
  final int downsampleFactor;
  final double minimumMeanLuminance;
  final double maximumMeanLuminance;
  final double maximumShadowClippingRatio;
  final double maximumHighlightClippingRatio;
  final double minimumSharpness;
  final double maximumCameraMotion;
  final double minimumRoiCoverage;
  final int shadowClipLuminance;
  final int highlightClipLuminance;

  bool isTooDark({
    required double meanLuminance,
    required double shadowClippingRatio,
  }) =>
      meanLuminance < minimumMeanLuminance ||
      shadowClippingRatio > maximumShadowClippingRatio;

  bool isOverexposed({
    required double meanLuminance,
    required double highlightClippingRatio,
  }) =>
      meanLuminance > maximumMeanLuminance ||
      highlightClippingRatio > maximumHighlightClippingRatio;

  bool isBlurred(double sharpness) => sharpness < minimumSharpness;

  bool isUnstable(double cameraMotion) => cameraMotion > maximumCameraMotion;

  bool hasInsufficientRoiCoverage(double coverage) =>
      coverage < minimumRoiCoverage;

  /// The setup profiles use intentionally different minimum framing areas.
  /// They are less strict than [minimumRoiCoverage], which separately guards
  /// that enough of the calibrated guitar region is observable.
  double minimumFramingCoverageFor(VisionSetupProfile profile) =>
      switch (profile) {
        VisionSetupProfile.leftHandFocus => 0.01,
        VisionSetupProfile.rightHandFocus => 0.01,
        VisionSetupProfile.fullUpperBody => 0.12,
        VisionSetupProfile.practiceBalanced => 0.18,
      };
}
