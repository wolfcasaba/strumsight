import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_estimate.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_priority.dart';
import 'package:strumsight/features/practice_generator/domain/policy/priority_policy.dart';
import 'package:strumsight/features/practice_generator/domain/service/priority_engine.dart';

void main() {
  final asOf = DateTime.utc(2026, 8, 16);

  SkillPriorityCandidate candidate(String skillId) => SkillPriorityCandidate(
    estimate: SkillEstimate(
      skillId: skillId,
      level: 0.5,
      uncertainty: 0.1,
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
    ),
    lastPracticedAt: asOf,
  );

  group('PriorityPolicy — versioned deterministic configuration', () {
    test('ties resolve by stable skill identifier independent of input order (A7)', () {
      final engine = const SkillPriorityEngine();
      final forward = engine.rank(
        candidates: <SkillPriorityCandidate>[
          candidate('skill.charlie'),
          candidate('skill.alpha'),
          candidate('skill.bravo'),
        ],
        asOf: asOf,
      );
      final reverse = engine.rank(
        candidates: <SkillPriorityCandidate>[
          candidate('skill.bravo'),
          candidate('skill.charlie'),
          candidate('skill.alpha'),
        ],
        asOf: asOf,
      );

      expect(
        forward.map((priority) => priority.skillId),
        <String>['skill.alpha', 'skill.bravo', 'skill.charlie'],
      );
      expect(
        reverse.map((priority) => priority.skillId),
        forward.map((priority) => priority.skillId),
      );
    });

    test('the configured policy version is retained in every output (A8)', () {
      final priority = SkillPriorityEngine(
        policy: PriorityPolicy(version: 'priority-policy-test-v2'),
      ).rank(candidates: <SkillPriorityCandidate>[candidate('skill.version')], asOf: asOf).single;

      expect(priority.policyVersion, 'priority-policy-test-v2');
    });

    test('coverage debt remains normalized across its configured horizon', () {
      final policy = PriorityPolicy(coverageDebtHorizon: const Duration(days: 20));

      expect(policy.coverageDebt(asOf: asOf, lastPracticedAt: asOf), 0);
      expect(
        policy.coverageDebt(
          asOf: asOf,
          lastPracticedAt: asOf.subtract(const Duration(days: 10)),
        ),
        0.5,
      );
      expect(
        policy.coverageDebt(
          asOf: asOf,
          lastPracticedAt: asOf.subtract(const Duration(days: 30)),
        ),
        1,
      );
    });

    test('rejects invalid versions, weights, and coverage horizons', () {
      expect(() => PriorityPolicy(version: ' '), throwsArgumentError);
      expect(() => PriorityPolicy(skillGapWeight: 1.1), throwsArgumentError);
      expect(
        () => PriorityPolicy(coverageDebtHorizon: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
