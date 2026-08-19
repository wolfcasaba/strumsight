import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/repository/practice_evidence_repository.dart';

void main() {
  SkillEvidence evidence({
    String skillId = 'chord.gMajor',
    required String outcomeId,
    DateTime? measuredAt,
    DateTime? validUntil,
  }) => SkillEvidence(
    skillId: skillId,
    source: EvidenceSource.learn,
    sourceOutcomeId: OutcomeId(outcomeId),
    measurementVersion: 1,
    measuredAt: measuredAt ?? DateTime.utc(2026, 8, 10),
    capturedAt: DateTime.utc(2026, 8, 20),
    confidence: 0.8,
    validUntil: validUntil,
    performance: PerformanceEvidence(
      metricCode: 'chordChangeAccuracy',
      value: 0.7,
    ),
  );

  group('InMemoryPracticeEvidenceRepository — expiry (A8)', () {
    test('valid: querying before validUntil returns the evidence', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(outcomeId: 'outcome-1', validUntil: DateTime.utc(2026, 8, 20)),
      );

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 19),
      );

      expect(result, hasLength(1));
    });

    test(
      'boundary: querying exactly at validUntil still returns the evidence (inclusive)',
      () {
        final repository = InMemoryPracticeEvidenceRepository();
        repository.save(
          evidence(
            outcomeId: 'outcome-1',
            validUntil: DateTime.utc(2026, 8, 20),
          ),
        );

        final result = repository.query(
          skillId: 'chord.gMajor',
          asOf: DateTime.utc(2026, 8, 20),
        );

        expect(result, hasLength(1));
      },
    );

    test('expired: querying after validUntil excludes it from the result', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(outcomeId: 'outcome-1', validUntil: DateTime.utc(2026, 8, 20)),
      );

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 21),
      );

      expect(result, isEmpty);
    });

    test('expired evidence stays in the store — it is not deleted', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(outcomeId: 'outcome-1', validUntil: DateTime.utc(2026, 8, 20)),
      );

      repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 21),
      );

      expect(repository.allForSkill('chord.gMajor'), hasLength(1));
      expect(repository.findByOutcomeId(OutcomeId('outcome-1')), isNotNull);
    });

    test('evidence with no validUntil never expires', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(evidence(outcomeId: 'outcome-1'));

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2099, 1, 1),
      );

      expect(result, hasLength(1));
    });
  });

  group('InMemoryPracticeEvidenceRepository — bounded query (A9)', () {
    test('query respects the skill boundary', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(skillId: 'chord.gMajor', outcomeId: 'outcome-1'),
      );
      repository.save(
        evidence(skillId: 'chord.cMajor', outcomeId: 'outcome-2'),
      );

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 20),
      );

      expect(result, hasLength(1));
      expect(result.single.skillId, 'chord.gMajor');
    });

    test('query respects the measuredAt time window', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(outcomeId: 'outcome-1', measuredAt: DateTime.utc(2026, 8, 1)),
      );
      repository.save(
        evidence(outcomeId: 'outcome-2', measuredAt: DateTime.utc(2026, 8, 10)),
      );
      repository.save(
        evidence(outcomeId: 'outcome-3', measuredAt: DateTime.utc(2026, 8, 19)),
      );

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 20),
        measuredFrom: DateTime.utc(2026, 8, 5),
        measuredTo: DateTime.utc(2026, 8, 15),
      );

      expect(result, hasLength(1));
      expect(result.single.sourceOutcomeId, OutcomeId('outcome-2'));
    });

    test('the measured window bounds are inclusive', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(outcomeId: 'outcome-1', measuredAt: DateTime.utc(2026, 8, 5)),
      );
      repository.save(
        evidence(outcomeId: 'outcome-2', measuredAt: DateTime.utc(2026, 8, 15)),
      );

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 20),
        measuredFrom: DateTime.utc(2026, 8, 5),
        measuredTo: DateTime.utc(2026, 8, 15),
      );

      expect(result, hasLength(2));
    });

    test('an unrelated skill never leaks into a bounded query result', () {
      final repository = InMemoryPracticeEvidenceRepository();
      repository.save(
        evidence(skillId: 'strum.downUp', outcomeId: 'outcome-1'),
      );

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 20),
      );

      expect(result, isEmpty);
    });
  });

  group('InMemoryPracticeEvidenceRepository — plan-scoped delete (E07-R29 §5.7 '
      'narrow exception, F2 measured regression)', () {
    test('deleteForPlan on the DEFAULT impl never treats unknown-ownership '
        'records as the caller\'s (two plans).', () {
      final repository = InMemoryPracticeEvidenceRepository();
      // Two plans, two outcomes, owned via the save-time data relation.
      repository.save(
        evidence(outcomeId: 'plan.a.outcome.1'),
        sourcePlanId: PlanId('plan.a'),
      );
      repository.save(
        evidence(outcomeId: 'plan.b.outcome.1'),
        sourcePlanId: PlanId('plan.b'),
      );

      final removed = repository.deleteForPlan(PlanId('plan.a'));

      expect(removed, 1);
      expect(repository.findByOutcomeId(OutcomeId('plan.a.outcome.1')), isNull);
      expect(
        repository.findByOutcomeId(OutcomeId('plan.b.outcome.1')),
        isNotNull,
        reason: 'plan.b record must survive a plan-scoped delete on plan.a',
      );
    });

    test(
      'a record saved WITHOUT a sourcePlanId has unknown ownership and '
      'is preserved by deleteForPlan (F2 default-implementation contract).',
      () {
        final repository = InMemoryPracticeEvidenceRepository();
        // Evidence whose ownership is unknowable from the record alone
        // (the Aggregator production path).
        repository.save(evidence(outcomeId: 'outcome.orphan'));

        final removed = repository.deleteForPlan(PlanId('plan.a'));

        expect(
          removed,
          0,
          reason: 'unknown ownership is a refusal, NOT a wildcard claim',
        );
        expect(
          repository.findByOutcomeId(OutcomeId('outcome.orphan')),
          isNotNull,
        );
      },
    );

    test('the legacy outcomePlanLookup callback still narrows the delete '
        'to records whose id matches the lookup (backward-compat).', () {
      final repository = InMemoryPracticeEvidenceRepository(
        outcomePlanLookup: (outcomeId) {
          if (outcomeId.startsWith('plan.a.')) return PlanId('plan.a');
          if (outcomeId.startsWith('plan.b.')) return PlanId('plan.b');
          return null;
        },
      );
      repository.save(evidence(outcomeId: 'plan.a.outcome.1'));
      repository.save(evidence(outcomeId: 'plan.b.outcome.1'));

      final removed = repository.deleteForPlan(PlanId('plan.a'));

      expect(removed, 1);
      expect(repository.findByOutcomeId(OutcomeId('plan.a.outcome.1')), isNull);
      expect(
        repository.findByOutcomeId(OutcomeId('plan.b.outcome.1')),
        isNotNull,
      );
    });
  });
}
