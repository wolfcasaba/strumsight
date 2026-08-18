import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('TodayPlanController', () {
    test('A3 below threshold: local 23:59 selects the current local day', () {
      final controller = TodayPlanController(
        clock: () => DateTime(2026, 8, 18, 23, 59),
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.18', localDate: LocalDate(2026, 8, 18)),
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );

      final state = controller.resolve(plan);

      expect(state.day?.id, DayId('day.18'));
    });

    test('A3 at threshold: local midnight selects the next local day', () {
      final controller = TodayPlanController(
        clock: () => DateTime(2026, 8, 19),
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.18', localDate: LocalDate(2026, 8, 18)),
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );

      final state = controller.resolve(plan);

      expect(state.day?.id, DayId('day.19'));
    });

    test('A3 above threshold: a local timezone change keeps the local day', () {
      final controller = TodayPlanController(
        // The clock owner has already converted the instant to the learner's
        // current locale. The controller must not reclassify it through UTC.
        clock: () => DateTime(2026, 8, 19, 0, 30),
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );

      final state = controller.resolve(plan);

      expect(state.localDate, LocalDate(2026, 8, 19));
      expect(state.day?.id, DayId('day.19'));
    });

    test('A4 selects the first pending block and sums remaining time', () {
      final completed = buildBlock(
        id: 'completed',
        order: 1,
        status: PracticeItemStatus.completed,
        estimatedElapsed: const Duration(minutes: 6),
      );
      final next = buildBlock(
        id: 'next',
        order: 2,
        estimatedElapsed: const Duration(minutes: 5),
      );
      final later = buildBlock(
        id: 'later',
        order: 3,
        estimatedElapsed: const Duration(minutes: 7),
      );
      final controller = TodayPlanController(
        clock: () => DateTime(2026, 8, 19, 9),
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.19',
            localDate: LocalDate(2026, 8, 19),
            blocks: <PracticeBlock>[completed, later, next],
          ),
        ],
      );

      final state = controller.resolve(plan);

      expect(state.nextBlock?.id, BlockId('next'));
      expect(state.remainingTime, const Duration(minutes: 12));
    });

    test('A5 shortening records the learner-reschedule reason', () {
      final block = buildBlock(id: 'next', order: 1);
      final day = buildDay(
        id: 'day.19',
        localDate: LocalDate(2026, 8, 19),
        blocks: <PracticeBlock>[block],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final controller = ActivePlanController(
        generateRevisionId: () => RevisionId('revision.2'),
        resolveCandidate: (_) => buildCandidate(),
      );

      final update = controller.shorten(day: day, plan: plan);

      expect(update.plan.activeRevisionId, RevisionId('revision.2'));
      expect(
        update.changeSet.changes.single.reason,
        PlanChangeReason.learnerReschedule,
      );
      expect(
        update.plan.days.single.blocks.single.prescription.activeDuration,
        const Duration(minutes: 1),
      );
    });

    test('A6 pausing preserves the plan and its days', () {
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );
      final controller = ActivePlanController(
        generateRevisionId: () => RevisionId('revision.2'),
        resolveCandidate: (_) => buildCandidate(),
      );

      final update = controller.pause(plan);

      expect(update.plan.status, PlanStatus.paused);
      expect(update.plan.days, plan.days);
      expect(
        update.changeSet.changes.single.reason,
        PlanChangeReason.learnerReschedule,
      );
    });
  });
}
