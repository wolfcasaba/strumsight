import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart'
    show VisionDeviceTier;

/// Ordered Vision work reductions from ADR 0182 Decision 3.
enum VisionDegradationStep {
  none,
  reduceOverlayFrequency,
  reducePosePipeline,
  reduceHandPipelineFps,
  reduceModelInputResolution,
  trackSingleHand,
  qualityMonitorOnly,
  visionDisabled,
}

/// Records whether a thermal decision came from the platform or the local
/// performance heuristic. The source is explicit so a future plugin cannot
/// silently turn the fallback path into a no-op.
enum VisionThermalDecisionSource { platform, heuristic }

/// Aggregate freshness statistics for a Vision session.
final class VisionFreshnessDistribution {
  const VisionFreshnessDistribution({
    required this.minimumMs,
    required this.averageMs,
    required this.maximumMs,
  }) : assert(minimumMs >= 0),
       assert(averageMs >= minimumMs && averageMs <= maximumMs);

  final int minimumMs;
  final int averageMs;
  final int maximumMs;
}

/// Session-local counter for inference freshness and dropped camera frames.
///
/// It deliberately stores aggregates only, so callers can create a
/// [VisionPerformanceSummary] without retaining raw frame history.
final class VisionPerformanceMonitor {
  int _processedFrameCount = 0;
  int _droppedFrameCount = 0;
  int _freshnessTotalMs = 0;
  int? _minimumFreshnessMs;
  int? _maximumFreshnessMs;

  int get processedFrameCount => _processedFrameCount;
  int get droppedFrameCount => _droppedFrameCount;

  double get droppedFrameRatio {
    final observedFrameCount = _processedFrameCount + _droppedFrameCount;
    return observedFrameCount == 0
        ? 0
        : _droppedFrameCount / observedFrameCount;
  }

  VisionFreshnessDistribution? get freshness {
    if (_processedFrameCount == 0) return null;
    return VisionFreshnessDistribution(
      minimumMs: _minimumFreshnessMs!,
      averageMs: _freshnessTotalMs ~/ _processedFrameCount,
      maximumMs: _maximumFreshnessMs!,
    );
  }

  void recordProcessedFrame({required int freshnessMs}) {
    if (freshnessMs < 0) {
      throw ArgumentError.value(
        freshnessMs,
        'freshnessMs',
        'Must not be negative.',
      );
    }
    _processedFrameCount += 1;
    _freshnessTotalMs += freshnessMs;
    _minimumFreshnessMs = _minimumFreshnessMs == null
        ? freshnessMs
        : freshnessMs < _minimumFreshnessMs!
        ? freshnessMs
        : _minimumFreshnessMs;
    _maximumFreshnessMs = _maximumFreshnessMs == null
        ? freshnessMs
        : freshnessMs > _maximumFreshnessMs!
        ? freshnessMs
        : _maximumFreshnessMs;
  }

  void recordDroppedFrame() {
    _droppedFrameCount += 1;
  }
}

/// Privacy-safe, session-level Vision performance result.
///
/// It contains aggregates only; no frames, camera identifiers, or device name
/// are recorded. [unavailable] makes unsupported benchmark outcomes explicit
/// while allowing the rest of the app to continue unchanged.
final class VisionPerformanceSummary {
  VisionPerformanceSummary.available({
    required this.tier,
    required List<VisionDegradationStep> appliedSteps,
    required this.droppedFrameRatio,
    required this.freshness,
    required List<Duration> degradationTimestamps,
    required this.thermalSource,
  }) : isAvailable = true,
       unavailableReason = null,
       appliedSteps = List.unmodifiable(appliedSteps),
       degradationTimestamps = List.unmodifiable(degradationTimestamps) {
    if (droppedFrameRatio < 0 || droppedFrameRatio > 1) {
      throw ArgumentError.value(
        droppedFrameRatio,
        'droppedFrameRatio',
        'Must be in the inclusive range 0..1.',
      );
    }
  }

  const VisionPerformanceSummary.unavailable(this.unavailableReason)
    : tier = null,
      appliedSteps = const <VisionDegradationStep>[],
      droppedFrameRatio = 0,
      freshness = null,
      degradationTimestamps = const <Duration>[],
      thermalSource = VisionThermalDecisionSource.heuristic,
      isAvailable = false;

  final VisionDeviceTier? tier;
  final List<VisionDegradationStep> appliedSteps;
  final double droppedFrameRatio;
  final VisionFreshnessDistribution? freshness;
  final List<Duration> degradationTimestamps;
  final VisionThermalDecisionSource thermalSource;
  final bool isAvailable;
  final String? unavailableReason;
}
