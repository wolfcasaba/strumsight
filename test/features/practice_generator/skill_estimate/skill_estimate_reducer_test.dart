import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/application/service/skill_estimate_reducer.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_estimate.dart';
import 'package:strumsight/features/practice_generator/domain/policy/evidence_weight_policy.dart';

void main() {
  final asOf = DateTime.utc(2026, 8, 20);

  SkillEvidence evidence({
    required String outcomeId,
    required double value,
    DateTime? measuredAt,
    DateTime? validUntil,
    double confidence = 1.0,
    int sampleCount = 8,
    EvidenceSource source = EvidenceSource.analyzeV2,
    DiscomfortReport? discomfort,
  }) => SkillEvidence(
    skillId: 'chord.gMajor',
    source: source,
    sourceOutcomeId: OutcomeId(outcomeId),
    measurementVersion: 1,
    measuredAt: measuredAt ?? asOf,
    capturedAt: asOf,
    confidence: confidence,
    validUntil: validUntil,
    performance: PerformanceEvidence(
      metricCode: 'chordChangeAccuracy',
      value: value,
      sampleCount: sampleCount,
    ),
    discomfort: discomfort,
  );

  SkillEstimate reduce(
    Iterable<SkillEvidence> evidence, {
    EvidenceWeightPolicy? policy,
  }) => SkillEstimateReducer(
    policy: policy,
  ).reduce(skillId: 'chord.gMajor', evidence: evidence, asOf: asOf);

  group('SkillEstimateReducer — evidence quantity matrix', () {
    test('zero evidence is unknown rather than a low 0.0 level (A5)', () {
      final estimate = reduce(const <SkillEvidence>[]);

      expect(estimate.state, SkillEstimateState.unknown);
      expect(estimate.level, isNull);
    });

    test(
      'one evidence yields a capped conservative value with high uncertainty',
      () {
        final policy = EvidenceWeightPolicy(singleEvidenceInfluenceCap: 0.2);
        final estimate = reduce(<SkillEvidence>[
          evidence(outcomeId: 'one', value: 1.0),
        ], policy: policy);

        expect(estimate.level, isNotNull);
        expect(
          (estimate.level! - 0.5).abs(),
          lessThanOrEqualTo(policy.singleEvidenceInfluenceCap),
        );
        expect(estimate.uncertainty, greaterThanOrEqualTo(0.7));
      },
    );

    test('many consistent evidence records yield low uncertainty', () {
      final estimate = reduce(
        List<SkillEvidence>.generate(
          8,
          (index) => evidence(
            outcomeId: 'consistent-$index',
            value: 0.8,
            measuredAt: asOf.subtract(Duration(days: index)),
          ),
        ),
      );

      expect(estimate.level, closeTo(0.8, 0.02));
      expect(estimate.uncertainty, lessThan(0.3));
    });
  });

  group('SkillEstimateReducer — deterministic conflict handling', () {
    test('sorting makes the estimate independent of input order (A1)', () {
      final first = evidence(
        outcomeId: 'a',
        value: 0.4,
        measuredAt: DateTime.utc(2026, 8, 18),
      );
      final second = evidence(
        outcomeId: 'b',
        value: 0.7,
        measuredAt: DateTime.utc(2026, 8, 19),
      );
      final third = evidence(outcomeId: 'c', value: 0.8, measuredAt: asOf);

      final forward = reduce(<SkillEvidence>[first, second, third]);
      final reverse = reduce(<SkillEvidence>[third, second, first]);

      expect(reverse, forward);
    });

    test('repeating one outcome does not multiply its influence (A3)', () {
      final one = evidence(outcomeId: 'same', value: 1.0);
      final repeated = reduce(<SkillEvidence>[one, one]);
      final single = reduce(<SkillEvidence>[one]);

      expect(repeated, single);
    });

    test(
      'conflicting values raise uncertainty instead of hiding disagreement (A4)',
      () {
        final consistent = reduce(<SkillEvidence>[
          evidence(outcomeId: 'one', value: 0.8),
          evidence(outcomeId: 'two', value: 0.8),
        ]);
        final conflicted = reduce(<SkillEvidence>[
          evidence(outcomeId: 'one', value: 0.1),
          evidence(outcomeId: 'two', value: 0.9),
        ]);

        expect(conflicted.state, SkillEstimateState.conflicted);
        expect(conflicted.uncertainty, greaterThan(consistent.uncertainty));
      },
    );

    test('time-separated monotonic improvement is a trend, not a conflict', () {
      final estimate = reduce(<SkillEvidence>[
        evidence(
          outcomeId: 'first',
          value: 0.20,
          measuredAt: DateTime.utc(2026, 8, 16),
        ),
        evidence(
          outcomeId: 'second',
          value: 0.25,
          measuredAt: DateTime.utc(2026, 8, 17),
        ),
        evidence(
          outcomeId: 'third',
          value: 0.85,
          measuredAt: DateTime.utc(2026, 8, 18),
        ),
        evidence(
          outcomeId: 'fourth',
          value: 0.90,
          measuredAt: DateTime.utc(2026, 8, 19),
        ),
      ]);

      expect(estimate.state, isNot(SkillEstimateState.conflicted));
      expect(estimate.trend, SkillTrend.improving);
      expect(estimate.trendDelta, greaterThan(0));
    });

    test('equal-time conflict has no ID-derived directional trend', () {
      final measuredAt = DateTime.utc(2026, 8, 19);
      final ascendingIds = reduce(<SkillEvidence>[
        evidence(outcomeId: 'alpha', value: 0.20, measuredAt: measuredAt),
        evidence(outcomeId: 'bravo', value: 0.25, measuredAt: measuredAt),
        evidence(outcomeId: 'charlie', value: 0.90, measuredAt: measuredAt),
      ]);
      final descendingIds = reduce(<SkillEvidence>[
        evidence(outcomeId: 'alpha', value: 0.90, measuredAt: measuredAt),
        evidence(outcomeId: 'bravo', value: 0.25, measuredAt: measuredAt),
        evidence(outcomeId: 'charlie', value: 0.20, measuredAt: measuredAt),
      ]);

      for (final estimate in <SkillEstimate>[ascendingIds, descendingIds]) {
        expect(estimate.state, SkillEstimateState.conflicted);
        expect(estimate.trend, SkillTrend.unknown);
        expect(estimate.trendDelta, 0);
      }
    });

    test(
      'expired evidence remains visible as stale with reduced influence (A6)',
      () {
        final estimate = reduce(<SkillEvidence>[
          evidence(
            outcomeId: 'expired',
            value: 0.9,
            measuredAt: DateTime.utc(2026, 8, 10),
            validUntil: DateTime.utc(2026, 8, 15),
          ),
        ]);

        expect(estimate.state, SkillEstimateState.stale);
        expect(estimate.evidenceSummary.stalePerformanceCount, 1);
        expect(estimate.uncertainty, greaterThanOrEqualTo(0.8));
      },
    );

    test('discomfort does not affect the performance level (A7)', () {
      final plain = reduce(<SkillEvidence>[
        evidence(outcomeId: 'one', value: 0.7),
      ]);
      final withDiscomfort = reduce(<SkillEvidence>[
        evidence(
          outcomeId: 'one',
          value: 0.7,
          discomfort: DiscomfortReport(category: DiscomfortCategory.pain),
        ),
      ]);

      expect(withDiscomfort.level, plain.level);
      expect(withDiscomfort.evidenceSummary.discomfortEvidenceCount, 1);
    });

    test('all reduced values stay within [0, 1] (A8)', () {
      for (final values in <List<double>>[
        <double>[0.0],
        <double>[1.0],
        <double>[0.0, 1.0],
        <double>[0.2, 0.4, 0.9, 0.7],
      ]) {
        final estimate = reduce(
          List<SkillEvidence>.generate(
            values.length,
            (index) => evidence(
              outcomeId: 'bounds-$index-${values[index]}',
              value: values[index],
            ),
          ),
        );
        expect(estimate.level, inInclusiveRange(0.0, 1.0));
        expect(estimate.uncertainty, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
