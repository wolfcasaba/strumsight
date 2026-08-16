/// Deterministic, explainable skill ranking.
library;

import '../model/practice_goal.dart';
import '../model/skill_evidence.dart';
import '../model/skill_priority.dart';
import '../policy/priority_policy.dart';

/// Produces a stable priority order without reading a clock or random source.
final class SkillPriorityEngine {
  const SkillPriorityEngine({this.policy = PriorityPolicy.defaultPolicy});

  final PriorityPolicy policy;

  /// Ranks [candidates] at caller-supplied [asOf].
  ///
  /// Duplicate skill IDs are rejected because they would make one ranked result
  /// ambiguous. Ties resolve solely by the stable skill identifier.
  List<SkillPriority> rank({
    required Iterable<SkillPriorityCandidate> candidates,
    required DateTime asOf,
  }) {
    final uniqueSkillIds = <String>{};
    final priorities = <SkillPriority>[];
    for (final candidate in candidates) {
      if (!uniqueSkillIds.add(candidate.estimate.skillId)) {
        throw ArgumentError.value(
          candidates,
          'candidates',
          'contains duplicate skill ${candidate.estimate.skillId}',
        );
      }
      priorities.add(_rank(candidate, asOf.toUtc()));
    }
    priorities.sort(_comparePriorities);
    return List<SkillPriority>.unmodifiable(priorities);
  }

  SkillPriority _rank(SkillPriorityCandidate candidate, DateTime asOf) {
    final isUnknown = candidate.estimate.isUnknown;
    final skillGap = isUnknown ? 0.0 : 1 - candidate.estimate.level!;
    final assessment = isUnknown ? policy.assessmentValue : 0.0;
    final goalAlignment =
        candidate.goals.any(
          (goal) =>
              goal.priority == GoalPriority.primary &&
              goal.skillIds.contains(candidate.estimate.skillId),
        )
        ? 1.0
        : 0.0;
    final coverageDebt = policy.coverageDebt(
      asOf: asOf,
      lastPracticedAt: candidate.lastPracticedAt,
    );
    final factors = <SkillPriorityFactor>[
      _factor(
        SkillPriorityFactorKind.skillGap,
        skillGap,
        policy.skillGapWeight * skillGap,
      ),
      _factor(
        SkillPriorityFactorKind.assessment,
        assessment,
        policy.assessmentWeight * assessment,
      ),
      _factor(
        SkillPriorityFactorKind.goalAlignment,
        goalAlignment,
        policy.primaryGoalWeight * goalAlignment,
      ),
      _factor(
        SkillPriorityFactorKind.prerequisite,
        candidate.prerequisiteDemand,
        policy.prerequisiteWeight * candidate.prerequisiteDemand,
      ),
      _factor(
        SkillPriorityFactorKind.uncertainty,
        candidate.estimate.uncertainty,
        -policy.uncertaintyPenalty * candidate.estimate.uncertainty,
      ),
      _factor(
        SkillPriorityFactorKind.coverageDebt,
        coverageDebt,
        policy.coverageDebtWeight * coverageDebt,
      ),
      _factor(
        SkillPriorityFactorKind.fatigue,
        candidate.fatigue,
        -policy.fatiguePenalty * candidate.fatigue,
      ),
      _factor(
        SkillPriorityFactorKind.novelty,
        candidate.novelty,
        -policy.noveltyPenalty * candidate.novelty,
      ),
    ];
    final safetyOverridden = candidate.evidence.any(
      (item) =>
          item.discomfort != null &&
          item.discomfort!.category != DiscomfortCategory.none,
    );
    final scoreBeforeSafety = _scoreOf(factors);
    if (safetyOverridden) {
      factors.add(
        _factor(
          SkillPriorityFactorKind.discomfortSafety,
          1,
          -scoreBeforeSafety,
        ),
      );
    }

    return SkillPriority(
      skillId: candidate.estimate.skillId,
      score: _scoreOf(factors),
      policyVersion: policy.version,
      factors: factors,
      isSafetyOverridden: safetyOverridden,
    );
  }

  SkillPriorityFactor _factor(
    SkillPriorityFactorKind kind,
    double normalizedValue,
    double contribution,
  ) => SkillPriorityFactor(
    kind: kind,
    normalizedValue: normalizedValue,
    contribution: contribution,
  );
}

double _scoreOf(Iterable<SkillPriorityFactor> factors) =>
    factors.fold<double>(0, (total, factor) => total + factor.contribution);

int _comparePriorities(SkillPriority first, SkillPriority second) {
  if (first.isSafetyOverridden != second.isSafetyOverridden) {
    return first.isSafetyOverridden ? 1 : -1;
  }
  final score = second.score.compareTo(first.score);
  if (score != 0) return score;
  return first.skillId.compareTo(second.skillId);
}
