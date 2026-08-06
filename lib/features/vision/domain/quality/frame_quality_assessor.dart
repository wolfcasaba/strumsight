import 'dart:typed_data';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../vision_setup_profile.dart';
import 'quality_thresholds.dart';
import 'vision_frame_quality.dart';

/// Framework-free grayscale input to [FrameQualityAssessor].
///
/// The platform adapter is responsible for converting camera buffers to this
/// luminance plane. Keeping that conversion outside this domain type avoids a
/// dependency on platform image formats and makes malformed input explicit.
final class GrayscaleFrame {
  GrayscaleFrame({
    required this.width,
    required this.height,
    required Uint8List luminance,
  }) : luminance = Uint8List.fromList(luminance);

  final int width;
  final int height;
  final Uint8List luminance;

  bool get isWellFormed =>
      width > 0 && height > 0 && luminance.length >= width * height;
}

/// Computes model-free image and inter-frame quality measurements.
///
/// Motion is intentionally a frame-delta proxy, not a claim about a hand or
/// guitar. The first well-formed frame has no prior reference and therefore
/// reports stability as [VisionMetricState.notObservable].
final class FrameQualityAssessor {
  FrameQualityAssessor({this.thresholds = const QualityThresholds.defaultV1()});

  final QualityThresholds thresholds;
  List<int>? _previousSamples;

  VisionFrameQuality assess(
    GrayscaleFrame frame, {
    required VisionSetupProfile profile,
    required NormalizedRect? roi,
  }) {
    if (!frame.isWellFormed) {
      _previousSamples = null;
      return _notObservable();
    }

    final samples = _downsample(frame);
    if (samples.isEmpty || _isConstant(samples)) {
      _previousSamples = null;
      return _notObservable();
    }

    final meanLuminance = _mean(samples);
    final shadowClippingRatio = _ratioAtMost(
      samples,
      thresholds.shadowClipLuminance,
    );
    final highlightClippingRatio = _ratioAtLeast(
      samples,
      thresholds.highlightClipLuminance,
    );
    final sharpness = _sharpness(frame);
    final cameraMotion = _cameraMotion(samples);
    final roiCoverageRatio = roi == null ? 0.0 : _area(roi);

    final lighting =
        thresholds.isTooDark(
          meanLuminance: meanLuminance,
          shadowClippingRatio: shadowClippingRatio,
        )
        ? VisionLighting.tooDark
        : thresholds.isOverexposed(
            meanLuminance: meanLuminance,
            highlightClippingRatio: highlightClippingRatio,
          )
        ? VisionLighting.overexposed
        : VisionLighting.good;
    final framing = roi == null
        ? VisionMetricState.notObservable
        : roiCoverageRatio >= thresholds.minimumFramingCoverageFor(profile)
        ? VisionMetricState.good
        : VisionMetricState.needsImprovement;
    final blur = thresholds.isBlurred(sharpness)
        ? VisionMetricState.needsImprovement
        : VisionMetricState.good;
    final stability = cameraMotion == null
        ? VisionMetricState.notObservable
        : thresholds.isUnstable(cameraMotion)
        ? VisionMetricState.needsImprovement
        : VisionMetricState.good;
    final roiCoverage = roi == null
        ? VisionMetricState.notObservable
        : thresholds.hasInsufficientRoiCoverage(roiCoverageRatio)
        ? VisionMetricState.needsImprovement
        : VisionMetricState.good;
    final overall = _overall(
      framing: framing,
      lighting: lighting,
      blur: blur,
      stability: stability,
      roiCoverage: roiCoverage,
    );

    _previousSamples = samples;
    return VisionFrameQuality(
      thresholdsVersion: thresholds.thresholdsVersion,
      framing: framing,
      lighting: lighting,
      blur: blur,
      stability: stability,
      roiCoverage: roiCoverage,
      overall: overall,
      meanLuminance: meanLuminance,
      highlightClippingRatio: highlightClippingRatio,
      shadowClippingRatio: shadowClippingRatio,
      sharpness: sharpness,
      cameraMotion: cameraMotion ?? 0,
      roiCoverageRatio: roiCoverageRatio,
    );
  }

