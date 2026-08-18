// E07-R17 — ReviewQueue: A1 (budget cap), A6 (replacementRequired),
// A7 (dedup), plus the constructor-shape contract that anchors the
// other two. The policy-side cells (A2/A3/A4/A5/A8) live in
// spaced_repetition_policy_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/review/review_fixtures.dart';

void main() {
  group('ReviewQueue — bounded review budget (A1)', () {
    test('A1: the selected minutes never exceed the review budget', () {
      final queue = ReviewQueue(totalDailyMinutes: 45, reviewBudgetMinutes: 10);
      final today = LocalDate(2026, 8, 18);
      final candidates = [
        buildSelectableReviewItem(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'g-to-c',
          minutes: 3,
          dueDate: today,
        ),
        buildSelectableReviewItem(
          kind: ReviewTargetKind.strummingPattern,
          targetId: 'pattern.dotted',
          minutes: 3,
          dueDate: today,
        ),
        buildSelectableReviewItem(
          kind: ReviewTargetKind.lesson,
          targetId: 'lesson.barre',
          minutes: 3,
          dueDate: today,
        ),
        buildSelectableReviewItem(
          kind: ReviewTargetKind.songSection,
          targetId: 'song:foo/verse',
          minutes: 3,
          dueDate: today,
        ),
      ];
      final available = <String>{
        for (final c in candidates) c.item.target.dedupKey,
      };

      final decision = queue.select(
        candidates: candidates,
        availableTargetIds: available,
      );

      expect(decision.selectedMinutes, lessThanOrEqualTo(10));
      // 3 + 3 + 3 = 9 fits, the 4th cannot fit (10 - 9 = 1 < 3).
      expect(decision.selected, hasLength(3));
      expect(decision.deferred, hasLength(1));
      // Same due date → order is the deterministic dedupKey order.
      // The 4th candidate sorts last by (`strummingPattern`
      //  >  `songSection`); it is the one that runs out of budget.
      expect(
        decision.deferred.first.item.target.dedupKey,
        'strummingPattern|pattern.dotted',
      );
    });

    test('A1/contract: the review budget must be strictly less than '
        'the total daily minutes — the queue cannot fill the day', () {
      expect(
        () => ReviewQueue(totalDailyMinutes: 30, reviewBudgetMinutes: 30),
        throwsArgumentError,
      );
      expect(
        () => ReviewQueue(totalDailyMinutes: 30, reviewBudgetMinutes: 40),
        throwsArgumentError,
      );
      expect(
        () => ReviewQueue(totalDailyMinutes: 30, reviewBudgetMinutes: -1),
        throwsArgumentError,
      );
    });

    test('A1/contract: a zero review budget is allowed — the queue '
        'defers every candidate', () {
      final queue = ReviewQueue(totalDailyMinutes: 30, reviewBudgetMinutes: 0);
      final today = LocalDate(2026, 8, 18);
      final candidates = [
        buildSelectableReviewItem(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'g-to-c',
          minutes: 5,
          dueDate: today,
        ),
      ];
      final available = <String>{candidates.first.item.target.dedupKey};

      final decision = queue.select(
        candidates: candidates,
        availableTargetIds: available,
      );

      expect(decision.selected, isEmpty);
      expect(decision.deferred, hasLength(1));
    });
  });

  group('ReviewQueue — replacement-required detection (A6)', () {
    test('A6a: a target missing from the current-target set is kept '
        'and flagged, not silently dropped', () {
      final queue = ReviewQueue(totalDailyMinutes: 45, reviewBudgetMinutes: 15);
      final today = LocalDate(2026, 8, 18);
      final candidates = [
        buildSelectableReviewItem(
          kind: ReviewTargetKind.chordTransition,
          targetId: 'g-to-c',
          minutes: 4,
          dueDate: today,
        ),
        buildSelectableReviewItem(
          kind: ReviewTargetKind.lesson,
          targetId: 'lesson.deleted-from-catalog',
          minutes: 5,
          dueDate: today,
        ),
      ];
      // The catalog only knows about the chord transition today.
      final available = <String>{candidates.first.item.target.dedupKey};

      final decision = queue.select(
        candidates: candidates,
        availableTargetIds: available,
      );

      // The missing target is preserved with a typed
      // replacementRequired signal — it is NOT selected, NOT
      // silently dropped, and NOT thrown.
      expect(decision.selected, hasLength(1));
      expect(decision.selected.first.item.target.targetId, 'g-to-c');
      expect(decision.replacementRequired, hasLength(1));
      expect(
        decision.replacementRequired.first.item.target.targetId,
        'lesson.deleted-from-catalog',
      );
      expect(decision.deferred, isEmpty);
    });

    test('A6b: an item whose dedupKey is missing from the catalog is '
        'kept with a replacementRequired signal and does not consume '
        'the daily budget', () {
      final queue = ReviewQueue(totalDailyMinutes: 45, reviewBudgetMinutes: 15);
      final today = LocalDate(2026, 8, 18);
      final present = buildSelectableReviewItem(
        kind: ReviewTargetKind.chordTransition,
        targetId: 'g-to-c',
        minutes: 4,
        dueDate: today,
      );
      final missing = buildSelectableReviewItem(
        kind: ReviewTargetKind.lesson,
        targetId: 'lesson.removed',
        minutes: 5,
        dueDate: today,
      );
      // The catalog only knows about `g-to-c` today.
      final available = <String>{present.item.target.dedupKey};

      final decision = queue.select(
        candidates: [present, missing],
        availableTargetIds: available,
      );

      expect(decision.selected, hasLength(1));
      expect(decision.selected.first.item.target.targetId, 'g-to-c');
      expect(decision.replacementRequired, hasLength(1));
      expect(decision.selectedMinutes, 4);
    });

    test('A6c: the replacement-required item does not consume budget — '
        'the queue treats it as out-of-catalog and never schedules it', () {
      final queue = ReviewQueue(totalDailyMinutes: 45, reviewBudgetMinutes: 5);
      final today = LocalDate(2026, 8, 18);
      final candidates = [
        buildSelectableReviewItem(
          kind: ReviewTargetKind.lesson,
          targetId: 'lesson.removed',
          minutes: 5,
          dueDate: today,
        ),
      ];
      final available = <String>{}; // The catalog is empty.

      final decision = queue.select(
        candidates: candidates,
        availableTargetIds: available,
      );

      expect(decision.selected, isEmpty);
      expect(decision.replacementRequired, hasLength(1));
      expect(decision.selectedMinutes, 0);
    });
  });

  group('ReviewQueue — deduplication on (kind, targetId) (A7)', () {
    test('A7: two candidates with the same target collapse to one '
        'entry in the queue, regardless of arrival order', () {
      final policy = ReviewQueue(
        totalDailyMinutes: 45,
        reviewBudgetMinutes: 10,
      );
      final today = LocalDate(2026, 8, 18);
      final shared = buildSelectableReviewItem(
        kind: ReviewTargetKind.chordTransition,
        targetId: 'g-to-c',
        minutes: 3,
        dueDate: today,
      );
      final alsoShared = buildSelectableReviewItem(
        kind: ReviewTargetKind.chordTransition,
        targetId: 'g-to-c',
        minutes: 5,
        dueDate: today,
      );
      final distinct = buildSelectableReviewItem(
        kind: ReviewTargetKind.lesson,
        targetId: 'lesson.barre',
        minutes: 4,
        dueDate: today,
      );
      final available = <String>{
        shared.item.target.dedupKey,
        distinct.item.target.dedupKey,
      };

      // The first occurrence wins; the queue never emits both.
      final decision = policy.select(
        candidates: [shared, alsoShared, distinct],
        availableTargetIds: available,
      );

      expect(decision.selected, hasLength(2));
      final selectedTargets = decision.selected
          .map((s) => s.item.target.dedupKey)
          .toSet();
      expect(selectedTargets, hasLength(2));
      expect(decision.selected.first.estimatedMinutes, 3);
    });

    test('A7/identity: dedup keys are `(kind, targetId)` — different '
        'kinds with the same targetId are NOT merged', () {
      final policy = ReviewQueue(
        totalDailyMinutes: 45,
        reviewBudgetMinutes: 10,
      );
      final today = LocalDate(2026, 8, 18);
      final asChord = buildSelectableReviewItem(
        kind: ReviewTargetKind.chordTransition,
        targetId: 'shared-id',
        minutes: 3,
        dueDate: today,
      );
      final asLesson = buildSelectableReviewItem(
        kind: ReviewTargetKind.lesson,
        targetId: 'shared-id',
        minutes: 4,
        dueDate: today,
      );
      final available = <String>{
        asChord.item.target.dedupKey,
        asLesson.item.target.dedupKey,
      };

      final decision = policy.select(
        candidates: [asChord, asLesson],
        availableTargetIds: available,
      );

      expect(decision.selected, hasLength(2));
    });

    test('the queue emits a deterministic order — selected, deferred, '
        'and replacement-required all sort by (dueDate, dedupKey)', () {
      final policy = ReviewQueue(totalDailyMinutes: 45, reviewBudgetMinutes: 3);
      final today = LocalDate(2026, 8, 18);
      final lateDue = buildSelectableReviewItem(
        kind: ReviewTargetKind.chordTransition,
        targetId: 'later',
        minutes: 2,
        dueDate: today,
      );
      final earlyDue = buildSelectableReviewItem(
        kind: ReviewTargetKind.chordTransition,
        targetId: 'earlier',
        minutes: 2,
        dueDate: LocalDate(2026, 8, 15),
      );
      final available = <String>{
        lateDue.item.target.dedupKey,
        earlyDue.item.target.dedupKey,
      };

      final decision = policy.select(
        candidates: [lateDue, earlyDue],
        availableTargetIds: available,
      );

      // The earlier-due item is selected first; the later-due item
      // is deferred because the budget is exhausted (3 minutes
      // accommodates 2 of the 4 needed).
      expect(decision.selected, hasLength(1));
      expect(decision.selected.first.item.target.targetId, 'earlier');
      expect(decision.deferred.first.item.target.targetId, 'later');
    });

    test('rejects a candidate whose estimated minutes are negative', () {
      final policy = ReviewQueue(totalDailyMinutes: 45, reviewBudgetMinutes: 5);
      final today = LocalDate(2026, 8, 18);
      final invalid = SelectableReviewItem(
        item: ReviewItem(
          target: buildReviewTarget(
            kind: ReviewTargetKind.chordTransition,
            targetId: 'g-to-c',
          ),
          currentInterval: const Duration(days: 1),
          dueDate: today,
        ),
        estimatedMinutes: -1,
      );

      expect(
        () => policy.select(
          candidates: [invalid],
          availableTargetIds: const <String>{},
        ),
        throwsArgumentError,
      );
    });
  });
}
