import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/policy/evidence_weight_policy.dart';

void main() {
  SkillEvidence evidence({
    required double value,
    required int sampleCount,
    required DateTime measuredAt,
    DateTime? validUntil,
    double confidence = 1.0,
  }) => SkillEvidence(
    skillId: 'chord.gMajor',
    source: EvidenceSource.analyzeV2,
    sourceOutcomeId: OutcomeId('outcome-$value-$sampleCount'),
    measurementVersion: 1,
    measuredAt: measuredAt,
    capturedAt: DateTime.utc(2026, 8, 20),
    confidence: confidence,
    validUntil: validUntil,
    performance: PerformanceEvidence(
      metricCode: 'chordChangeAccuracy',
      value: value,
      sampleCount: sampleCount,
    ),
  );

  group('EvidenceWeightPolicy — bounded influence (A2)', () {
    test('caps even a maximally reliable, confident, recent measurement', () {
      final policy = EvidenceWeightPolicy(singleEvidenceInfluenceCap: 0.2);
      final weight = policy.weightFor(
        evidence(
          value: 1.0,
          sampleCount: 100,
          measuredAt: DateTime.utc(2026, 8, 20),
        ),
        asOf: DateTime.utc(2026, 8, 20),
      );

      expect(weight, lessThanOrEqualTo(policy.singleEvidenceInfluenceCap));
      expect(weight, policy.singleEvidenceInfluenceCap);
    });

    test(
      'uses supplied time for recency and reduces stale evidence weight',
      () {
        final policy = EvidenceWeightPolicy(
          recencyHalfLife: Duration(days: 10),
          staleWeightMultiplier: 0.1,
        );
        final current = evidence(
          value: 0.8,
          sampleCount: 8,
          measuredAt: DateTime.utc(2026, 8, 20),
        );
        final expired = evidence(
          value: 0.8,
          sampleCount: 8,
          measuredAt: DateTime.utc(2026, 8, 10),
          validUntil: DateTime.utc(2026, 8, 15),
        );

        expect(
          policy.weightFor(expired, asOf: DateTime.utc(2026, 8, 20)),
          lessThan(policy.weightFor(current, asOf: DateTime.utc(2026, 8, 20))),
        );
      },
    );
  });
}
