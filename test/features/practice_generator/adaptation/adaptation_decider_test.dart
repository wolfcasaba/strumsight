import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  final asOf = DateTime.utc(2026, 8, 16, 12);

  SkillEstimate estimate({double uncertainty = 0.1}) => SkillEstimate(
    skillId: 'skill.chordChanges',
    level: 0.7,
    uncertainty: uncertainty,
    state: SkillEstimateState.stable,
    trend: SkillTrend.improving,
    trendDelta: 0.1,
    lastObservedAt: asOf,
    evidenceIds: const <String>['estimate-source'],
    evidenceSummary: const EvidenceSummary(
      validPerformanceCount: 3,
      stalePerformanceCount: 0,
      discomfortOnlyCount: 0,
    ),
  );

  SkillEvidence evidence(
    int index, {
    double? performance = 0.9,
    double confidence = 0.9,
    DiscomfortCategory? discomfort,
    EvidenceSource source = EvidenceSource.progress,
  }) => SkillEvidence(
    skillId: 'skill.chordChanges',
    source: source,
    sourceOutcomeId: OutcomeId('outcome-$index'),
    measurementVersion: 1,
    measuredAt: asOf.subtract(Duration(days: index % 4)),
    capturedAt: asOf,
    confidence: confidence,
    performance: performance == null
        ? null
        : PerformanceEvidence(metricCode: 'accuracy', value: performance),
    discomfort: discomfort == null
        ? null
        : DiscomfortReport(category: discomfort),
  );

  DifficultyProfile profile({int difficultyLevel = 4, int tempoBpm = 120}) =>
      DifficultyProfile(
        difficultyLevel: difficultyLevel,
        tempoBpm: tempoBpm,
        supportsTempo: true,
        loopCount: 2,
        variationLevel: 2,
        strictnessLevel: 2,
      );

  AdaptationRequest request({
    required Iterable<SkillEvidence> evidenceItems,
    SkillEstimate? skillEstimate,
    DifficultyProfile? current,
    DateTime? lastAdvanceAt,
  }) => AdaptationRequest(
    skillId: 'skill.chordChanges',
    current: current ?? profile(),
    estimate: skillEstimate ?? estimate(),
    evidence: evidenceItems,
    asOf: asOf,
    lastAdvanceAt: lastAdvanceAt,
  );

  final decider = AdaptationDecider();

  group('A1: one adaptation advances by at most one difficulty step', () {
    test('abundant successful evidence changes every difficulty control by one '
        'bounded step', () {
      final decision = decider.decide(
        request(
          evidenceItems: List<SkillEvidence>.generate(
            8,
            (index) => evidence(index),
          ),
        ),
      );

      expect(decision.action, AdaptationAction.advance);
      expect(decision.next.difficultyLevel, 5);
      expect(decision.next.tempoBpm, 130);
      expect(decision.next.loopCount, 3);
      expect(decision.next.variationLevel, 3);
      expect(decision.next.strictnessLevel, 3);
    });
  });

  group('progression evidence threshold is inclusive', () {
    test('one successful session below the minimum does not advance', () {
      final decision = decider.decide(
        request(evidenceItems: <SkillEvidence>[evidence(1), evidence(2)]),
      );

      expect(decision.action, AdaptationAction.maintain);
      expect(decision.reasons, contains(AdaptationReason.insufficientEvidence));
    });

    test('exactly the minimum successful sessions advance', () {
      final decision = decider.decide(
        request(
          evidenceItems: <SkillEvidence>[evidence(1), evidence(2), evidence(3)],
        ),
      );

      expect(decision.action, AdaptationAction.advance);
    });

    test('uncertain estimate does not advance despite sufficient sessions', () {
      final decision = decider.decide(
        request(
          skillEstimate: estimate(uncertainty: 0.7),
          evidenceItems: <SkillEvidence>[evidence(1), evidence(2), evidence(3)],
        ),
      );

      expect(decision.action, AdaptationAction.maintain);
      expect(
        decision.reasons,
        contains(AdaptationReason.insufficientConfidence),
      );
    });
  });

  test('A2: one weak session does not regress', () {
    final decision = decider.decide(
      request(evidenceItems: <SkillEvidence>[evidence(1, performance: 0.2)]),
    );

    expect(decision.action, AdaptationAction.maintain);
    expect(decision.next, profile());
  });

  test('A3: repeated struggle regresses by one bounded step', () {
    final decision = decider.decide(
      request(
        evidenceItems: <SkillEvidence>[
          evidence(1, performance: 0.2),
          evidence(2, performance: 0.3),
        ],
      ),
    );

    expect(decision.action, AdaptationAction.regress);
    expect(decision.next.difficultyLevel, 3);
    expect(decision.reasons, contains(AdaptationReason.repeatedStruggle));
  });

  test(
    'A4: discomfort blocks advancement regardless of strong performance',
    () {
      final decision = decider.decide(
        request(
          evidenceItems: <SkillEvidence>[
            evidence(1),
            evidence(2),
            evidence(3, discomfort: DiscomfortCategory.pain),
          ],
        ),
      );

      expect(decision.action, AdaptationAction.maintain);
      expect(
        decision.reasons,
        contains(AdaptationReason.discomfortBlocksAdvance),
      );
    },
  );

  test('A5: an explicit too-hard self-report regresses immediately', () {
    final decision = decider.decide(
      request(
        evidenceItems: <SkillEvidence>[
          evidence(
            1,
            performance: null,
            source: EvidenceSource.selfReport,
            discomfort: DiscomfortCategory.frustration,
          ),
        ],
      ),
    );

    expect(decision.action, AdaptationAction.regress);
    expect(decision.reasons, contains(AdaptationReason.explicitTooHard));
  });

  test('A6: sufficient evidence inside the advance cooldown is held', () {
    final decision = decider.decide(
      request(
        lastAdvanceAt: asOf.subtract(const Duration(days: 6)),
        evidenceItems: <SkillEvidence>[evidence(1), evidence(2), evidence(3)],
      ),
    );

    expect(decision.action, AdaptationAction.maintain);
    expect(decision.reasons, contains(AdaptationReason.cooldownActive));
  });

  test('A7: an advancing tempo is clamped to the supported policy range', () {
    final decision = decider.decide(
      request(
        current: profile(tempoBpm: 175),
        evidenceItems: <SkillEvidence>[evidence(1), evidence(2), evidence(3)],
      ),
    );

    expect(decision.action, AdaptationAction.advance);
    expect(decision.next.tempoBpm, 180);
  });

  test(
    'A8: every decision retains stable evidence references and policy provenance',
    () {
      final decision = decider.decide(
        request(
          evidenceItems: <SkillEvidence>[evidence(3), evidence(1), evidence(2)],
        ),
      );

      expect(decision.evidenceIds, <String>[
        'outcome-1',
        'outcome-2',
        'outcome-3',
      ]);
      expect(decision.policyVersion, 'progression-policy-v1');
    },
  );
}
