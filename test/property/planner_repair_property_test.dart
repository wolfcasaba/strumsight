// E07-R11 — A2 property gate: PlanRepairer.repair always terminates within
// its configured maxIterations, regardless of how many blocks are invalid,
// whether some are genuinely unfixable (completed), or how tight the hard
// daily maximum is. It also spot-checks A3 (never above the hard maximum),
// A4 (every change is reasoned), A5 (determinism), and A6 (a completed
// block is never touched) across the same randomized trials.
//
// Seed: PROPERTY_SEED env var — CI passes the run id, locally absent -> 42
// (the deterministic dev loop, see HORIZON §9).
//
// Real-violation trial (ADR 0263 §mérce, brief §6.1, documented in the
// round handoff §10): with the `iteration <= maxIterations` bound removed
// from PlanRepairer.repair, this test goes red/times out for the larger
// generated trials, because the loop then keeps re-validating and
// re-fixing the day indefinitely once only unfixable (completed) issues
// remain instead of giving up.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../fixtures/practice_generator/validation/validation_fixtures.dart';

int _seed() {
  final raw = Platform.environment['PROPERTY_SEED'];
  return raw == null ? 42 : int.parse(raw);
}

void main() {
  final rng = math.Random(_seed());

  test(
    'PlanRepairer.repair terminates within maxIterations for every input',
    () {
      for (var trial = 0; trial < 300; trial++) {
        final candidate = buildCandidate();
        final blockCount = 1 + rng.nextInt(8);
        final maxIterations = 1 + rng.nextInt(6);
        final avoidAll = rng.nextBool();
        final completedCount = rng.nextInt(blockCount + 1);
        final tightMaximum = rng.nextBool();

        final blocks = <PracticeBlock>[
          for (var i = 0; i < blockCount; i++)
            buildBlock(
              id: 'trial.$trial.block.${i + 1}',
              order: i + 1,
              prescription: buildPrescription(candidate),
              status: i < completedCount
                  ? PracticeItemStatus.completed
                  : PracticeItemStatus.planned,
            ),
        ];
        final day = buildDay(
          id: 'trial.$trial.day',
          localDate: LocalDate(2026, 8, 17),
          blocks: blocks,
        );
        final plan = buildPlan(
          id: 'trial.$trial.plan',
          days: <PracticeDay>[day],
        );
        final context = buildContext(
          catalog: buildCatalog(candidates: [candidate]),
          hardAvoidIdentities: avoidAll
              ? <String>[identityOf(candidate)]
              : const [],
          availability: buildAvailability(
            maximumMinutes: tightMaximum ? 1 + rng.nextInt(10) : 120,
          ),
        );
        final repairer = PlanRepairer(maxIterations: maxIterations);

        final outcome = repairer.repair(plan, context);

        // A2: bounded, always returns.
        expect(outcome.iterationsUsed, lessThanOrEqualTo(maxIterations));

        // A5: determinism.
        final repeat = repairer.repair(plan, context);
        expect(repeat.succeeded, outcome.succeeded);
        expect(repeat.iterationsUsed, outcome.iterationsUsed);
        expect(repeat.plan, outcome.plan);
        expect(
          repeat.changeSet == null
              ? null
              : jsonEncode(repeat.changeSet!.toJson()),
          outcome.changeSet == null
              ? null
              : jsonEncode(outcome.changeSet!.toJson()),
        );

        if (outcome.succeeded) {
          final repairedDay = outcome.plan!.days.single;

          // A3: never above the hard maximum.
          final daily = context.availability.forDate(repairedDay.localDate);
          if (daily != null &&
              daily.maximumStrength == ConstraintStrength.hard) {
            final totalMicros = repairedDay.blocks.fold<int>(
              0,
              (total, block) => total + block.estimatedElapsed.inMicroseconds,
            );
            expect(
              totalMicros,
              lessThanOrEqualTo(
                Duration(minutes: daily.maximumMinutes).inMicroseconds,
              ),
            );
          }

          // A4: every change is reasoned.
          final changeSet = outcome.changeSet;
          if (changeSet != null) {
            for (final change in changeSet.changes) {
              expect(change.reason, PlanChangeReason.systemAdaptation);
              expect(change.evidenceRefs, isNotEmpty);
            }
          }

          // A6: every completed block survives untouched.
          final completedBefore = blocks
              .where((block) => block.status == PracticeItemStatus.completed)
              .toList();
          for (final before in completedBefore) {
            final matching = repairedDay.blocks.where(
              (block) => block.id == before.id,
            );
            expect(matching, hasLength(1));
            expect(matching.single, before);
          }
        }
      }
    },
  );
}
