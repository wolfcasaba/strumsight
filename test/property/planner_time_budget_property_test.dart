// E07-R14 — A4 property gate: the sum of every typed TimeBudget field is
// exact, and the budget never exceeds the hard daily maximum, even for
// randomized inputs. The same trial also spot-checks A3 (no negative
// segments), A5 (primary focus minimum), and A8 (determinism). The
// `extendToday` flag and the F2 `roundingIncrement` / `ceilingMinutes`
// policy knobs are exercised in dedicated trials so each code path gets
// randomized, not just the default.
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

Duration _minDuration(Duration a, Duration b) => a <= b ? a : b;

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
        lessThanOrEqualTo(allocation.ceilingCap),
        reason: 'trial $trial: planned ceiling must hold',
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
        // Shorten-to-hard-max must NEVER look like the ceiling path.
        expect(
          change.evidenceRefs,
          isNot(contains('timeBudget.ceilingCapped')),
          reason:
              'trial $trial: hard-max clamp must not wear the ceiling label',
        );
      }
    }
  });

  test('F1 extend-today: a typed extension change-set grows the day up to '
      'the effective upper bound without breaching it', () {
    for (var trial = 0; trial < 80; trial++) {
      final hardMaximum = 15 + rng.nextInt(76); // 15..90
      // Keep `asked` strictly below `hardMaximum` so the extension
      // branch is exercised on every trial.
      final asked = Duration(minutes: 5 + rng.nextInt(hardMaximum - 5));
      const ceilingMinutes = Duration(minutes: 90);
      final extensionTarget = _minDuration(
        Duration(minutes: hardMaximum),
        ceilingMinutes,
      );

      final allocation = TimeBudgetAllocator().allocate(
        availability: buildAvailability(maximumMinutes: hardMaximum),
        requestedTotal: asked,
        fromRevisionId: allocationFromRevisionId,
        toRevisionId: allocationToRevisionId,
        extendToday: true,
      );

      expect(
        allocation.scaling,
        TimeBudgetScaling.extended,
        reason: 'trial $trial: extendToday must trigger extension',
      );
      expect(
        allocation.budget.elapsedSession,
        extensionTarget,
        reason: 'trial $trial: extension target',
      );
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.hardMaximum),
        reason: 'trial $trial: hard maximum invariant',
      );
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.ceilingCap),
        reason: 'trial $trial: planned ceiling invariant',
      );

      final changeSet = allocation.changeSet;
      expect(changeSet, isNotNull, reason: 'trial $trial: change set');
      final change = changeSet!.changes.single;
      expect(
        change.reason,
        PlanChangeReason.systemAdaptation,
        reason: 'trial $trial: extension carries the typed reason',
      );
      expect(
        change.evidenceRefs,
        contains('timeBudget.extendedToAvailable'),
        reason: 'trial $trial: extension evidence',
      );
      expect(
        change.before['requestedElapsedMicros'],
        asked.inMicroseconds,
        reason: 'trial $trial: before is the requested total',
      );
      expect(
        change.after['allocatedElapsedMicros'],
        extensionTarget.inMicroseconds,
        reason: 'trial $trial: after is the extended total',
      );

      // A4 / A3 invariants for the extended allocation.
      final budget = allocation.budget;
      expect(
        budget.activePlaying + budget.rest + budget.setup + budget.reflection,
        budget.elapsedSession,
        reason: 'trial $trial: sum invariant after extension',
      );
      expect(
        budget.segments.fold<Duration>(
          Duration.zero,
          (acc, segment) => acc + segment.duration,
        ),
        budget.activePlaying,
        reason: 'trial $trial: segments sum after extension',
      );
      for (final segment in budget.segments) {
        expect(
          segment.duration.isNegative,
          isFalse,
          reason: 'trial $trial: no negative segments after extension',
        );
      }
    }
  });

  test('F2 ceiling/rounding: the policy knobs shrink the day and floor-round '
      'per-slot minutes without breaching the hard maximum', () {
    for (var trial = 0; trial < 60; trial++) {
      // A planned ceiling that sits below the hard maximum. The ceiling is
      // bounded strictly below the hard maximum so the ceiling-clamp
      // branch is exercised on every trial.
      final hardMaximum = 30 + rng.nextInt(61); // 30..90
      final ceilingMinutes = 6 + rng.nextInt(hardMaximum - 6);
      final ceiling = Duration(minutes: ceilingMinutes);
      final hardMax = Duration(minutes: hardMaximum);

      // Step 1: ceiling caps the day when the request lies in
      //   ceilingCap < asked <= hardMax.
      final requestedMinutes =
          ceilingMinutes + 1 + rng.nextInt(hardMaximum - ceilingMinutes);
      final askedPastCeiling = Duration(minutes: requestedMinutes);
      final policy = TimeAllocationPolicy(
        roundingIncrement: const Duration(minutes: 1),
        minimumBlockLength: const Duration(minutes: 1),
        primaryMinimumMinutes: 3,
        microPlanThreshold: const Duration(minutes: 5),
        ceilingMinutes: ceiling,
      );
      final allocation = TimeBudgetAllocator(policy: policy).allocate(
        availability: buildAvailability(maximumMinutes: hardMaximum),
        requestedTotal: askedPastCeiling,
        fromRevisionId: allocationFromRevisionId,
        toRevisionId: allocationToRevisionId,
      );

      expect(
        allocation.scaling,
        TimeBudgetScaling.shortened,
        reason: 'trial $trial: ceiling path shortens',
      );
      expect(
        allocation.budget.elapsedSession,
        ceiling,
        reason: 'trial $trial: ceiling clamp',
      );
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(hardMax),
        reason: 'trial $trial: ceiling clamp stays within hard max',
      );
      expect(
        allocation.budget.elapsedSession,
        lessThanOrEqualTo(allocation.ceilingCap),
        reason: 'trial $trial: ceiling clamp equals ceilingCap',
      );
      final ceilingChange = allocation.changeSet!.changes.single;
      expect(
        ceilingChange.evidenceRefs,
        contains('timeBudget.ceilingCapped'),
        reason: 'trial $trial: ceiling evidence',
      );

      // Step 2: a 2-minute rounding step on the same day must keep the
      // total exact, keep every segment a multiple of 2, and stay below
      // the hard maximum. `minimumBlockLength` tracks the step so the
      // policy accepts the tuning.
      final step2Policy = TimeAllocationPolicy(
        roundingIncrement: const Duration(minutes: 2),
        minimumBlockLength: const Duration(minutes: 2),
        primaryMinimumMinutes: 3,
        microPlanThreshold: const Duration(minutes: 5),
        ceilingMinutes: ceiling,
      );
      final rounded = TimeBudgetAllocator(policy: step2Policy).allocate(
        availability: buildAvailability(maximumMinutes: hardMaximum),
        requestedTotal: askedPastCeiling,
        fromRevisionId: allocationFromRevisionId,
        toRevisionId: allocationToRevisionId,
      );
      expect(
        rounded.budget.elapsedSession,
        allocation.budget.elapsedSession,
        reason: 'trial $trial: rounding must not change the total',
      );
      expect(
        rounded.budget.elapsedSession,
        lessThanOrEqualTo(hardMax),
        reason: 'trial $trial: rounding refund must stay under hard max',
      );
      for (final segment in rounded.budget.segments) {
        if (segment.kind != BlockKind.primaryFocus) {
          expect(
            segment.duration.inMinutes % 2,
            0,
            reason:
                'trial $trial: non-primary segments must be multiples of '
                'the step (${segment.kind.code}=${segment.duration.inMinutes})',
          );
        }
        expect(
          segment.duration.isNegative,
          isFalse,
          reason: 'trial $trial: no negative rounded segments',
        );
      }
    }
  });
}
