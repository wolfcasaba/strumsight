// R19 (audit M4) — the Today Hub's snapshot comes from the REAL active
// plan.
//
// MEASURED before this round: `todayPlanRepositoryProvider` resolved to
// `UnavailableTodayPlanRepository` and nothing in `lib/` overrode it, so a
// learner who generated AND activated a plan on the practice hub still met
// the "start your first practice" hero on the app's landing tab. The plan
// was real all along (`activePracticePlanProvider`); only the projection
// was missing.
//
//   T1 — a scheduled day names the next block and its real counts,
//   T2 — no plan (and a non-active plan) stays the honest zero-state,
//   T3 — a day with nothing to run says WHY, never "you have no plan",
//   T4 — a completed day reports a full day so the hub can recap,
//   T5 — a plan the store cannot read is `unreadable`, NEVER "no plan"
//        (audit M6: an error must not be reclassified as a fresh start),
//   T6 — with NO stored language preference the hub copy follows the PHONE
//        (re-audit M5: `null` used to mean English, not "follow the
//        system"),
//   T7 — an explicit preference still wins over the phone.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/today/data/active_plan_today_plan_repository.dart';
import 'package:strumsight/features/today/domain/today_plan_snapshot.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/practice_generator/plan/plan_fixtures.dart' as fixtures;

/// The fixture plan schedules exactly one day: 2026-08-17.
DateTime _onPlanDay() => DateTime(2026, 8, 17, 9);

ActivePlanTodayPlanRepository _repository(
  AdaptivePracticePlan? plan, {
  DateTime? now,
}) {
  final reading = now ?? _onPlanDay();
  return ActivePlanTodayPlanRepository(
    controller: TodayPlanController(clock: () => reading),
    plan: plan,
    l10n: lookupAppLocalizations(const Locale('en')),
  );
}

void main() {
  group('the projection of an active plan', () {
    test('T1 a scheduled day names the next block and its counts', () {
      final snapshot = _repository(fixtures.plan()).load();

      expect(snapshot.availability, TodayPlanAvailability.ready);
      expect(snapshot.hasPlan, isTrue);
      expect(snapshot.recommendedTaskLabel, 'Primary focus');
      expect(snapshot.completedTaskCount, 0);
      expect(snapshot.totalTaskCount, 1);
      expect(snapshot.isDayCompleted, isFalse);
    });

    test('T2a no plan is the honest zero-state', () {
      final snapshot = _repository(null).load();

      expect(snapshot.availability, TodayPlanAvailability.unavailable);
      expect(snapshot.hasPlan, isFalse);
    });

    test('T2b a paused plan is not "today\'s plan" either', () {
      final paused = fixtures.plan().copyWith(status: PlanStatus.paused);

      expect(
        _repository(paused).load().availability,
        TodayPlanAvailability.unavailable,
      );
    });

    test('T3a a rest day says why, and still counts as having a plan', () {
      final rest = PracticeDay(
        id: DayId('day.rest'),
        localDate: LocalDate(2026, 8, 17),
        status: PracticeItemStatus.planned,
        timeBudget: const Duration(minutes: 20),
        blocks: const <PracticeBlock>[],
        // A rest day has no blocks, but the model still requires the plan's
        // focus skills to be named (`PracticeDay` rejects an empty list).
        primaryFocusSkillIds: const <String>['rhythm.quarterNotes'],
        reasonCodes: [ScheduleDecisionReason.restDay.code],
      );
      final plan = fixtures.plan().copyWith(days: [rest]);

      final snapshot = _repository(plan).load();

      expect(snapshot.availability, TodayPlanAvailability.ready);
      expect(snapshot.hasPlan, isTrue);
      expect(
        snapshot.recommendedTaskLabel,
        'Rest is part of your plan. There is nothing to catch up on today.',
      );
      expect(snapshot.totalTaskCount, 0);
    });

    test('T3b an unscheduled day says why', () {
      final elsewhere = DateTime(2026, 8, 20, 9);
      final snapshot = _repository(fixtures.plan(), now: elsewhere).load();

      expect(snapshot.availability, TodayPlanAvailability.ready);
      expect(
        snapshot.recommendedTaskLabel,
        'Your active plan has no session for this local calendar day.',
      );
      expect(snapshot.totalTaskCount, 0);
    });

    test('T4 a completed day reports a full day, so the hub recaps', () {
      final done = fixtures.day(status: PracticeItemStatus.completed);
      final plan = fixtures.plan().copyWith(days: [done]);

      final snapshot = _repository(plan).load();

      expect(snapshot.availability, TodayPlanAvailability.ready);
      expect(snapshot.isDayCompleted, isTrue);
      expect(snapshot.recommendedTaskLabel, isNull);
    });
  });

  // The PROVIDER-level cells (T1p/T2p/T5/T6/T7) were retired in the
  // 2026-09-19 integration. `todayPlanRepositoryProvider` on this tree is
  // the `main` line's `CurriculumTodayPlanRepository`: the hub's plan is the
  // curriculum LADDER's next rung, not the practice generator's activated
  // plan, and the two are different products with different zero-states
  // (`test/features/today/today_hub_test.dart` pins the shipped one). The
  // projection this file exists for is still fully measured above — the
  // four groups over `ActivePlanTodayPlanRepository` itself — so the class
  // stays honest for whichever surface binds it next; only the claim about
  // WHICH provider the Today tab reads was removed, because it is no longer
  // true.
}
