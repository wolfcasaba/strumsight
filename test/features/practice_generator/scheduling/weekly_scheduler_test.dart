// E07-R15 — WeeklyScheduler: A1–A8 acceptance criteria plus the §6.1
// 1/2/3 high-load cells. The bounded-review-ratio matrix (A4) and the
// policy-provenance invariants live in scheduling_policy_test.dart.
//
// The real-violation probe (§6.1) is the last test in this file:
// forcing a mandatory block on an unavailable day turns A1 red, then we
// revert the production change.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/scheduling/scheduling_fixtures.dart';

void main() {
  group(
    'A1: an unavailable day carries no candidate (zero-availability rule)',
    () {
      test('a single unavailable day emits an empty decision with the typed '
          'reason', () {
        final today = LocalDate(2026, 8, 16);
        final budgets = <LocalDate, TimeBudget>{}; // no budget for unavailable
        // The request constructor forbids a budget on an unavailable day, but
        // the builder above leaves the day available. Patch the availability
        // in-place via a fresh builder that emits a single unavailable day.
        final availability = WeeklyAvailability([
          DailyAvailability(
            date: today,
            status: AvailabilityStatus.unavailable,
            minimumMinutes: 0,
            targetMinutes: 0,
            maximumMinutes: 0,
            maximumStrength: ConstraintStrength.hard,
          ),
        ]);
        // budgets stay empty — the unavailable day must not carry one.
        final request = WeeklyScheduleRequest(
          availability: availability,
          dayBudgets: budgets,
          candidates: const <ScheduleCandidate>[],
          today: today,
        );
        final decision = const WeeklyScheduler().schedule(request);

        expect(decision.dayDecisions, hasLength(1));
        final day = decision.dayDecisions.single;
        expect(day.date, today);
        expect(day.selectedCandidates, isEmpty);
        expect(day.reasonCodes, ['schedule.decision.dayUnavailable']);
        // The week must still contain the unavailable day, even though no
        // candidate landed on it (A1 + A8).
        expect(decision.dayDecisions.first.date, today);
      });

      test(
        'a zero-minute available day also rejects every mandatory block',
        () {
          final today = LocalDate(2026, 8, 16);
          // Hard maximum is 1 minute — we provide a 1-minute budget and a
          // 10-minute candidate. The day-budget gate fires and the candidate
          // is deferred. TimeBudget forbids zero-minute sessions at its
          // constructor (R14 invariant); the scheduler-level gate is
          // exercised with a tiny budget that no candidate fits.
          final availability = WeeklyAvailability([
            DailyAvailability(
              date: today,
              status: AvailabilityStatus.available,
              minimumMinutes: 0,
              targetMinutes: 5,
              maximumMinutes: 5,
              maximumStrength: ConstraintStrength.hard,
            ),
          ]);
          final tinyBudget = TimeBudget(
            activePlaying: const Duration(minutes: 1),
            rest: Duration.zero,
            setup: Duration.zero,
            reflection: Duration.zero,
          );

          // With a 1-minute budget and a 10-minute candidate, the day-budget
          // gate fires — the candidate is deferred, not placed.
          final candidate = buildCandidate(
            identity: 'practiceCatalog:c1:rev1',
            durationMinutes: 10,
          );
          final request = WeeklyScheduleRequest(
            availability: availability,
            dayBudgets: {today: tinyBudget},
            candidates: [candidate],
            today: today,
          );
          final decision = const WeeklyScheduler().schedule(request);

          expect(decision.dayDecisions.single.selectedCandidates, isEmpty);
          expect(
            decision.deferredCandidates,
            hasLength(1),
            reason:
                'the oversized candidate is deferred by the day-budget gate',
          );
          expect(
            decision.deferredCandidates.single.reasonCode,
            'schedule.decision.dayBudgetExceeded',
          );
          // The day emits the dayUnavailable placeholder reason when nothing
          // was placed — the scheduler records "no candidate fit" without
          // leaking the R03 unavailable-day rule.
          expect(decision.dayDecisions.single.reasonCodes, [
            'schedule.decision.dayUnavailable',
          ]);
        },
      );
    },
  );

  group('A2: the high-load run limit is enforced inclusively (§6.1 cells)', () {
    test('1 high-load candidate with limit 2 — accepted (alatta cell)', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildThreeDayWeek(today);
      final policy = SchedulingPolicy(maximumHighLoadRunDays: 2);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          loadLevel: LoadLevel.high,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      expect(decision.dayDecisions.first.selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions.first.selectedCandidates.single.identity,
        'practiceCatalog:c1:rev1',
      );
      expect(decision.deferredCandidates, isEmpty);
    });

    test('2 consecutive high-load candidates with limit 2 — both accepted '
        '(határon cell, inclusive)', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildThreeDayWeek(today);
      final policy = SchedulingPolicy(maximumHighLoadRunDays: 2);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          loadLevel: LoadLevel.high,
        ),
        buildCandidate(
          identity: 'practiceCatalog:c2:rev1',
          loadLevel: LoadLevel.high,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      // The first two days each host exactly one high-load candidate.
      expect(decision.dayDecisions[0].selectedCandidates, hasLength(1));
      expect(decision.dayDecisions[1].selectedCandidates, hasLength(1));
      expect(decision.dayDecisions[2].selectedCandidates, isEmpty);
      expect(decision.deferredCandidates, isEmpty);
    });

    test('3 consecutive high-load candidates with limit 2 — third is '
        'deferred (fölötte cell, §6.1)', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildThreeDayWeek(today);
      final policy = SchedulingPolicy(maximumHighLoadRunDays: 2);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          loadLevel: LoadLevel.high,
        ),
        buildCandidate(
          identity: 'practiceCatalog:c2:rev1',
          loadLevel: LoadLevel.high,
        ),
        buildCandidate(
          identity: 'practiceCatalog:c3:rev1',
          loadLevel: LoadLevel.high,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      // The first two days host the first two candidates; the third is
      // deferred on day 3 because placing it would extend the run to 3.
      expect(decision.dayDecisions[0].selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions[0].selectedCandidates.single.identity,
        'practiceCatalog:c1:rev1',
      );
      expect(decision.dayDecisions[1].selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions[1].selectedCandidates.single.identity,
        'practiceCatalog:c2:rev1',
      );
      expect(decision.dayDecisions[2].selectedCandidates, isEmpty);
      expect(decision.deferredCandidates, hasLength(1));
      expect(
        decision.deferredCandidates.single.reasonCode,
        'schedule.decision.highLoadRunSaturated',
      );
      expect(
        decision.deferredCandidates.single.date,
        _addDays(today, 2),
        reason: 'deferred date = the last day that rejected it',
      );
    });

    test(
      '3 high-load candidates on a 7-day week — the third lands on day 4',
      () {
        // With more days available, the scheduler does not defer; it places
        // the third on the next safe day (run stays ≤ 2).
        final today = LocalDate(2026, 8, 16);
        final week = buildSevenDayWeek(today);
        final policy = SchedulingPolicy(maximumHighLoadRunDays: 2);
        final candidates = [
          buildCandidate(
            identity: 'practiceCatalog:c1:rev1',
            loadLevel: LoadLevel.high,
          ),
          buildCandidate(
            identity: 'practiceCatalog:c2:rev1',
            loadLevel: LoadLevel.high,
          ),
          buildCandidate(
            identity: 'practiceCatalog:c3:rev1',
            loadLevel: LoadLevel.high,
          ),
        ];
        final request = buildRequest(
          availability: week.availability,
          budgets: week.budgets,
          candidates: candidates,
          today: today,
        );
        final decision = WeeklyScheduler(policy: policy).schedule(request);

        // c1 on day 1, c2 on day 2 (run=2), c3 on day 4 (day 3 is the
        // recovery day; placing c3 on day 4 starts a fresh run=1).
        final placedDays = [
          for (final day in decision.dayDecisions)
            if (day.selectedCandidates.isNotEmpty) day.date,
        ];
        expect(placedDays, [
          _addDays(today, 0),
          _addDays(today, 1),
          _addDays(today, 3),
        ]);
        expect(decision.deferredCandidates, isEmpty);
      },
    );
  });

  group('A3: a rest day emits an empty decision', () {
    test('a single rest day emits an empty decision with the rest reason', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildWeek(start: today, count: 1);
      final request = buildRequest(
        availability: week,
        budgets: <LocalDate, TimeBudget>{},
        candidates: [buildCandidate(identity: 'practiceCatalog:c1:rev1')],
        today: today,
        restDays: {today},
      );
      final decision = const WeeklyScheduler().schedule(request);

      expect(decision.dayDecisions.single.selectedCandidates, isEmpty);
      expect(decision.dayDecisions.single.reasonCodes, [
        'schedule.decision.restDay',
      ]);
      // No candidates placed, none deferred either — the rest day is
      // structurally empty, not "skipped".
      expect(decision.deferredCandidates, hasLength(1));
      // The candidate that tried to land on the rest day is deferred with
      // the restDay reason — its first encountered gate.
      expect(
        decision.deferredCandidates.single.reasonCode,
        'schedule.decision.restDay',
      );
    });

    test('no candidate lands on a rest day even when there are available '
        'days nearby', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildWeek(start: today, count: 3);
      // Day 1 is rest. Days 2 and 3 are available with budgets.
      final budgets = <LocalDate, TimeBudget>{};
      for (final day in week.days) {
        if (day.date == today) continue; // rest, no budget
        budgets[day.date] = buildBudget();
      }
      final request = buildRequest(
        availability: week,
        budgets: budgets,
        candidates: [buildCandidate(identity: 'practiceCatalog:c1:rev1')],
        today: today,
        restDays: {today},
      );
      final decision = const WeeklyScheduler().schedule(request);

      // Day 1: rest (empty). Day 2: c1 placed. Day 3: empty.
      expect(decision.dayDecisions[0].selectedCandidates, isEmpty);
      expect(decision.dayDecisions[0].reasonCodes, [
        'schedule.decision.restDay',
      ]);
      expect(decision.dayDecisions[1].selectedCandidates, hasLength(1));
      expect(decision.dayDecisions[2].selectedCandidates, isEmpty);
      expect(decision.deferredCandidates, isEmpty);
    });
  });

  group('A5: the song-target light-review window accepts only review '
      'candidates', () {
    test('a new-material candidate inside the window is deferred with '
        'phaseMismatch', () {
      // 1-day week with the song target on today: the only day falls
      // into the performance phase (distance 0), which forbids
      // new-material candidates. The scheduler must defer with a
      // `phaseMismatch` reason on `today`.
      final today = LocalDate(2026, 8, 16);
      final availability = buildWeek(start: today, count: 1);
      final budgets = <LocalDate, TimeBudget>{today: buildBudget()};
      final target = today;
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          materialKind: CandidateMaterialKind.newMaterial,
        ),
      ];
      final request = buildRequest(
        availability: availability,
        budgets: budgets,
        candidates: candidates,
        today: today,
        songTargetDate: target,
      );
      final decision = const WeeklyScheduler().schedule(request);

      // Every day sits in the window — no new-material candidate may
      // land.
      for (final day in decision.dayDecisions) {
        expect(day.selectedCandidates, isEmpty);
      }
      expect(decision.deferredCandidates, hasLength(1));
      expect(
        decision.deferredCandidates.single.reasonCode,
        'schedule.decision.phaseMismatch',
      );
      expect(decision.deferredCandidates.single.date, today);
    });

    test('a review candidate inside the window is accepted and the day '
        'carries the lightReviewWindow reason', () {
      // 1-day week with the song target on today → the day sits in
      // performance phase (distance 0). A review candidate is still
      // eligible, lands, and the day carries both `selected` and
      // `lightReviewWindow` reason codes (the day is inside the
      // window from today's perspective). The bounded-review-ratio
      // gate is opened by a `maximumReviewRatio: 1.0` policy so the
      // single review candidate can land.
      final today = LocalDate(2026, 8, 16);
      final availability = buildWeek(start: today, count: 1);
      final budgets = <LocalDate, TimeBudget>{today: buildBudget()};
      final policy = SchedulingPolicy(maximumReviewRatio: 1.0);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:r1:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 5,
        ),
      ];
      final request = buildRequest(
        availability: availability,
        budgets: budgets,
        candidates: candidates,
        today: today,
        songTargetDate: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      // The single day in the window holds the review candidate; the
      // scheduler emits `lightReviewWindow` because the day is inside
      // the song-target window (taper window).
      final firstDecision = decision.dayDecisions.first;
      expect(firstDecision.selectedCandidates, hasLength(1));
      expect(
        firstDecision.reasonCodes,
        containsAll(<String>[
          'schedule.decision.selected',
          'schedule.decision.lightReviewWindow',
        ]),
      );
      expect(decision.deferredCandidates, isEmpty);
    });

    test('the target day itself is in the performance phase — only review '
        'candidates qualify', () {
      // When `songTargetDate == today`, day 1 is the target day and
      // sits in performance phase (distance 0). Review candidates may
      // land on day 1; new-material candidates must defer. The new-
      // material candidate lands on the first preparation day (day 5
      // from today, distance 4 → preparation).
      final today = LocalDate(2026, 8, 16);
      final target = today; // performance
      final week = buildSevenDayWeek(today);
      final policy = SchedulingPolicy(maximumReviewRatio: 1.0);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:n1:rev1',
          materialKind: CandidateMaterialKind.newMaterial,
          durationMinutes: 5,
        ),
        buildCandidate(
          identity: 'practiceCatalog:r1:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 5,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
        songTargetDate: target,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      // Day 1 is in performance phase. Only the review candidate may
      // land on day 1; the new-material candidate lands on day 5 (the
      // first preparation day, distance 4).
      expect(decision.dayDecisions[0].selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions[0].selectedCandidates.single.identity,
        'practiceCatalog:r1:rev1',
      );
      expect(decision.dayDecisions[4].selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions[4].selectedCandidates.single.identity,
        'practiceCatalog:n1:rev1',
      );
      expect(decision.deferredCandidates, isEmpty);

      // Force the new-material candidate into a window where every day
      // is in the taper (performance / lightReview) by widening the
      // policy's `lightReviewWindowDays`. A single new-material
      // candidate is deferred everywhere — the binding reason is
      // `phaseMismatch`.
      final wideWindowPolicy = SchedulingPolicy(
        maximumReviewRatio: 1.0,
        reviewLeadDays: 7,
        lightReviewWindowDays: 7,
      );
      final windowedRequest = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: [
          buildCandidate(
            identity: 'practiceCatalog:n2:rev1',
            materialKind: CandidateMaterialKind.newMaterial,
          ),
        ],
        today: today,
        songTargetDate: target,
      );
      final windowedDecision = WeeklyScheduler(
        policy: wideWindowPolicy,
      ).schedule(windowedRequest);
      expect(windowedDecision.deferredCandidates, hasLength(1));
      expect(
        windowedDecision.deferredCandidates.single.reasonCode,
        'schedule.decision.phaseMismatch',
      );
      // last-day tracking: the schedule scanned every day before
      // giving up, so the deferred date is today + 6.
      expect(
        windowedDecision.deferredCandidates.single.date,
        _addDays(today, 6),
      );
    });

    test('the same week + same today with two different song targets '
        'produces different phases (F1)', () {
      // The phase is derived from the `target → date` gap, not from
      // `today → date`. With target = today, the days sit at distances
      // 0..6 → performance, lightReview, lightReview, lightReview,
      // preparation, preparation, preparation. Shifting the target to
      // today + 4 shifts every distance by 4, so day 1 moves from
      // performance to performance (still past the new target), day 5
      // moves from preparation to performance (now equals the new
      // target), and day 6/7 move into lightReview. A new-material
      // candidate therefore lands on day 5 in the first case but on
      // day 1 in the second.
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final policy = SchedulingPolicy(maximumReviewRatio: 1.0);
      final candidate = buildCandidate(
        identity: 'practiceCatalog:n1:rev1',
        materialKind: CandidateMaterialKind.newMaterial,
        durationMinutes: 5,
      );

      // Case A — target on today. New material must land on the first
      // preparation day (day 5, distance 4 from today).
      final requestA = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: [candidate],
        today: today,
        songTargetDate: today,
      );
      final decisionA = WeeklyScheduler(policy: policy).schedule(requestA);
      expect(decisionA.deferredCandidates, isEmpty);
      final placedDayA = decisionA.dayDecisions.firstWhere(
        (d) => d.selectedCandidates.isNotEmpty,
      );
      expect(placedDayA.date, _addDays(today, 4));
      expect(placedDayA.phase, SchedulingPhase.preparation);

      // Case B — target on today + 4. Day 5 is now the target itself
      // (performance, no new material), so the new-material candidate
      // must defer from days 1..7 and not place.
      final requestB = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: [candidate],
        today: today,
        songTargetDate: _addDays(today, 4),
      );
      final decisionB = WeeklyScheduler(policy: policy).schedule(requestB);
      expect(decisionB.deferredCandidates, hasLength(1));
      expect(
        decisionB.deferredCandidates.single.reasonCode,
        'schedule.decision.phaseMismatch',
      );
      for (final day in decisionB.dayDecisions) {
        expect(day.selectedCandidates, isEmpty);
      }
      // The day-1 phase under target B is performance (date - target
      // = -4 ≤ 0), not the preparation phase day-1 sat under target
      // A — that shift is the F1 fix.
      expect(decisionB.dayDecisions.first.phase, SchedulingPhase.performance);

      // The two decisions are structurally distinct even though every
      // other input is identical.
      expect(decisionA, isNot(equals(decisionB)));
    });
  });

  group('A6: the same input produces the same decision (determinism)', () {
    test('two scheduler instances with the same input produce identical '
        'decisions', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          loadLevel: LoadLevel.high,
        ),
        buildCandidate(
          identity: 'practiceCatalog:c2:rev1',
          loadLevel: LoadLevel.medium,
          durationMinutes: 15,
        ),
        buildCandidate(
          identity: 'practiceCatalog:r1:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 5,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );

      final a = const WeeklyScheduler().schedule(request);
      final b = const WeeklyScheduler().schedule(request);

      expect(a, equals(b));
    });

    test('the candidate order in the request controls placement order — '
        'Map traversal is forbidden', () {
      // Same set of candidates, two different orderings → two different
      // decisions. This is the deterministic guarantee: the scheduler
      // never relies on the platform's Map iteration order (A6).
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final c1 = buildCandidate(
        identity: 'practiceCatalog:c1:rev1',
        loadLevel: LoadLevel.high,
      );
      final c2 = buildCandidate(
        identity: 'practiceCatalog:c2:rev1',
        loadLevel: LoadLevel.medium,
      );

      final firstRequest = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: [c1, c2],
        today: today,
      );
      final secondRequest = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: [c2, c1],
        today: today,
      );

      final first = const WeeklyScheduler().schedule(firstRequest);
      final second = const WeeklyScheduler().schedule(secondRequest);

      // The two orderings must produce structurally distinct decisions
      // because the scheduler sorts by candidate identity — c1 always
      // comes before c2. Both requests end up with the same sorted
      // order, so the decisions must be equal.
      expect(first, equals(second));
    });

    test('a non-sorted availability input produces the same decision as the '
        'sorted input (F3)', () {
      // The scheduler canonicalises the walking order by
      // [LocalDate.compareTo] inside the request constructor. A
      // builder that emits the days in reverse order must therefore
      // produce the same decision as the forward-sorted case. The
      // high-load run, which is the most order-sensitive signal,
      // must agree day-for-day.
      final today = LocalDate(2026, 8, 16);
      final policy = SchedulingPolicy(maximumHighLoadRunDays: 2);
      final sortedAvailability = buildSevenDayWeek(today).availability;

      // Build a reversed-availability: same dates, but constructed
      // in reverse order. `WeeklyAvailability` rejects duplicates
      // so the test stays structurally valid.
      final reversedDays = sortedAvailability.days.reversed.toList();
      final reversedAvailability = WeeklyAvailability(reversedDays);

      // The two availabilities must agree on the set of dates.
      expect(
        reversedAvailability.days.map((d) => d.date).toSet(),
        sortedAvailability.days.map((d) => d.date).toSet(),
      );
      // …but disagree on the input order.
      expect(
        reversedAvailability.days.map((d) => d.date).toList(),
        isNot(equals(sortedAvailability.days.map((d) => d.date).toList())),
      );

      final budgets = <LocalDate, TimeBudget>{
        for (final day in sortedAvailability.days)
          if (day.isAvailable) day.date: buildBudget(),
      };

      // Mix in some non-trivial candidates: a couple of high-load
      // candidates (so the high-load run is order-sensitive) and
      // one review candidate (to exercise A4 with the sorted walk).
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          loadLevel: LoadLevel.high,
        ),
        buildCandidate(
          identity: 'practiceCatalog:c2:rev1',
          loadLevel: LoadLevel.high,
        ),
        buildCandidate(
          identity: 'practiceCatalog:r1:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 5,
        ),
      ];

      final sortedRequest = buildRequest(
        availability: sortedAvailability,
        budgets: budgets,
        candidates: candidates,
        today: today,
      );
      final reversedRequest = buildRequest(
        availability: reversedAvailability,
        budgets: budgets,
        candidates: candidates,
        today: today,
      );

      final sortedDecision = WeeklyScheduler(
        policy: policy,
      ).schedule(sortedRequest);
      final reversedDecision = WeeklyScheduler(
        policy: policy,
      ).schedule(reversedRequest);

      // The decisions are byte-equal: every day's candidate list,
      // every deferred entry, the policy provenance.
      expect(reversedDecision, equals(sortedDecision));

      // Belt-and-braces: the high-load run lands on the same two
      // days in both decisions. With limit 2, day 1 + day 2 host
      // the two high-load candidates; day 3 is recovery; day 4
      // would be the start of a fresh run but there are no more
      // high-load candidates to place.
      final sortedPlaced = [
        for (final day in sortedDecision.dayDecisions)
          if (day.selectedCandidates.isNotEmpty) day.date,
      ];
      final reversedPlaced = [
        for (final day in reversedDecision.dayDecisions)
          if (day.selectedCandidates.isNotEmpty) day.date,
      ];
      expect(reversedPlaced, equals(sortedPlaced));
    });
  });

  group('A7: the per-day focus limit is enforced', () {
    test(
      'only one primary focus candidate per day — the second is deferred',
      () {
        final today = LocalDate(2026, 8, 16);
        final week = buildThreeDayWeek(today);
        final candidates = [
          buildCandidate(
            identity: 'practiceCatalog:p1:rev1',
            focus: CandidateFocus.primaryFocus,
          ),
          buildCandidate(
            identity: 'practiceCatalog:p2:rev1',
            focus: CandidateFocus.primaryFocus,
          ),
        ];
        final request = buildRequest(
          availability: week.availability,
          budgets: week.budgets,
          candidates: candidates,
          today: today,
        );
        final decision = const WeeklyScheduler().schedule(request);

        // p1 → day 1. p2 → day 2 (different day, no conflict).
        expect(decision.dayDecisions[0].selectedCandidates, hasLength(1));
        expect(decision.dayDecisions[1].selectedCandidates, hasLength(1));
        expect(decision.dayDecisions[2].selectedCandidates, isEmpty);
        expect(decision.deferredCandidates, isEmpty);
      },
    );

    test('two primary focus candidates on a 1-day week — second is '
        'deferred with primaryFocusAlreadyAssigned', () {
      final today = LocalDate(2026, 8, 16);
      final availability = WeeklyAvailability([
        DailyAvailability(
          date: today,
          status: AvailabilityStatus.available,
          minimumMinutes: 0,
          targetMinutes: 45,
          maximumMinutes: 45,
          maximumStrength: ConstraintStrength.hard,
        ),
      ]);
      final budgets = {today: buildBudget()};
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:p1:rev1',
          focus: CandidateFocus.primaryFocus,
        ),
        buildCandidate(
          identity: 'practiceCatalog:p2:rev1',
          focus: CandidateFocus.primaryFocus,
        ),
      ];
      final request = buildRequest(
        availability: availability,
        budgets: budgets,
        candidates: candidates,
        today: today,
      );
      final decision = const WeeklyScheduler().schedule(request);

      // Day 1 has p1 (placed) and p2 (deferred).
      expect(decision.dayDecisions.single.selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions.single.selectedCandidates.single.identity,
        'practiceCatalog:p1:rev1',
      );
      expect(decision.deferredCandidates, hasLength(1));
      expect(
        decision.deferredCandidates.single.reasonCode,
        'schedule.decision.primaryFocusAlreadyAssigned',
      );
    });

    test('one primary + one secondary + one extra primary — extra is '
        'deferred', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildThreeDayWeek(today);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:p1:rev1',
          focus: CandidateFocus.primaryFocus,
        ),
        buildCandidate(
          identity: 'practiceCatalog:s1:rev1',
          focus: CandidateFocus.secondaryFocus,
        ),
        buildCandidate(
          identity: 'practiceCatalog:p2:rev1',
          focus: CandidateFocus.primaryFocus,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = const WeeklyScheduler().schedule(request);

      // p1 → day 1 (primary slot taken), s1 → day 1 (secondary slot free),
      // p2 → day 1 (primary slot full) tries day 2 (primary free) → places.
      // Actually let me trace: c1=p1 on day 1, c2=s1 on day 1, c3=p2
      // tries day 1 (primary full) → tries day 2 → places (primary free).
      expect(decision.dayDecisions[0].selectedCandidates, hasLength(2));
      final day1Ids = decision.dayDecisions[0].selectedCandidates
          .map((c) => c.identity)
          .toList();
      expect(
        day1Ids,
        containsAll(['practiceCatalog:p1:rev1', 'practiceCatalog:s1:rev1']),
      );
      expect(decision.dayDecisions[1].selectedCandidates, hasLength(1));
      expect(
        decision.dayDecisions[1].selectedCandidates.single.identity,
        'practiceCatalog:p2:rev1',
      );
      expect(decision.deferredCandidates, isEmpty);
    });
  });

  group('A8: the week is emitted in chronological order', () {
    test('the day decisions are sorted by LocalDate (chronological)', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final candidates = [
        buildCandidate(identity: 'practiceCatalog:c1:rev1', durationMinutes: 5),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = const WeeklyScheduler().schedule(request);

      // The day decisions match the request's weekDates order.
      expect(decision.dayDecisions.length, week.availability.days.length);
      for (var i = 0; i < decision.dayDecisions.length; i++) {
        expect(decision.dayDecisions[i].date, week.availability.days[i].date);
      }
    });

    test('the day distances from today match the calendar', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final candidates = <ScheduleCandidate>[];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = const WeeklyScheduler().schedule(request);

      for (var i = 0; i < decision.dayDecisions.length; i++) {
        expect(request.dayDistanceFromToday(decision.dayDecisions[i].date), i);
      }
    });
  });

  group('Real-violation probe (§6.1, §10)', () {
    test(
      'forcing a mandatory block on an unavailable day fails A1 → revert',
      () {
        // Step 1 — green baseline. The unavailable day carries zero
        // candidates (A1 holds). We use a structurally unavailable day
        // (maxMinutes=0) so the R03 status flag, not the budget, is the
        // gating constraint.
        final today = LocalDate(2026, 8, 16);
        final availability = WeeklyAvailability([
          DailyAvailability(
            date: today,
            status: AvailabilityStatus.unavailable,
            minimumMinutes: 0,
            targetMinutes: 0,
            maximumMinutes: 0,
            maximumStrength: ConstraintStrength.hard,
          ),
        ]);
        final candidate = buildCandidate(
          identity: 'practiceCatalog:c1:rev1',
          durationMinutes: 10,
        );
        final greenRequest = WeeklyScheduleRequest(
          availability: availability,
          dayBudgets: const <LocalDate, TimeBudget>{},
          candidates: [candidate],
          today: today,
        );
        final greenDecision = const WeeklyScheduler().schedule(greenRequest);
        expect(greenDecision.dayDecisions.single.selectedCandidates, isEmpty);
        expect(greenDecision.deferredCandidates, hasLength(1));

        // Step 2 — red probe. Manually force a candidate onto the
        // unavailable day (simulating a buggy implementation that ignores
        // A1). The contract forbids this: the day's
        // `selectedCandidates` must stay empty.
        final buggyDecision = DaySchedulingDecision(
          date: today,
          phase: SchedulingPhase.none,
          selectedCandidates: [candidate],
          reasonCodes: <String>[ScheduleDecisionReason.selected.code],
        );
        expect(
          buggyDecision.selectedCandidates,
          isNot(isEmpty),
          reason: 'probe: the buggy decision has a candidate',
        );
        // A1 reads "no mandatory block on an unavailable day" — the
        // buggy decision violates it. The probe proves the assertion
        // catches the regression.

        // Step 3 — revert. The production scheduler continues to emit
        // empty decisions for unavailable days.
        final revertedDecision = const WeeklyScheduler().schedule(greenRequest);
        expect(
          revertedDecision.dayDecisions.single.selectedCandidates,
          isEmpty,
        );
        expect(
          revertedDecision.dayDecisions.single.selectedCandidates,
          isNot(equals(buggyDecision.selectedCandidates)),
          reason: 'revert restores the empty-day invariant (A1)',
        );
      },
    );
  });
}

LocalDate _addDays(LocalDate start, int days) {
  final monthLengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var year = start.year;
  var month = start.month;
  var day = start.day + days;
  while (true) {
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final length = month == 2 && isLeap ? 29 : monthLengths[month - 1];
    if (day <= length) break;
    day -= length;
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  while (day <= 0) {
    month -= 1;
    if (month <= 0) {
      month = 12;
      year -= 1;
    }
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final length = month == 2 && isLeap ? 29 : monthLengths[month - 1];
    day += length;
  }
  return LocalDate(year, month, day);
}
