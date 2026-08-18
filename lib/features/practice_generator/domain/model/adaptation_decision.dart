/// Typed, explainable output and input models for cross-session adaptation.
library;

import 'skill_estimate.dart';
import 'skill_evidence.dart';

/// The bounded outcome of one difficulty-adaptation decision.
enum AdaptationAction {
  advance('adaptation.action.advance'),
  regress('adaptation.action.regress'),
  maintain('adaptation.action.maintain');

  const AdaptationAction(this.code);

  final String code;
}

/// Stable, machine-readable rationale carried by an [AdaptationDecision].
enum AdaptationReason {
  sufficientEvidence('adaptation.reason.sufficientEvidence'),
  insufficientEvidence('adaptation.reason.insufficientEvidence'),
  insufficientConfidence('adaptation.reason.insufficientConfidence'),
  cooldownActive('adaptation.reason.cooldownActive'),
  repeatedStruggle('adaptation.reason.repeatedStruggle'),
  explicitTooHard('adaptation.reason.explicitTooHard'),
  discomfortBlocksAdvance('adaptation.reason.discomfortBlocksAdvance'),
  safetyBlocksAdvance('adaptation.reason.safetyBlocksAdvance');

  const AdaptationReason(this.code);

  final String code;
}

/// The current or next difficulty settings for one exercise prescription.
///
/// The levels represent typed adaptation controls rather than the legacy
/// per-attempt [ProgressionRule]. The adaptation decider changes each control
/// only by the policy's one permitted step.
final class DifficultyProfile {
  DifficultyProfile({
    required this.difficultyLevel,
    required this.tempoBpm,
    required this.supportsTempo,
    required this.loopCount,
    required this.variationLevel,
    required this.strictnessLevel,
  }) {
    if (difficultyLevel < 0) {
      throw ArgumentError.value(
        difficultyLevel,
        'difficultyLevel',
        'must not be negative',
      );
    }
    if (loopCount < 1) {
      throw ArgumentError.value(loopCount, 'loopCount', 'must be at least 1');
    }
    if (variationLevel < 0) {
      throw ArgumentError.value(
        variationLevel,
        'variationLevel',
        'must not be negative',
      );
    }
    if (strictnessLevel < 0) {
      throw ArgumentError.value(
        strictnessLevel,
        'strictnessLevel',
        'must not be negative',
      );
    }
    if (!supportsTempo && tempoBpm != null) {
      throw ArgumentError.value(
        tempoBpm,
        'tempoBpm',
        'must be absent when the exercise does not support tempo',
      );
    }
    if (supportsTempo && (tempoBpm == null || tempoBpm! <= 0)) {
      throw ArgumentError.value(
        tempoBpm,
        'tempoBpm',
        'must be positive for a tempo-capable exercise',
      );
    }
  }

  final int difficultyLevel;
  final int? tempoBpm;
  final bool supportsTempo;
  final int loopCount;
  final int variationLevel;
  final int strictnessLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DifficultyProfile &&
          other.difficultyLevel == difficultyLevel &&
          other.tempoBpm == tempoBpm &&
          other.supportsTempo == supportsTempo &&
          other.loopCount == loopCount &&
          other.variationLevel == variationLevel &&
          other.strictnessLevel == strictnessLevel;

  @override
  int get hashCode => Object.hash(
    difficultyLevel,
    tempoBpm,
    supportsTempo,
    loopCount,
    variationLevel,
    strictnessLevel,
  );
}

/// Deterministic input supplied by the application for one adaptation.
///
/// [asOf] and [lastAdvanceAt] are caller-supplied; the domain never reads a
/// wall clock. An explicit safety block is kept distinct from discomfort so
/// callers can conservatively prevent advancement when an external safety
/// constraint is active.
final class AdaptationRequest {
  AdaptationRequest({
    required String skillId,
    required this.current,
    required this.estimate,
    required Iterable<SkillEvidence> evidence,
    required DateTime asOf,
    DateTime? lastAdvanceAt,
    this.safetyBlocked = false,
  }) : skillId = _requireText(skillId, 'skillId'),
       evidence = List<SkillEvidence>.unmodifiable(evidence),
       asOf = asOf.toUtc(),
       lastAdvanceAt = lastAdvanceAt?.toUtc() {
    if (estimate.skillId != this.skillId) {
      throw ArgumentError.value(
        estimate.skillId,
        'estimate.skillId',
        'must match skillId (${this.skillId})',
      );
    }
    if (this.evidence.isEmpty) {
      throw ArgumentError.value(
        evidence,
        'evidence',
        'must not be empty; every decision needs evidence provenance',
      );
    }
    final outcomeIds = <String>{};
    for (final item in this.evidence) {
      if (item.skillId != this.skillId) {
        throw ArgumentError.value(
          item.skillId,
          'evidence.skillId',
          'must match skillId (${this.skillId})',
        );
      }
      if (!outcomeIds.add(item.sourceOutcomeId.value)) {
        throw ArgumentError.value(
          item.sourceOutcomeId,
          'evidence',
          'must not contain duplicate sourceOutcomeId values',
        );
      }
    }
    final lastAdvance = this.lastAdvanceAt;
    if (lastAdvance != null && lastAdvance.isAfter(this.asOf)) {
      throw ArgumentError.value(
        lastAdvanceAt,
        'lastAdvanceAt',
        'must not be after asOf',
      );
    }
  }

  final String skillId;
  final DifficultyProfile current;
  final SkillEstimate estimate;
  final List<SkillEvidence> evidence;
  final DateTime asOf;
  final DateTime? lastAdvanceAt;
  final bool safetyBlocked;
}

/// An immutable, evidence-referenced decision for the next session.
final class AdaptationDecision {
  AdaptationDecision({
    required this.action,
    required this.current,
    required this.next,
    required Iterable<AdaptationReason> reasons,
    required Iterable<String> evidenceIds,
    required String policyVersion,
  }) : reasons = _sortReasons(reasons),
       evidenceIds = _sortEvidenceIds(evidenceIds),
       policyVersion = _requireText(policyVersion, 'policyVersion') {
    if (this.reasons.isEmpty) {
      throw ArgumentError.value(reasons, 'reasons', 'must not be empty');
    }
  }

  final AdaptationAction action;
  final DifficultyProfile current;
  final DifficultyProfile next;
  final List<AdaptationReason> reasons;
  final List<String> evidenceIds;
  final String policyVersion;
}

List<AdaptationReason> _sortReasons(Iterable<AdaptationReason> reasons) {
  final result = reasons.toSet().toList()
    ..sort((a, b) => a.code.compareTo(b.code));
  return List<AdaptationReason>.unmodifiable(result);
}

List<String> _sortEvidenceIds(Iterable<String> evidenceIds) {
  final result = <String>{};
  for (final evidenceId in evidenceIds) {
    result.add(_requireText(evidenceId, 'evidenceIds entry'));
  }
  final sorted = result.toList()..sort();
  if (sorted.isEmpty) {
    throw ArgumentError.value(evidenceIds, 'evidenceIds', 'must not be empty');
  }
  return List<String>.unmodifiable(sorted);
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
