// Javító sáv 2026-09-06 (R4) — the Today screen's actions over the ACTIVE
// plan, composed for the first time (`today_plan_actions.dart`).
//
// A1 — pause moves the active plan to `paused` under a NEW revision.
// A2 — skip marks today's first pending block `skipped` and persists it.
// A3 — without an active plan nothing is written (nothingToChange).
// A4 — shorten with nothing pending is nothingToChange and the stored
//      revision does not move.
//
// R10 (2026-09-07) — the Swap button, disabled by R4 because the controller
// had no swap operation:
// A5 — swap replaces today's exercise with a same-skill catalog alternative
//      and the replacement survives a repository read-back.
// A6 — swap with no usable alternative reports `noAlternative` and leaves
//      the stored plan (exercise AND revision) untouched.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/presentation/today_plan_actions.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';
import '../../../support/preference_store.dart';

/// A second catalog candidate that shares the fixture block's skill target
/// (`rhythm.quarterNotes`), supports tempo (the fixture's success criterion
/// requires it) and can execute the fixture's 5-minute active duration — so
/// it is the alternative a swap must actually find.
ExerciseCandidate alternativeCandidate() {
  final capabilities = allCapabilitiesUnsupported()
    ..[ExerciseCapability.supportsTempo] = CapabilitySupport.supported;
  return ExerciseCandidate(
    exerciseId: 'exercise.rhythm.alt',
    source: CandidateSource.practiceCatalog,
    skillTargets: const <String>['rhythm.quarterNotes'],
    prerequisites: const <String>['guitar.tuned'],
    supportedDurations: SupportedDurations(
      minimum: const Duration(minutes: 1),
      maximum: const Duration(minutes: 10),
    ),
    difficultyRange: DifficultyRange.exact('beginner'),
    capabilities: capabilities,
    loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
    offlineAvailable: true,
    contentRevision: 'content.v1',
  );
}

/// The repository deserializes a stored block through this resolver, so the
/// swapped-in id has to resolve too — otherwise A5 could not read back.
ExerciseCandidate resolveWithAlternative(String exerciseId) {
  if (exerciseId == 'exercise.rhythm.alt') return alternativeCandidate();
  return resolveCandidate(exerciseId);
}

PracticeCatalogSnapshot catalogSnapshot(List<ExerciseCandidate> candidates) {
  return PracticeCatalogSnapshot(
    catalogRevision: 'catalog.test',
    contentRevision: 'content.v1',
    candidates: candidates,
  );
}

void main() {
  ProviderContainer buildContainer({
    PracticeCatalogSnapshot? catalog,
    ExerciseCandidateResolver resolve = resolveCandidate,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        practiceGeneratorClockProvider.overrideWithValue(
          () => DateTime(2026, 8, 17, 10),
        ),
        exerciseCandidateResolverProvider.overrideWithValue(resolve),
        if (catalog != null)
          practiceCatalogSnapshotProvider.overrideWithValue(catalog),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<AdaptivePracticePlan?> activePlan(ProviderContainer container) =>
      container.read(activePracticePlanProvider.future);

  group('TodayPlanActions', () {
    test('A1 — pause parks the active plan under a new revision', () async {
      final container = buildContainer();
      await container
          .read(localPracticePlanRepositoryProvider)
          .activate(plan());
      expect((await activePlan(container))!.status, PlanStatus.active);

      final outcome = await container
          .read(todayPlanActionsProvider)
          .apply(TodayPlanAction.pause);

      expect(outcome, TodayPlanActionOutcome.applied);
      final stored = (await activePlan(container))!;
      expect(stored.status, PlanStatus.paused);
      expect(stored.activeRevisionId, isNot(RevisionId('revision.1')));
    });

    test('A2 — skip marks today\'s first pending block skipped', () async {
      final container = buildContainer();
      await container
          .read(localPracticePlanRepositoryProvider)
          .activate(plan());

      final outcome = await container
          .read(todayPlanActionsProvider)
          .apply(TodayPlanAction.skip);

      expect(outcome, TodayPlanActionOutcome.applied);
      final stored = (await activePlan(container))!;
      expect(
        stored.days.single.blocks.single.status,
        PracticeItemStatus.skipped,
      );
    });

    test('A3 — without an active plan nothing is written', () async {
      final container = buildContainer();

      final outcome = await container
          .read(todayPlanActionsProvider)
          .apply(TodayPlanAction.skip);

      expect(outcome, TodayPlanActionOutcome.nothingToChange);
      expect(await activePlan(container), isNull);
    });

    test(
      'A4 — shorten with nothing pending leaves the revision alone',
      () async {
        final container = buildContainer();
        final allSkipped = plan().copyWith(
          days: <PracticeDay>[
            day().replaceContent(
              blocks: <PracticeBlock>[
                block(status: PracticeItemStatus.skipped),
              ],
            ),
          ],
        );
        await container
            .read(localPracticePlanRepositoryProvider)
            .activate(allSkipped);

        final outcome = await container
            .read(todayPlanActionsProvider)
            .apply(TodayPlanAction.shorten);

        expect(outcome, TodayPlanActionOutcome.nothingToChange);
        final stored = (await activePlan(container))!;
        expect(stored.activeRevisionId, RevisionId('revision.1'));
      },
    );

    test('A5 — swap replaces today\'s exercise and persists it', () async {
      final catalog = catalogSnapshot(<ExerciseCandidate>[
        resolveCandidate('exercise.rhythm'),
        alternativeCandidate(),
      ]);
      final container = buildContainer(
        catalog: catalog,
        resolve: resolveWithAlternative,
      );
      await container
          .read(localPracticePlanRepositoryProvider)
          .activate(plan());

      final outcome = await container
          .read(todayPlanActionsProvider)
          .apply(TodayPlanAction.swap);

      expect(outcome, TodayPlanActionOutcome.applied);
      // Read back THROUGH the repository — the assertion is persistence,
      // not an in-memory snapshot the action happened to return.
      final stored = (await activePlan(container))!;
      final swapped = stored.days.single.blocks.single;
      expect(swapped.prescription.exerciseId, 'exercise.rhythm.alt');
      expect(swapped.status, PracticeItemStatus.planned);
      expect(stored.activeRevisionId, isNot(RevisionId('revision.1')));
    });

    test('A6 — swap without an alternative changes nothing', () async {
      final catalog = catalogSnapshot(<ExerciseCandidate>[
        resolveCandidate('exercise.rhythm'),
      ]);
      final container = buildContainer(catalog: catalog);
      await container
          .read(localPracticePlanRepositoryProvider)
          .activate(plan());

      final outcome = await container
          .read(todayPlanActionsProvider)
          .apply(TodayPlanAction.swap);

      expect(outcome, TodayPlanActionOutcome.noAlternative);
      final stored = (await activePlan(container))!;
      expect(
        stored.days.single.blocks.single.prescription.exerciseId,
        'exercise.rhythm',
      );
      expect(stored.activeRevisionId, RevisionId('revision.1'));
    });
  });

  test('the repository round-trips the fixture plan (guards the fixtures '
      'above, not the actions)', () async {
    final container = buildContainer();
    final repository = container.read(localPracticePlanRepositoryProvider);

    await repository.activate(plan());
    final read = await repository.readActivePlan();

    expect(read, isA<Success<AdaptivePracticePlan?>>());
  });
}
