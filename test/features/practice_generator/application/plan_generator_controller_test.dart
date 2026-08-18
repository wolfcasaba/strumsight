import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  test('A7: immutable state rejects an invalid transition', () {
    expect(
      () => GenerationState.initial.transitionTo(GenerationStatus.completed),
      throwsStateError,
    );
  });

  test('A7: controller publishes ordered immutable terminal state', () async {
    final controller = PlanGeneratorController(
      orchestrator: GenerationOrchestrator(activation: _NoopActivation()),
    );
    final states = <GenerationState>[];
    final subscription = controller.states.listen(states.add);

    final result = await controller.generate(_input());

    await subscription.cancel();
    expect(result, isA<Success<AdaptivePracticePlan>>());
    expect(controller.state.status, GenerationStatus.completed);
    expect(
      states.map((state) => state.status),
      contains(GenerationStatus.running),
    );
    expect(states.last.status, GenerationStatus.completed);
  });

  test('A8: generation returns a future while activation is pending', () async {
    final activation = _BlockingActivation();
    final controller = PlanGeneratorController(
      orchestrator: GenerationOrchestrator(activation: activation),
    );

    final pending = controller.generate(_input());
    await activation.started.future;

    expect(controller.state.status, GenerationStatus.running);
    activation.complete();
    expect(await pending, isA<Success<AdaptivePracticePlan>>());
  });
}

GenerationPlanInput _input() {
  final candidate = buildCandidate();
  final availability = buildAvailability();
  final request = PracticeGenerationRequest(
    id: GenerationRequestId('request.controller'),
    createdAt: DateTime.utc(2026, 8, 18),
    locale: 'en',
    generationMode: GenerationMode.starter,
    planHorizonDays: 1,
    availability: availability,
    constraints: LearnerConstraints(const <LearnerConstraint>[]),
    goals: <PracticeGoal>[buildGoal()],
  );
  return GenerationPlanInput(
    request: request,
    schedule: WeeklyScheduleDecision(
      dayDecisions: <DaySchedulingDecision>[
        DaySchedulingDecision(
          date: availability.days.single.date,
          phase: SchedulingPhase.none,
          selectedCandidates: <ScheduleCandidate>[
            ScheduleCandidate(
              identity: candidate.sortKey,
              focus: CandidateFocus.primaryFocus,
              materialKind: CandidateMaterialKind.newMaterial,
              loadLevel: LoadLevel.low,
              duration: const Duration(minutes: 5),
              skillTargets: candidate.skillTargets,
            ),
          ],
          reasonCodes: const <String>['schedule.decision.selected'],
        ),
      ],
      deferredCandidates: const <DeferredCandidate>[],
      policyVersion: SchedulingPolicy.defaultPolicy.version,
      policy: SchedulingPolicy.defaultPolicy,
    ),
    validationContext: buildContext(
      availability: availability,
      catalog: buildCatalog(candidates: <ExerciseCandidate>[candidate]),
    ),
    planId: PlanId('plan.controller'),
    initialRevisionId: RevisionId('revision.controller'),
  );
}

final class _NoopActivation implements GenerationPlanActivation {
  @override
  Future<void> activate(AdaptivePracticePlan plan) async {}
}

final class _BlockingActivation implements GenerationPlanActivation {
  final Completer<void> started = Completer<void>();
  final Completer<void> _completion = Completer<void>();

  @override
  Future<void> activate(AdaptivePracticePlan plan) {
    started.complete();
    return _completion.future;
  }

  void complete() => _completion.complete();
}
