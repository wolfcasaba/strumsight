import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

/// Riverpod 3 wraps a provider-creation error in a [ProviderException]
/// (possibly nested, when the failure comes from a chain of `ref.watch`
/// calls) whenever it crosses a `container.read`/`ref.watch` boundary.
/// The B2 guard cells below care about the ROOT cause
/// (`UnimplementedError`, the deliberate open-seam signal — round brief
/// §10.9 / ADR 0482 / D9), not how many wrapping layers Riverpod added.

// 2026-09-05: a `_throwsUnimplementedSeam` matcher MEGSZŰNT, mert nincs
// többé nyitott seam ebben a fájlban — a katalógus-feloldó és a
// terv-bemenet építő is be van kötve. A matchert nem `ignore`-ral
// hagytuk bent: egy „dobásra váró" segéd egy bekötött rendszerben azt
// sugallná, hogy még van mire várni.

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
      // MINOR-5 fix: a positive assertion on the concrete type, not a
      // lone `isNot` that doesn't independently falsify anything.
      expect(
        deleteUseCase.evidenceRepository,
        isA<LocalPracticeEvidenceRepository>(),
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

      // M3 fix: the today-provider now exposes a function, computed at
      // READ time, never a value cached in provider state.
      final today = container.read(practiceGeneratorTodayProvider);
      final activePlan = await container.read(
        activePracticePlanProvider.future,
      );

      expect(today(), isA<LocalDate>());
      expect(activePlan, isNull); // nothing activated in this test scope.
    });
  });

  test('M3: practiceGeneratorTodayProvider computes "today" at READ time — '
      'two different clock readings in the SAME container produce two '
      'different results (no LocalDate frozen in provider state)', () {
    var current = DateTime.utc(2026, 9, 2, 23, 59);
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        exerciseCandidateResolverProvider.overrideWithValue(
          (exerciseId) => buildCandidate(exerciseId: exerciseId),
        ),
        generationPlanInputBuilderProvider.overrideWithValue(
          (request) => _fixtureInput(request),
        ),
        practiceGeneratorClockProvider.overrideWithValue(() => current),
      ],
    );
    addTearDown(container.dispose);

    final today = container.read(practiceGeneratorTodayProvider);
    final first = today();
    current = DateTime.utc(2026, 9, 3, 0, 1);
    final second = today();

    expect(first, LocalDate(2026, 9, 2));
    expect(second, LocalDate(2026, 9, 3));
  });

  test("M4: a corrupt active-plan pointer surfaces as an AsyncError, never "
      'silently reclassified as "no active plan" '
      '(LocalPracticePlanRepository\'s own doc-contract, '
      'local_practice_plan_repository.dart:358-361)', () async {
    final store = InMemoryKeyValueStore({
      'ss.practice_generator.plan.active_pointer': 'not-json-at-all{{{',
    });
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        exerciseCandidateResolverProvider.overrideWithValue(
          (exerciseId) => buildCandidate(exerciseId: exerciseId),
        ),
        generationPlanInputBuilderProvider.overrideWithValue(
          (request) => _fixtureInput(request),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(activePracticePlanProvider.future),
      throwsA(isA<Object>()),
    );
    expect(
      container.read(activePracticePlanProvider),
      isA<AsyncError<AdaptivePracticePlan?>>(),
    );
  });

  test('M5: generationOrchestratorProvider is autoDispose — its progress '
      'stream closes once nothing watches it, without waiting for the '
      'whole container to be disposed (ADR 0482 / D8, brief §5.5)', () async {
    final container = buildContainer();
    var closed = false;
    final subscription = container.listen(
      generationOrchestratorProvider,
      (previous, next) {},
    );
    final orchestrator = container.read(generationOrchestratorProvider);
    orchestrator.progress.listen((_) {}, onDone: () => closed = true);

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(closed, isTrue);
  });

  group(
    'B2 guard: a production-shape container (keyValueStoreProvider '
    'overridden ONLY) — which provider builds and which throws is a '
    'MEASURED fact, not an assumption (round brief §10.1, ADR 0482 / D9)',
    () {
      ProviderContainer buildProductionShapeContainer() {
        final container = ProviderContainer(
          overrides: [
            keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      test('1/6 PlanSetup: planSetupControllerProvider builds', () {
        final container = buildProductionShapeContainer();
        expect(
          () => container.read(planSetupControllerProvider),
          returnsNormally,
        );
      });

      // 2026-09-05: a cella MEGFORDULT. Korábban azt rögzítette, hogy a
      // provider DOB, mert nem volt éles `ExerciseCandidateResolver`. Az a
      // seam azóta be van kötve (beépített katalógus + tervezői metaadat),
      // ezért a mért tény most az ellenkezője. A cella nem törlődött: a
      // hibaosztály ugyanaz marad, csak az elvárt irány fordult.
      test('2/6 PlanPreview: planPreviewControllerFactoryProvider builds — '
          'az éles ExerciseCandidateResolver be van kötve', () {
        final container = buildProductionShapeContainer();
        expect(
          () => container.read(planPreviewControllerFactoryProvider),
          returnsNormally,
        );
      });

      test('3/6 PlanPrivacy: deletePracticePlanningDataProvider and '
          'exportPracticePlanningDataProvider both build', () {
        final container = buildProductionShapeContainer();
        expect(
          () => container.read(deletePracticePlanningDataProvider),
          returnsNormally,
        );
        expect(
          () => container.read(exportPracticePlanningDataProvider),
          returnsNormally,
        );
      });

      test('4/6 PlanChangeReview: revisePracticePlanProvider builds', () {
        final container = buildProductionShapeContainer();
        expect(
          () => container.read(revisePracticePlanProvider),
          returnsNormally,
        );
      });

      test('5/6 TodayPlan: todayPlanControllerProvider builds', () {
        final container = buildProductionShapeContainer();
        expect(
          () => container.read(todayPlanControllerProvider),
          returnsNormally,
        );
      });

      test('6/6 WeeklyPlan: a nap ÉS az aktív terv is felold — a terv '
          'hiánya `null`, nem kivétel', () async {
        final container = buildProductionShapeContainer();
        expect(
          () => container.read(practiceGeneratorTodayProvider),
          returnsNormally,
        );
        // Üres tárolón NINCS mentett terv. A helyes válasz `null` — az a
        // „még nincs terv" állapot, amit a képernyő maga is kezel —, nem
        // kivétel és nem kitalált üres terv.
        await expectLater(
          container.read(activePracticePlanProvider.future),
          completion(isNull),
        );
      });

      test(
        'GEN: generationOrchestratorProvider és startPlanGenerationProvider '
        'egyaránt felépül — mindkét seam be van kötve',
        () {
          final container = buildProductionShapeContainer();
          expect(
            () => container.read(generationOrchestratorProvider),
            returnsNormally,
          );
          expect(
            () => container.read(startPlanGenerationProvider),
            returnsNormally,
          );
        },
      );
    },
  );

  test('production default: the evidence repository is the PERSISTENT '
      'implementation, never the never-forgets in-memory test fake '
      '(A1/A7)', () {
    final container = buildContainer();

    final repository = container.read(practiceEvidenceRepositoryProvider);

    expect(repository, isA<LocalPracticeEvidenceRepository>());
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
