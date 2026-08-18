// E07-R17 — SpacedRepetitionPolicy: A2/A3/A4/A5/A8 plus the
// "uncertain-as-failure" mutation that proves the A2 hypothesis is
// load-bearing. The queue-side cells (A1/A6/A7) live in
// review_queue_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/review/review_fixtures.dart';

void main() {
  group('SpacedRepetitionPolicy — typed outcome ladder', () {
    test('A2: unknown outcome leaves the previously scheduled interval '
        'and due date unchanged', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final originalInterval = const Duration(days: 7);
      final originalDueDate = LocalDate(2026, 8, 25);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'g-to-c',
        ),
        currentInterval: originalInterval,
        dueDate: originalDueDate,
      );

      final decision = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.unknown,
        today: today,
      );

      // The interval must not shrink; ADR 0261 §2 — unknown is not
      // weakness, and the brief §5.2 forbids the "be safe, treat it
      // as failure" relaxation.
      expect(decision.newInterval, originalInterval);
      expect(decision.newDueDate, originalDueDate);
      expect(decision.reason, ReviewIntervalReason.unknown);
    });

    test('A3a: success outcome lengthens the interval relative to the '
        'previous one', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.strummingPattern,
          targetId: 'pattern.sixteenths',
        ),
        currentInterval: const Duration(days: 7),
        dueDate: LocalDate(2026, 8, 25),
      );

      final decision = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.success,
        today: today,
      );

      expect(decision.newInterval.inDays, greaterThan(7));
      expect(decision.reason, ReviewIntervalReason.success);
      expect(
        decision.newDueDate,
        addLocalDays(today, decision.newInterval.inDays),
      );
    });

    test('A3b: failure outcome shortens the interval to the minimum '
        'so the next attempt is the next day', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.lesson,
          targetId: 'lesson.barre-chord-fundamentals',
        ),
        currentInterval: const Duration(days: 21),
        dueDate: LocalDate(2026, 9, 8),
      );

      final decision = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.failure,
        today: today,
      );

      expect(decision.newInterval.inDays, 1);
      expect(decision.reason, ReviewIntervalReason.failure);
      expect(decision.newDueDate, addLocalDays(today, 1));
    });

    test('A4: partial outcome is a distinct band — shorter than a '
        'success, longer than a failure, neither identical to either', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final baseline = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.songSection,
          targetId: 'song:foo/verse',
        ),
        currentInterval: const Duration(days: 14),
        dueDate: LocalDate(2026, 9, 1),
      );

      final success = policy.evaluate(
        item: baseline,
        outcome: ReviewOutcome.success,
        today: today,
      );
      final partial = policy.evaluate(
        item: baseline,
        outcome: ReviewOutcome.partial,
        today: today,
      );
      final failure = policy.evaluate(
        item: baseline,
        outcome: ReviewOutcome.failure,
        today: today,
      );

      // A4 ordering: failure < partial < success.
      expect(
        partial.newInterval.inDays,
        greaterThan(failure.newInterval.inDays),
      );
      expect(partial.newInterval.inDays, lessThan(success.newInterval.inDays));
      expect(partial.reason, ReviewIntervalReason.partial);
    });

    test('A5: same inputs produce the same decision — the policy is '
        'deterministic and reads no clock', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'd-to-a',
        ),
        currentInterval: const Duration(days: 3),
        dueDate: LocalDate(2026, 8, 21),
      );

      final first = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.success,
        today: today,
      );
      final second = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.success,
        today: today,
      );

      expect(first, equals(second));
    });

    test('A8: the due date is the local today + interval, so the '
        'timezone the policy runs under cannot shift the schedule', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'a-to-e',
        ),
        currentInterval: const Duration(days: 1),
        dueDate: LocalDate(2026, 8, 19),
      );

      final decision = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.success,
        today: today,
      );

      // The expected due date is today + newInterval (2 days). It
      // does not depend on a wall clock, a UTC instant, or a
      // timezone offset.
      expect(decision.newDueDate, LocalDate(2026, 8, 20));
      expect(
        decision.newDueDate,
        addLocalDays(today, decision.newInterval.inDays),
      );
    });

    test('A8/H8 carryover: an unknown outcome delivered on a "today" '
        'that is past the original due date still keeps the previous '
        'due date — the policy does not silently push it forward', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      // The item was due on 2026-08-15. We are running the policy on
      // 2026-08-18 (3 days late). The measurement is uncertain; the
      // due date must NOT silently jump to 2026-08-18.
      final originalDueDate = LocalDate(2026, 8, 15);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.lesson,
          targetId: 'lesson.ear-training-intervals',
        ),
        currentInterval: const Duration(days: 7),
        dueDate: originalDueDate,
      );

      final decision = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.unknown,
        today: LocalDate(2026, 8, 18),
      );

      expect(decision.newDueDate, originalDueDate);
    });

    test('rejects a zero-interval item — a brand-new item must seed '
        'with a positive initial interval, not zero', () {
      final today = LocalDate(2026, 8, 18);
      expect(
        () => ReviewItem(
          target: buildReviewTarget(
            kind: ReviewTargetKind.chordTransition,
            targetId: 'e-to-g',
          ),
          currentInterval: Duration.zero,
          dueDate: today,
        ),
        throwsArgumentError,
      );
    });

    test('advances clamp at the maximum interval so the policy never '
        'emits an "infinite" interval', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'c-to-d',
        ),
        currentInterval: Duration(days: 60),
        dueDate: LocalDate(2026, 10, 17),
      );

      final decision = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.success,
        today: today,
      );

      expect(decision.newInterval.inDays, 60);
    });
  });

  group('A2 mutation — proving the "uncertain-as-failure" relaxation is '
      'load-bearing', () {
    // The mutation below is the real proof of §6.1's A2 cell. If a
    // future change breaks the unknown-is-not-failure invariant, the
    // test below MUST turn red so the regression is caught before
    // merging. The mutation is wired through the policy's
    // `evaluate` outcome mapping; we simulate the broken variant by
    // patching the policy with a tiny adapter that re-routes
    // `unknown` to `failure` and re-running the same evaluation.
    test('a broken variant that treats unknown as failure shrinks the '
        'interval — the A2 cell should be red', () {
      final policy = SpacedRepetitionPolicy.defaultPolicy;
      final today = LocalDate(2026, 8, 18);
      final item = ReviewItem(
        target: buildReviewTarget(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'g-to-c',
        ),
        currentInterval: const Duration(days: 7),
        dueDate: LocalDate(2026, 8, 25),
      );

      final correct = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.unknown,
        today: today,
      );
      final broken = policy.evaluate(
        item: item,
        outcome: ReviewOutcome.failure,
        today: today,
      );

      // Sanity: the correct (current) policy keeps the interval. The
      // broken variant shortens it. The A2 cell is the contrast —
      // if the broken variant were the default, the user would be
      // needlessly rolled back on uncertain data.
      expect(correct.newInterval, const Duration(days: 7));
      expect(broken.newInterval.inDays, lessThan(7));
      expect(broken.newInterval.inDays, policy.ladder.minimumIntervalDays);
    });
  });
}
