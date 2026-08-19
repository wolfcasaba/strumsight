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
    EvidenceSource source = EvidenceSource.analyzeV2,
  }) => SkillEvidence(
    skillId: 'chord.gMajor',
    source: source,
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

  group(
    'EvidenceWeightPolicy — vision sourceReliability (E07-R25 §0.0.1, A3)',
    () {
      test(
        'vision reliability is below analyzeV2, above progress (cap-respecting)',
        () {
          final policy = EvidenceWeightPolicy();
          final visionReliability = policy.sourceReliability(
            EvidenceSource.vision,
          );
          final analyzeReliability = policy.sourceReliability(
            EvidenceSource.analyzeV2,
          );
          final progressReliability = policy.sourceReliability(
            EvidenceSource.progress,
          );

          expect(visionReliability, lessThan(analyzeReliability));
          expect(visionReliability, greaterThan(progressReliability));
          expect(
            visionReliability,
            greaterThanOrEqualTo(0),
            reason: 'reliability must be a non-negative scalar',
          );
          expect(
            visionReliability,
            lessThanOrEqualTo(1),
            reason: 'reliability must be at most 1',
          );
        },
      );

      test('low-confidence vision evidence stays well below the cap (A3)', () {
        final policy = EvidenceWeightPolicy(singleEvidenceInfluenceCap: 0.25);
        final weight = policy.weightFor(
          evidence(
            value: 0.5,
            sampleCount: 1,
            measuredAt: DateTime.utc(2026, 8, 20),
            confidence: 0.2,
            source: EvidenceSource.vision,
          ),
          asOf: DateTime.utc(2026, 8, 20),
        );
        expect(weight, lessThan(policy.singleEvidenceInfluenceCap));
        // A very-low-confidence vision record must not dominate the
        // aggregate — it is naturally bounded by sourceReliability *
        // confidence.
        expect(weight, lessThan(0.2));
      });
    },
  );
}
