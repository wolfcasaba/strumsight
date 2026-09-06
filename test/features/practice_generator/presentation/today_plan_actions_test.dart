// Javító sáv 2026-09-06 (R4) — the Today screen's actions over the ACTIVE
// plan, composed for the first time (`today_plan_actions.dart`).
//
// A1 — pause moves the active plan to `paused` under a NEW revision.
// A2 — skip marks today's first pending block `skipped` and persists it.
// A3 — without an active plan nothing is written (nothingToChange).
// A4 — shorten with nothing pending is nothingToChange and the stored
//      revision does not move.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/presentation/today_plan_actions.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';
import '../../../support/preference_store.dart';

void main() {
  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        ...preferenceOverrides(),
        practiceGeneratorClockProvider.overrideWithValue(
          () => DateTime(2026, 8, 17, 10),
        ),
        exerciseCandidateResolverProvider.overrideWithValue(resolveCandidate),
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

    test('A4 — shorten with nothing pending leaves the revision alone',
        () async {
      final container = buildContainer();
      final allSkipped = plan().copyWith(
        days: <PracticeDay>[
          day().replaceContent(
            blocks: <PracticeBlock>[block(status: PracticeItemStatus.skipped)],
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
