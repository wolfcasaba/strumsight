import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/public.dart';

void main() {
  group('VisionQualitySummary', () {
    test(
      'chooses exactly one cue using the required complete priority order',
      () {
        final summary = VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(
            framing: VisionMetricState.needsImprovement,
            lighting: VisionLighting.tooDark,
            blur: VisionMetricState.needsImprovement,
            stability: VisionMetricState.needsImprovement,
            roiCoverage: VisionMetricState.needsImprovement,
          ),
        ]);

        expect(summary.setupCue, VisionSetupCue.adjustFraming);
        expect(summary.activeCueCount, 1);
      },
    );

    test('resolves same-severity lighting failures deterministically', () {
      final first = VisionQualitySummary.fromFrames(<VisionFrameQuality>[
        _quality(lighting: VisionLighting.tooDark),
      ]);
      final second = VisionQualitySummary.fromFrames(<VisionFrameQuality>[
        _quality(lighting: VisionLighting.tooDark),
      ]);

      expect(first.setupCue, VisionSetupCue.improveLighting);
      expect(second.setupCue, first.setupCue);
    });

    test('uses each later cue only when every earlier concern is good', () {
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(lighting: VisionLighting.overexposed),
        ]).setupCue,
        VisionSetupCue.improveLighting,
      );
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(blur: VisionMetricState.needsImprovement),
        ]).setupCue,
        VisionSetupCue.reduceBlur,
      );
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(stability: VisionMetricState.needsImprovement),
        ]).setupCue,
        VisionSetupCue.stabilizeCamera,
      );
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(roiCoverage: VisionMetricState.needsImprovement),
        ]).setupCue,
        VisionSetupCue.increaseRoiCoverage,
      );
    });

    test('prioritizes each cue over every lower-priority concern', () {
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(
            blur: VisionMetricState.needsImprovement,
            stability: VisionMetricState.needsImprovement,
            roiCoverage: VisionMetricState.needsImprovement,
          ),
        ]).setupCue,
        VisionSetupCue.reduceBlur,
      );
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(
            stability: VisionMetricState.needsImprovement,
            roiCoverage: VisionMetricState.needsImprovement,
          ),
        ]).setupCue,
        VisionSetupCue.stabilizeCamera,
      );
      expect(
        VisionQualitySummary.fromFrames(<VisionFrameQuality>[
          _quality(roiCoverage: VisionMetricState.needsImprovement),
        ]).setupCue,
        VisionSetupCue.increaseRoiCoverage,
      );
    });

    test('does not turn unavailable evidence into technical feedback', () {
      final summary = VisionQualitySummary.fromFrames(<VisionFrameQuality>[
        _quality(overall: VisionMetricState.notObservable),
      ]);

      expect(summary.setupCue, VisionSetupCue.notObservable);
      expect(summary.activeCueCount, 1);
    });
  });
}

VisionFrameQuality _quality({
  VisionMetricState framing = VisionMetricState.good,
  VisionLighting lighting = VisionLighting.good,
  VisionMetricState blur = VisionMetricState.good,
  VisionMetricState stability = VisionMetricState.good,
  VisionMetricState roiCoverage = VisionMetricState.good,
  VisionMetricState overall = VisionMetricState.good,
}) => VisionFrameQuality(
  thresholdsVersion: 'test-v1',
  framing: framing,
  lighting: lighting,
  blur: blur,
  stability: stability,
  roiCoverage: roiCoverage,
  overall: overall,
  meanLuminance: 100,
  highlightClippingRatio: 0,
  shadowClippingRatio: 0,
  sharpness: 20,
  cameraMotion: 0,
  roiCoverageRatio: 1,
);
