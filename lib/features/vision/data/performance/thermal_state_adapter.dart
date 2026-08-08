import 'package:strumsight/features/vision/domain/performance/vision_performance_summary.dart';

/// Aggregate values used when the platform cannot report thermal pressure.
final class VisionThermalHeuristicInput {
  const VisionThermalHeuristicInput({
    required this.receivedFrames,
    required this.droppedFrames,
    required this.averageFreshnessMs,
    required this.averageProcessingTimeMs,
  }) : assert(receivedFrames >= 0),
       assert(droppedFrames >= 0),
       assert(averageFreshnessMs >= 0),
       assert(averageProcessingTimeMs >= 0);

  final int receivedFrames;
  final int droppedFrames;
  final int averageFreshnessMs;
  final int averageProcessingTimeMs;
}

/// Source-labelled thermal load that can be passed to a scheduling policy.
final class VisionThermalDecision {
  const VisionThermalDecision({required this.load, required this.source})
    : assert(load >= 0 && load <= 100);

  final int load;
  final VisionThermalDecisionSource source;

  @override
  bool operator ==(Object other) =>
      other is VisionThermalDecision &&
      other.load == load &&
      other.source == source;

  @override
  int get hashCode => Object.hash(load, source);
}

/// Prefers an injected platform load, otherwise uses a bounded local
/// heuristic. There is deliberately no platform-plugin call in this round.
final class ThermalStateAdapter {
  const ThermalStateAdapter();

  VisionThermalDecision evaluate({
    int? platformThermalLoad,
    required VisionThermalHeuristicInput heuristic,
  }) {
    if (platformThermalLoad != null) {
      if (platformThermalLoad < 0 || platformThermalLoad > 100) {
        throw ArgumentError.value(
          platformThermalLoad,
          'platformThermalLoad',
          'Must be in the inclusive range 0..100.',
        );
      }
      return VisionThermalDecision(
        load: platformThermalLoad,
        source: VisionThermalDecisionSource.platform,
      );
    }

    final observedFrames = heuristic.receivedFrames + heuristic.droppedFrames;
    final droppedRatio = observedFrames == 0
        ? 0
        : heuristic.droppedFrames / observedFrames;
    final droppedLoad = droppedRatio * 40;
    final freshnessLoad = (heuristic.averageFreshnessMs / 200).clamp(0, 1) * 30;
    final processingLoad =
        (heuristic.averageProcessingTimeMs / 100).clamp(0, 1) * 30;
    final load = (droppedLoad + freshnessLoad + processingLoad).round().clamp(
      0,
      100,
    );

    return VisionThermalDecision(
      load: load,
      source: VisionThermalDecisionSource.heuristic,
    );
  }
}