  void reset() => _previousSamples = null;

  VisionFrameQuality _notObservable() => VisionFrameQuality(
    thresholdsVersion: thresholds.thresholdsVersion,
    framing: VisionMetricState.notObservable,
    lighting: VisionLighting.notObservable,
    blur: VisionMetricState.notObservable,
    stability: VisionMetricState.notObservable,
    roiCoverage: VisionMetricState.notObservable,
    overall: VisionMetricState.notObservable,
    meanLuminance: 0,
    highlightClippingRatio: 0,
    shadowClippingRatio: 0,
    sharpness: 0,
    cameraMotion: 0,
    roiCoverageRatio: 0,
  );

  List<int> _downsample(GrayscaleFrame frame) {
    final samples = <int>[];
    for (var y = 0; y < frame.height; y += thresholds.downsampleFactor) {
      for (var x = 0; x < frame.width; x += thresholds.downsampleFactor) {
        samples.add(frame.luminance[y * frame.width + x]);
      }
    }
    return samples;
  }

  double _sharpness(GrayscaleFrame frame) {
    var differenceTotal = 0;
    var comparisons = 0;
    final step = thresholds.downsampleFactor;
    for (var y = 0; y < frame.height; y += step) {
      for (var x = 0; x < frame.width; x += step) {
        final value = frame.luminance[y * frame.width + x];
        if (x + step < frame.width) {
          differenceTotal +=
              (value - frame.luminance[y * frame.width + x + step]).abs();
          comparisons += 1;
        }
        if (y + step < frame.height) {
          differenceTotal +=
              (value - frame.luminance[(y + step) * frame.width + x]).abs();
          comparisons += 1;
        }
      }
    }
    return comparisons == 0 ? 0 : differenceTotal / comparisons;
  }

  double? _cameraMotion(List<int> samples) {
    final previous = _previousSamples;
    if (previous == null || previous.length != samples.length) return null;
    var differenceTotal = 0;
    for (var index = 0; index < samples.length; index += 1) {
      differenceTotal += (samples[index] - previous[index]).abs();
    }
    return differenceTotal / samples.length;
  }

  static bool _isConstant(List<int> samples) =>
      samples.every((sample) => sample == samples.first);

  static double _mean(List<int> samples) =>
      samples.fold<int>(0, (sum, sample) => sum + sample) / samples.length;

  static double _ratioAtMost(List<int> samples, int limit) =>
      samples.where((sample) => sample <= limit).length / samples.length;

  static double _ratioAtLeast(List<int> samples, int limit) =>
      samples.where((sample) => sample >= limit).length / samples.length;

  static double _area(NormalizedRect rect) =>
      (rect.right - rect.left) * (rect.bottom - rect.top);

  static VisionMetricState _overall({
    required VisionMetricState framing,
    required VisionLighting lighting,
    required VisionMetricState blur,
    required VisionMetricState stability,
    required VisionMetricState roiCoverage,
  }) {
    if (framing == VisionMetricState.notObservable ||
        lighting == VisionLighting.notObservable ||
        blur == VisionMetricState.notObservable ||
        stability == VisionMetricState.notObservable ||
        roiCoverage == VisionMetricState.notObservable) {
      return VisionMetricState.notObservable;
    }
    if (framing == VisionMetricState.needsImprovement ||
        lighting != VisionLighting.good ||
        blur == VisionMetricState.needsImprovement ||
        stability == VisionMetricState.needsImprovement ||
        roiCoverage == VisionMetricState.needsImprovement) {
      return VisionMetricState.needsImprovement;
    }
    return VisionMetricState.good;
  }
}
