import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_goal.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
import 'package:strumsight/features/practice_generator/domain/service/request_validator.dart';

void main() {
  PracticeGoal goal({
    required String id,
    PracticeGoalType type = PracticeGoalType.foundation,
    GoalPriority priority = GoalPriority.primary,
    PracticeGoalStatus status = PracticeGoalStatus.proposed,
    String? normalizedTargetId,
  }) => PracticeGoal(
    id: GoalId(id),
    type: type,
    priority: priority,
    status: status,
    createdAt: DateTime.utc(2026, 8, 15),
    normalizedTargetId: normalizedTargetId,
  );

  group('PracticeGoal lifecycle', () {
    test('allows only defined lifecycle transitions (A8)', () {
      final proposed = goal(id: 'goal-1');
      final active = proposed.transitionTo(PracticeGoalStatus.active);
      final achieved = active.transitionTo(PracticeGoalStatus.achieved);

      expect(active.status, PracticeGoalStatus.active);
      expect(achieved.status, PracticeGoalStatus.achieved);
      expect(
        () => proposed.transitionTo(PracticeGoalStatus.achieved),
        throwsStateError,
      );
      expect(
        () => achieved.transitionTo(PracticeGoalStatus.active),
        throwsStateError,
      );
    });

    test('status codes are stable and fail loudly when unknown', () {
      expect(PracticeGoalStatus.fromCode('paused'), PracticeGoalStatus.paused);
      expect(() => PracticeGoalStatus.fromCode(''), throwsArgumentError);
      expect(() => PracticeGoalStatus.fromCode('done'), throwsArgumentError);
    });
  });

  group('goal executability', () {
    test('an unnormalized custom goal is not executable (A7)', () {
      expect(
        goal(id: 'goal-custom', type: PracticeGoalType.custom).isExecutable,
        isFalse,
      );
      expect(
        goal(
          id: 'goal-normalized',
          type: PracticeGoalType.custom,
          normalizedTargetId: 'skill:alternate-picking',
        ).isExecutable,
        isTrue,
      );
    });

    test('too many primary goals is a warning rather than an error (A6)', () {
      final result = const RequestValidator().validate(
        goals: [
          goal(id: 'goal-1'),
          goal(id: 'goal-2'),
        ],
        availability: WeeklyAvailability(const []),
        scheduledMinutes: const {},
      );

      expect(result.hasErrors, isFalse);
      expect(result.findings.single.severity, ValidationSeverity.warning);
      expect(
        result.findings.single.code,
        RequestValidationCode.tooManyPrimaryGoals,
      );
    });
  });

  test('metric target requires all measurement safeguards', () {
    final target = MetricTarget(
      metricCode: 'timing.error.ms',
      direction: MetricDirection.atMost,
      threshold: 20,
      measurementCapability: 'timingEvidenceV1',
      minimumConfidence: 0.8,
      minimumSampleCount: 12,
      targetDate: LocalDate(2026, 9, 1),
    );

    expect(target.minimumSampleCount, 12);
    expect(
      () => MetricTarget(
        metricCode: 'timing.error.ms',
        direction: MetricDirection.atMost,
        threshold: double.nan,
        measurementCapability: 'timingEvidenceV1',
        minimumConfidence: 0.8,
        minimumSampleCount: 12,
      ),
      throwsArgumentError,
    );
  });
}
