// E07-R14 — A4 property gate: the sum of every typed TimeBudget field is
// exact, and the budget never exceeds the hard daily maximum, even for
// randomized inputs. The same trial also spot-checks A3 (no negative
// segments), A5 (primary focus minimum), and A8 (determinism).
//
// Seed: PROPERTY_SEED env var — CI passes the run id, locally absent -> 42
// (the deterministic dev loop, see HORIZON §9).
//
// Real-violation trial (ADR 0298 §mérce, brief §6.1, documented in the
// round handoff §10): if the allocator's per-slot block minutes were rounded
// up instead of down, the elapsedSession would exceed the hard maximum for
// the larger trials and the trial would go red.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../fixtures/practice_generator/allocation/allocation_fixtures.dart';

int _seed() {
  final raw = Platform.environment['PROPERTY_SEED'];
  return raw == null ? 42 : int.parse(raw);
}

void main() {
  final rng = math.Random(_seed());

  test('TimeBudgetAllocator keeps the sum exact and the day within the hard '
      'maximum', () {
    for (var trial = 0; trial < 300; trial++) {
      // Random hard maximum in the [5, 90] minute range that the brief
      // covers (5/10/20/45/90 are the reference frames).
      final hardMaximum = 5 + rng.nextInt(86);
      // The requested total is chosen either as a non-zero difference
      // from the maximum (exercising the clamp) or as a value below it.
      final overrun = rng.nextBool();
      final requestedTotal = overrun
          ? Duration(minutes: hardMaximum + 1 + rng.nextInt(30))
          : Duration(minutes: 1 + rng.nextInt(hardMaximum));
      final hardMaxDuration = Duration(minutes: hardMaximum);

      final allocation = TimeBudgetAllocator().allocate(
        availability: buildAvailability(maximumMinutes: hardMaximum),
        requestedTotal: requestedTotal,
        fromRevisionId: allocationFromRevisionId,
        toRevisionId: allocationToRevisionId,
      );

      // A4: the sum is exact, the budget fits the hard maximum.
      final budget = allocation.budget;
      expect(
        budget.activePlaying + budget.rest + budget.setup + budget.reflection,
        budget.elapsedSession,
        reason: 'trial $trial: sum must equal elapsedSession',
      );
      expect(
        budget.elapsedSession,
        lessThanOrEqualTo(hardMaxDuration),
        reason: 'trial $trial: hard maximum must hold',
      );
      expect(
        budget.elapsedSession,
        lessThanOrEqualTo(requestedTotal),
        reason: 'trial $trial: the allocator never adds time',
      );

      // A3: no negative segments, and every segment is at least the
      // policy's minimum block length.
      for (final segment in budget.segments) {
        expect(
          segment.duration.isNegative,
          isFalse,
          reason: 'trial $trial: negative segment',
        );
        expect(
          segment.duration,
          greaterThanOrEqualTo(
            TimeAllocationPolicy.defaultPolicy.minimumBlockLength,
          ),
          reason: 'trial $trial: sub-minimum fragment',
        );
      }
      // The sum of segments must equal activePlaying.
      expect(
        budget.segments.fold<Duration>(
          Duration.zero,
          (acc, segment) => acc + segment.duration,
        ),
        budget.activePlaying,
        reason: 'trial $trial: segments must sum to activePlaying',
      );

      // A5: primary focus minimum guarantee (when one is present and the
      // day is long enough to honour it). For very short days the
      // safe-overload path collapses the plan to a single block that
      // carries the entire available time — the minimum then
      // intentionally gives way to feasibility.
      final primary = budget.segments
          .where((segment) => segment.kind == BlockKind.primaryFocus)
          .toList();
      if (primary.isNotEmpty &&
          requestedTotal >=
              Duration(
                minutes:
                    TimeAllocationPolicy.defaultPolicy.primaryMinimumMinutes,
              )) {
        expect(
          primary.first.duration,
          greaterThanOrEqualTo(
            Duration(
              minutes: TimeAllocationPolicy.defaultPolicy.primaryMinimumMinutes,
            ),
          ),
          reason: 'trial $trial: primary focus minimum',
        );
      }

      // A8: deterministic — running the same allocation again yields the
      // exact same budget.
      final repeat = TimeBudgetAllocator().allocate(
        availability: buildAvailability(maximumMinutes: hardMaximum),
        requestedTotal: requestedTotal,
        fromRevisionId: allocationFromRevisionId,
        toRevisionId: allocationToRevisionId,
      );
      expect(repeat.budget, allocation.budget);
      expect(repeat.scaling, allocation.scaling);

      // A7: a shortening always emits a change set with the typed
      // reason and the alphanumeric evidence code.
      if (requestedTotal > hardMaxDuration) {
        expect(allocation.scaling, TimeBudgetScaling.shortened);
        final changeSet = allocation.changeSet;
        expect(changeSet, isNotNull, reason: 'trial $trial: change set');
        final change = changeSet!.changes.single;
        expect(
          change.reason,
          PlanChangeReason.systemAdaptation,
          reason: 'trial $trial: reason',
        );
        expect(
          change.evidenceRefs,
          contains('timeBudget.hardMaximumClamped'),
          reason: 'trial $trial: evidence',
        );
      }
    }
  });
}
