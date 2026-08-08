import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/vision_degradation_policy.dart';

void main() {
  const policy = VisionDegradationPolicy();

  group('VisionDegradationPolicy entry matrix', () {
    for (final entry in <VisionPerformanceSnapshot, VisionDegradationStep>{
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 11,
        poseFramesPerSecond: 10,
      ): VisionDegradationStep.reduceOverlayFrequency,
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 9,
        poseFramesPerSecond: 10,
      ): VisionDegradationStep.reducePosePipeline,
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 15,
        poseFramesPerSecond: 4,
      ): VisionDegradationStep.reduceHandPipelineFps,
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 7,
        poseFramesPerSecond: 10,
      ): VisionDegradationStep.reduceModelInputResolution,
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 5,
        poseFramesPerSecond: 10,
      ): VisionDegradationStep.trackSingleHand,
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 3,
        poseFramesPerSecond: 10,
      ): VisionDegradationStep.qualityMonitorOnly,
      const VisionPerformanceSnapshot(
        handFramesPerSecond: 15,
        poseFramesPerSecond: 10,
        audioProcessingLatencyIncreaseMs: 15,
      ): VisionDegradationStep.visionDisabled,
    }.entries) {
      test('selects ${entry.value} for its published entry threshold', () {
        expect(
          policy
              .decide(
                currentStep: VisionDegradationStep.none,
                snapshot: entry.key,
              )
              .step,
          entry.value,
        );
      });
    }

    test('a mild violation never skips directly to vision disabled', () {
      final decision = policy.decide(
        currentStep: VisionDegradationStep.none,
        snapshot: const VisionPerformanceSnapshot(
          handFramesPerSecond: 11,
          poseFramesPerSecond: 10,
        ),
      );

      expect(decision.step, VisionDegradationStep.reduceOverlayFrequency);
      expect(decision.isVisionAvailable, isTrue);
    });

    test('audio pressure changes only the vision decision', () {
      const snapshot = VisionPerformanceSnapshot(
        handFramesPerSecond: 15,
        poseFramesPerSecond: 10,
        audioProcessingLatencyIncreaseMs: 15,
      );

      policy.decide(
        currentStep: VisionDegradationStep.none,
        snapshot: snapshot,
      );

      expect(snapshot.audioProcessingLatencyIncreaseMs, 15);
    });
  });

  group('VisionDegradationPolicy hysteresis', () {
    test('recovers one step only after the documented exit threshold', () {
      const underPressure = VisionPerformanceSnapshot(
        handFramesPerSecond: 11,
        poseFramesPerSecond: 10,
      );
      const stillBelowExit = VisionPerformanceSnapshot(
        handFramesPerSecond: 12,
        poseFramesPerSecond: 10,
      );
      const recovered = VisionPerformanceSnapshot(
        handFramesPerSecond: 13,
        poseFramesPerSecond: 10,
      );

      final entered = policy.decide(
        currentStep: VisionDegradationStep.none,
        snapshot: underPressure,
      );
      final held = policy.decide(
        currentStep: entered.step,
        snapshot: stillBelowExit,
      );
      final exited = policy.decide(currentStep: held.step, snapshot: recovered);

      expect(held.step, VisionDegradationStep.reduceOverlayFrequency);
      expect(exited.step, VisionDegradationStep.none);
      expect(exited.transitionCount, 1);
    });

    for (final entry in <VisionDegradationStep, VisionPerformanceSnapshot>{
      VisionDegradationStep.reduceOverlayFrequency:
          const VisionPerformanceSnapshot(
            handFramesPerSecond: 13,
            poseFramesPerSecond: 10,
          ),
      VisionDegradationStep.reducePosePipeline: const VisionPerformanceSnapshot(
        handFramesPerSecond: 11,
        poseFramesPerSecond: 10,
      ),
      VisionDegradationStep.reduceHandPipelineFps:
          const VisionPerformanceSnapshot(
            handFramesPerSecond: 15,
            poseFramesPerSecond: 6,
          ),
      VisionDegradationStep.reduceModelInputResolution:
          const VisionPerformanceSnapshot(
            handFramesPerSecond: 9,
            poseFramesPerSecond: 10,
          ),
      VisionDegradationStep.trackSingleHand: const VisionPerformanceSnapshot(
        handFramesPerSecond: 7,
        poseFramesPerSecond: 10,
      ),
      VisionDegradationStep.qualityMonitorOnly: const VisionPerformanceSnapshot(
        handFramesPerSecond: 5,
        poseFramesPerSecond: 10,
      ),
      VisionDegradationStep.visionDisabled: const VisionPerformanceSnapshot(
        handFramesPerSecond: 15,
        poseFramesPerSecond: 10,
        audioProcessingLatencyIncreaseMs: 11,
      ),
    }.entries) {
      test('${entry.key} exits only one step at its recovery margin', () {
        final decision = policy.decide(
          currentStep: entry.key,
          snapshot: entry.value,
        );

        expect(decision.step.index, entry.key.index - 1);
        expect(decision.transitionCount, 1);
      });
    }
  });
}
