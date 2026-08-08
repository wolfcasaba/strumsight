import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart'
    show VisionDeviceTier;
import 'package:strumsight/features/vision/domain/performance/vision_device_tier.dart';
import 'package:strumsight/features/vision/domain/performance/vision_performance_summary.dart';

void main() {
  group('VisionDeviceTierClassifier', () {
    const classifier = VisionDeviceTierClassifier();

    test(
      'classifies measured frame processing time at every tier boundary',
      () {
        expect(
          classifier.classify(const VisionDeviceTierBenchmarkInput(33)).tier,
          VisionDeviceTier.flagship,
        );
        expect(
          classifier.classify(const VisionDeviceTierBenchmarkInput(34)).tier,
          VisionDeviceTier.mid,
        );
        expect(
          classifier.classify(const VisionDeviceTierBenchmarkInput(66)).tier,
          VisionDeviceTier.mid,
        );
        expect(
          classifier.classify(const VisionDeviceTierBenchmarkInput(67)).tier,
          VisionDeviceTier.basic,
        );
      },
    );

    test('returns the same tier for the same measured input', () {
      const input = VisionDeviceTierBenchmarkInput(50);

      expect(classifier.classify(input), classifier.classify(input));
    });

    test('maps every existing tier to its explicit inference profile', () {
      expect(
        VisionDeviceTierProfiles.forTier(VisionDeviceTier.basic),
        const VisionDeviceTierProfile(
          handFramesPerSecond: 8,
          poseCadenceEveryNthFrame: 8,
          inputResolutionPx: 192,
          overlayFramesPerSecond: 15,
        ),
      );
      expect(
        VisionDeviceTierProfiles.forTier(VisionDeviceTier.mid),
        const VisionDeviceTierProfile(
          handFramesPerSecond: 12,
          poseCadenceEveryNthFrame: 6,
          inputResolutionPx: 256,
          overlayFramesPerSecond: 24,
        ),
      );
      expect(
        VisionDeviceTierProfiles.forTier(VisionDeviceTier.flagship),
        const VisionDeviceTierProfile(
          handFramesPerSecond: 15,
          poseCadenceEveryNthFrame: 4,
          inputResolutionPx: 320,
          overlayFramesPerSecond: 30,
        ),
      );
    });
  });

  group('VisionPerformanceSummary', () {
    test('counts synthetic drops and freshness without retaining frames', () {
      final monitor = VisionPerformanceMonitor()
        ..recordProcessedFrame(freshnessMs: 10)
        ..recordDroppedFrame()
        ..recordProcessedFrame(freshnessMs: 30)
        ..recordDroppedFrame();

      expect(monitor.processedFrameCount, 2);
      expect(monitor.droppedFrameCount, 2);
      expect(monitor.droppedFrameRatio, 0.5);
      expect(monitor.freshness!.minimumMs, 10);
      expect(monitor.freshness!.averageMs, 20);
      expect(monitor.freshness!.maximumMs, 30);
    });

    test('keeps only aggregate performance values', () {
      final summary = VisionPerformanceSummary.available(
        tier: VisionDeviceTier.mid,
        appliedSteps: const <VisionDegradationStep>[
          VisionDegradationStep.reduceOverlayFrequency,
        ],
        droppedFrameRatio: 0.1,
        freshness: const VisionFreshnessDistribution(
          minimumMs: 10,
          averageMs: 20,
          maximumMs: 30,
        ),
        degradationTimestamps: const <Duration>[Duration(seconds: 1)],
        thermalSource: VisionThermalDecisionSource.heuristic,
      );

      expect(summary.isAvailable, isTrue);
      expect(summary.droppedFrameRatio, 0.1);
      expect(summary.freshness!.averageMs, 20);
      expect(summary.thermalSource, VisionThermalDecisionSource.heuristic);
    });

    test('makes an unsupported benchmark explicitly unavailable', () {
      const summary = VisionPerformanceSummary.unavailable('benchmark-failed');

      expect(summary.isAvailable, isFalse);
      expect(summary.unavailableReason, 'benchmark-failed');
      expect(summary.tier, isNull);
    });
  });
}
