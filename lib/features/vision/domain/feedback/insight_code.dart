import '../evidence/vision_evidence.dart';
import 'feedback_policy.dart';

/// Closed, localizable feedback codes emitted by the deterministic policy.
enum InsightCode {
  setupNotObservable,
  frettingStable,
  frettingFocus,
  frettingImproved,
  pickingStable,
  pickingFocus,
  pickingImproved,
  postureStable,
  postureFocus,
  postureImproved,
  experimentalObservation;

  String get safetyCode => switch (this) {
    InsightCode.setupNotObservable => 'visionInsightSetupNotObservable',
    InsightCode.frettingStable => 'visionInsightFrettingStable',
    InsightCode.frettingFocus => 'visionInsightFrettingFocus',
    InsightCode.frettingImproved => 'visionInsightFrettingImproved',
    InsightCode.pickingStable => 'visionInsightPickingStable',
    InsightCode.pickingFocus => 'visionInsightPickingFocus',
    InsightCode.pickingImproved => 'visionInsightPickingImproved',
    InsightCode.postureStable => 'visionInsightPostureStable',
    InsightCode.postureFocus => 'visionInsightPostureFocus',
    InsightCode.postureImproved => 'visionInsightPostureImproved',
    InsightCode.experimentalObservation =>
      'visionInsightExperimentalObservation',
  };

  bool get isImprovement => switch (this) {
    InsightCode.frettingImproved ||
    InsightCode.pickingImproved ||
    InsightCode.postureImproved => true,
    _ => false,
  };
}

/// The direction determines the confidence gate, not the rendered wording.
enum InsightDirection { setup, positive, negative }

/// Immutable, rendering-free outcome of the feedback policy.
///
/// Priority and direction come from the closed policy catalog so public
/// callers cannot forge cue ordering or safety direction.
final class VisionInsight {
  VisionInsight({
    required this.code,
    required this.policyVersion,
    required List<String> evidenceIds,
    required this.confidence,
  }) : evidenceIds = List<String>.unmodifiable(evidenceIds),
       priority = _policyFor(code).priority,
       direction = _policyFor(code).direction {
    if (policyVersion.trim().isEmpty ||
        evidenceIds.isEmpty ||
        !(confidence.isFinite && confidence >= 0 && confidence <= 1)) {
      throw ArgumentError(
        'A version, evidence, and finite confidence are required.',
      );
    }
  }

  final InsightCode code;
  final String policyVersion;
  final List<String> evidenceIds;
  final double confidence;
  final int priority;
  final InsightDirection direction;

  static FeedbackPolicy _policyFor(InsightCode code) {
    final policy = FeedbackPolicies.catalog[code];
    if (policy == null) {
      throw ArgumentError.value(code, 'code', 'Missing feedback policy.');
    }
    return policy;
  }

  @override
  bool operator ==(Object other) =>
      other is VisionInsight &&
      other.code == code &&
      other.policyVersion == policyVersion &&
      _sameList(other.evidenceIds, evidenceIds) &&
      other.confidence == confidence &&
      other.priority == priority &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(
    code,
    policyVersion,
    Object.hashAll(evidenceIds),
    confidence,
    priority,
    direction,
  );

  static bool _sameList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

/// A caller's typed proposal. The policy validates it before emission.
///
/// Raw metric values have family-specific semantics, so this boundary never
/// derives a technical judgement from a number alone.
final class FeedbackCandidate {
  FeedbackCandidate({
    required this.code,
    required this.evidence,
    required this.practiceId,
    required this.capabilityLevel,
    this.comparisonEvidence,
    this.comparisonPracticeId,
    this.comparisonCapabilityLevel,
  }) {
    if (practiceId.trim().isEmpty || capabilityLevel.trim().isEmpty) {
      throw ArgumentError('Practice and capability level are required.');
    }
  }

  final InsightCode code;
  final VisionEvidence evidence;
  final String practiceId;
  final String capabilityLevel;
  final VisionEvidence? comparisonEvidence;
  final String? comparisonPracticeId;
  final String? comparisonCapabilityLevel;

  bool get hasComparableImprovement =>
      comparisonEvidence != null &&
      comparisonPracticeId == practiceId &&
      comparisonCapabilityLevel == capabilityLevel &&
      comparisonEvidence!.metric.key == evidence.metric.key &&
      comparisonEvidence!.id != evidence.id &&
      comparisonEvidence!.provenance.window.endUs <
          evidence.provenance.window.startUs;
}
