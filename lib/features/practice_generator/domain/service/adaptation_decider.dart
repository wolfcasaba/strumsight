/// Deterministic, evidence-based cross-session difficulty adaptation.
library;

import '../model/adaptation_decision.dart';
import '../model/skill_evidence.dart';
import '../policy/progression_policy.dart';

/// Applies the centralized [ProgressionPolicy] to one [AdaptationRequest].
///
/// This is deliberately distinct from [ProgressionRule], which expresses a
/// pre-authored, single-attempt exercise rule. Here the result comes from
/// cross-session evidence and always carries that evidence's provenance.
final class AdaptationDecider {
  AdaptationDecider({ProgressionPolicy? policy})
    : policy = policy ?? ProgressionPolicy.defaultPolicy;

  final ProgressionPolicy policy;

  AdaptationDecision decide(AdaptationRequest request) {
    final evidenceIds = request.evidence
        .map((item) => item.sourceOutcomeId.value)
        .toList();
    final validEvidence = request.evidence
        .where((item) => item.isValidAt(request.asOf))
        .toList();

    if (_hasExplicitTooHard(validEvidence)) {
      return _decision(
        action: AdaptationAction.regress,
        request: request,
        next: _regress(request.current),
        reasons: const <AdaptationReason>[AdaptationReason.explicitTooHard],
        evidenceIds: evidenceIds,
      );
    }

    if (_hasDiscomfort(validEvidence)) {
      return _decision(
        action: AdaptationAction.maintain,
        request: request,
        next: request.current,
        reasons: const <AdaptationReason>[
          AdaptationReason.discomfortBlocksAdvance,
        ],
        evidenceIds: evidenceIds,
      );
    }

    if (request.safetyBlocked) {
      return _decision(
        action: AdaptationAction.maintain,
        request: request,
        next: request.current,
        reasons: const <AdaptationReason>[AdaptationReason.safetyBlocksAdvance],
        evidenceIds: evidenceIds,
      );
    }

    if (_struggleCount(validEvidence) >= policy.repeatedStruggleEvidence) {
      return _decision(
        action: AdaptationAction.regress,
        request: request,
        next: _regress(request.current),
        reasons: const <AdaptationReason>[AdaptationReason.repeatedStruggle],
        evidenceIds: evidenceIds,
      );
    }

    if (request.estimate.uncertainty > policy.maximumEstimateUncertainty) {
      return _decision(
        action: AdaptationAction.maintain,
        request: request,
        next: request.current,
        reasons: const <AdaptationReason>[
          AdaptationReason.insufficientConfidence,
        ],
        evidenceIds: evidenceIds,
      );
    }

    if (_successCount(validEvidence) < policy.minimumSuccessfulEvidence) {
      return _decision(
        action: AdaptationAction.maintain,
        request: request,
        next: request.current,
        reasons: const <AdaptationReason>[
          AdaptationReason.insufficientEvidence,
        ],
        evidenceIds: evidenceIds,
      );
    }

    final lastAdvanceAt = request.lastAdvanceAt;
    if (lastAdvanceAt != null &&
        policy.isAdvanceInCooldown(lastAdvanceAt, request.asOf)) {
      return _decision(
        action: AdaptationAction.maintain,
        request: request,
        next: request.current,
        reasons: const <AdaptationReason>[AdaptationReason.cooldownActive],
        evidenceIds: evidenceIds,
      );
    }

    return _decision(
      action: AdaptationAction.advance,
      request: request,
      next: _advance(request.current),
      reasons: const <AdaptationReason>[AdaptationReason.sufficientEvidence],
      evidenceIds: evidenceIds,
    );
  }

  AdaptationDecision _decision({
    required AdaptationAction action,
    required AdaptationRequest request,
    required DifficultyProfile next,
    required Iterable<AdaptationReason> reasons,
    required Iterable<String> evidenceIds,
  }) => AdaptationDecision(
    action: action,
    current: request.current,
    next: next,
    reasons: reasons,
    evidenceIds: evidenceIds,
    policyVersion: policy.version,
  );

  bool _hasExplicitTooHard(Iterable<SkillEvidence> evidence) => evidence.any(
    (item) =>
        item.source == EvidenceSource.selfReport &&
        item.discomfort?.category == DiscomfortCategory.frustration,
  );

  bool _hasDiscomfort(Iterable<SkillEvidence> evidence) => evidence.any(
    (item) =>
        item.discomfort?.category != null &&
        item.discomfort!.category != DiscomfortCategory.none,
  );

  int _successCount(Iterable<SkillEvidence> evidence) => evidence
      .where(
        (item) =>
            item.performance != null &&
            item.confidence >= policy.minimumEvidenceConfidence &&
            item.performance!.value >= policy.successfulPerformanceThreshold,
      )
      .length;

  int _struggleCount(Iterable<SkillEvidence> evidence) => evidence
      .where(
        (item) =>
            item.performance != null &&
            item.confidence >= policy.minimumEvidenceConfidence &&
            item.performance!.value <= policy.strugglePerformanceThreshold,
      )
      .length;

  DifficultyProfile _advance(DifficultyProfile current) => DifficultyProfile(
    difficultyLevel: current.difficultyLevel + policy.maximumDifficultyStep,
    tempoBpm: _nextTempo(current, policy.tempoStepBpm),
    supportsTempo: current.supportsTempo,
    loopCount: current.loopCount + policy.maximumDifficultyStep,
    variationLevel: current.variationLevel + policy.maximumDifficultyStep,
    strictnessLevel: current.strictnessLevel + policy.maximumDifficultyStep,
  );

  DifficultyProfile _regress(DifficultyProfile current) => DifficultyProfile(
    difficultyLevel: _decreaseToMinimum(
      current.difficultyLevel,
      policy.minimumDifficultyLevel,
    ),
    tempoBpm: _nextTempo(current, -policy.tempoStepBpm),
    supportsTempo: current.supportsTempo,
    loopCount: _decreaseToMinimum(current.loopCount, policy.minimumLoopCount),
    variationLevel: _decreaseToMinimum(
      current.variationLevel,
      policy.minimumVariationLevel,
    ),
    strictnessLevel: _decreaseToMinimum(
      current.strictnessLevel,
      policy.minimumStrictnessLevel,
    ),
  );

  int? _nextTempo(DifficultyProfile current, int delta) {
    final tempo = current.tempoBpm;
    if (!current.supportsTempo || tempo == null) return null;
    return policy.clampTempoBpm(tempo + delta);
  }

  int _decreaseToMinimum(int value, int minimum) =>
      value > minimum + policy.maximumDifficultyStep
      ? value - policy.maximumDifficultyStep
      : minimum;
}
