/// One deterministic quality state derived from a camera frame.
///
/// The model deliberately records setup observability only. It carries no
/// landmark, inference, or technical-playing claim.
enum VisionMetricState { good, needsImprovement, notObservable }

enum VisionLighting { good, tooDark, overexposed, notObservable }

enum VisionSetupCue {
  none,
  adjustFraming,
  improveLighting,
  reduceBlur,
  stabilizeCamera,
  increaseRoiCoverage,
  notObservable,
}

final class VisionFrameQuality {
  VisionFrameQuality({
    required this.thresholdsVersion,
    required this.framing,
    required this.lighting,
    required this.blur,
    required this.stability,
    required this.roiCoverage,
    required this.overall,
    required double meanLuminance,
    required double highlightClippingRatio,
    required double shadowClippingRatio,
    required double sharpness,
    required double cameraMotion,
    required double roiCoverageRatio,
  }) : meanLuminance = _finiteOrZero(meanLuminance),
       highlightClippingRatio = _finiteOrZero(highlightClippingRatio),
       shadowClippingRatio = _finiteOrZero(shadowClippingRatio),
       sharpness = _finiteOrZero(sharpness),
       cameraMotion = _finiteOrZero(cameraMotion),
       roiCoverageRatio = _finiteOrZero(roiCoverageRatio) {
    if (thresholdsVersion.trim().isEmpty) {
      throw ArgumentError.value(
        thresholdsVersion,
        'thresholdsVersion',
        'Must not be empty.',
      );
    }
  }

  final String thresholdsVersion;
  final VisionMetricState framing;
  final VisionLighting lighting;
  final VisionMetricState blur;
  final VisionMetricState stability;
  final VisionMetricState roiCoverage;
  final VisionMetricState overall;
  final double meanLuminance;
  final double highlightClippingRatio;
  final double shadowClippingRatio;
  final double sharpness;
  final double cameraMotion;
  final double roiCoverageRatio;

  /// Exposes every numeric output for finite-value guards and diagnostics.
  List<double> get measurements => <double>[
    meanLuminance,
    highlightClippingRatio,
    shadowClippingRatio,
    sharpness,
    cameraMotion,
    roiCoverageRatio,
  ];

  bool get hasTechnicalFeedback => overall == VisionMetricState.good;

  static double _finiteOrZero(double value) => value.isFinite ? value : 0;
}
