import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('TodayPlanController', () {
    test(
      'A7: a cast map with a non-string value is rejected without throwing',
      () {
        final hostile = <String, Object?>{
          'destination': 1,
        }.cast<String, String>();

        expect(() => TodayPlanRouteRequest.tryParse(hostile), returnsNormally);
        expect(TodayPlanRouteRequest.tryParse(hostile), isNull);
      },
    );

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

  // R35 (MI-K): the Today projection now carries the REAL missed-day
  // verdict, so the catch-up explainer's entry point can be gated on the
  // policy instead of on a second, screen-local guess at what a missed day
  // is (ADR 0269).
  group('TodayPlanController — the missed-day verdict on the state', () {
    TodayPlanController controllerAt19() =>
        TodayPlanController(clock: () => DateTime(2026, 8, 19));

    test('a past planned primary-focus day counts as missed', () {
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.17', localDate: LocalDate(2026, 8, 17)),
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );

      final state = controllerAt19().resolve(plan);

      expect(state.missedDays?.missedDayCount, 1);
      expect(state.missedDays?.mode, RescheduleMode.simpleReschedule);
      expect(state.hasMissedDays, isTrue);
    });

    test('a rest day is never a missed day (ADR 0269 §2)', () {
      final plan = buildPlan(
        days: <PracticeDay>[
          PracticeDay(
            id: DayId('day.17'),
            localDate: LocalDate(2026, 8, 17),
            status: PracticeItemStatus.planned,
            timeBudget: const Duration(minutes: 30),
            blocks: const <PracticeBlock>[],
            primaryFocusSkillIds: const <String>['rest'],
            reasonCodes: <String>[ScheduleDecisionReason.restDay.code],
          ),
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );

      final state = controllerAt19().resolve(plan);

      expect(state.missedDays?.missedDayCount, 0);
      expect(state.hasMissedDays, isFalse);
    });

    test('no active plan carries no verdict at all', () {
      final state = controllerAt19().resolve(null);

      expect(state.missedDays, isNull);
      expect(state.hasMissedDays, isFalse);
    });

    test('A1: the verdict carries the NEXT day budget unchanged — the '
        'projection can never grow a day from missed time', () {
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.17', localDate: LocalDate(2026, 8, 17)),
          buildDay(
            id: 'day.19',
            localDate: LocalDate(2026, 8, 19),
            timeBudget: const Duration(minutes: 25),
          ),
        ],
      );

      final state = controllerAt19().resolve(plan);

      // The 19th is the first day that is today-or-later, so its own hard
      // ceiling is the frame ADR 0258 §3 forbids growing. A missed day on
      // the 17th must not add a single minute to it.
      expect(state.missedDays?.nextDayBudget, const Duration(minutes: 25));
      expect(state.missedDays?.missedDayCount, 1);
    });

    test('the catch-up offer is scoped to the plan AND its revision', () {
      final first = buildPlan(revisionId: 'revision.1');
      final second = buildPlan(revisionId: 'revision.2');

      expect(
        TodayPlanController.catchUpOfferKey(first),
        isNot(TodayPlanController.catchUpOfferKey(second)),
      );
      expect(
        TodayPlanController.catchUpOfferKey(first),
        TodayPlanController.catchUpOfferKey(buildPlan()),
      );
    });

    test('the default log forgets nothing WITHIN one controller', () async {
      final controller = controllerAt19();
      final plan = buildPlan();

      expect(controller.hasOfferedCatchUp(plan), isFalse);
      await controller.markCatchUpOffered(plan);
      expect(controller.hasOfferedCatchUp(plan), isTrue);
      // A different revision is a different offer.
      expect(
        controller.hasOfferedCatchUp(buildPlan(revisionId: 'revision.9')),
        isFalse,
      );
    });
  });
}
