// E07-R14 — TimeBudgetAllocator: A1, A2, A3, A5, A6, A7.
//
// A4 (sum precision under rounding) and A8 (deterministic policy) live in
// their dedicated test files. The matrix barrier between the three
// hard-maximum cells (alatta / határon / fölötte) is exercised here, plus
// the F1 extension cells (extend-today typed scaling) and the F2 wiring
// of the policy's `roundingIncrement` / `ceilingMinutes` knobs.

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
          expect(
            segment.duration,
            lessThanOrEqualTo(allocation.budget.elapsedSession),
            reason:
                'no segment may exceed the daily total ($minutes, '
                '${segment.kind.code}=${segment.duration.inMinutes})',
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

    test(
      'a ceiling-clamp shorten is distinct from a hard-max shorten and stays '
      'inside the hard maximum (F1/F2 wiring)',
      () {
        // 30-minute planned ceiling inside a 60-minute day: requesting
        // 45 minutes neither breaches the hard maximum nor the planned
        // ceiling when read at the requested value, but the planned
        // ceiling forces a shorten.
        final policy = TimeAllocationPolicy(
          roundingIncrement: const Duration(minutes: 1),
          minimumBlockLength: const Duration(minutes: 1),
          primaryMinimumMinutes: 3,
          microPlanThreshold: const Duration(minutes: 5),
          ceilingMinutes: const Duration(minutes: 30),
        );
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 45),
          maximumMinutes: 60,
          policy: policy,
        );

        expect(allocation.scaling, TimeBudgetScaling.shortened);
        // The clamp drops to the planned ceiling, not the hard maximum.
        expect(allocation.budget.elapsedSession, const Duration(minutes: 30));
        expect(
          allocation.budget.elapsedSession,
          lessThanOrEqualTo(allocation.hardMaximum),
        );
        final change = allocation.changeSet!.changes.single;
        expect(change.evidenceRefs, contains('timeBudget.ceilingCapped'));
        expect(
          change.evidenceRefs,
          isNot(contains('timeBudget.hardMaximumClamped')),
          reason: 'the ceiling path must not look like a hard-max clamp',
        );
        expect(
          change.after['allocatedElapsedMicros'],
          const Duration(minutes: 30).inMicroseconds,
        );
      },
    );

    test('extend-today grows the day up to the effective upper bound and '
        'emits a typed change-set with the extension evidence (F1)', () {
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 45,
        extendToday: true,
      );

      expect(allocation.scaling, TimeBudgetScaling.extended);
      expect(
        allocation.budget.elapsedSession,
        const Duration(minutes: 45),
        reason: 'extension targets the hard maximum when below the ceiling',
      );
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.hardMaximum),
      );
      final changeSet = allocation.changeSet;
      expect(changeSet, isNotNull);
      expect(changeSet!.changes, hasLength(1));
      final change = changeSet.changes.single;
      expect(change.reason, PlanChangeReason.systemAdaptation);
      expect(change.target, 'timeBudget');
      expect(change.evidenceRefs, contains('timeBudget.extendedToAvailable'));
      expect(
        change.before['requestedElapsedMicros'],
        const Duration(minutes: 20).inMicroseconds,
      );
      expect(
        change.before['hardMaximumMicros'],
        const Duration(minutes: 45).inMicroseconds,
      );
      expect(
        change.after['allocatedElapsedMicros'],
        const Duration(minutes: 45).inMicroseconds,
      );
    });

    test('extend-today honours the planned ceiling when it sits below the hard '
        'maximum (F1 vs F2 interaction)', () {
      // 45-minute hard maximum, 30-minute planned ceiling: extension
      // targets the SMALLER of the two constraints.
      final policy = TimeAllocationPolicy(
        roundingIncrement: const Duration(minutes: 1),
        minimumBlockLength: const Duration(minutes: 1),
        primaryMinimumMinutes: 3,
        microPlanThreshold: const Duration(minutes: 5),
        ceilingMinutes: const Duration(minutes: 30),
      );
      final allocation = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 45,
        policy: policy,
        extendToday: true,
      );

      expect(allocation.scaling, TimeBudgetScaling.extended);
      expect(allocation.budget.elapsedSession, const Duration(minutes: 30));
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.hardMaximum),
      );
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.ceilingCap),
      );
      final change = allocation.changeSet!.changes.single;
      expect(change.evidenceRefs, contains('timeBudget.extendedToAvailable'));
    });

    test(
      'extend-today is a no-op when the request already matches the effective '
      'upper bound',
      () {
        // Request == hard maximum == planned ceiling: no room to extend,
        // no scaling.
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 45),
          maximumMinutes: 45,
          extendToday: true,
        );

        expect(allocation.scaling, TimeBudgetScaling.none);
        expect(allocation.changeSet, isNull);
        expect(allocation.budget.elapsedSession, const Duration(minutes: 45));
      },
    );

    test('extend-today combined with a request above the hard maximum is '
        'rejected loudly (no silent clamp)', () {
      expect(
        () => runAllocation(
          requestedTotal: const Duration(minutes: 50),
          maximumMinutes: 45,
          extendToday: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('A8 wiring: roundingIncrement and ceilingMinutes affect the output', () {
    test('a 2-minute rounding step changes per-slot minutes while keeping '
        'the sum exact (F2)', () {
      // 33 minutes -> large template. With the default policy the
      // per-slot minutes are [5, 11, 6, 5]; with roundingIncrement=2
      // floor-rounding pushes each slot to the next even value and the
      // refund flows back into the primary focus, producing an
      // observably different layout. `minimumBlockLength` has to track
      // the step — the policy rejects a step that would let rounding
      // create sub-block fragments.
      final policyStep2 = TimeAllocationPolicy(
        roundingIncrement: const Duration(minutes: 2),
        minimumBlockLength: const Duration(minutes: 2),
        primaryMinimumMinutes: 3,
        microPlanThreshold: const Duration(minutes: 5),
        ceilingMinutes: const Duration(minutes: 90),
      );
      final defaultAllocation = runAllocation(
        requestedTotal: const Duration(minutes: 33),
        maximumMinutes: 33,
        policy: TimeAllocationPolicy.defaultPolicy,
      );
      final roundedAllocation = runAllocation(
        requestedTotal: const Duration(minutes: 33),
        maximumMinutes: 33,
        policy: policyStep2,
      );

      // The two allocations differ, both sum exactly, and every non-primary
      // segment is a multiple of 2 (the primary slot absorbs the rounding
      // tail so the sum invariant holds — see ADR 0298 §2 brief).
      expect(roundedAllocation.budget, isNot(equals(defaultAllocation.budget)));
      expect(
        roundedAllocation.budget.elapsedSession,
        const Duration(minutes: 33),
      );
      expect(
        roundedAllocation.budget.elapsedSession,
        lessThanOrEqualTo(roundedAllocation.hardMaximum),
      );
      expect(
        roundedAllocation.budget.segments.fold<Duration>(
          Duration.zero,
          (acc, segment) => acc + segment.duration,
        ),
        roundedAllocation.budget.activePlaying,
      );
      for (final segment in roundedAllocation.budget.segments) {
        if (segment.kind == BlockKind.primaryFocus) continue;
        expect(
          segment.duration.inMinutes % 2,
          0,
          reason:
              'non-primary segment ${segment.kind.code}=${segment.duration.inMinutes} '
              'must be a multiple of 2 after floor-rounding',
        );
      }
    });

    test(
      'rounding refund never crosses the hard maximum (F2 ceiling repair)',
      () {
        // With a 3-minute rounding step the warmup/secondary slots
        // floor to zero and the refund flows to the primary focus; the
        // sum invariant and the hard maximum together must still hold.
        // `minimumBlockLength` tracks the step so the policy accepts
        // the tuning.
        final policyStep3 = TimeAllocationPolicy(
          roundingIncrement: const Duration(minutes: 3),
          minimumBlockLength: const Duration(minutes: 3),
          primaryMinimumMinutes: 3,
          microPlanThreshold: const Duration(minutes: 5),
          ceilingMinutes: const Duration(minutes: 90),
        );
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 21),
          maximumMinutes: 21,
          policy: policyStep3,
        );
        expect(allocation.budget.elapsedSession, const Duration(minutes: 21));
        expect(
          allocation.budget.elapsedSession,
          lessThanOrEqualTo(allocation.hardMaximum),
        );
        expect(
          allocation.budget.segments.fold<Duration>(
            Duration.zero,
            (acc, segment) => acc + segment.duration,
          ),
          allocation.budget.activePlaying,
          reason: 'the segments must sum to activePlaying',
        );
      },
    );

    test(
      'ceilingMinutes caps the day and emits the dedicated evidence (F2)',
      () {
        final policy = TimeAllocationPolicy(
          roundingIncrement: const Duration(minutes: 1),
          minimumBlockLength: const Duration(minutes: 1),
          primaryMinimumMinutes: 3,
          microPlanThreshold: const Duration(minutes: 5),
          ceilingMinutes: const Duration(minutes: 30),
        );
        final allocation = runAllocation(
          requestedTotal: const Duration(minutes: 45),
          maximumMinutes: 60,
          policy: policy,
        );
        expect(allocation.scaling, TimeBudgetScaling.shortened);
        expect(allocation.budget.elapsedSession, const Duration(minutes: 30));
        expect(allocation.ceilingCap, const Duration(minutes: 30));
        final change = allocation.changeSet!.changes.single;
        expect(change.evidenceRefs, contains('timeBudget.ceilingCapped'));
      },
    );
  });
}
