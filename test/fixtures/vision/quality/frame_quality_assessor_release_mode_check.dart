import 'dart:typed_data';

import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/domain/quality/frame_quality_assessor.dart';
import 'package:strumsight/features/vision/domain/quality/quality_thresholds.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';

void main() {
  final quality =
      FrameQualityAssessor(thresholds: _thresholds(downsampleFactor: 1)).assess(
        _sharpFrame(),
        profile: VisionSetupProfile.practiceBalanced,
        roi: NormalizedRect(left: double.nan, top: 0, right: 1, bottom: 1),
      );
  if (quality.framing != VisionMetricState.notObservable ||
      quality.roiCoverage != VisionMetricState.notObservable) {
    throw StateError('non-finite ROI must be notObservable');
  }

  final invalidDownsampleFactor = int.parse('0');
  final assessor = FrameQualityAssessor(
    thresholds: _thresholds(downsampleFactor: invalidDownsampleFactor),
  );
  try {
    assessor.assess(
      _sharpFrame(),
      profile: VisionSetupProfile.practiceBalanced,
      roi: const NormalizedRect.full(),
    );
  } on ArgumentError {
    return;
  }
  throw StateError('non-positive downsample factor must throw ArgumentError');
}

QualityThresholds _thresholds({required int downsampleFactor}) =>
    QualityThresholds(
      thresholdsVersion: 'release-check-v1',
      downsampleFactor: downsampleFactor,
      minimumMeanLuminance: 40,
      maximumMeanLuminance: 215,
      maximumShadowClippingRatio: 0.20,
      maximumHighlightClippingRatio: 0.20,
      minimumSharpness: 10,
      maximumCameraMotion: 12,
      minimumRoiCoverage: 0.20,
    );

GrayscaleFrame _sharpFrame() => GrayscaleFrame(
  width: 8,
  height: 8,
  luminance: Uint8List.fromList(
    List<int>.generate(64, (index) => index.isEven ? 80 : 180),
  ),
);
