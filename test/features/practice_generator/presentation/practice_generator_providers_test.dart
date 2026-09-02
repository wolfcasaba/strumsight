import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

/// E15-R14 §6/A3: every MANDATORY constructor dependency of the 6 plan
/// screens (round brief §0.0.B/R4) resolves from ONE `ProviderScope`, with
/// NO route opened and NO screen touched (ADR 0482 / D1, D7).
void main() {
  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        exerciseCandidateResolverProvider.overrideWithValue(
          (exerciseId) => buildCandidate(exerciseId: exerciseId),
        ),
        generationPlanInputBuilderProvider.overrideWithValue(
          (request) => _fixtureInput(request),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('practice_generator_providers — A3 (one cell per screen)', () {
    test('PlanSetupScreen: PlanSetupController builds from the scope', () {
      final container = buildContainer();

      final controller = container.read(planSetupControllerProvider);

      expect(controller, isA<PlanSetupController>());
      expect(controller.state.currentStep, 0);
    });

    test('PlanPreviewScreen: PlanPreviewController builds with the REAL '
        'LocalPracticePlanRepository as its activation (ADR 0482 / D4) — '
        'never a no-op', () {
      final container = buildContainer();
      final buildPreviewController = container.read(
        planPreviewControllerFactoryProvider,
      );
      final plan = buildPlan();

      final controller = buildPreviewController(
        initialPlan: plan,
        validationContext: buildContext(),
      );

      expect(controller, isA<PlanPreviewController>());
      expect(
        identical(
          controller.activation,
          container.read(localPracticePlanRepositoryProvider),
        ),
        isTrue,
        reason:
            'the preview controller must share the composition root\'s '
            'single, real LocalPracticePlanRepository instance',
      );
    });

    test('PlanPrivacyScreen: DeletePracticePlanningData + '
        'ExportPracticePlanningData build from the scope, both bound to the '
        'PERSISTENT evidence repository (ADR 0482 / D2)', () {
      final container = buildContainer();

      final deleteUseCase = container.read(deletePracticePlanningDataProvider);
      final exportUseCase = container.read(exportPracticePlanningDataProvider);

      expect(deleteUseCase, isA<DeletePracticePlanningData>());
      expect(exportUseCase, isA<ExportPracticePlanningData>());
      expect(
        deleteUseCase.evidenceRepository,
        isNot(isA<InMemoryPracticeEvidenceRepository>()),
      );
      expect(
        identical(
          deleteUseCase.evidenceRepository,
          exportUseCase.evidenceRepository,
        ),
        isTrue,
      );
    });

    test('PlanChangeReviewScreen: the RevisePracticePlan that PRODUCES the '
        'proposal builds from the scope', () {
      final container = buildContainer();

      final revise = container.read(revisePracticePlanProvider);

      expect(revise, isA<RevisePracticePlan>());
      final plan = buildPlan();
      final revision = PlanRevision(
        id: RevisionId('revision.1'),
        planId: plan.id,
        number: 1,
        createdAt: DateTime.utc(2026, 8, 20),
        reason: PlanRevisionReason.learnerReschedule,
        changeSet: PlanChangeSet(
          fromRevisionId: RevisionId('revision.0'),
          toRevisionId: RevisionId('revision.1'),
          changes: const <PlanChange>[],
        ),
        snapshot: plan,
        previous: null,
      );
      final proposal = revise(
        RevisePracticePlanRequest(
          previous: revision,
          nextRevisionId: RevisionId('revision.2'),
          candidateSnapshot: plan,
          changes: const <PlanChange>[],
          reason: PlanRevisionReason.learnerReschedule,
          confirmation: PlanChangeConfirmation.pending,
        ),
      );
      expect(proposal, isA<PlanRevisionProposal>());
    });

    test('TodayPlanScreen: TodayPlanController builds from the scope', () {
      final container = buildContainer();

      final controller = container.read(todayPlanControllerProvider);

      expect(controller, isA<TodayPlanController>());
    });

    test('WeeklyPlanScreen: the active-plan provider and the today provider '
        'both build from the scope', () async {
      final container = buildContainer();

      final today = container.read(practiceGeneratorTodayProvider);
      final activePlan = await container.read(
        activePracticePlanProvider.future,
      );

      expect(today, isA<LocalDate>());
      expect(activePlan, isNull); // nothing activated in this test scope.
    });
  });

  test('production default: the evidence repository is the PERSISTENT '
      'implementation, never the never-forgets in-memory test fake '
      '(A1/A7)', () {
    final container = buildContainer();

    final repository = container.read(practiceEvidenceRepositoryProvider);

    expect(repository, isA<LocalPracticeEvidenceRepository>());
    expect(repository, isNot(isA<InMemoryPracticeEvidenceRepository>()));
  });

  test('D8: disposing the ProviderScope closes the GenerationOrchestrator\'s '
      'progress stream', () async {
    final container = buildContainer();
    final orchestrator = container.read(generationOrchestratorProvider);
    var closed = false;
    orchestrator.progress.listen((_) {}, onDone: () => closed = true);

    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(closed, isTrue);
  });
}

GenerationPlanInput _fixtureInput(PracticeGenerationRequest request) {
  final candidate = buildCandidate();
  final availability = request.availability.days.isEmpty
      ? buildAvailability()
      : request.availability;
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
    planId: PlanId('plan.provider-fixture'),
    initialRevisionId: RevisionId('revision.provider-fixture'),
  );
}
