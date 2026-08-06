import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_source_ref.dart';
import 'package:strumsight/features/ai_tutor/domain/services/tutor_claim_validator.dart';

void main() {
  const validator = TutorClaimValidator();

  final trustedSources = <TutorSourceRef>[
    const TutorSourceRef(
      sourceId: 'kb-guitar-v2',
      title: 'Guitar Knowledge Base',
      locale: 'en',
      topic: 'chords',
      knowledgeVersion: 2,
      chunkIndex: 0,
      chunkHash: 'abc123',
    ),
    const TutorSourceRef(
      sourceId: 'kb-guitar-v2',
      title: 'Guitar Knowledge Base',
      locale: 'en',
      topic: 'scales',
      knowledgeVersion: 2,
      chunkIndex: 1,
      chunkHash: 'def456',
    ),
  ];

  group('TutorClaimValidator — grounded claim type taxonomy', () {
    test('reuses the R16 grounded claim type set exactly', () {
      expect(TutorClaimValidator.groundedClaimTypes, <String>{
        'measuredFact',
        'computedTrend',
        'knowledgeFact',
        'userProvidedFact',
        'inference',
        'recommendation',
        'safetyNotice',
      });
    });
  });

  group('TutorClaimValidator — valid claims pass', () {
    test('measuredFact with trusted evidenceRef passes', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(
            type: 'measuredFact',
            evidenceRefs: {'kb-guitar-v2#1'},
          ),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('computedTrend with trusted evidenceRef passes', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(
            type: 'computedTrend',
            evidenceRefs: {'kb-guitar-v2#2'},
          ),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });

    test('knowledgeFact with trusted evidenceRef passes', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(
            type: 'knowledgeFact',
            evidenceRefs: {'kb-guitar-v2#1'},
          ),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });

    test('userProvidedFact passes without evidenceRefs', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'userProvidedFact', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });

    test('inference passes without evidenceRefs', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'inference', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });

    test('recommendation passes without evidenceRefs', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'recommendation', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });

    test('safetyNotice passes without evidenceRefs', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'safetyNotice', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });

    test('multiple valid claims pass', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(
            type: 'knowledgeFact',
            evidenceRefs: {'kb-guitar-v2#1'},
          ),
          const TutorClaim(type: 'inference', evidenceRefs: {}),
          const TutorClaim(type: 'recommendation', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });
  });

  group('TutorClaimValidator — invented metric blocks', () {
    test('measuredFact with empty evidenceRefs is invalid', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'measuredFact', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaimEvidence),
      );
    });

    test('measuredFact with non-trusted evidenceRef is invalid', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(
            type: 'measuredFact',
            evidenceRefs: {'untrusted-source#99'},
          ),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaimEvidence),
      );
    });

    test('computedTrend with empty evidenceRefs is invalid', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'computedTrend', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaimEvidence),
      );
    });

    test('knowledgeFact with empty evidenceRefs is invalid', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'knowledgeFact', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaimEvidence),
      );
    });

    test(
      'invented metric with mixed valid and invalid claims still blocks',
      () {
        final result = validator.validate(
          claims: <TutorClaim>[
            const TutorClaim(
              type: 'knowledgeFact',
              evidenceRefs: {'kb-guitar-v2#1'},
            ),
            const TutorClaim(type: 'measuredFact', evidenceRefs: {}),
            const TutorClaim(type: 'inference', evidenceRefs: {}),
          ],
          trustedSourceRefs: trustedSources,
        );
        expect(result.isValid, isFalse);
        expect(
          result.issues,
          contains(TutorClaimValidationIssue.unsupportedClaimEvidence),
        );
        expect(
          result.issues,
          isNot(contains(TutorClaimValidationIssue.unsupportedClaim)),
        );
      },
    );
  });

  group('TutorClaimValidator — unsupported claim types', () {
    test('unknown claim type is rejected', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(type: 'hallucinatedScore', evidenceRefs: {}),
        ],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaim),
      );
    });

    test('empty string type is rejected', () {
      final result = validator.validate(
        claims: <TutorClaim>[const TutorClaim(type: '', evidenceRefs: {})],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaim),
      );
    });
  });

  group('TutorClaimValidator — empty claims', () {
    test('empty claims list is valid', () {
      final result = validator.validate(
        claims: const <TutorClaim>[],
        trustedSourceRefs: trustedSources,
      );
      expect(result.isValid, isTrue);
    });
  });

  group('TutorClaimValidator — no trusted sources', () {
    test('measuredFact with no trusted sources available is invalid', () {
      final result = validator.validate(
        claims: <TutorClaim>[
          const TutorClaim(
            type: 'measuredFact',
            evidenceRefs: {'kb-guitar-v2#1'},
          ),
        ],
        trustedSourceRefs: const <TutorSourceRef>[],
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains(TutorClaimValidationIssue.unsupportedClaimEvidence),
      );
    });
  });

  group('TutorClaimValidator — chunkId resolution', () {
    test(
      'resolves TutorSourceRef.chunkId as the canonical form for matching',
      () {
        final src = const TutorSourceRef(
          sourceId: 'kb-guitar-v2',
          title: 'KB',
          locale: 'en',
          topic: 'chords',
          knowledgeVersion: 2,
          chunkIndex: 0,
          chunkHash: 'abc',
        );
        expect(src.chunkId, 'kb-guitar-v2#1');
      },
    );
  });
}
