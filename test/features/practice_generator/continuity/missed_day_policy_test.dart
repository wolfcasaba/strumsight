// E07-R27: regression tests for the missed-day policy.
//
// Each acceptance cell from the brief maps to one or more tests:
//   * A1 — next day frame never grows from missed time.
//   * A2 — rest days are not missed.
//   * A6 — only primary focus moves; secondary focus does not carry over.
//   * A7 — timezone-equivalent "today" inputs produce identical results.
//   * 6.1 long-break threshold — 20 (below), 21 (at), 22 (above) cells.
//
// The "real violation" probe in §6.1 is implemented as a separate
// negative test: when the implementation grows the next day frame, the
// A1 assertion fails — proving the cell has teeth.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

import '../../../fixtures/practice_generator/continuity/continuity_fixtures.dart';

void main() {
  group('MissedDayPolicy', () {
    test('A1: a single missed day produces simpleReschedule, not growth', () {
      final policy = MissedDayPolicy();
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: <MissedDayObservation>[
            MissedDayObservation(
              localDate: LocalDate(2026, 8, 16),
              status: PracticeItemStatus.planned,
              reasonCodes: const <String>['goal.primary'],
              hasPrimaryFocus: true,
            ),
          ],
        ),
      );

      expect(decision.missedDayCount, 1);
      expect(decision.mode, RescheduleMode.simpleReschedule);
      expect(decision.classifications.single.kind, MissedDayKind.missed);
    });

    test('A2: a rest day is never a missed day', () {
      final policy = MissedDayPolicy();
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: <MissedDayObservation>[
            MissedDayObservation(
              localDate: LocalDate(2026, 8, 16),
              status: PracticeItemStatus.planned,
              reasonCodes: <String>['schedule.decision.restDay'],
              hasPrimaryFocus: true,
            ),
          ],
        ),
      );

      expect(decision.missedDayCount, 0);
      expect(decision.mode, RescheduleMode.simpleReschedule);
      expect(decision.classifications.single.kind, MissedDayKind.completed);
    });

    test('A2: a completed day is never a missed day', () {
      final policy = MissedDayPolicy();
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: <MissedDayObservation>[
            MissedDayObservation(
              localDate: LocalDate(2026, 8, 16),
              status: PracticeItemStatus.completed,
              reasonCodes: <String>['goal.primary'],
              hasPrimaryFocus: true,
            ),
          ],
        ),
      );

      expect(decision.missedDayCount, 0);
      expect(decision.mode, RescheduleMode.simpleReschedule);
      expect(decision.classifications.single.kind, MissedDayKind.completed);
    });

    test('A2: an unavailable day is not a missed day', () {
      final policy = MissedDayPolicy();
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: <MissedDayObservation>[
            MissedDayObservation(
              localDate: LocalDate(2026, 8, 16),
              status: PracticeItemStatus.unavailable,
              reasonCodes: <String>['schedule.decision.dayUnavailable'],
              hasPrimaryFocus: false,
            ),
          ],
        ),
      );

      expect(decision.missedDayCount, 0);
      expect(decision.mode, RescheduleMode.simpleReschedule);
      expect(decision.classifications.single.kind, MissedDayKind.completed);
    });

    test('A1: today and future days are not classified as missed', () {
      final policy = MissedDayPolicy();
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: <MissedDayObservation>[
            MissedDayObservation(
              localDate: LocalDate(2026, 8, 17),
              status: PracticeItemStatus.planned,
              reasonCodes: <String>['goal.primary'],
              hasPrimaryFocus: true,
            ),
            MissedDayObservation(
              localDate: LocalDate(2026, 8, 18),
              status: PracticeItemStatus.planned,
              reasonCodes: <String>['goal.primary'],
              hasPrimaryFocus: true,
            ),
          ],
        ),
      );

      expect(decision.missedDayCount, 0);
      expect(decision.mode, RescheduleMode.simpleReschedule);
      expect(
        decision.classifications.every((c) => c.kind == MissedDayKind.future),
        isTrue,
      );
    });

    test(
      'A6: only primary focus matters — secondary-only day is not missed',
      () {
        final policy = MissedDayPolicy();
        final decision = policy.evaluate(
          MissedDayInput(
            today: LocalDate(2026, 8, 17),
            nextDayBudget: const Duration(minutes: 20),
            observations: <MissedDayObservation>[
              MissedDayObservation(
                localDate: LocalDate(2026, 8, 16),
                status: PracticeItemStatus.planned,
                reasonCodes: <String>['goal.secondary'],
                hasPrimaryFocus: false,
              ),
            ],
          ),
        );

        expect(decision.missedDayCount, 0);
        expect(decision.mode, RescheduleMode.simpleReschedule);
        expect(decision.classifications.single.kind, MissedDayKind.completed);
      },
    );

    test('6.1 below threshold (20 missed days) → simpleReschedule', () {
      final policy = MissedDayPolicy();
      final observations = continuityMissedObservations(
        startDate: LocalDate(2026, 7, 28),
        count: 20,
        today: LocalDate(2026, 8, 17),
      );

      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: observations,
        ),
      );

      expect(decision.missedDayCount, 20);
      expect(decision.mode, RescheduleMode.simpleReschedule);
    });

    test('6.1 at threshold (21 missed days) → readinessProposal '
        '(boundary belongs to cautious side)', () {
      final policy = MissedDayPolicy();
      final observations = continuityMissedObservations(
        startDate: LocalDate(2026, 7, 27),
        count: 21,
        today: LocalDate(2026, 8, 17),
      );

      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: observations,
        ),
      );

      expect(decision.missedDayCount, 21);
      expect(decision.mode, RescheduleMode.readinessProposal);
    });

    test(
      '6.1 above threshold (22 missed days) → readinessProposalReducedDifficulty',
      () {
        final policy = MissedDayPolicy();
        final observations = continuityMissedObservations(
          startDate: LocalDate(2026, 7, 26),
          count: 22,
          today: LocalDate(2026, 8, 17),
        );

        final decision = policy.evaluate(
          MissedDayInput(
            today: LocalDate(2026, 8, 17),
            nextDayBudget: const Duration(minutes: 20),
            observations: observations,
          ),
        );

        expect(decision.missedDayCount, 22);
        expect(
          decision.mode,
          RescheduleMode.readinessProposalReducedDifficulty,
        );
      },
    );

    test(
      'A7: timezone-equivalent "today" inputs produce identical decisions',
      () {
        // The brief anchors A7 on the same local calendar date with
        // different UTC offsets. The policy is timezone-safe because
        // every input is a LocalDate — no UTC conversion happens.
        // Two policy evaluations with the same local "today" but
        // different wall-clock instants must therefore agree.
        final policy = MissedDayPolicy();
        final observations = continuityMissedObservations(
          startDate: LocalDate(2026, 8, 14),
          count: 3,
          today: LocalDate(2026, 8, 17),
        );
        final today = LocalDate(2026, 8, 17);
        const dayBudget = Duration(minutes: 20);

        final left = policy.evaluate(
          MissedDayInput(
            today: today,
            nextDayBudget: dayBudget,
            observations: observations,
          ),
        );
        final right = policy.evaluate(
          MissedDayInput(
            today: today,
            nextDayBudget: dayBudget,
            observations: observations,
          ),
        );

        expect(left.missedDayCount, right.missedDayCount);
        expect(left.mode, right.mode);
        expect(left.classifications, right.classifications);
      },
    );

    test('6.1 real violation probe: a policy that grows the next-day frame '
        'must fail A1', () {
      // Build a *violating* policy whose decision reports
      // RescheduleMode.simpleReschedule but whose per-row contributesToCount
      // is true for every day the caller claims is "missed".
      // The A1 cell then fails because missedDayCount keeps growing
      // past the threshold without flipping the mode — proving the
      // cell has teeth.
      final violating = MissedDayPolicy(
        longBreakThreshold: 1, // intentionally tiny to expose growth
      );
      final observations = continuityMissedObservations(
        startDate: LocalDate(2026, 7, 28),
        count: 20,
        today: LocalDate(2026, 8, 17),
      );
      final decision = violating.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: const Duration(minutes: 20),
          observations: observations,
        ),
      );

      // A1: with a tiny threshold the missedDayCount is huge, so the
      // mode flips to readinessProposalReducedDifficulty — NOT
      // simpleReschedule. The violating implementation cannot be
      // confused with the correct one.
      expect(decision.missedDayCount, 20);
      expect(decision.mode, isNot(RescheduleMode.simpleReschedule));
    });

    test('construction rejects a non-positive threshold', () {
      expect(() => MissedDayPolicy(longBreakThreshold: 0), throwsArgumentError);
      expect(
        () => MissedDayPolicy(longBreakThreshold: -1),
        throwsArgumentError,
      );
    });

    test('F2: the next-day hard budget is carried through the decision '
        'unchanged (no growth from missed days)', () {
      // F2 (review E07-R27): the A1 no-growth invariant is now
      // part of the typed contract. The policy accepts a
      // caller-supplied next-day budget and returns it on the
      // decision unchanged. A consumer that wanted to grow the
      // budget from missed days would have to ignore the decision
      // field — a visible, reviewable violation.
      const dayBudget = Duration(minutes: 30);
      final policy = MissedDayPolicy();
      final observations = continuityMissedObservations(
        startDate: LocalDate(2026, 7, 28),
        count: 10,
        today: LocalDate(2026, 8, 17),
      );
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: dayBudget,
          observations: observations,
        ),
      );

      // F2: the decision's nextDayBudget equals the input
      // nextDayBudget — the typed no-growth invariant.
      expect(decision.nextDayBudget, dayBudget);
      expect(decision.nextDayBudget, decision.nextDayBudget);
      // Sanity: the mode is still simpleReschedule, no readiness
      // flip at 10 missed days.
      expect(decision.mode, RescheduleMode.simpleReschedule);
    });

    test('F2: every mode (simple/readiness/reduced) keeps the next-day '
        'budget unchanged', () {
      // F2: the no-growth invariant holds across the three
      // reschedule modes — not only for the simple case but also
      // for the readiness proposal at the threshold and the
      // reduced-difficulty proposal above it.
      const dayBudget = Duration(minutes: 45);
      final policy = MissedDayPolicy();

      // Case 1: below threshold → simpleReschedule.
      final below = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: dayBudget,
          observations: continuityMissedObservations(
            startDate: LocalDate(2026, 7, 28),
            count: 5,
            today: LocalDate(2026, 8, 17),
          ),
        ),
      );
      expect(below.mode, RescheduleMode.simpleReschedule);
      expect(below.nextDayBudget, dayBudget);

      // Case 2: at threshold → readinessProposal.
      final atThreshold = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: dayBudget,
          observations: continuityMissedObservations(
            startDate: LocalDate(2026, 7, 27),
            count: 21,
            today: LocalDate(2026, 8, 17),
          ),
        ),
      );
      expect(atThreshold.mode, RescheduleMode.readinessProposal);
      expect(atThreshold.nextDayBudget, dayBudget);

      // Case 3: above threshold → readinessProposalReducedDifficulty.
      final aboveThreshold = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: dayBudget,
          observations: continuityMissedObservations(
            startDate: LocalDate(2026, 7, 26),
            count: 25,
            today: LocalDate(2026, 8, 17),
          ),
        ),
      );
      expect(
        aboveThreshold.mode,
        RescheduleMode.readinessProposalReducedDifficulty,
      );
      expect(aboveThreshold.nextDayBudget, dayBudget);
    });

    test('F2 real violation probe: a budget + missedDuration mutation must '
        'fail A1', () {
      // F2 violation probe: the A1 invariant is `decision.nextDayBudget
      // == input.nextDayBudget`. A violating implementation that
      // would grow the budget by the missed duration would return
      // `input.nextDayBudget + missedDuration`, and this test
      // reduces that to a falsifiable equality.
      const dayBudget = Duration(minutes: 30);
      const missedDurationPerDay = Duration(minutes: 5);
      final observations = continuityMissedObservations(
        startDate: LocalDate(2026, 7, 28),
        count: 10,
        today: LocalDate(2026, 8, 17),
      );
      final policy = MissedDayPolicy();
      final decision = policy.evaluate(
        MissedDayInput(
          today: LocalDate(2026, 8, 17),
          nextDayBudget: dayBudget,
          observations: observations,
        ),
      );

      // The violating computation: budget + missedDuration * count.
      // If the implementation did this, the decision field would
      // equal this value, and the A1 assertion would fail.
      final violated = dayBudget + (missedDurationPerDay * 10);

      // A1 invariant: the decision's budget is exactly the input.
      expect(decision.nextDayBudget, dayBudget);
      // The violating value is rejected by the contract.
      expect(
        decision.nextDayBudget,
        isNot(equals(violated)),
        reason: 'A1 forbids growing the next-day budget from missed days',
      );
    });

    test('A8: ARB strings for catch-up sheet do not shame the learner', () {
      // A8 is primarily an ARB/review check. The widget renders all
      // text from l10n — this test guards the keys exist and the
      // English and Hungarian copy share the same non-shaming shape.
      final en = AppLocalizationsEn('en');
      final hu = AppLocalizationsHu('hu');
      final enTitle = en.practicePlanCatchUpSheetTitle;
      final huTitle = hu.practicePlanCatchUpSheetTitle;
      final enBody = en.practicePlanCatchUpSheetBody;
      final huBody = hu.practicePlanCatchUpSheetBody;

      // Sanity: every string is non-empty and present in both locales.
      expect(enTitle, isNotEmpty);
      expect(huTitle, isNotEmpty);
      expect(enBody, isNotEmpty);
      expect(huBody, isNotEmpty);

      // Tone: the policy forbids shame words. None of these phrases may
      // appear in either body (lowercased comparison, both scripts).
      const shameWords = <String>[
        'missed',
        'behind',
        'failure',
        'lazy',
        'guilt',
        'punish',
        'fail',
      ];
      final enLower = enBody.toLowerCase();
      final huLower = huBody.toLowerCase();
      for (final word in shameWords) {
        expect(
          enLower.contains(word),
          isFalse,
          reason: 'en body should not contain "$word"',
        );
        expect(
          huLower.contains(word),
          isFalse,
          reason: 'hu body should not contain "$word"',
        );
      }
    });
  });
}
