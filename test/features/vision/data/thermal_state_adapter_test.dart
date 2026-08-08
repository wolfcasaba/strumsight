import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/data/performance/device_tier_benchmark.dart';
import 'package:strumsight/features/vision/data/performance/thermal_state_adapter.dart';
import 'package:strumsight/features/vision/domain/performance/vision_performance_summary.dart';

void main() {
  group('DeviceTierBenchmark', () {
    const benchmark = DeviceTierBenchmark();

    test('converts an invalid benchmark sample to an unavailable result', () {
      final result = benchmark.evaluate(
        const DeviceTierBenchmarkMeasurement(averageFrameProcessingTimeMs: -1),
      );

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, 'invalid-frame-processing-time');
    });
  });

  group('ThermalStateAdapter', () {
    const adapter = ThermalStateAdapter();
    const heuristic = VisionThermalHeuristicInput(
      receivedFrames: 100,
      droppedFrames: 10,
      averageFreshnessMs: 100,
      averageProcessingTimeMs: 50,
    );

    test('uses a platform thermal state when one is supplied', () {
      final decision = adapter.evaluate(
        platformThermalLoad: 80,
        heuristic: heuristic,
      );

      expect(decision.source, VisionThermalDecisionSource.platform);
      expect(decision.load, 80);
    });

    test('falls back to a deterministic performance heuristic', () {
      final first = adapter.evaluate(heuristic: heuristic);
      final second = adapter.evaluate(heuristic: heuristic);

      expect(first.source, VisionThermalDecisionSource.heuristic);
      expect(first, second);
      expect(first.load, inInclusiveRange(0, 100));
    });
  });
}
