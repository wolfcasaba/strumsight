import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_estimate.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_evidence.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/ai_tutor/domain/services/skill_evidence_reducer.dart';

void main() {
  const reducer = SkillEvidenceReducer();
  final skillId = SkillId('rhythm.pulse');

  group('SkillEvidence', () {
    test('normalizes provenance fields and timestamps', () {
      final evidence = _evidence(
        skillId: skillId,
        id: ' evidence-1 ',
        provenanceId: ' session/1 ',
        comparisonKey: ' pulse/80 ',
        comparableGroupId: ' group-1 ',
        observedAt: DateTime.utc(2026, 8, 5, 10).toLocal(),
      );

      expect(evidence.id, 'evidence-1');
      expect(evidence.provenanceId, 'session/1');
      expect(evidence.comparisonKey, 'pulse/80');
      expect(evidence.comparableGroupId, 'group-1');
      expect(evidence.observedAt.isUtc, isTrue);
    });

    test('rejects versionless evidence with a stable error code', () {
      expect(
        SkillEvidenceValidationCode.schemaVersionMissing,
        'skillEvidence.schemaVersion.missing',
      );
      expect(
        () => SkillEvidence(
          id: 'evidence-1',
          skillId: skillId,
          provenanceId: 'session/1',
          comparisonKey: 'pulse/80',
          comparableGroupId: 'group-1',
          source: SkillEvidenceSource.practiceSession,
          scoreBasisPoints: 8000,
          observedAt: DateTime.utc(2026, 8, 5, 10),
          schemaVersion: null,
          scorerVersion: 1,
        ),
        throwsA(
          isA<SkillEvidenceValidationException>().having(
            (error) => error.code,
            'code',
            SkillEvidenceValidationCode.schemaVersionMissing,
          ),
        ),
      );
    });

    test('uses documented source weights and value equality', () {
      expect(
        SkillEvidenceSource.practiceSession.weightBasisPoints,
        skillBasisPointScale,
      );
      expect(
        SkillEvidenceSource.songSection.weightBasisPoints,
        skillBasisPointScale,
      );
      expect(
        SkillEvidenceSource.analyzeSession.weightBasisPoints,
        skillBasisPointScale,
      );
      expect(SkillEvidenceSource.userSelfReport.weightBasisPoints, 4000);
      expect(SkillEvidenceSource.tutorAssessment.weightBasisPoints, 2000);

      final first = _evidence(skillId: skillId);
      final second = _evidence(skillId: skillId);
      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('rejects malformed evidence fields and unsupported versions', () {
      expect(
        () => _evidence(skillId: skillId, id: ' '),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
      expect(
        () => _evidence(skillId: skillId, provenanceId: ' '),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
      expect(
        () => _evidence(skillId: skillId, comparisonKey: ' '),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
      expect(
        () => _evidence(skillId: skillId, comparableGroupId: ' '),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
      expect(
        () => _evidence(
          skillId: skillId,
          scoreBasisPoints: skillBasisPointScale + 1,
        ),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
      expect(
        () => _rawEvidence(skillId: skillId, schemaVersion: 0),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
      expect(
        () => _rawEvidence(skillId: skillId, scorerVersion: 0),
        throwsA(isA<SkillEvidenceValidationException>()),
      );
    });

    test('formats evidence validation errors with their stable code', () {
      try {
        _evidence(skillId: skillId, id: ' ');
      } on SkillEvidenceValidationException catch (error) {
        expect(
          error.toString(),
          'SkillEvidenceValidationException(skillEvidence.id.empty)',
        );
      }
    });
  });

  group('SkillEvidenceReducer comparable-group matrix', () {
    test('returns insufficient for zero comparable groups', () {
      final estimate = reducer.reduce(skillId: skillId, evidence: const []);

      expect(estimate.status, SkillEstimateStatus.insufficient);
      expect(estimate.comparableGroupCount, 0);
      expect(estimate.scoreBasisPoints, isNull);
      expect(estimate.trend, isNull);
      expect(estimate.confidenceBasisPoints, 0);
    });

    test('returns insufficient for one comparable group', () {
      final estimate = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[_evidence(skillId: skillId)],
      );

      expect(estimate.status, SkillEstimateStatus.insufficient);
      expect(estimate.comparableGroupCount, 1);
      expect(estimate.scoreBasisPoints, isNull);
      expect(estimate.trend, isNull);
      expect(estimate.confidenceBasisPoints, 2000);
    });

    test('returns a trend estimate for two comparable groups', () {
      final estimate = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[
          _evidence(
            skillId: skillId,
            id: 'first',
            comparableGroupId: 'session-1',
            scoreBasisPoints: 4000,
            observedAt: DateTime.utc(2026, 8, 4, 10),
          ),
          _evidence(
            skillId: skillId,
            id: 'second',
            comparableGroupId: 'session-2',
            scoreBasisPoints: 8000,
            observedAt: DateTime.utc(2026, 8, 5, 10),
          ),
        ],
      );

      expect(estimate.status, SkillEstimateStatus.trend);
      expect(estimate.comparableGroupCount, 2);
      expect(estimate.scoreBasisPoints, 6000);
      expect(estimate.trend, SkillTrend.improving);
      expect(estimate.confidenceBasisPoints, 4000);
    });

    test('keeps declining and stable trends distinct', () {
      final declining = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[
          _evidence(
            skillId: skillId,
            id: 'first',
            comparableGroupId: 'session-1',
            scoreBasisPoints: 8000,
            observedAt: DateTime.utc(2026, 8, 4),
          ),
          _evidence(
            skillId: skillId,
            id: 'second',
            comparableGroupId: 'session-2',
            scoreBasisPoints: 4000,
            observedAt: DateTime.utc(2026, 8, 5),
          ),
        ],
      );
      final stable = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[
          _evidence(
            skillId: skillId,
            id: 'stable-first',
            comparableGroupId: 'session-1',
            scoreBasisPoints: 6000,
            observedAt: DateTime.utc(2026, 8, 4),
          ),
          _evidence(
            skillId: skillId,
            id: 'stable-second',
            comparableGroupId: 'session-2',
            scoreBasisPoints: 6000,
            observedAt: DateTime.utc(2026, 8, 5),
          ),
        ],
      );

      expect(declining.trend, SkillTrend.declining);
      expect(stable.trend, SkillTrend.stable);
    });
  });

  group('SkillEvidenceReducer determinism', () {
    test('uses the literal stable tie-break for equal group timestamps', () {
      expect(
        SkillEvidenceReducer.stableGroupTieBreak,
        'observedAtUtcAscending, comparableGroupIdLexicalAscending',
      );

      final estimate = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[
          _evidence(
            skillId: skillId,
            id: 'beta',
            comparableGroupId: 'beta',
            scoreBasisPoints: 8000,
          ),
          _evidence(
            skillId: skillId,
            id: 'alpha',
            comparableGroupId: 'alpha',
            scoreBasisPoints: 3000,
          ),
        ],
      );

      expect(estimate.trend, SkillTrend.improving);
      expect(
        estimate.contributingEvidenceIds,
        equals(<String>['alpha', 'beta']),
      );
    });

    test('is bit-identical for seeded shuffled evidence permutations', () {
      final evidence = <SkillEvidence>[
        _evidence(
          skillId: skillId,
          id: 'a',
          comparableGroupId: 'session-1',
          scoreBasisPoints: 3000,
          observedAt: DateTime.utc(2026, 8, 2),
        ),
        _evidence(
          skillId: skillId,
          id: 'b',
          comparableGroupId: 'session-2',
          scoreBasisPoints: 5000,
          observedAt: DateTime.utc(2026, 8, 3),
        ),
        _evidence(
          skillId: skillId,
          id: 'c',
          comparableGroupId: 'session-3',
          scoreBasisPoints: 7000,
          observedAt: DateTime.utc(2026, 8, 4),
        ),
        _evidence(
          skillId: skillId,
          id: 'd',
          comparableGroupId: 'session-4',
          scoreBasisPoints: 9000,
          observedAt: DateTime.utc(2026, 8, 5),
        ),
      ];
      final expected = reducer.reduce(skillId: skillId, evidence: evidence);

      for (final seed in <int>[1, 7, 42, 20260805]) {
        final shuffled = List<SkillEvidence>.of(evidence)
          ..shuffle(Random(seed));
        final actual = reducer.reduce(skillId: skillId, evidence: shuffled);

        expect(actual, equals(expected), reason: 'seed=$seed');
        expect(actual.hashCode, expected.hashCode, reason: 'seed=$seed');
      }
    });

    test(
      'gives self-report evidence lower weight than a direct measurement',
      () {
        final estimate = reducer.reduce(
          skillId: skillId,
          evidence: <SkillEvidence>[
            _evidence(
              skillId: skillId,
              id: 'direct-one',
              comparableGroupId: 'session-1',
              scoreBasisPoints: 8000,
              source: SkillEvidenceSource.practiceSession,
              observedAt: DateTime.utc(2026, 8, 4),
            ),
            _evidence(
              skillId: skillId,
              id: 'self-report',
              comparableGroupId: 'session-1',
              scoreBasisPoints: 0,
              source: SkillEvidenceSource.userSelfReport,
              observedAt: DateTime.utc(2026, 8, 4),
            ),
            _evidence(
              skillId: skillId,
              id: 'direct-two',
              comparableGroupId: 'session-2',
              scoreBasisPoints: 8000,
              observedAt: DateTime.utc(2026, 8, 5),
            ),
          ],
        );

        expect(estimate.scoreBasisPoints, 6857);
      },
    );
  });

  group('SkillEvidenceReducer duplicate protection', () {
    test('keeps an identical duplicate evidence ID idempotent', () {
      final evidence = _evidence(skillId: skillId, id: 'same');

      final estimate = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[evidence, evidence],
      );

      expect(estimate.evidenceCount, 1);
      expect(estimate.contributingEvidenceIds, equals(<String>['same']));
    });

    test('rejects conflicting evidence that reuses an ID', () {
      expect(
        () => reducer.reduce(
          skillId: skillId,
          evidence: <SkillEvidence>[
            _evidence(skillId: skillId, id: 'same', scoreBasisPoints: 1000),
            _evidence(skillId: skillId, id: 'same', scoreBasisPoints: 9000),
          ],
        ),
        throwsA(
          isA<SkillEvidenceReducerException>().having(
            (error) => error.code,
            'code',
            SkillEvidenceReducerCode.duplicateEvidenceIdConflict,
          ),
        ),
      );
    });

    test('rejects evidence for a different skill with a stable code', () {
      expect(
        () => reducer.reduce(
          skillId: skillId,
          evidence: <SkillEvidence>[
            _evidence(skillId: SkillId('rhythm.onBeatAccuracy')),
          ],
        ),
        throwsA(
          isA<SkillEvidenceReducerException>().having(
            (error) => error.code,
            'code',
            SkillEvidenceReducerCode.unexpectedSkill,
          ),
        ),
      );
    });

    test('uses lexical comparison-key selection when partitions tie', () {
      final estimate = reducer.reduce(
        skillId: skillId,
        evidence: <SkillEvidence>[
          _evidence(
            skillId: skillId,
            id: 'zeta',
            comparisonKey: 'zeta',
            comparableGroupId: 'zeta-group',
          ),
          _evidence(
            skillId: skillId,
            id: 'alpha',
            comparisonKey: 'alpha',
            comparableGroupId: 'alpha-group',
          ),
        ],
      );

      expect(estimate.comparisonKey, 'alpha');
      expect(estimate.contributingEvidenceIds, equals(<String>['alpha']));
    });

    test('formats reducer errors with their stable code', () {
      try {
        reducer.reduce(
          skillId: skillId,
          evidence: <SkillEvidence>[
            _evidence(skillId: skillId, id: 'same', scoreBasisPoints: 1000),
            _evidence(skillId: skillId, id: 'same', scoreBasisPoints: 9000),
          ],
        );
      } on SkillEvidenceReducerException catch (error) {
        expect(
          error.toString(),
          'SkillEvidenceReducerException(skillEvidenceReducer.evidenceId.conflict)',
        );
      }
    });
  });

  group('SkillEstimate validation', () {
    test('rejects structurally invalid estimates', () {
      expect(
        () => _estimate(
          skillId: skillId,
          confidenceBasisPoints: skillBasisPointScale + 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => _estimate(
          skillId: skillId,
          evidenceCount: 1,
          contributingEvidenceIds: const <String>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => _estimate(
          skillId: skillId,
          scoreBasisPoints: skillBasisPointScale + 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => _estimate(skillId: skillId, comparableGroupCount: 2),
        throwsArgumentError,
      );
      expect(
        () => _estimate(
          skillId: skillId,
          status: SkillEstimateStatus.trend,
          comparableGroupCount: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}

SkillEvidence _evidence({
  required SkillId skillId,
  String id = 'evidence-1',
  String provenanceId = 'practice-session/1',
  String comparisonKey = 'pulse/80',
  String comparableGroupId = 'session-1',
  SkillEvidenceSource source = SkillEvidenceSource.practiceSession,
  int scoreBasisPoints = 6000,
  DateTime? observedAt,
}) {
  return _rawEvidence(
    skillId: skillId,
    id: id,
    provenanceId: provenanceId,
    comparisonKey: comparisonKey,
    comparableGroupId: comparableGroupId,
    source: source,
    scoreBasisPoints: scoreBasisPoints,
    observedAt: observedAt,
  );
}

SkillEvidence _rawEvidence({
  required SkillId skillId,
  String id = 'evidence-1',
  String provenanceId = 'practice-session/1',
  String comparisonKey = 'pulse/80',
  String comparableGroupId = 'session-1',
  SkillEvidenceSource source = SkillEvidenceSource.practiceSession,
  int scoreBasisPoints = 6000,
  DateTime? observedAt,
  int? schemaVersion = 1,
  int? scorerVersion = 1,
}) {
  return SkillEvidence(
    id: id,
    skillId: skillId,
    provenanceId: provenanceId,
    comparisonKey: comparisonKey,
    comparableGroupId: comparableGroupId,
    source: source,
    scoreBasisPoints: scoreBasisPoints,
    observedAt: observedAt ?? DateTime.utc(2026, 8, 5, 10),
    schemaVersion: schemaVersion,
    scorerVersion: scorerVersion,
  );
}

SkillEstimate _estimate({
  required SkillId skillId,
  SkillEstimateStatus status = SkillEstimateStatus.insufficient,
  int? scoreBasisPoints,
  int confidenceBasisPoints = 0,
  int evidenceCount = 0,
  int comparableGroupCount = 0,
  List<String> contributingEvidenceIds = const <String>[],
}) {
  return SkillEstimate(
    skillId: skillId,
    status: status,
    scoreBasisPoints: scoreBasisPoints,
    confidenceBasisPoints: confidenceBasisPoints,
    evidenceCount: evidenceCount,
    comparableGroupCount: comparableGroupCount,
    contributingEvidenceIds: contributingEvidenceIds,
    updatedAt: null,
  );
}
