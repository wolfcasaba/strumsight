// E07-R11 — PlanRepairer: A3, A4, A5, A6, plus a unit-level demonstration
// of A2's iteration cap (the fuzz proof lives in
// test/property/planner_repair_property_test.dart).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

List<PracticeBlock> _hardAvoidedBlocks(
  int count,
  ExercisePrescription prescription,
) => [
  for (var i = 0; i < count; i++)
    buildBlock(id: 'block.${i + 1}', order: i + 1, prescription: prescription),
];

void main() {
  group('A3: repair never exceeds the hard time maximum', () {
    test('trims blocks until the day fits the hard maximum', () {
      final candidate = buildCandidate();
      final prescription = buildPrescription(candidate);
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(
            id: 'block.1',
            order: 1,
            prescription: prescription,
            estimatedElapsed: const Duration(minutes: 6),
          ),
          buildBlock(
            id: 'block.2',
            order: 2,
            prescription: prescription,
            estimatedElapsed: const Duration(minutes: 6),
          ),
          buildBlock(
            id: 'block.3',
            order: 3,
            prescription: prescription,
            estimatedElapsed: const Duration(minutes: 6),
          ),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        availability: buildAvailability(maximumMinutes: 10),
      );

      final outcome = const PlanRepairer().repair(plan, context);

      expect(outcome.succeeded, isTrue);
      final repairedDay = outcome.plan!.days.single;
      final totalMicros = repairedDay.blocks.fold<int>(
        0,
        (total, block) => total + block.estimatedElapsed.inMicroseconds,
      );
      expect(
        totalMicros,
        lessThanOrEqualTo(const Duration(minutes: 10).inMicroseconds),
      );
      expect(outcome.changeSet, isNotNull);
    });
  });

  group('A4: every repair step is reasoned', () {
    test('every change in the change set carries systemAdaptation', () {
      final candidate = buildCandidate();
      final prescription = buildPrescription(candidate);
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: _hardAvoidedBlocks(2, prescription),
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        hardAvoidIdentities: <String>[identityOf(candidate)],
      );

      final outcome = const PlanRepairer().repair(plan, context);

      expect(outcome.succeeded, isTrue);
      final changeSet = outcome.changeSet!;
      expect(changeSet.changes, isNotEmpty);
      for (final change in changeSet.changes) {
        expect(change.reason, PlanChangeReason.systemAdaptation);
        expect(change.evidenceRefs, isNotEmpty);
      }
    });
  });

  group('A5: repair is deterministic', () {
    test('the same invalid plan repairs to the same result twice', () {
      final candidate = buildCandidate();
      final prescription = buildPrescription(candidate);
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: _hardAvoidedBlocks(3, prescription),
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        hardAvoidIdentities: <String>[identityOf(candidate)],
      );

      final first = const PlanRepairer().repair(plan, context);
      final second = const PlanRepairer().repair(plan, context);

      expect(first.succeeded, isTrue);
      expect(second.succeeded, isTrue);
      expect(first.plan, second.plan);
      expect(
        jsonEncode(first.changeSet!.toJson()),
        jsonEncode(second.changeSet!.toJson()),
      );
      expect(first.iterationsUsed, second.iterationsUsed);
    });
  });

  group('A6: repair never touches the completed past', () {
    test('a completed block violation cannot be repaired away', () {
      final candidate = buildCandidate();
      final prescription = buildPrescription(candidate);
      final completedBlock = buildBlock(
        id: 'block.1',
        order: 1,
        prescription: prescription,
        status: PracticeItemStatus.completed,
      );
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[completedBlock],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        hardAvoidIdentities: <String>[identityOf(candidate)],
      );

      final outcome = const PlanRepairer().repair(plan, context);

      expect(outcome.succeeded, isFalse);
      expect(outcome.plan, isNull);
      expect(
        outcome.remainingIssues.map((issue) => issue.code),
        contains(PlanValidationCode.hardAvoidViolated),
      );
    });

    test('a fatal completed-history violation is never attempted', () {
      final completedBlock = buildBlock(
        id: 'block.1',
        order: 1,
        status: PracticeItemStatus.completed,
      );
      final previousDay = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        status: PracticeItemStatus.completed,
        blocks: <PracticeBlock>[completedBlock],
      );
      final modifiedBlock = buildBlock(
        id: 'block.2',
        order: 1,
        status: PracticeItemStatus.completed,
      );
      final currentDay = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        status: PracticeItemStatus.completed,
        blocks: <PracticeBlock>[modifiedBlock],
      );
      final previousPlan = buildPlan(days: <PracticeDay>[previousDay]);
      final currentPlan = buildPlan(days: <PracticeDay>[currentDay]);
      final context = buildContext(previousSnapshot: previousPlan);

      final outcome = const PlanRepairer().repair(currentPlan, context);

      expect(outcome.succeeded, isFalse);
      expect(outcome.iterationsUsed, 0);
      expect(
        outcome.remainingIssues.map((issue) => issue.code),
        contains(PlanValidationCode.completedHistoryModified),
      );
    });
  });

  group('the iteration cap (A2, unit-level)', () {
    test('repair succeeds when the fix count is within the cap', () {
      final candidate = buildCandidate();
      final prescription = buildPrescription(candidate);
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: _hardAvoidedBlocks(3, prescription),
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        hardAvoidIdentities: <String>[identityOf(candidate)],
      );

      final outcome = const PlanRepairer(
        maxIterations: 3,
      ).repair(plan, context);

      expect(outcome.succeeded, isTrue);
      expect(outcome.iterationsUsed, lessThanOrEqualTo(3));
    });

    test('repair gives up and reports failure when the cap is exhausted', () {
      final candidate = buildCandidate();
      final prescription = buildPrescription(candidate);
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: _hardAvoidedBlocks(4, prescription),
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        hardAvoidIdentities: <String>[identityOf(candidate)],
      );

      final outcome = const PlanRepairer(
        maxIterations: 3,
      ).repair(plan, context);

      expect(outcome.succeeded, isFalse);
      expect(outcome.iterationsUsed, 3);
      expect(
        outcome.remainingIssues.map((issue) => issue.code),
        contains(PlanValidationCode.hardAvoidViolated),
      );
    });
  });

  group('a valid plan needs no repair', () {
    test('an already-valid plan returns success with no change set', () {
      final candidate = buildCandidate();
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(candidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final outcome = const PlanRepairer().repair(plan, context);

      expect(outcome.succeeded, isTrue);
      expect(outcome.changeSet, isNull);
      expect(outcome.plan, plan);
      expect(outcome.iterationsUsed, 0);
    });
  });
}
