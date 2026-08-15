import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_estimate.dart';

void main() {
  group('SkillEstimate — unknown state (A5)', () {
    test('unknown has no performance level, never a 0.0 default', () {
      final estimate = SkillEstimate.unknown(skillId: 'chord.gMajor');

      expect(estimate.state, SkillEstimateState.unknown);
      expect(estimate.level, isNull);
      expect(estimate.isUnknown, isTrue);
    });

    test('known estimates keep performance and uncertainty bounded', () {
      final estimate = SkillEstimate(
        skillId: 'chord.gMajor',
        level: 0.7,
        uncertainty: 0.3,
        state: SkillEstimateState.stable,
        trend: SkillTrend.improving,
        trendDelta: 0.1,
        lastObservedAt: DateTime.utc(2026, 8, 15),
        evidenceIds: const <String>['outcome-1'],
        evidenceSummary: const EvidenceSummary(
          validPerformanceCount: 1,
          stalePerformanceCount: 0,
          discomfortOnlyCount: 0,
        ),
      );

      expect(estimate.level, inInclusiveRange(0.0, 1.0));
      expect(estimate.uncertainty, inInclusiveRange(0.0, 1.0));
    });
  });

  group('SkillEstimate — discomfort separation (A7)', () {
    test(
      'the summary carries discomfort separately from performance evidence',
      () {
        const summary = EvidenceSummary(
          validPerformanceCount: 2,
          stalePerformanceCount: 0,
          discomfortOnlyCount: 1,
        );

        expect(summary.validPerformanceCount, 2);
        expect(summary.discomfortOnlyCount, 1);
        expect(summary.description, contains('1 discomfort-only'));
      },
    );
  });
}
