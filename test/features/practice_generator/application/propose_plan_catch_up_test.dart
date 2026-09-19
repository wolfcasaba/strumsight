/// `ProposePlanCatchUp` — the producer behind the change-review route.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../fixtures/practice_generator/validation/validation_fixtures.dart';

final LocalDate _today = LocalDate(2026, 9, 7);
final DateTime _now = DateTime(2026, 9, 7, 9);

ProposePlanCatchUp _useCase() {
  var next = 0;
  return ProposePlanCatchUp(
    revise: RevisePracticePlan(clock: () => _now),
    repository: LocalPracticePlanRepository(
      keyValueStore: InMemoryKeyValueStore(),
      resolveCandidate: (exerciseId) => buildCandidate(exerciseId: exerciseId),
    ),
    today: () => _today,
    generateId: () => 'catchup-${next++}',
  );
}

AdaptivePracticePlan _plan(Iterable<PracticeDay> days) {
  final ordered = days.toList(growable: false);
  return AdaptivePracticePlan(
    id: PlanId('plan.catchup'),
    schemaVersion: 1,
    status: PlanStatus.active,
    title: 'Catch-up plan',
    createdAt: DateTime.utc(2026, 8, 31),
    startDate: ordered.first.localDate,
    endDate: ordered.last.localDate,
    goals: <PracticeGoal>[buildGoal()],
    days: ordered,
    activeRevisionId: RevisionId('revision.catchup.1'),
    generationProvenance: GenerationRequestId('request.catchup'),
    policyVersions: const <String, String>{
      'catalog': catalogRevision,
      'content': defaultContentRevision,
    },
  );
}

PlanCatchUpProposal? _valueOf(AppResult<PlanCatchUpProposal?> result) =>
    switch (result) {
      Success<PlanCatchUpProposal?>(:final value) => value,
      Failure<PlanCatchUpProposal?>(:final error) => throw StateError('$error'),
    };

void main() {
  test('a plan with nothing missed proposes nothing', () async {
    final plan = _plan(<PracticeDay>[
      buildDay(id: 'day.future', localDate: LocalDate(2026, 9, 10)),
    ]);

    final result = await _useCase()(plan);

    expect(result.isSuccess, isTrue);
    expect(_valueOf(result), isNull);
  });

  test('one missed day is a local adjustment — no review needed', () async {
    final plan = _plan(<PracticeDay>[
      buildDay(id: 'day.missed', localDate: LocalDate(2026, 9, 1)),
      buildDay(id: 'day.future', localDate: LocalDate(2026, 9, 10)),
    ]);

    final proposal = _valueOf(await _useCase()(plan))!;

    expect(proposal.proposal.changeSet.changes, hasLength(1));
    expect(proposal.requiresReview, isFalse);
    expect(
      proposal.proposal.changeSet.changes.single.reason,
      PlanChangeReason.missedPractice,
    );
  });

  test('two missed days require an explicit decision', () async {
    final plan = _plan(<PracticeDay>[
      buildDay(id: 'day.missed.1', localDate: LocalDate(2026, 9, 1)),
      buildDay(id: 'day.missed.2', localDate: LocalDate(2026, 9, 2)),
      buildDay(id: 'day.future', localDate: LocalDate(2026, 9, 10)),
    ]);

    final proposal = _valueOf(await _useCase()(plan))!;

    expect(proposal.requiresReview, isTrue);
    // Pending until the learner decides — the revision is withheld.
    expect(proposal.proposal.revision, isNull);
    expect(
      proposal.proposal.confirmation,
      PlanChangeConfirmation.pending,
    );
  });

  test('an already-expired day is never proposed again (idempotent)', () async {
    final expired = buildDay(
      id: 'day.missed',
      localDate: LocalDate(2026, 9, 1),
    ).transitionTo(PracticeItemStatus.expired);
    final plan = _plan(<PracticeDay>[
      expired,
      buildDay(id: 'day.future', localDate: LocalDate(2026, 9, 10)),
    ]);

    final result = await _useCase()(plan);

    expect(_valueOf(result), isNull);
  });

  test('a completed past day is not a missed day', () async {
    final completed = buildDay(
      id: 'day.done',
      localDate: LocalDate(2026, 9, 1),
      status: PracticeItemStatus.completed,
    );
    final plan = _plan(<PracticeDay>[
      completed,
      buildDay(id: 'day.future', localDate: LocalDate(2026, 9, 10)),
    ]);

    expect(_valueOf(await _useCase()(plan)), isNull);
  });
}
