/// Explainable inputs and outputs for deterministic skill ranking.
library;

import 'practice_goal.dart';
import 'skill_estimate.dart';
import 'skill_evidence.dart';

/// Every independent contributor to a [SkillPriority] score.
enum SkillPriorityFactorKind {
  skillGap,
  assessment,
  goalAlignment,
  prerequisite,
  uncertainty,
  coverageDebt,
  fatigue,
  novelty,
  discomfortSafety,
}

/// A normalized factor and its signed contribution to one priority score.
final class SkillPriorityFactor {
  SkillPriorityFactor({
    required this.kind,
    required double normalizedValue,
    required double contribution,
  }) : normalizedValue = _requireUnitInterval(
         normalizedValue,
         'normalizedValue',
       ),
       contribution = _requireFinite(contribution, 'contribution');

  final SkillPriorityFactorKind kind;
  final double normalizedValue;
  final double contribution;
}

/// A ranked, explainable skill with immutable policy provenance.
final class SkillPriority {
  SkillPriority({
    required String skillId,
    required double score,
    required String policyVersion,
    required Iterable<SkillPriorityFactor> factors,
    required this.isSafetyOverridden,
  }) : skillId = _requireText(skillId, 'skillId'),
       score = _requireFinite(score, 'score'),
       policyVersion = _requireText(policyVersion, 'policyVersion'),
       factors = List<SkillPriorityFactor>.unmodifiable(factors) {
    final kinds = <SkillPriorityFactorKind>{};
    for (final factor in this.factors) {
      if (!kinds.add(factor.kind)) {
        throw ArgumentError.value(
          factors,
          'factors',
          'must contain each factor kind at most once',
        );
      }
    }
    final explainedScore = this.factors.fold<double>(
      0,
      (total, factor) => total + factor.contribution,
    );
    if ((explainedScore - this.score).abs() > 0.0000001) {
      throw ArgumentError.value(
        factors,
        'factors',
        'contributions must add up to score',
      );
    }
  }

  final String skillId;
  final double score;
  final String policyVersion;
  final List<SkillPriorityFactor> factors;

  /// True when discomfort evidence makes this candidate unsafe to schedule.
  final bool isSafetyOverridden;

  /// Looks up the live factor rather than reconstructing an explanation later.
  SkillPriorityFactor? factorFor(SkillPriorityFactorKind kind) {
    for (final factor in factors) {
      if (factor.kind == kind) return factor;
    }
    return null;
  }
}

/// All explicit, precomputed inputs needed to rank one skill.
///
/// Hard learner constraints are deliberately not accepted here: they belong to
/// the candidate filter, never the ranking score (ADR 0258).
final class SkillPriorityCandidate {
  SkillPriorityCandidate({
    required this.estimate,
    Iterable<PracticeGoal> goals = const <PracticeGoal>[],
    Iterable<SkillEvidence> evidence = const <SkillEvidence>[],
    double prerequisiteDemand = 0,
    DateTime? lastPracticedAt,
    double fatigue = 0,
    double novelty = 0,
  }) : goals = List<PracticeGoal>.unmodifiable(goals),
       evidence = List<SkillEvidence>.unmodifiable(evidence),
       prerequisiteDemand = _requireUnitInterval(
         prerequisiteDemand,
         'prerequisiteDemand',
       ),
       lastPracticedAt = lastPracticedAt?.toUtc(),
       fatigue = _requireUnitInterval(fatigue, 'fatigue'),
       novelty = _requireUnitInterval(novelty, 'novelty') {
    if (this.evidence.any((item) => item.skillId != estimate.skillId)) {
      throw ArgumentError.value(
        evidence,
        'evidence',
        'every record must belong to ${estimate.skillId}',
      );
    }
  }

  final SkillEstimate estimate;
  final List<PracticeGoal> goals;
  final List<SkillEvidence> evidence;

  /// How strongly another selected skill depends on this one first.
  final double prerequisiteDemand;

  /// Explicit input for coverage debt; null means no practice history exists.
  final DateTime? lastPracticedAt;
  final double fatigue;
  final double novelty;
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

double _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
  return value;
}

double _requireFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
  return value;
}
