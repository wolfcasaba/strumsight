import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  const ranker = InsightRanker();

  EvidenceBackedAnalysisInsight insight(
    String id,
    EvidenceInsightKind kind,
    EvidenceInsightPriority priority,
  ) => EvidenceBackedAnalysisInsight(
    ruleId: id,
    ruleVersion: 1,
    priority: priority,
    kind: kind,
    factIds: const <String>[AnalysisMetricId.timingTargetMeanAbsoluteError],
    evidenceIds: const <String>['event-1'],
    messageKey: 'key',
    messageArgs: const <String, String>{},
    confidence: 1,
    recommendedAction: const CalibrateInputAction(),
  );

  test(
    'maximum policy shows four of nine insights and ranks every remainder',
    () {
      final values = <EvidenceBackedAnalysisInsight>[
        insight(
          'z-improvement',
          EvidenceInsightKind.improvement,
          EvidenceInsightPriority.high,
        ),
        insight(
          'a-improvement',
          EvidenceInsightKind.improvement,
          EvidenceInsightPriority.high,
        ),
        insight(
          'strength',
          EvidenceInsightKind.strength,
          EvidenceInsightPriority.low,
        ),
        insight(
          'next',
          EvidenceInsightKind.nextAction,
          EvidenceInsightPriority.critical,
        ),
        insight(
          'quality',
          EvidenceInsightKind.qualityWarning,
          EvidenceInsightPriority.critical,
        ),
        insight(
          'another-quality',
          EvidenceInsightKind.qualityWarning,
          EvidenceInsightPriority.high,
        ),
        insight(
          'b-improvement',
          EvidenceInsightKind.improvement,
          EvidenceInsightPriority.medium,
        ),
        insight(
          'c-improvement',
          EvidenceInsightKind.improvement,
          EvidenceInsightPriority.low,
        ),
        insight(
          'second-strength',
          EvidenceInsightKind.strength,
          EvidenceInsightPriority.medium,
        ),
      ];
      final ranked = ranker.rank(values);
      expect(ranked.visibleInsights, hasLength(4));
      expect(ranked.improvement!.ruleId, 'a-improvement');
      expect(ranked.strength!.ruleId, 'second-strength');
      expect(ranked.additionalInsights.map((value) => value.ruleId), <String>[
        'another-quality',
        'z-improvement',
        'b-improvement',
        'c-improvement',
        'strength',
      ]);
    },
  );

  test('same-priority ordering is rule ID ordered for repeated ranking', () {
    final values = <EvidenceBackedAnalysisInsight>[
      insight(
        'rule-z',
        EvidenceInsightKind.improvement,
        EvidenceInsightPriority.high,
      ),
      insight(
        'rule-a',
        EvidenceInsightKind.improvement,
        EvidenceInsightPriority.high,
      ),
      insight(
        'rule-m',
        EvidenceInsightKind.improvement,
        EvidenceInsightPriority.high,
      ),
    ];
    final expected = <String>['rule-a', 'rule-m', 'rule-z'];
    for (var trial = 0; trial < 100; trial++) {
      final ranked = ranker.rank(values.reversed);
      expect(<String>[
        ranked.improvement!.ruleId,
        ...ranked.additionalInsights.map((item) => item.ruleId),
      ], expected);
    }
  });

  test('no strength is fabricated when no strength rule produced evidence', () {
    final ranked = ranker.rank(<EvidenceBackedAnalysisInsight>[
      insight(
        'improvement',
        EvidenceInsightKind.improvement,
        EvidenceInsightPriority.high,
      ),
    ]);
    expect(ranked.strength, isNull);
  });
}
