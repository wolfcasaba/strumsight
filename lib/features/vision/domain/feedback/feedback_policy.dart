import '../evidence/vision_observation.dart';
import 'insight_code.dart';

/// Capability family required to interpret an insight code.
enum FeedbackCapability { any, fretting, picking, posture }

/// Versioned, code-specific gates for deterministic feedback selection.
final class FeedbackPolicy {
  FeedbackPolicy({
    required this.code,
    required this.requiredCapability,
    required this.direction,
    required this.positiveConfidenceThreshold,
    required this.negativeConfidenceThreshold,
    required this.minimumDuration,
    required this.cooldown,
    required this.priority,
  }) {
    if (!_isProbability(positiveConfidenceThreshold) ||
        !_isProbability(negativeConfidenceThreshold) ||
        negativeConfidenceThreshold <= positiveConfidenceThreshold ||
        minimumDuration <= Duration.zero ||
        cooldown < Duration.zero) {
      throw ArgumentError('Feedback policy gates are invalid.');
    }
  }

  final InsightCode code;
  final FeedbackCapability requiredCapability;
  final InsightDirection direction;
  final double positiveConfidenceThreshold;
  final double negativeConfidenceThreshold;
  final Duration minimumDuration;
  final Duration cooldown;
  final int priority;

  double get confidenceThreshold => direction == InsightDirection.negative
      ? negativeConfidenceThreshold
      : positiveConfidenceThreshold;

  bool supports(EvidenceMetric metric) => switch (requiredCapability) {
    FeedbackCapability.any => true,
    FeedbackCapability.fretting =>
      metric.family == EvidenceMetricFamily.fretting,
    FeedbackCapability.picking => metric.family == EvidenceMetricFamily.picking,
    FeedbackCapability.posture => metric.family == EvidenceMetricFamily.posture,
  };

  static bool _isProbability(double value) =>
      value.isFinite && value >= 0 && value <= 1;
}

/// The closed policy registry. Adding a code requires adding a safety and ARB
/// entry in the same change.
abstract final class FeedbackPolicies {
  static const String policyVersion = 'e05-r23-v1';

  static final Map<InsightCode, FeedbackPolicy> catalog =
      Map<InsightCode, FeedbackPolicy>.unmodifiable(
        <InsightCode, FeedbackPolicy>{
          InsightCode.setupNotObservable: _policy(
            InsightCode.setupNotObservable,
            FeedbackCapability.any,
            InsightDirection.setup,
            priority: 100,
            cooldown: Duration(seconds: 2),
          ),
          InsightCode.frettingStable: _policy(
            InsightCode.frettingStable,
            FeedbackCapability.fretting,
            InsightDirection.positive,
          ),
          InsightCode.frettingFocus: _policy(
            InsightCode.frettingFocus,
            FeedbackCapability.fretting,
            InsightDirection.negative,
          ),
          InsightCode.frettingImproved: _policy(
            InsightCode.frettingImproved,
            FeedbackCapability.fretting,
            InsightDirection.positive,
          ),
          InsightCode.pickingStable: _policy(
            InsightCode.pickingStable,
            FeedbackCapability.picking,
            InsightDirection.positive,
          ),
          InsightCode.pickingFocus: _policy(
            InsightCode.pickingFocus,
            FeedbackCapability.picking,
            InsightDirection.negative,
          ),
          InsightCode.pickingImproved: _policy(
            InsightCode.pickingImproved,
            FeedbackCapability.picking,
            InsightDirection.positive,
          ),
          InsightCode.postureStable: _policy(
            InsightCode.postureStable,
            FeedbackCapability.posture,
            InsightDirection.positive,
          ),
          InsightCode.postureFocus: _policy(
            InsightCode.postureFocus,
            FeedbackCapability.posture,
            InsightDirection.negative,
          ),
          InsightCode.postureImproved: _policy(
            InsightCode.postureImproved,
            FeedbackCapability.posture,
            InsightDirection.positive,
          ),
          InsightCode.experimentalObservation: _policy(
            InsightCode.experimentalObservation,
            FeedbackCapability.any,
            InsightDirection.positive,
            priority: 10,
          ),
        },
      );

  static FeedbackPolicy _policy(
    InsightCode code,
    FeedbackCapability requiredCapability,
    InsightDirection direction, {
    int priority = 50,
    Duration cooldown = const Duration(seconds: 5),
  }) => FeedbackPolicy(
    code: code,
    requiredCapability: requiredCapability,
    direction: direction,
    positiveConfidenceThreshold: 0.70,
    negativeConfidenceThreshold: 0.85,
    minimumDuration: const Duration(milliseconds: 250),
    cooldown: cooldown,
    priority: priority,
  );
}
