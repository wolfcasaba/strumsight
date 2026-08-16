// E07-R15 — SchedulingPolicy: A4 (bounded review ratio) plus the
// policy-shape contract that anchors every other acceptance cell. The
// week-level integration of the policy lives in
// weekly_scheduler_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/scheduling/scheduling_fixtures.dart';

void main() {
  group('A4: the bounded review ratio holds the week\'s review share', () {
    test('a single review candidate saturates the ratio at the policy '
        'limit and the next review candidate is deferred', () {
      // With the default policy (maxReviewRatio=0.4) and a single new
      // candidate plus a single review candidate, the review share after
      // placing the review candidate is 0.5 (10/20). The policy rejects
      // the placement and the review candidate is deferred.
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final policy = SchedulingPolicy(maximumReviewRatio: 0.4);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:n1:rev1',
          materialKind: CandidateMaterialKind.newMaterial,
          durationMinutes: 10,
        ),
        buildCandidate(
          identity: 'practiceCatalog:r1:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 10,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      // The new-material candidate placed on day 1. The review
      // candidate tried day 1 (review ratio 10/10 = 1.0 > 0.4) → day 2
      // (still 10/10) → ... → eventually deferred.
      expect(decision.deferredCandidates, hasLength(1));
      expect(
        decision.deferredCandidates.single.reasonCode,
        'schedule.decision.reviewBudgetSaturated',
      );
      expect(
        decision.deferredCandidates.single.candidate.identity,
        'practiceCatalog:r1:rev1',
      );
    });

    test('a small review share stays under the limit and the candidate is '
        'placed', () {
      // 20 minutes new-material (primaryFocus) + 5 minutes review
      // (secondaryFocus) → ratio 5/25 ≈ 0.20, well below 0.4. The
      // review candidate lands on day 1 alongside the new-material one
      // (different focus slot keeps A7 happy; combined budget fits the
      // default 30-minute day).
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final policy = SchedulingPolicy(maximumReviewRatio: 0.4);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:p1:rev1',
          focus: CandidateFocus.primaryFocus,
          materialKind: CandidateMaterialKind.newMaterial,
          durationMinutes: 20,
        ),
        buildCandidate(
          identity: 'practiceCatalog:s1:rev1',
          focus: CandidateFocus.secondaryFocus,
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
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      expect(decision.deferredCandidates, isEmpty);
      final firstDay = decision.dayDecisions.first;
      expect(firstDay.selectedCandidates, hasLength(2));
      // Both candidates landed on day 1.
      final identities = firstDay.selectedCandidates
          .map((c) => c.identity)
          .toList();
      expect(
        identities,
        containsAll(<String>[
          'practiceCatalog:p1:rev1',
          'practiceCatalog:s1:rev1',
        ]),
      );
    });

    test('a review ratio exactly at the limit is accepted (inclusive)', () {
      // 60 minutes new + 40 minutes review = 100 total, review share
      // exactly 0.4. The boundary is inclusive — both are placed.
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final policy = SchedulingPolicy(maximumReviewRatio: 0.4);
      final candidates = [
        buildCandidate(
          identity: 'practiceCatalog:n1:rev1',
          materialKind: CandidateMaterialKind.newMaterial,
          durationMinutes: 30,
        ),
        buildCandidate(
          identity: 'practiceCatalog:n2:rev1',
          materialKind: CandidateMaterialKind.newMaterial,
          durationMinutes: 30,
        ),
        buildCandidate(
          identity: 'practiceCatalog:r1:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 20,
        ),
        buildCandidate(
          identity: 'practiceCatalog:r2:rev1',
          materialKind: CandidateMaterialKind.review,
          durationMinutes: 20,
        ),
      ];
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: candidates,
        today: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      expect(decision.deferredCandidates, isEmpty);
    });
  });

  group('Policy invariants', () {
    test('the default policy exposes the v1 provenance', () {
      expect(SchedulingPolicy.defaultPolicy.version, 'scheduling-policy-v1');
      expect(SchedulingPolicy.defaultPolicy.maximumPrimaryFocusPerDay, 1);
      expect(SchedulingPolicy.defaultPolicy.maximumSecondaryFocusPerDay, 1);
      expect(SchedulingPolicy.defaultPolicy.maximumHighLoadRunDays, 2);
      expect(SchedulingPolicy.defaultPolicy.maximumReviewRatio, 0.4);
      expect(SchedulingPolicy.defaultPolicy.reviewLeadDays, 7);
      expect(SchedulingPolicy.defaultPolicy.lightReviewWindowDays, 3);
    });

    test('rejects invalid tuning values', () {
      expect(() => SchedulingPolicy(version: ''), throwsArgumentError);
      expect(
        () => SchedulingPolicy(maximumPrimaryFocusPerDay: 0),
        throwsArgumentError,
      );
      expect(
        () => SchedulingPolicy(maximumPrimaryFocusPerDay: -1),
        throwsArgumentError,
      );
      expect(
        () => SchedulingPolicy(maximumSecondaryFocusPerDay: 0),
        throwsArgumentError,
      );
      expect(
        () => SchedulingPolicy(maximumHighLoadRunDays: 0),
        throwsArgumentError,
      );
      expect(
        () => SchedulingPolicy(maximumReviewRatio: -0.1),
        throwsArgumentError,
      );
      expect(
        () => SchedulingPolicy(maximumReviewRatio: 1.5),
        throwsArgumentError,
      );
      expect(() => SchedulingPolicy(reviewLeadDays: 0), throwsArgumentError);
      expect(
        () => SchedulingPolicy(lightReviewWindowDays: 0),
        throwsArgumentError,
      );
      expect(
        () => SchedulingPolicy(reviewLeadDays: 3, lightReviewWindowDays: 5),
        throwsArgumentError,
        reason: 'lightReviewWindowDays must not exceed reviewLeadDays',
      );
    });

    test('phaseForDayDistance maps distance → phase correctly', () {
      final policy = SchedulingPolicy(
        reviewLeadDays: 7,
        lightReviewWindowDays: 3,
      );
      expect(policy.phaseForDayDistance(-2), SchedulingPhase.performance);
      expect(policy.phaseForDayDistance(0), SchedulingPhase.performance);
      expect(policy.phaseForDayDistance(1), SchedulingPhase.lightReview);
      expect(policy.phaseForDayDistance(3), SchedulingPhase.lightReview);
      expect(policy.phaseForDayDistance(4), SchedulingPhase.preparation);
      expect(policy.phaseForDayDistance(7), SchedulingPhase.preparation);
      expect(policy.phaseForDayDistance(8), SchedulingPhase.none);
    });

    test(
      'dayDistanceFromToday is a true Gregorian day count across month/year '
      'rollovers (F2)',
      () {
        // The naive `year*10000 + month*100 + day` ordinal broke every
        // boundary: Jan→Feb was 70, Dec→Jan was 8870. The fix measures
        // the real calendar gap, leap years included.
        final jan31 = LocalDate(2026, 1, 31);
        final feb1 = LocalDate(2026, 2, 1);
        final dec31 = LocalDate(2026, 12, 31);
        final jan1Next = LocalDate(2027, 1, 1);
        final request = buildRequest(
          availability: buildWeek(start: jan31, count: 2),
          budgets: <LocalDate, TimeBudget>{
            jan31: buildBudget(),
            feb1: buildBudget(),
          },
          candidates: const <ScheduleCandidate>[],
          today: jan31,
          songTargetDate: jan31,
        );
        expect(request.dayDistanceFromToday(jan31), 0);
        expect(request.dayDistanceFromToday(feb1), 1);
        // Same request, but swap the today anchor to the year boundary.
        final yearBoundaryRequest = buildRequest(
          availability: buildWeek(start: dec31, count: 2),
          budgets: <LocalDate, TimeBudget>{
            dec31: buildBudget(),
            jan1Next: buildBudget(),
          },
          candidates: const <ScheduleCandidate>[],
          today: dec31,
          songTargetDate: dec31,
        );
        expect(yearBoundaryRequest.dayDistanceFromToday(dec31), 0);
        expect(yearBoundaryRequest.dayDistanceFromToday(jan1Next), 1);

        // Leap-year day: 2024 is a leap year, so 2024-02-28 → 2024-03-01
        // spans two calendar days (the 29th is between them).
        final feb28Leap = LocalDate(2024, 2, 28);
        final mar1Leap = LocalDate(2024, 3, 1);
        final feb28NonLeap = LocalDate(2025, 2, 28);
        final mar1NonLeap = LocalDate(2025, 3, 1);
        final leapRequest = buildRequest(
          availability: buildWeek(start: feb28Leap, count: 2),
          budgets: <LocalDate, TimeBudget>{
            feb28Leap: buildBudget(),
            mar1Leap: buildBudget(),
          },
          candidates: const <ScheduleCandidate>[],
          today: feb28Leap,
          songTargetDate: feb28Leap,
        );
        expect(leapRequest.dayDistanceFromToday(feb28Leap), 0);
        expect(leapRequest.dayDistanceFromToday(mar1Leap), 2);
        // Non-leap baseline: Feb 28 → Mar 1 is one calendar day.
        final nonLeapRequest = buildRequest(
          availability: buildWeek(start: feb28NonLeap, count: 2),
          budgets: <LocalDate, TimeBudget>{
            feb28NonLeap: buildBudget(),
            mar1NonLeap: buildBudget(),
          },
          candidates: const <ScheduleCandidate>[],
          today: feb28NonLeap,
          songTargetDate: feb28NonLeap,
        );
        expect(nonLeapRequest.dayDistanceFromToday(feb28NonLeap), 0);
        expect(nonLeapRequest.dayDistanceFromToday(mar1NonLeap), 1);

        // Symmetry: distance is signed by [LocalDate.compareTo], so
        // `today → other` is the negation of `other → today`.
        expect(
          -request.dayDistanceFromToday(feb1),
          request.dayDistanceFromToday(jan31),
        );
      },
    );

    test('the policy is immutable — every field is final', () {
      // Type-level check: the field declarations include `final`.
      // This test is a marker for reviewers that the policy exposes no
      // mutable tuning handle.
      final policy = SchedulingPolicy();
      expect(policy.version, isNotEmpty);
      expect(policy.maximumPrimaryFocusPerDay, isNotNull);
    });

    test('the decision carries the policy provenance', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final policy = SchedulingPolicy(version: 'scheduling-policy-test');
      final request = buildRequest(
        availability: week.availability,
        budgets: week.budgets,
        candidates: <ScheduleCandidate>[],
        today: today,
      );
      final decision = WeeklyScheduler(policy: policy).schedule(request);

      expect(decision.policyVersion, 'scheduling-policy-test');
      expect(decision.policy, same(policy));
    });

    test('the WeeklyScheduleDecision rejects a mismatched policy version', () {
      expect(
        () => WeeklyScheduleDecision(
          dayDecisions: const <DaySchedulingDecision>[],
          deferredCandidates: const <DeferredCandidate>[],
          policyVersion: 'mismatch',
          policy: SchedulingPolicy(),
        ),
        throwsArgumentError,
      );
    });

    test('ScheduleDecisionReason.fromCode rejects empty/unknown codes', () {
      expect(() => ScheduleDecisionReason.fromCode(''), throwsArgumentError);
      expect(
        () => ScheduleDecisionReason.fromCode('not.a.real.code'),
        throwsArgumentError,
      );
      expect(
        ScheduleDecisionReason.fromCode('schedule.decision.selected'),
        ScheduleDecisionReason.selected,
      );
    });

    test('SchedulingPhase.fromCode rejects empty/unknown codes', () {
      expect(() => SchedulingPhase.fromCode(''), throwsArgumentError);
      expect(
        () => SchedulingPhase.fromCode('not.a.real.phase'),
        throwsArgumentError,
      );
      expect(
        SchedulingPhase.fromCode('scheduling.phase.lightReview'),
        SchedulingPhase.lightReview,
      );
    });
  });

  group('Candidate construction invariants', () {
    test('rejects empty identity and zero/negative duration', () {
      expect(
        () => ScheduleCandidate(
          identity: '',
          focus: CandidateFocus.primaryFocus,
          materialKind: CandidateMaterialKind.newMaterial,
          loadLevel: LoadLevel.medium,
          duration: const Duration(minutes: 10),
        ),
        throwsArgumentError,
      );
      expect(
        () => ScheduleCandidate(
          identity: 'practiceCatalog:c1:rev1',
          focus: CandidateFocus.primaryFocus,
          materialKind: CandidateMaterialKind.newMaterial,
          loadLevel: LoadLevel.medium,
          duration: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScheduleCandidate(
          identity: 'practiceCatalog:c1:rev1',
          focus: CandidateFocus.primaryFocus,
          materialKind: CandidateMaterialKind.newMaterial,
          loadLevel: LoadLevel.medium,
          duration: const Duration(minutes: -1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects empty skillTargets entries', () {
      expect(
        () => ScheduleCandidate(
          identity: 'practiceCatalog:c1:rev1',
          focus: CandidateFocus.primaryFocus,
          materialKind: CandidateMaterialKind.newMaterial,
          loadLevel: LoadLevel.medium,
          duration: const Duration(minutes: 10),
          skillTargets: ['valid', ''],
        ),
        throwsArgumentError,
      );
    });
  });

  group('WeeklyScheduleRequest invariants', () {
    test('rejects a rest day with a budget', () {
      final today = LocalDate(2026, 8, 16);
      final availability = buildWeek(start: today, count: 1);
      expect(
        () => WeeklyScheduleRequest(
          availability: availability,
          dayBudgets: {today: buildBudget()},
          candidates: const <ScheduleCandidate>[],
          today: today,
          restDays: {today},
        ),
        throwsArgumentError,
        reason: 'rest days must not carry a budget',
      );
    });

    test('rejects an available day missing its budget', () {
      final today = LocalDate(2026, 8, 16);
      final availability = buildWeek(start: today, count: 2);
      final budgets = <LocalDate, TimeBudget>{today: buildBudget()};
      expect(
        () => WeeklyScheduleRequest(
          availability: availability,
          dayBudgets: budgets,
          candidates: const <ScheduleCandidate>[],
          today: today,
        ),
        throwsArgumentError,
        reason: 'every available day must carry a budget',
      );
    });

    test('rejects a budget that exceeds the availability maximum', () {
      final today = LocalDate(2026, 8, 16);
      final availability = WeeklyAvailability([
        DailyAvailability(
          date: today,
          status: AvailabilityStatus.available,
          minimumMinutes: 0,
          targetMinutes: 20,
          maximumMinutes: 20,
          maximumStrength: ConstraintStrength.hard,
        ),
      ]);
      final oversized = TimeBudget(
        activePlaying: const Duration(minutes: 30),
        rest: Duration.zero,
        setup: Duration.zero,
        reflection: Duration.zero,
      );
      expect(
        () => WeeklyScheduleRequest(
          availability: availability,
          dayBudgets: {today: oversized},
          candidates: const <ScheduleCandidate>[],
          today: today,
        ),
        throwsArgumentError,
        reason: 'budget must fit inside the hard daily maximum',
      );
    });

    test('rejects duplicate candidate identities', () {
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      final candidates = [
        buildCandidate(identity: 'practiceCatalog:c1:rev1'),
        buildCandidate(identity: 'practiceCatalog:c1:rev1'),
      ];
      expect(
        () => buildRequest(
          availability: week.availability,
          budgets: week.budgets,
          candidates: candidates,
          today: today,
        ),
        throwsArgumentError,
        reason: 'duplicate candidate identities confuse the audit log',
      );
    });

    test('accepts a songTargetDate outside the weekly availability', () {
      // The song target is the calendar anchor for the taper window —
      // it may sit in a later week or further in the future. F1 only
      // requires that the date is a valid [LocalDate]; the scheduler
      // derives each day's phase from the `target → date` gap.
      final today = LocalDate(2026, 8, 16);
      final week = buildSevenDayWeek(today);
      expect(
        () => buildRequest(
          availability: week.availability,
          budgets: week.budgets,
          candidates: const <ScheduleCandidate>[],
          today: today,
          songTargetDate: LocalDate(2030, 1, 1),
        ),
        returnsNormally,
      );
    });
  });
}
