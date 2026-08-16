import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_goal.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_estimate.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_priority.dart';
import 'package:strumsight/features/practice_generator/domain/service/priority_engine.dart';

void main() {
  final asOf = DateTime.utc(2026, 8, 16);

  SkillEstimate estimate({
    required String skillId,
    double? level,
    double uncertainty = 0.1,
  }) {
    if (level == null) return SkillEstimate.unknown(skillId: skillId);
    return SkillEstimate(
      skillId: skillId,
      level: level,
      uncertainty: uncertainty,
      state: SkillEstimateState.stable,
      trend: SkillTrend.flat,
      trendDelta: 0,
      lastObservedAt: asOf,
      evidenceIds: const <String>[],
      evidenceSummary: const EvidenceSummary(
        validPerformanceCount: 2,
        stalePerformanceCount: 0,
        discomfortOnlyCount: 0,
      ),
    );
  }

  PracticeGoal primaryGoal(String skillId) => PracticeGoal(
    id: GoalId('goal-$skillId'),
    type: PracticeGoalType.technique,
    priority: GoalPriority.primary,
    status: PracticeGoalStatus.active,
    createdAt: asOf,
    skillIds: <String>[skillId],
  );

  SkillEvidence painEvidence(String skillId) => SkillEvidence(
    skillId: skillId,
    source: EvidenceSource.selfReport,
    sourceOutcomeId: OutcomeId('pain-$skillId'),
    measurementVersion: 1,
    measuredAt: asOf,
    capturedAt: asOf,
    confidence: 1,
    discomfort: DiscomfortReport(category: DiscomfortCategory.pain),
  );

  SkillPriorityCandidate candidate({
    required String skillId,
    double? level,
    double uncertainty = 0.1,
    Iterable<PracticeGoal> goals = const <PracticeGoal>[],
    Iterable<SkillEvidence> evidence = const <SkillEvidence>[],
    double prerequisiteDemand = 0,
    DateTime? lastPracticedAt,
    double fatigue = 0,
    double novelty = 0,
  }) => SkillPriorityCandidate(
    estimate: estimate(
      skillId: skillId,
      level: level,
      uncertainty: uncertainty,
    ),
    goals: goals,
    evidence: evidence,
    prerequisiteDemand: prerequisiteDemand,
    lastPracticedAt: lastPracticedAt ?? asOf,
    fatigue: fatigue,
    novelty: novelty,
  );

  SkillPriority rankOne(SkillPriorityCandidate item) => const SkillPriorityEngine()
      .rank(candidates: <SkillPriorityCandidate>[item], asOf: asOf)
      .single;

  group('SkillPriorityEngine — explainable ranking', () {
    test('factor contributions add up exactly to the priority score (A1)', () {
      final priority = rankOne(
        candidate(
          skillId: 'skill.explained',
          level: 0.4,
          uncertainty: 0.3,
          goals: <PracticeGoal>[primaryGoal('skill.explained')],
          prerequisiteDemand: 0.8,
          lastPracticedAt: asOf.subtract(const Duration(days: 15)),
          fatigue: 0.2,
          novelty: 0.1,
        ),
      );

      expect(priority.factors, isNotEmpty);
      expect(
        priority.factors.fold<double>(
          0,
          (total, factor) => total + factor.contribution,
        ),
        closeTo(priority.score, 0.0000001),
      );
    });

    test('unknown skill is an assessment priority between strong and weak (A2)', () {
      final priorities = const SkillPriorityEngine().rank(
        candidates: <SkillPriorityCandidate>[
          candidate(skillId: 'skill.strong', level: 0.9),
          candidate(skillId: 'skill.unknown'),
          candidate(skillId: 'skill.weak', level: 0.1),
        ],
        asOf: asOf,
      );

      final byId = <String, SkillPriority>{
        for (final priority in priorities) priority.skillId: priority,
      };
      expect(byId['skill.weak']!.score, greaterThan(byId['skill.unknown']!.score));
      expect(
        byId['skill.unknown']!.score,
        greaterThan(byId['skill.strong']!.score),
      );
      expect(
        byId['skill.unknown']!.factorFor(
          SkillPriorityFactorKind.assessment,
        )!.normalizedValue,
        greaterThan(0),
      );
      expect(
        byId['skill.unknown']!.factorFor(
          SkillPriorityFactorKind.skillGap,
        )!.normalizedValue,
        0,
      );
    });

    test('primary goal boosts a skill but discomfort safety overrides it (A3)', () {
      final safe = rankOne(
        candidate(
          skillId: 'skill.safe',
          level: 0.5,
          goals: <PracticeGoal>[primaryGoal('skill.safe')],
        ),
      );
      final painful = rankOne(
        candidate(
          skillId: 'skill.painful',
          level: 0.5,
          goals: <PracticeGoal>[primaryGoal('skill.painful')],
          evidence: <SkillEvidence>[painEvidence('skill.painful')],
        ),
      );

      expect(
        safe.factorFor(SkillPriorityFactorKind.goalAlignment)!.contribution,
        greaterThan(0),
      );
      expect(painful.isSafetyOverridden, isTrue);
      expect(
        painful.factorFor(SkillPriorityFactorKind.discomfortSafety)!.contribution,
        lessThan(0),
      );
    });

    test('prerequisite demand moves a skill ahead of an otherwise equal skill (A4)', () {
      final priorities = const SkillPriorityEngine().rank(
        candidates: <SkillPriorityCandidate>[
          candidate(skillId: 'skill.unlocked', level: 0.5),
          candidate(
            skillId: 'skill.prerequisite',
            level: 0.5,
            prerequisiteDemand: 1,
          ),
        ],
        asOf: asOf,
      );

      expect(priorities.first.skillId, 'skill.prerequisite');
    });

    test('higher estimate uncertainty applies a ranking penalty (A5)', () {
      final certain = rankOne(
        candidate(skillId: 'skill.certain', level: 0.5, uncertainty: 0.1),
      );
      final uncertain = rankOne(
        candidate(skillId: 'skill.uncertain', level: 0.5, uncertainty: 0.9),
      );

      expect(uncertain.score, lessThan(certain.score));
      expect(
        uncertain.factorFor(SkillPriorityFactorKind.uncertainty)!.contribution,
        lessThan(certain.factorFor(SkillPriorityFactorKind.uncertainty)!.contribution),
      );
    });

    test('coverage debt grows as a skill remains unpracticed (A6)', () {
      final recent = rankOne(
        candidate(skillId: 'skill.recent', level: 0.5, lastPracticedAt: asOf),
      );
      final overdue = rankOne(
        candidate(
          skillId: 'skill.overdue',
          level: 0.5,
          lastPracticedAt: asOf.subtract(const Duration(days: 30)),
        ),
      );

      expect(overdue.score, greaterThan(recent.score));
      expect(
        overdue.factorFor(SkillPriorityFactorKind.coverageDebt)!.normalizedValue,
        greaterThan(
          recent.factorFor(SkillPriorityFactorKind.coverageDebt)!.normalizedValue,
        ),
      );
    });

    test('hard constraints never appear as a ranking factor (A9)', () {
      final priority = rankOne(candidate(skillId: 'skill.filtered', level: 0.5));

      expect(
        priority.factors.map((factor) => factor.kind.name),
        isNot(contains('hardConstraint')),
      );
    });
  });
}
