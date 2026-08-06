import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/public.dart';

void main() {
  const thresholds = QualityThresholds(
    thresholdsVersion: 'test-v1',
    downsampleFactor: 1,
    minimumMeanLuminance: 40,
    maximumMeanLuminance: 215,
    maximumShadowClippingRatio: 0.20,
    maximumHighlightClippingRatio: 0.20,
    minimumSharpness: 10,
    maximumCameraMotion: 12,
    minimumRoiCoverage: 0.20,
  );

  group('FrameQualityAssessor', () {
    test(
      'assesses the synthetic dark, clipped, blurred and sharp fixtures',
      () {
        final assessor = FrameQualityAssessor(thresholds: thresholds);

        final dark = assessor.assess(
          _frame(
            width: 8,
            height: 8,
            pixels: _checkerboard(8, 8, low: 10, high: 30),
          ),
          profile: VisionSetupProfile.practiceBalanced,
          roi: const NormalizedRect.full(),
        );
        final clipped = assessor.assess(
          _frame(
            width: 8,
            height: 8,
            pixels: _checkerboard(8, 8, low: 230, high: 255),
          ),
          profile: VisionSetupProfile.practiceBalanced,
          roi: const NormalizedRect.full(),
        );
        final blurred = assessor.assess(
          _frame(width: 8, height: 8, pixels: _softGradient(8, 8)),
          profile: VisionSetupProfile.practiceBalanced,
          roi: const NormalizedRect.full(),
        );
        final blurredWide = assessor.assess(
          _frame(width: 16, height: 12, pixels: _softGradient(16, 12)),
          profile: VisionSetupProfile.practiceBalanced,
          roi: const NormalizedRect.full(),
        );
        assessor.assess(
          _frame(
            width: 8,
            height: 8,
            pixels: _checkerboard(8, 8, low: 80, high: 180),
          ),
          profile: VisionSetupProfile.practiceBalanced,
          roi: const NormalizedRect.full(),
        );
        final sharpStable = assessor.assess(
          _frame(
            width: 8,
            height: 8,
            pixels: _checkerboard(8, 8, low: 80, high: 180),
          ),
          profile: VisionSetupProfile.practiceBalanced,
          roi: const NormalizedRect.full(),
        );

        expect(dark.lighting, VisionLighting.tooDark);
        expect(clipped.lighting, VisionLighting.overexposed);
        expect(blurred.blur, VisionMetricState.needsImprovement);
        expect(blurredWide.blur, VisionMetricState.needsImprovement);
        expect(sharpStable.overall, VisionMetricState.good);
        expect(sharpStable.thresholdsVersion, 'test-v1');
      },
    );

    test('uses all three luminance and clipping threshold cells', () {
      expect(
        thresholds.isTooDark(meanLuminance: 39, shadowClippingRatio: 0),
        isTrue,
      );
      expect(
        thresholds.isTooDark(meanLuminance: 40, shadowClippingRatio: 0.20),
        isFalse,
      );
      expect(
        thresholds.isTooDark(meanLuminance: 41, shadowClippingRatio: 0.30),
        isTrue,
      );

      expect(
        thresholds.isOverexposed(
          meanLuminance: 214,
          highlightClippingRatio: 0.20,
        ),
        isFalse,
      );
      expect(
        thresholds.isOverexposed(
          meanLuminance: 215,
          highlightClippingRatio: 0.20,
        ),
        isFalse,
      );
      expect(
        thresholds.isOverexposed(
          meanLuminance: 216,
          highlightClippingRatio: 0.30,
        ),
        isTrue,
      );
    });

    test('uses all three sharpness, motion and coverage threshold cells', () {
      expect(thresholds.isBlurred(9.9), isTrue);
      expect(thresholds.isBlurred(10), isFalse);
      expect(thresholds.isBlurred(10.1), isFalse);

      expect(thresholds.isUnstable(11.9), isFalse);
      expect(thresholds.isUnstable(12), isFalse);
      expect(thresholds.isUnstable(12.1), isTrue);

      expect(thresholds.hasInsufficientRoiCoverage(0.10), isTrue);
      expect(thresholds.hasInsufficientRoiCoverage(0.20), isFalse);
      expect(thresholds.hasInsufficientRoiCoverage(0.30), isFalse);
    });

    test(
      'returns notObservable with finite measurements for degenerate input',
      () {
        final quality = FrameQualityAssessor(thresholds: thresholds).assess(
          GrayscaleFrame(width: 0, height: 0, luminance: Uint8List(0)),
          profile: VisionSetupProfile.leftHandFocus,
          roi: null,
        );

        expect(quality.overall, VisionMetricState.notObservable);
        expect(quality.lighting, VisionLighting.notObservable);
        expect(
          quality.measurements,
          everyElement(predicate((double value) => value.isFinite)),
        );
      },
    );

    test('partial ROI is a separate frame-quality concern', () {
      final assessor = FrameQualityAssessor(thresholds: thresholds);
      assessor.assess(
        _frame(
          width: 8,
          height: 8,
          pixels: _checkerboard(8, 8, low: 80, high: 180),
        ),
        profile: VisionSetupProfile.leftHandFocus,
        roi: const NormalizedRect.full(),
      );
      final quality = assessor.assess(
        _frame(
          width: 8,
          height: 8,
          pixels: _checkerboard(8, 8, low: 80, high: 180),
        ),
        profile: VisionSetupProfile.leftHandFocus,
        roi: const NormalizedRect(
          left: 0.45,
          top: 0.45,
          right: 0.55,
          bottom: 0.55,
        ),
      );

      expect(quality.framing, VisionMetricState.good);
      expect(quality.roiCoverage, VisionMetricState.needsImprovement);
    });

    test('does not compare motion across an unobservable frame', () {
      final assessor = FrameQualityAssessor(thresholds: thresholds);
      final sharpFrame = _frame(
        width: 8,
        height: 8,
        pixels: _checkerboard(8, 8, low: 80, high: 180),
      );

      assessor.assess(
        sharpFrame,
        profile: VisionSetupProfile.practiceBalanced,
        roi: const NormalizedRect.full(),
      );
      assessor.assess(
        _frame(width: 8, height: 8, pixels: List<int>.filled(64, 100)),
        profile: VisionSetupProfile.practiceBalanced,
        roi: const NormalizedRect.full(),
      );
      final afterGap = assessor.assess(
        sharpFrame,
        profile: VisionSetupProfile.practiceBalanced,
        roi: const NormalizedRect.full(),
      );

      expect(afterGap.stability, VisionMetricState.notObservable);
    });
  });
}

GrayscaleFrame _frame({
  required int width,
  required int height,
  required List<int> pixels,
}) => GrayscaleFrame(
  width: width,
  height: height,
  luminance: Uint8List.fromList(pixels),
);

List<int> _checkerboard(
  int width,
  int height, {
  required int low,
  required int high,
}) => List<int>.generate(
  width * height,
  (index) => ((index ~/ width) + (index % width)).isEven ? low : high,
);

List<int> _softGradient(int width, int height) => List<int>.generate(
  width * height,
  (index) => 100 + (index % width) + (index ~/ width),
);
