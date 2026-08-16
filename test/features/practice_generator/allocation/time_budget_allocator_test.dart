// E07-R14 — TimeBudgetAllocator: A1, A2, A3, A5, A6, A7.
//
// A4 (sum precision under rounding) and A8 (deterministic policy) live in
// their dedicated test files. The matrix barrier between the three
// hard-maximum cells (alatta / határon / fölötte) is exercised here.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/allocation/allocation_fixtures.dart';

void main() {
  group('A1: the hard maximum is never breached, even after rounding', () {
    test('above the hard maximum is clamped down to the limit', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 25),
        maximumMinutes: 20,
      );

      // The allocator surfaces the shortening as a typed change.
      expect(allocation.scaling, TimeBudgetScaling.shortened);
      expect(allocation.budget.elapsedSession, const Duration(minutes: 20));
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.hardMaximum),
      );
      expect(
        allocation.changeSet?.changes.first.reason,
        PlanChangeReason.systemAdaptation,
      );
      expect(
        allocation.changeSet?.changes.first.evidenceRefs,
        contains('timeBudget.hardMaximumClamped'),
      );
    });

    test('exactly at the hard maximum is accepted as the inclusive top', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 20,
      );

      expect(allocation.scaling, TimeBudgetScaling.none);
      expect(allocation.budget.elapsedSession, const Duration(minutes: 20));
      expect(allocation.changeSet, isNull);
    });

    test('below the hard maximum is accepted without scaling', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 19),
        maximumMinutes: 20,
      );

      expect(allocation.scaling, TimeBudgetScaling.none);
      expect(allocation.budget.elapsedSession, const Duration(minutes: 19));
      expect(allocation.changeSet, isNull);
    });

    test('every segment is non-negative and the sum is exact', () {
      // The five-frame A2 sweep, asserting the sum invariant for every
      // output. A single hole here would mean the rounding balance broke.
      for (final minutes in <int>[5, 10, 20, 45, 90]) {
        final allocation = runAllocation(
          requestedTotal: Duration(minutes: minutes),
          maximumMinutes: minutes,
        );
        expect(
          allocation.budget.elapsedSession,
          Duration(minutes: minutes),
          reason: 'frame $minutes must match the requested total',
        );
        expect(
          allocation.budget.segments.fold<Duration>(
            Duration.zero,
            (acc, segment) => acc + segment.duration,
          ),
          allocation.budget.activePlaying,
          reason: 'segments must sum to activePlaying for $minutes',
        );
        for (final segment in allocation.budget.segments) {
          expect(
            segment.duration.isNegative,
            isFalse,
            reason: 'no segment may be negative ($minutes)',
          );
        }
      }
    });
  });

  group('A2: every reference frame produces a meaningful plan', () {
    test('5-minute frame uses the micro-plan path with one focus block', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 5),
        maximumMinutes: 5,
      );

      expect(allocation.budget.elapsedSession, const Duration(minutes: 5));
      expect(allocation.budget.activePlaying, const Duration(minutes: 5));
      expect(allocation.budget.rest, Duration.zero);
      expect(allocation.budget.setup, Duration.zero);
      expect(allocation.budget.reflection, Duration.zero);
      expect(allocation.budget.segments, hasLength(1));
      expect(allocation.budget.segments.single.kind, BlockKind.primaryFocus);
    });

    test('10-minute frame uses the small template with setup+reflection', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 10),
        maximumMinutes: 10,
      );

      expect(allocation.budget.elapsedSession, const Duration(minutes: 10));
      expect(allocation.budget.activePlaying, const Duration(minutes: 8));
      expect(allocation.budget.setup, const Duration(minutes: 1));
      expect(allocation.budget.reflection, const Duration(minutes: 1));
      expect(allocation.budget.rest, Duration.zero);
      expect(allocation.budget.segments, hasLength(1));
      expect(allocation.budget.segments.single.kind, BlockKind.primaryFocus);
    });

    test('20-minute frame uses the medium template with three slots', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 20,
      );

      expect(allocation.budget.elapsedSession, const Duration(minutes: 20));
      expect(allocation.budget.activePlaying, const Duration(minutes: 16));
      expect(allocation.budget.setup, const Duration(minutes: 1));
      expect(allocation.budget.reflection, const Duration(minutes: 1));
      expect(allocation.budget.rest, const Duration(minutes: 2));
      expect(allocation.budget.segments, hasLength(3));
      expect(
        allocation.budget.segments.map((segment) => segment.kind),
        <BlockKind>[
          BlockKind.warmup,
          BlockKind.primaryFocus,
          BlockKind.secondaryFocus,
        ],
      );
    });

    test('45-minute frame uses the large template with four slots', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 45),
        maximumMinutes: 45,
      );

      expect(allocation.budget.elapsedSession, const Duration(minutes: 45));
      expect(allocation.budget.segments, hasLength(4));
      expect(
        allocation.budget.segments.map((segment) => segment.kind),
        <BlockKind>[
          BlockKind.warmup,
          BlockKind.primaryFocus,
          BlockKind.secondaryFocus,
          BlockKind.maintenance,
        ],
      );
    });

    test('90-minute frame uses the extra-large template with five slots', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 90),
        maximumMinutes: 90,
      );

      expect(allocation.budget.elapsedSession, const Duration(minutes: 90));
      expect(allocation.budget.segments, hasLength(5));
      expect(
        allocation.budget.segments.map((segment) => segment.kind),
        <BlockKind>[
          BlockKind.warmup,
          BlockKind.primaryFocus,
          BlockKind.secondaryFocus,
          BlockKind.maintenance,
          BlockKind.song,
        ],
      );
    });
  });

  group('A3: no negative or sub-minute fragment blocks', () {
    test('every segment is at least the policy minimum block length', () {
      for (final minutes in <int>[5, 6, 10, 13, 20, 31, 45, 61, 90]) {
        final allocation = runAllocation(
          requestedTotal: Duration(minutes: minutes),
          maximumMinutes: minutes,
        );
        for (final segment in allocation.budget.segments) {
          expect(
            segment.duration,
            greaterThanOrEqualTo(
              TimeAllocationPolicy.defaultPolicy.minimumBlockLength,
            ),
            reason: 'segment ${segment.kind.code} below minimum at $minutes',
          );
        }
      }
    });

    test(
      'a too-small day falls back to a single primary focus, no reserves',
      () {
        // The 1-minute available day is below every template's primary
        // minimum; the fragment policy must collapse to a single block.
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 1),
          maximumMinutes: 1,
        );

        expect(allocation.budget.elapsedSession, const Duration(minutes: 1));
        expect(allocation.budget.segments, hasLength(1));
        expect(allocation.budget.segments.single.kind, BlockKind.primaryFocus);
      },
    );
  });

  group('A5: the primary focus always receives the policy minimum', () {
    test('a generous day still gives the primary focus its minimum', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 90),
        maximumMinutes: 90,
      );

      final primary = allocation.budget.segments.firstWhere(
        (segment) => segment.kind == BlockKind.primaryFocus,
      );
      expect(
        primary.duration,
        greaterThanOrEqualTo(
          Duration(
            minutes: TimeAllocationPolicy.defaultPolicy.primaryMinimumMinutes,
          ),
        ),
      );
    });

    test('the smallest non-micro day still gives the primary focus its '
        'minimum', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 13),
        maximumMinutes: 13,
      );

      final primary = allocation.budget.segments.firstWhere(
        (segment) => segment.kind == BlockKind.primaryFocus,
      );
      expect(
        primary.duration,
        greaterThanOrEqualTo(
          Duration(
            minutes: TimeAllocationPolicy.defaultPolicy.primaryMinimumMinutes,
          ),
        ),
      );
    });
  });

  group(
    'A6: the micro-plan is a single focus block, not a proportional shrink',
    () {
      test('4 minutes collapses to one primary focus block', () {
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 4),
          maximumMinutes: 4,
        );

        expect(allocation.budget.segments, hasLength(1));
        expect(allocation.budget.segments.single.kind, BlockKind.primaryFocus);
      });

      test('5 minutes collapses to one primary focus block', () {
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 5),
          maximumMinutes: 5,
        );

        expect(allocation.budget.segments, hasLength(1));
        expect(allocation.budget.segments.single.kind, BlockKind.primaryFocus);
      });
    },
  );

  group('A7: the shortening decision is reasoned and traceable', () {
    test(
      'the change set targets the timeBudget and carries the typed reason',
      () {
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 30),
          maximumMinutes: 20,
        );

        expect(allocation.scaling, TimeBudgetScaling.shortened);
        final changeSet = allocation.changeSet;
        expect(changeSet, isNotNull);
        expect(changeSet!.changes, hasLength(1));
        final change = changeSet.changes.single;
        expect(change.reason, PlanChangeReason.systemAdaptation);
        expect(change.target, 'timeBudget');
        expect(change.evidenceRefs, isNotEmpty);
        expect(
          change.before['requestedElapsedMicros'],
          const Duration(minutes: 30).inMicroseconds,
        );
        expect(
          change.after['allocatedElapsedMicros'],
          const Duration(minutes: 20).inMicroseconds,
        );
      },
    );

    test('no change is emitted when the requested total is honoured', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 20,
      );

      expect(allocation.scaling, TimeBudgetScaling.none);
      expect(allocation.changeSet, isNull);
    });
  });
}
