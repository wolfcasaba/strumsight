// E07-R14 — TimeAllocationPolicy: A8 (deterministic) plus the policy-shape
// contract that anchors every other acceptance cell. The hard-maximum
// boundary (A1) and the integer-balance property (A4) live next to it in
// the property test.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/allocation/allocation_fixtures.dart';

void main() {
  group('A8: the policy is deterministic and reproduces the v1 contract', () {
    test('the default policy exposes the v1 provenance', () {
      expect(
        TimeAllocationPolicy.defaultPolicy.version,
        'time-allocation-policy-v1',
      );
      expect(
        TimeAllocationPolicy.defaultPolicy.roundingIncrement,
        const Duration(minutes: 1),
      );
      expect(
        TimeAllocationPolicy.defaultPolicy.minimumBlockLength,
        const Duration(minutes: 1),
      );
      expect(TimeAllocationPolicy.defaultPolicy.primaryMinimumMinutes, 3);
      expect(
        TimeAllocationPolicy.defaultPolicy.microPlanThreshold,
        const Duration(minutes: 5),
      );
    });

    test('the same inputs produce identical allocations twice', () {
      final first = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 20,
      );
      final second = runAllocation(
        requestedTotal: const Duration(minutes: 20),
        maximumMinutes: 20,
      );

      expect(first.budget, second.budget);
      expect(first.scaling, second.scaling);
      expect(first.changeSet, second.changeSet);
    });

    test('the same inputs always produce the same allocation, regardless of '
        'which allocator instance runs them', () {
      // Two allocators with the same default policy must produce the same
      // budget when given the same inputs.
      final a = TimeBudgetAllocator(policy: TimeAllocationPolicy.defaultPolicy)
          .allocate(
            availability: buildAvailability(maximumMinutes: 45),
            requestedTotal: const Duration(minutes: 45),
            fromRevisionId: allocationFromRevisionId,
            toRevisionId: allocationToRevisionId,
          );
      final b = TimeBudgetAllocator(policy: TimeAllocationPolicy.defaultPolicy)
          .allocate(
            availability: buildAvailability(maximumMinutes: 45),
            requestedTotal: const Duration(minutes: 45),
            fromRevisionId: allocationFromRevisionId,
            toRevisionId: allocationToRevisionId,
          );

      expect(a.budget, b.budget);
      expect(a.scaling, b.scaling);
    });

    test('rejects invalid tuning values', () {
      expect(() => TimeAllocationPolicy(version: ' '), throwsArgumentError);
      expect(
        () => TimeAllocationPolicy(roundingIncrement: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => TimeAllocationPolicy(minimumBlockLength: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => TimeAllocationPolicy(primaryMinimumMinutes: 0),
        throwsArgumentError,
      );
      expect(
        () => TimeAllocationPolicy(primaryMinimumMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => TimeAllocationPolicy(ceilingMinutes: Duration.zero),
        throwsArgumentError,
      );
      // The rounding increment must not exceed the minimum block length,
      // otherwise every increment would also be a fragment.
      expect(
        () => TimeAllocationPolicy(
          roundingIncrement: const Duration(minutes: 2),
          minimumBlockLength: const Duration(minutes: 1),
        ),
        throwsArgumentError,
      );
    });

    test('the policy exposes a typed template selector that matches the '
        'brief\'s reference frames', () {
      final policy = TimeAllocationPolicy.defaultPolicy;
      // The micro-plan threshold is the 5-minute micro-plan cutoff.
      expect(
        policy.templateFor(const Duration(minutes: 5)).orderedKinds,
        <BlockKind>[BlockKind.primaryFocus],
      );
      // 10 minutes uses the small template.
      expect(
        policy.templateFor(const Duration(minutes: 10)).orderedKinds,
        <BlockKind>[BlockKind.primaryFocus],
      );
      // 20 minutes uses the medium template.
      expect(
        policy.templateFor(const Duration(minutes: 20)).orderedKinds,
        <BlockKind>[
          BlockKind.warmup,
          BlockKind.primaryFocus,
          BlockKind.secondaryFocus,
        ],
      );
      // 45 minutes uses the large template.
      expect(
        policy.templateFor(const Duration(minutes: 45)).orderedKinds,
        <BlockKind>[
          BlockKind.warmup,
          BlockKind.primaryFocus,
          BlockKind.secondaryFocus,
          BlockKind.maintenance,
        ],
      );
      // 90 minutes uses the extra-large template.
      expect(
        policy.templateFor(const Duration(minutes: 90)).orderedKinds,
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
}
