import 'package:strumsight/features/vision/domain/performance/vision_performance_summary.dart'
    show VisionDegradationStep;

export 'package:strumsight/features/vision/domain/performance/vision_performance_summary.dart'
    show VisionDegradationStep;

/// The measured signals used to choose the next Vision degradation step.
final class VisionPerformanceSnapshot {
  const VisionPerformanceSnapshot({
    required this.handFramesPerSecond,
    required this.poseFramesPerSecond,
    this.audioProcessingLatencyIncreaseMs = 0,
  }) : assert(handFramesPerSecond >= 0),
       assert(poseFramesPerSecond >= 0),
       assert(audioProcessingLatencyIncreaseMs >= 0);

  final int handFramesPerSecond;
  final int poseFramesPerSecond;
  final int audioProcessingLatencyIncreaseMs;
}

/// A single, bounded policy transition. Recovery can advance by one step per
/// evaluation; degradation may move directly to the least severe step that
/// covers the measured violation.
final class VisionDegradationDecision {
  const VisionDegradationDecision({
    required this.step,
    required this.previousStep,
  });

  final VisionDegradationStep step;
  final VisionDegradationStep previousStep;

  bool get isVisionAvailable => step != VisionDegradationStep.visionDisabled;
  bool get changed => step != previousStep;

  /// A policy invocation performs at most one state transition.
  int get transitionCount => changed ? 1 : 0;
}

/// Stateless, hysteresis-aware Vision degradation policy.
///
/// The caller owns the returned step as session state. Keeping that state out
/// of this service makes the same input and current step deterministic.
final class VisionDegradationPolicy {
  const VisionDegradationPolicy();

  static const int overlayEntryHandFramesPerSecond = 12;
  static const int poseEntryHandFramesPerSecond = 10;
  static const int handEntryPoseFramesPerSecond = 5;
  static const int resolutionEntryHandFramesPerSecond = 8;
  static const int singleHandEntryFramesPerSecond = 6;
  static const int qualityOnlyEntryHandFramesPerSecond = 4;
  static const int visionDisabledEntryAudioLatencyIncreaseMs = 15;

  // A one-FPS recovery margin prevents threshold flapping. Audio has a three
  // millisecond margin, returning only once the increase is below 12 ms.
  static const int overlayExitHandFramesPerSecond = 13;
  static const int poseExitHandFramesPerSecond = 11;
  static const int handExitPoseFramesPerSecond = 6;
  static const int resolutionExitHandFramesPerSecond = 9;
  static const int singleHandExitFramesPerSecond = 7;
  static const int qualityOnlyExitHandFramesPerSecond = 5;
  static const int visionDisabledExitAudioLatencyIncreaseMs = 12;

  VisionDegradationDecision decide({
    required VisionDegradationStep currentStep,
    required VisionPerformanceSnapshot snapshot,
  }) {
    final requiredStep = _requiredStep(snapshot);
    if (requiredStep.index > currentStep.index) {
      return VisionDegradationDecision(
        step: requiredStep,
        previousStep: currentStep,
      );
    }
    if (requiredStep.index == currentStep.index ||
        !_canRecover(currentStep, snapshot)) {
      return VisionDegradationDecision(
        step: currentStep,
        previousStep: currentStep,
      );
    }

    return VisionDegradationDecision(
      step: VisionDegradationStep.values[currentStep.index - 1],
      previousStep: currentStep,
    );
  }

  VisionDegradationStep _requiredStep(VisionPerformanceSnapshot snapshot) {
    if (snapshot.audioProcessingLatencyIncreaseMs >=
        visionDisabledEntryAudioLatencyIncreaseMs) {
      return VisionDegradationStep.visionDisabled;
    }
    if (snapshot.handFramesPerSecond < qualityOnlyEntryHandFramesPerSecond) {
      return VisionDegradationStep.qualityMonitorOnly;
    }
    if (snapshot.handFramesPerSecond < singleHandEntryFramesPerSecond) {
      return VisionDegradationStep.trackSingleHand;
    }
    if (snapshot.handFramesPerSecond < resolutionEntryHandFramesPerSecond) {
      return VisionDegradationStep.reduceModelInputResolution;
    }
    if (snapshot.poseFramesPerSecond < handEntryPoseFramesPerSecond) {
      return VisionDegradationStep.reduceHandPipelineFps;
    }
    if (snapshot.handFramesPerSecond < poseEntryHandFramesPerSecond) {
      return VisionDegradationStep.reducePosePipeline;
    }
    if (snapshot.handFramesPerSecond < overlayEntryHandFramesPerSecond) {
      return VisionDegradationStep.reduceOverlayFrequency;
    }
    return VisionDegradationStep.none;
  }

  bool _canRecover(
    VisionDegradationStep currentStep,
    VisionPerformanceSnapshot snapshot,
  ) => switch (currentStep) {
    VisionDegradationStep.none => false,
    VisionDegradationStep.reduceOverlayFrequency =>
      snapshot.handFramesPerSecond >= overlayExitHandFramesPerSecond,
    VisionDegradationStep.reducePosePipeline =>
      snapshot.handFramesPerSecond >= poseExitHandFramesPerSecond,
    VisionDegradationStep.reduceHandPipelineFps =>
      snapshot.poseFramesPerSecond >= handExitPoseFramesPerSecond,
    VisionDegradationStep.reduceModelInputResolution =>
      snapshot.handFramesPerSecond >= resolutionExitHandFramesPerSecond,
    VisionDegradationStep.trackSingleHand =>
      snapshot.handFramesPerSecond >= singleHandExitFramesPerSecond,
    VisionDegradationStep.qualityMonitorOnly =>
      snapshot.handFramesPerSecond >= qualityOnlyExitHandFramesPerSecond,
    VisionDegradationStep.visionDisabled =>
      snapshot.audioProcessingLatencyIncreaseMs <
          visionDisabledExitAudioLatencyIncreaseMs,
  };
}
