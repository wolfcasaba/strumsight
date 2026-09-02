import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

/// E15-R14 §6/A4: [StartPlanGeneration] assembles the Setup-wizard's draft
/// into a [GenerationPlanInput] (via an injected builder — the assembly
/// itself needs a catalog/evidence pipeline outside this round's scope,
/// ADR 0482 §Kontextus point 4) and calls ONLY the existing
/// [GenerationOrchestrator] — no new generation logic, per the round's
/// STOP-protocol.
void main() {
  group('StartPlanGeneration', () {
    test('A4 success: the draft becomes an active AdaptivePracticePlan '
        'through the existing GenerationOrchestrator', () async {
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      addTearDown(orchestrator.dispose);
      final draft = _draft();
      final useCase = StartPlanGeneration(
        orchestrator: orchestrator,
        buildInput: (request) => _input(request),
      );

      final result = await useCase(draft);

      expect(result, isA<Success<AdaptivePracticePlan>>());
      expect(
        (result as Success<AdaptivePracticePlan>).value.status,
        PlanStatus.active,
      );
      expect(activation.calls, 1);
    });

    test(
      'A4 failure: a broken assembly surfaces as an AppResult failure, '
      'never a thrown exception, and never activates a partial plan',
      () async {
        final activation = _RecordingActivation();
        final orchestrator = GenerationOrchestrator(activation: activation);
        addTearDown(orchestrator.dispose);
        final draft = _draft();
        final useCase = StartPlanGeneration(
          orchestrator: orchestrator,
          buildInput: (request) =>
              _input(request, scheduledIdentity: 'practiceCatalog:missing:v1'),
        );

        final result = await useCase(draft);

        expect(result, isA<Failure<AdaptivePracticePlan>>());
        expect(activation.calls, isZero);
      },
    );

    test('delegates strictly to the injected orchestrator/builder — the '
        'GenerationPlanInput handed to generate() is exactly what the '
        'builder produced', () async {
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      addTearDown(orchestrator.dispose);
      final draft = _draft();
      GenerationPlanInput? seen;
      final useCase = StartPlanGeneration(
        orchestrator: orchestrator,
        buildInput: (request) {
          final input = _input(request);
          seen = input;
          return input;
        },
      );

      await useCase(draft);

      expect(seen, isNotNull);
      expect(seen!.request, draft);
    });

    test('MINOR-4: a builder that THROWS surfaces as an AppResult failure, '
        'not a thrown exception (start_plan_generation.dart:45 is now '
        'guarded, matching this class\'s own "never a thrown exception" '
        'doc-contract)', () async {
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      addTearDown(orchestrator.dispose);
      final draft = _draft();
      final useCase = StartPlanGeneration(
        orchestrator: orchestrator,
        buildInput: (request) => throw StateError('assembly exploded'),
      );

      final result = await useCase(draft);

      expect(result, isA<Failure<AdaptivePracticePlan>>());
      expect(activation.calls, isZero);
    });
  });

  group('MINOR-7: measured through the composition root, not standalone', () {
    test('startPlanGenerationProvider wires the SAME orchestrator the '
        'composition root itself builds and disposes (ADR 0482 / D8, M5) — '
        'not a standalone re-construction the test made up', () {
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          exerciseCandidateResolverProvider.overrideWithValue(
            (exerciseId) => buildCandidate(exerciseId: exerciseId),
          ),
          generationPlanInputBuilderProvider.overrideWithValue(
            (request) => _input(request),
          ),
        ],
      );
      addTearDown(container.dispose);

      final useCase = container.read(startPlanGenerationProvider);

      expect(useCase, isA<StartPlanGeneration>());
      expect(
        identical(
          useCase.orchestrator,
          container.read(generationOrchestratorProvider),
        ),
        isTrue,
      );
    });
  });
}

PracticeGenerationRequest _draft() => PracticeGenerationRequest(
  id: GenerationRequestId('request.start-plan-generation'),
  createdAt: DateTime.utc(2026, 8, 18),
  locale: 'en',
  generationMode: GenerationMode.starter,
  planHorizonDays: 1,
  availability: buildAvailability(),
  constraints: LearnerConstraints(const <LearnerConstraint>[]),
  goals: <PracticeGoal>[buildGoal()],
);

GenerationPlanInput _input(
  PracticeGenerationRequest request, {
  String? scheduledIdentity,
}) {
  final candidate = buildCandidate();
  final availability = request.availability;
  return GenerationPlanInput(
    request: request,
    schedule: WeeklyScheduleDecision(
      dayDecisions: <DaySchedulingDecision>[
        DaySchedulingDecision(
          date: availability.days.single.date,
          phase: SchedulingPhase.none,
          selectedCandidates: <ScheduleCandidate>[
            ScheduleCandidate(
              identity: scheduledIdentity ?? candidate.sortKey,
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
    planId: PlanId('plan.start-plan-generation'),
    initialRevisionId: RevisionId('revision.start-plan-generation'),
  );
}

final class _RecordingActivation implements GenerationPlanActivation {
  int calls = 0;

  @override
  Future<void> activate(AdaptivePracticePlan plan) async {
    calls += 1;
  }
}
