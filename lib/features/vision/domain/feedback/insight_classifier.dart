/// The evidence-to-candidate seam (E09-R28a).
///
/// `FeedbackPolicyEngine` deliberately accepts already-classified
/// [FeedbackCandidate]s, so something upstream has to decide which
/// [InsightCode] a window of evidence is even a candidate for. That decision
/// is the landmark-dependent half of the pipeline, and R28a ships no landmark
/// model — so it ships only the fail-closed default below. A later round
/// replaces the implementation; this interface is what it plugs into.
library;

import '../evidence/vision_evidence.dart';
import 'insight_code.dart';

/// One classification request.
///
/// [practiceId] and [capabilityLevel] are the comparison keys
/// [FeedbackCandidate] uses to reject an "improved" claim that compares two
/// different practice contexts.
final class VisionInsightInput {
  VisionInsightInput({
    required List<VisionEvidence> evidence,
    required this.practiceId,
    required this.capabilityLevel,
  }) : evidence = List<VisionEvidence>.unmodifiable(evidence);

  final List<VisionEvidence> evidence;
  final String practiceId;
  final String capabilityLevel;
}

/// Proposes feedback candidates from fused evidence.
///
/// A classifier only proposes: every candidate still passes the policy
/// engine's confidence, duration, capability, and safety gates.
abstract interface class VisionInsightClassifier {
  List<FeedbackCandidate> classify(VisionInsightInput input);
}

/// Emits only what is measurable without landmarks.
///
/// Fail-closed by construction: `observed` and `inferred` evidence produce
/// nothing at all, because without a landmark model no technique judgement
/// can be earned. `notObservable` evidence produces the one honest code —
/// [InsightCode.setupNotObservable], the "reframe / recalibrate" cue — which
/// is ADR 0179's prescribed answer, not a negative verdict on the player.
final class SetupOnlyInsightClassifier implements VisionInsightClassifier {
  const SetupOnlyInsightClassifier();

  @override
  List<FeedbackCandidate> classify(VisionInsightInput input) =>
      <FeedbackCandidate>[
        for (final evidence in input.evidence)
          if (evidence.observationState == ObservationState.notObservable)
            FeedbackCandidate(
              code: InsightCode.setupNotObservable,
              evidence: evidence,
              practiceId: input.practiceId,
              capabilityLevel: input.capabilityLevel,
            ),
      ];
}
