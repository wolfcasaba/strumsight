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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/i18n/effective_locale.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/today/data/active_plan_today_plan_repository.dart';
import 'package:strumsight/features/today/domain/today_plan_snapshot.dart';
import 'package:strumsight/features/today/providers/today_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/practice_generator/plan/plan_fixtures.dart' as fixtures;
import '../../support/preference_store.dart';

/// The fixture plan schedules exactly one day: 2026-08-17.
DateTime _onPlanDay() => DateTime(2026, 8, 17, 9);

Future<AdaptivePracticePlan?> _activePlan(Ref ref) async => fixtures.plan();

Future<AdaptivePracticePlan?> _noPlan(Ref ref) async => null;

/// The same corrupt active-plan pointer
/// `practice_generator_providers_test.dart`'s M4 cell uses — a REAL read
/// failure, not a mocked one.
const _corruptPointer = <String, Object>{
  'ss.practice_generator.plan.active_pointer': 'not-json-at-all{{{',
};

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

  group('todayPlanSnapshotProvider reads the real active plan', () {
    test('T1p an activated plan reaches the hub', () async {
      final container = ProviderContainer(
        overrides: [
          ...preferenceOverrides(),
          // The hub's copy now follows the PHONE when no preference is
          // stored (T6), so this cell states the phone's language instead
          // of depending on whatever the test host reports.
          platformLocalesProvider.overrideWithValue(const [Locale('en')]),
          practiceGeneratorClockProvider.overrideWithValue(_onPlanDay),
          activePracticePlanProvider.overrideWith(_activePlan),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activePracticePlanProvider.future);
      final snapshot = container.read(todayPlanSnapshotProvider);

      expect(snapshot.availability, TodayPlanAvailability.ready);
      expect(snapshot.recommendedTaskLabel, 'Primary focus');
      expect(snapshot.totalTaskCount, 1);
    });

    test('T2p no activated plan stays the zero-state', () async {
      final container = ProviderContainer(
        overrides: [
          ...preferenceOverrides(),
          activePracticePlanProvider.overrideWith(_noPlan),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activePracticePlanProvider.future);
      final snapshot = container.read(todayPlanSnapshotProvider);

      expect(snapshot.availability, TodayPlanAvailability.unavailable);
      expect(snapshot.hasPlan, isFalse);
    });

    test('T5 a corrupt plan record is unreadable, never "no plan"', () async {
      final container = ProviderContainer(
        overrides: [...preferenceOverrides(_corruptPointer)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(activePracticePlanProvider.future),
        throwsA(isA<Object>()),
      );
      final snapshot = container.read(todayPlanSnapshotProvider);

      expect(snapshot.availability, TodayPlanAvailability.unreadable);
      expect(snapshot.hasPlan, isFalse);
      expect(snapshot.availability, isNot(TodayPlanAvailability.unavailable));
    });

    test('T6 an unset language preference follows the phone', () async {
      final container = _hubOnHungarianPhone();

      await container.read(activePracticePlanProvider.future);
      final snapshot = container.read(todayPlanSnapshotProvider);

      expect(
        snapshot.recommendedTaskLabel,
        'Elsődleges fókusz',
        reason:
            'MEASURED before the re-audit: a stored `null` (the DEFAULT, '
            'meaning "follow the system") resolved to English, so this hero '
            'read "Primary focus" inside an otherwise Hungarian app',
      );
    });

    test('T7 an explicit preference still wins over the phone', () async {
      final container = _hubOnHungarianPhone(
        preferences: {StorageKeys.locale: 'en'},
      );

      await container.read(activePracticePlanProvider.future);
      final snapshot = container.read(todayPlanSnapshotProvider);

      expect(snapshot.recommendedTaskLabel, 'Primary focus');
    });
  });
}

/// The hub, on a Hungarian phone, with the fixture plan active.
ProviderContainer _hubOnHungarianPhone({Map<String, Object>? preferences}) {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(preferences),
      platformLocalesProvider.overrideWithValue(const [Locale('hu')]),
      practiceGeneratorClockProvider.overrideWithValue(_onPlanDay),
      activePracticePlanProvider.overrideWith(_activePlan),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
