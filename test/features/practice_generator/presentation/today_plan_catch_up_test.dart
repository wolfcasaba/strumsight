// R35 (MI-K) — the catch-up explainer's ENTRY POINT.
//
// `CatchUpSheet` (ADR 0269 §5, E07-R27 A8) shipped with zero references in
// `lib/`: the non-shaming explanation of how a missed day is handled existed
// as a widget and as an ARB block, and no shipped surface could open it.
// These cells drive the REAL `MissedDayPolicy` through the REAL
// `TodayPlanController`, so the offer can never disagree with the policy
// that decides what a missed day even is.
//
// Acceptance map:
//   A1 — the offer appears only when the policy counts a missed day, and the
//        screen's gate agrees with a directly-evaluated policy verdict.
//   A2 — a rest day is not a missed day, so it raises no offer (ADR 0269 §2).
//   A3 — the offer opens the real sheet.
//   A4 — offered ONCE per plan revision: the acknowledgement is persisted,
//        so a remount over the same store stays silent, and a fresh store
//        (a different device) offers it again — the violation probe that
//        proves persistence, not luck, is what silences it.
//   A5 — the notice never states a number (no missed count, no streak): the
//        tone rule of ADR 0269 §5 is an acceptance cell, not a style wish.
//   A6 — a failed write is a re-offer, never a crash and never a lie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/practice_generator/data/local/catch_up_notice_store.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

final _today = LocalDate(2026, 8, 19);
DateTime _clock() => DateTime(2026, 8, 19);

final _catchUp = find.byKey(const Key('today-plan-catch-up'));
final _openCatchUp = find.byKey(const Key('today-plan-catch-up-open'));
final _dismissCatchUp = find.byKey(const Key('today-plan-catch-up-dismiss'));
final _sheetTitle = find.byKey(const Key('catch-up-title'));

/// A plan whose 17th is a planned primary-focus day that never happened —
/// the policy's own definition of a missed day — plus today's own day.
AdaptivePracticePlan _planWithMissedDay({String revisionId = 'revision.1'}) {
  return buildPlan(
    revisionId: revisionId,
    days: <PracticeDay>[
      buildDay(id: 'day.17', localDate: LocalDate(2026, 8, 17)),
      buildDay(id: 'day.19', localDate: _today),
    ],
  );
}

/// The same shape, except the 17th is a scheduled REST day: no missed day
/// exists, so nothing may be offered (ADR 0269 §2).
AdaptivePracticePlan _planWithRestDay() {
  return buildPlan(
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
      buildDay(id: 'day.19', localDate: _today),
    ],
  );
}

/// The policy verdict, evaluated directly from the same plan — the cells
/// compare the SCREEN against this, never against a hand-written expectation.
int _policyMissedDayCount(AdaptivePracticePlan plan) {
  final decision = MissedDayPolicy().evaluate(
    MissedDayInput(
      today: _today,
      nextDayBudget: const Duration(minutes: 30),
      observations: <MissedDayObservation>[
        for (final day in plan.days)
          MissedDayObservation(
            localDate: day.localDate,
            status: day.status,
            reasonCodes: day.reasonCodes,
            hasPrimaryFocus: day.blocks.any(
              (block) => block.kind == BlockKind.primaryFocus,
            ),
          ),
      ],
    ),
  );
  return decision.missedDayCount;
}

/// A REAL remount, never a rebuild.
///
/// `pumpWidget` reuses the existing element when the widget type and key
/// match, so a second `pumpWidget(TodayPlanScreen(...))` would keep the
/// SAME `State` — and with it the in-frame acknowledgement flag, which
/// would make the persistence cells below pass for the wrong reason. The
/// empty pump tears the tree down first (the R33 harness lesson).
Future<void> _pump(
  WidgetTester tester,
  TodayPlanController controller,
  AdaptivePracticePlan? plan,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TodayPlanScreen(controller: controller, plan: plan),
    ),
  );
}

