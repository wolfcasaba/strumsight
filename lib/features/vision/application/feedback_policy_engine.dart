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
    if (candidate.code == InsightCode.setupNotObservable) {
      return candidate.evidence.observationState ==
          ObservationState.notObservable;
    }
    if (candidate.code == InsightCode.experimentalObservation) {
      return candidate.evidence.observationState ==
              ObservationState.experimental &&
          candidate.evidence.confidence >= policy.confidenceThreshold;
    }
    if (candidate.evidence.observationState == ObservationState.notObservable ||
        candidate.evidence.observationState == ObservationState.experimental ||
        candidate.evidence.confidence < policy.confidenceThreshold) {
      return false;
    }
    return !candidate.code.isImprovement || candidate.hasComparableImprovement;
  }

  VisionInsight _toInsight(FeedbackCandidate candidate) {
    final policy = FeedbackPolicies.catalog[candidate.code]!;
    final evidence = <VisionEvidence>[
      candidate.evidence,
      if (candidate.comparisonEvidence != null) candidate.comparisonEvidence!,
    ]..sort((first, second) => first.id.compareTo(second.id));
    final confidence = evidence
        .map((item) => item.confidence)
        .reduce((first, second) => first < second ? first : second);
    return VisionInsight(
      code: candidate.code,
      policyVersion: FeedbackPolicies.policyVersion,
      evidenceIds: evidence.map((item) => item.id).toList(growable: false),
      confidence: confidence,
      priority: policy.priority,
      direction: policy.direction,
    );
  }

  static int _compareInsights(VisionInsight first, VisionInsight second) {
    final priority = second.priority.compareTo(first.priority);
    if (priority != 0) return priority;
    final code = first.code.safetyCode.compareTo(second.code.safetyCode);
    if (code != 0) return code;
    return first.evidenceIds.join(',').compareTo(second.evidenceIds.join(','));
  }
}
