import '../domain/evidence/vision_evidence.dart';
import '../domain/feedback/cue_budget.dart';
import '../domain/feedback/feedback_policy.dart';
import '../domain/feedback/insight_code.dart';
import '../domain/safety/safety_claim_guard.dart';

/// Stable output of one feedback-policy evaluation.
final class FeedbackDecision {
  const FeedbackDecision({
    required this.insights,
    required this.realtimeCue,
    required this.sessionSummary,
  });

  final List<VisionInsight> insights;
  final VisionInsight? realtimeCue;
  final List<VisionInsight> sessionSummary;
}

/// Converts explicitly classified [FeedbackCandidate]s into guarded insights.
final class FeedbackPolicyEngine {
  FeedbackPolicyEngine({
    required this.cueBudget,
    SafetyClaimGuard? safetyClaimGuard,
  }) : _safetyClaimGuard = safetyClaimGuard ?? const SafetyClaimGuard();

  final CueBudget cueBudget;
  final SafetyClaimGuard _safetyClaimGuard;

  FeedbackDecision evaluate(Iterable<FeedbackCandidate> candidates) {
    final insights = <VisionInsight>[
      for (final candidate in candidates)
        if (_accepts(candidate)) _toInsight(candidate),
    ]..sort(_compareInsights);
    final stableInsights = List<VisionInsight>.unmodifiable(insights);
    return FeedbackDecision(
      insights: stableInsights,
      realtimeCue: cueBudget.selectRealtime(stableInsights),
      sessionSummary: cueBudget.sessionSummary(stableInsights),
    );
  }

  bool _accepts(FeedbackCandidate candidate) {
    final policy = FeedbackPolicies.catalog[candidate.code];
    if (policy == null ||
        !_safetyClaimGuard.evaluate(candidate.code.safetyCode).isAllowed ||
        !policy.supports(candidate.evidence.metric) ||
        candidate.evidence.provenance.window.duration <
            policy.minimumDuration) {
      return false;
    }
    final acceptsPrimary = switch (candidate.code) {
      InsightCode.setupNotObservable =>
        candidate.evidence.observationState == ObservationState.notObservable,
      InsightCode.experimentalObservation =>
        candidate.evidence.observationState == ObservationState.experimental,
      _ => _isObservedOrInferred(candidate.evidence),
    };
    if (!acceptsPrimary ||
        candidate.evidence.confidence < policy.confidenceThreshold ||
        !_acceptsComparison(candidate, policy) ||
        _emittedConfidence(candidate) < policy.confidenceThreshold) {
      return false;
    }
    return !candidate.code.isImprovement || candidate.hasComparableImprovement;
  }

  bool _acceptsComparison(FeedbackCandidate candidate, FeedbackPolicy policy) {
    final comparison = candidate.comparisonEvidence;
    if (comparison == null) return true;
    return _isObservedOrInferred(comparison) &&
        comparison.confidence >= policy.confidenceThreshold &&
        comparison.id != candidate.evidence.id &&
        comparison.provenance.window.endUs <
            candidate.evidence.provenance.window.startUs;
  }

  static bool _isObservedOrInferred(VisionEvidence evidence) =>
      evidence.observationState == ObservationState.observed ||
      evidence.observationState == ObservationState.inferred;

  static double _emittedConfidence(FeedbackCandidate candidate) {
    final comparison = candidate.comparisonEvidence;
    if (comparison == null) return candidate.evidence.confidence;
    return candidate.evidence.confidence < comparison.confidence
        ? candidate.evidence.confidence
        : comparison.confidence;
  }

  VisionInsight _toInsight(FeedbackCandidate candidate) {
    final evidence = <VisionEvidence>[
      candidate.evidence,
      if (candidate.comparisonEvidence != null) candidate.comparisonEvidence!,
    ]..sort((first, second) => first.id.compareTo(second.id));
    return VisionInsight(
      code: candidate.code,
      policyVersion: FeedbackPolicies.policyVersion,
      evidenceIds: evidence.map((item) => item.id).toList(growable: false),
      confidence: _emittedConfidence(candidate),
    );
  }

  static int _compareInsights(VisionInsight first, VisionInsight second) {
    // Match CueBudget's direction-safe deterministic ordering.
    final priority = second.priority.compareTo(first.priority);
    if (priority != 0) return priority;
    final confidence = second.confidence.compareTo(first.confidence);
    if (confidence != 0) return confidence;
    final direction = _directionTieRank(
      first.direction,
    ).compareTo(_directionTieRank(second.direction));
    if (direction != 0) return direction;
    final code = first.code.safetyCode.compareTo(second.code.safetyCode);
    if (code != 0) return code;
    return first.evidenceIds.join(',').compareTo(second.evidenceIds.join(','));
  }

  static int _directionTieRank(InsightDirection direction) =>
      switch (direction) {
        InsightDirection.setup => 0,
        InsightDirection.positive => 1,
        InsightDirection.negative => 2,
      };
}