void main() {
  group('TodayPlanScreen — the catch-up offer (ADR 0269)', () {
    testWidgets('A1: a missed day raises the offer, and the policy agrees', (
      tester,
    ) async {
      final plan = _planWithMissedDay();
      expect(
        _policyMissedDayCount(plan),
        1,
        reason: 'fixture sanity: the policy itself must count this day',
      );

      await _pump(tester, TodayPlanController(clock: _clock), plan);

      expect(_catchUp, findsOneWidget);
      // The day state is still rendered — the offer is added ABOVE it, it
      // never replaces the screen's own content.
      expect(find.byKey(const Key('today-plan-scheduled')), findsOneWidget);
    });

    testWidgets('A1: no missed day means no offer at all', (tester) async {
      final plan = buildPlan(
        days: <PracticeDay>[buildDay(id: 'day.19', localDate: _today)],
      );
      expect(_policyMissedDayCount(plan), 0);

      await _pump(tester, TodayPlanController(clock: _clock), plan);

      expect(_catchUp, findsNothing);
      expect(find.byKey(const Key('today-plan-scheduled')), findsOneWidget);
    });

    testWidgets('A1: no active plan cannot raise an offer', (tester) async {
      await _pump(tester, TodayPlanController(clock: _clock), null);

      expect(_catchUp, findsNothing);
      expect(find.byKey(const Key('today-plan-empty')), findsOneWidget);
    });

    testWidgets('A2: a scheduled rest day raises no offer', (tester) async {
      final plan = _planWithRestDay();
      expect(
        _policyMissedDayCount(plan),
        0,
        reason: 'ADR 0269 §2: a rest day is a completed day, not a miss',
      );

      await _pump(tester, TodayPlanController(clock: _clock), plan);

      expect(_catchUp, findsNothing);
    });

    testWidgets('A3: the offer opens the real CatchUpSheet', (tester) async {
      await _pump(
        tester,
        TodayPlanController(clock: _clock),
        _planWithMissedDay(),
      );

      expect(_sheetTitle, findsNothing);
      await tester.tap(_openCatchUp);
      await tester.pumpAndSettle();

      expect(_sheetTitle, findsOneWidget);
      // The sheet's five factual rows — the ADR's whole point, reached from
      // a shipped surface for the first time.
      expect(
        find.byKey(const Key('catch-up-row-no-backlog-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('catch-up-row-rest-day-title')),
        findsOneWidget,
      );
    });

    testWidgets('A4: reading the sheet acknowledges the offer', (tester) async {
      final store = InMemoryKeyValueStore();
      final log = StoredCatchUpNoticeLog(keyValueStore: store);
      final plan = _planWithMissedDay();
      await _pump(
        tester,
        TodayPlanController(clock: _clock, catchUpNoticeLog: log),
        plan,
      );

      await tester.tap(_openCatchUp);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catch-up-dismiss')));
      await tester.pumpAndSettle();

      expect(_sheetTitle, findsNothing);
      expect(_catchUp, findsNothing);
      expect(
        log.wasAcknowledged(TodayPlanController.catchUpOfferKey(plan)),
        isTrue,
      );
    });

    testWidgets('A4: "Got it" acknowledges without opening the sheet', (
      tester,
    ) async {
      final log = StoredCatchUpNoticeLog(
        keyValueStore: InMemoryKeyValueStore(),
      );
      await _pump(
        tester,
        TodayPlanController(clock: _clock, catchUpNoticeLog: log),
        _planWithMissedDay(),
      );

      await tester.tap(_dismissCatchUp);
      await tester.pumpAndSettle();

      expect(_catchUp, findsNothing);
      expect(_sheetTitle, findsNothing);
    });

    testWidgets('A4: offered ONCE — a remount over the same store stays '
        'silent, a fresh store offers again', (tester) async {
      final store = InMemoryKeyValueStore();
      final plan = _planWithMissedDay();

      await _pump(
        tester,
        TodayPlanController(
          clock: _clock,
          catchUpNoticeLog: StoredCatchUpNoticeLog(keyValueStore: store),
        ),
        plan,
      );
      await tester.tap(_dismissCatchUp);
      await tester.pumpAndSettle();

      // A brand-new screen AND a brand-new controller — only the persisted
      // log carries the acknowledgement across.
      await _pump(
        tester,
        TodayPlanController(
          clock: _clock,
          catchUpNoticeLog: StoredCatchUpNoticeLog(keyValueStore: store),
        ),
        plan,
      );
      expect(_catchUp, findsNothing);

      // Violation probe: with an EMPTY store the very same plan raises the
      // offer again. Without this the cell above would also pass if the
      // notice had simply been deleted from the screen.
      await _pump(
        tester,
        TodayPlanController(
          clock: _clock,
          catchUpNoticeLog: StoredCatchUpNoticeLog(
            keyValueStore: InMemoryKeyValueStore(),
          ),
        ),
        plan,
      );
      expect(_catchUp, findsOneWidget);
    });

    testWidgets('A4: a NEW plan revision is offered again', (tester) async {
      final store = InMemoryKeyValueStore();
      TodayPlanController controller() => TodayPlanController(
        clock: _clock,
        catchUpNoticeLog: StoredCatchUpNoticeLog(keyValueStore: store),
      );

      await _pump(tester, controller(), _planWithMissedDay());
      await tester.tap(_dismissCatchUp);
      await tester.pumpAndSettle();

      await _pump(
        tester,
        controller(),
        _planWithMissedDay(revisionId: 'revision.2'),
      );

      expect(
        _catchUp,
        findsOneWidget,
        reason:
            'a revision is a new plan state (ADR 0256) — the old '
            'acknowledgement must not silence it',
      );
    });

    testWidgets('A5: the offer never states a number', (tester) async {
      await _pump(
        tester,
        TodayPlanController(clock: _clock),
        _planWithMissedDay(),
      );

      final texts = tester
          .widgetList<Text>(
            find.descendant(of: _catchUp, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .toList(growable: false);
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(
          RegExp(r'\d').hasMatch(text),
          isFalse,
          reason:
              'ADR 0269 §5: the copy may not carry a missed count, a '
              'streak, or any other tally — found "$text"',
        );
      }
    });

    testWidgets('A6: a failing store re-offers instead of crashing', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore()
        ..failingKeys.add(StoredCatchUpNoticeLog.storageKey);
      final log = StoredCatchUpNoticeLog(keyValueStore: store);
      final plan = _planWithMissedDay();

      await _pump(
        tester,
        TodayPlanController(clock: _clock, catchUpNoticeLog: log),
        plan,
      );
      await tester.tap(_dismissCatchUp);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The write did not land, and the log says so instead of pretending.
      expect(log.lastWriteFailure, isNotNull);
      expect(
        log.wasAcknowledged(TodayPlanController.catchUpOfferKey(plan)),
        isFalse,
      );

      // The honest consequence: the next mount offers it once more.
      await _pump(
        tester,
        TodayPlanController(clock: _clock, catchUpNoticeLog: log),
        plan,
      );
      expect(_catchUp, findsOneWidget);
    });
  });
}
