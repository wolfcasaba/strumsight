import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';

void main() {
  final previous = revision(number: 1);

  AdaptivePracticePlan candidateWithBlockDuration(Duration duration) {
    final original = previous.snapshot.days.single;
    final updated = original.blocks.single.replaceContent(
      estimatedElapsed: duration,
    );
    return previous.snapshot.copyWith(
      days: <PracticeDay>[
        PracticeDay(
          id: original.id,
          localDate: original.localDate,
          status: original.status,
          timeBudget: original.timeBudget,
          blocks: <PracticeBlock>[updated],
          primaryFocusSkillIds: original.primaryFocusSkillIds,
          reasonCodes: original.reasonCodes,
        ),
      ],
    );
  }

  PlanChange durationChange(String blockId) => PlanChange(
    type: PlanChangeType.updated,
    target: 'day:day.1:block:$blockId',
    before: const <String, Object?>{'estimatedElapsedMicros': 360000000},
    after: const <String, Object?>{'estimatedElapsedMicros': 420000000},
    reason: PlanChangeReason.systemAdaptation,
    evidenceRefs: const <String>['outcome.1'],
    confidence: .8,
    requiresUserConfirmation: false,
    reversible: true,
  );

  RevisePracticePlan revise({DateTime Function()? clock}) =>
      RevisePracticePlan(clock: clock ?? () => DateTime.utc(2026, 8, 19, 12));

  RevisePracticePlanRequest request({
    required Iterable<PlanChange> changes,
    required AdaptivePracticePlan candidate,
    PlanChangeConfirmation confirmation = PlanChangeConfirmation.pending,
  }) => RevisePracticePlanRequest(
    previous: previous,
    nextRevisionId: RevisionId('revision.2'),
    candidateSnapshot: candidate,
    changes: changes,
    reason: PlanRevisionReason.systemAdaptation,
    confirmation: confirmation,
  );

  test('A1/A2: rejects a change set that targets a completed block', () {
    final completedBlock = block(status: PracticeItemStatus.completed);
    final completedPlan = previous.snapshot.copyWith(
      days: <PracticeDay>[
        PracticeDay(
          id: DayId('day.1'),
          localDate: LocalDate(2026, 8, 17),
          status: PracticeItemStatus.inProgress,
          timeBudget: const Duration(minutes: 20),
          blocks: <PracticeBlock>[completedBlock],
          primaryFocusSkillIds: const <String>['rhythm.quarterNotes'],
          reasonCodes: const <String>['goal.primary'],
        ),
      ],
    );
    final completedPrevious = PlanRevision(
      id: RevisionId('revision.completed'),
      planId: completedPlan.id,
      number: 1,
      createdAt: DateTime.utc(2026, 8, 19),
      reason: PlanRevisionReason.initialGeneration,
      snapshot: completedPlan,
    );
    final input = RevisePracticePlanRequest(
      previous: completedPrevious,
      nextRevisionId: RevisionId('revision.next'),
      candidateSnapshot: completedPlan,
      changes: <PlanChange>[durationChange('block.1')],
      reason: PlanRevisionReason.systemAdaptation,
      confirmation: PlanChangeConfirmation.accepted,
    );

    expect(() => revise().call(input), throwsStateError);
  });

  test('A4 below threshold: one future block duration change is automatic', () {
    final result = revise().call(
      request(
        changes: <PlanChange>[durationChange('block.1')],
        candidate: candidateWithBlockDuration(const Duration(minutes: 7)),
      ),
    );

    expect(result.requiresUserConfirmation, isFalse);
    expect(result.isActive, isTrue);
    expect(result.revision!.number, 2);
  });

  test('A4 at threshold: two future block changes require confirmation', () {
    final result = revise().call(
      request(
        changes: <PlanChange>[
          durationChange('block.1'),
          durationChange('block.1'),
        ],
        candidate: candidateWithBlockDuration(const Duration(minutes: 7)),
      ),
    );

    expect(result.requiresUserConfirmation, isTrue);
    expect(result.isActive, isFalse);
  });

  test('A4 above threshold: three changes remain pending with a diff', () {
    final result = revise().call(
      request(
        changes: <PlanChange>[
          durationChange('block.1'),
          durationChange('block.1'),
          durationChange('block.1'),
        ],
        candidate: candidateWithBlockDuration(const Duration(minutes: 7)),
      ),
    );

    expect(result.requiresUserConfirmation, isTrue);
    expect(result.changeSet.changes, hasLength(3));
    expect(result.isActive, isFalse);
  });

  test('A5: a rejected major change stays auditable but is not active', () {
    final result = revise().call(
      request(
        changes: <PlanChange>[
          durationChange('block.1'),
          durationChange('block.1'),
        ],
        candidate: candidateWithBlockDuration(const Duration(minutes: 7)),
        confirmation: PlanChangeConfirmation.rejected,
      ),
    );

    expect(result.isActive, isFalse);
    expect(result.confirmation, PlanChangeConfirmation.rejected);
    expect(result.changeSet.changes, hasLength(2));
  });

  test('A8: creates a strictly later revision using the existing guard', () {
    final result = revise().call(
      request(
        changes: <PlanChange>[durationChange('block.1')],
        candidate: candidateWithBlockDuration(const Duration(minutes: 7)),
      ),
    );

    expect(result.revision!.previousRevisionId, previous.id);
    expect(result.revision!.number, greaterThan(previous.number));
  });
}
