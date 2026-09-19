import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';
import '../../fixtures/practice_generator/validation/validation_fixtures.dart';

/// E17-R06 §6 (ADR 0525): the four remaining Practice Generator screens
/// are reachable from `TodayPlanScreen` — through a real
/// `ProviderContainer` in the shape `main.dart` builds (the key-value
/// store injected, the composition root otherwise untouched) — and the
/// change-review's accept / reject both return to Today (A2, A3). The
/// screens open ONLY from Today's own AppBar menu: no shell-root entry,
/// no new feature flag (§5.1, §5.2, A4).
void main() {
  group('E17-R06 / A2 — TodayPlan → each of the four screens', () {
    testWidgets('Weekly plan opens (no active plan → its own empty state)', (
      tester,
    ) async {
      final container = _container();
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-weekly');

      expect(find.byType(WeeklyPlanScreen), findsOneWidget);
      expect(find.byType(TodayPlanScreen), findsNothing);
    });

    testWidgets('Weekly plan opens on the ACTIVE plan read back from the '
        'real plan repository', (tester) async {
      final container = _container(overrides: [_fixtureResolver()]);
      await _activateFixturePlan(container);
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-weekly');

      expect(find.byType(WeeklyPlanScreen), findsOneWidget);
      expect(find.byKey(const Key('weekly-plan-day-day.1')), findsOneWidget);
    });

    testWidgets('Plan preview without an active plan is an explicit '
        '"create a plan first" state, never an empty preview', (tester) async {
      final container = _container();
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-preview');

      expect(
        find.byKey(const Key('today-plan-preview-no-plan')),
        findsOneWidget,
      );
      expect(find.byType(PlanPreviewScreen), findsNothing);
    });

    testWidgets('Plan preview opens on the ACTIVE plan with a controller '
        'built by the composition root', (tester) async {
      final container = _container(overrides: [_fixtureResolver()]);
      await _activateFixturePlan(container);
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-preview');

      expect(find.byType(PlanPreviewScreen), findsOneWidget);
    });

    testWidgets('Plan change review without an active plan is an explicit '
        '"nothing to review" state', (tester) async {
      final container = _container();
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-change-review');

      expect(
        find.byKey(const Key('today-plan-change-review-empty')),
        findsOneWidget,
      );
      expect(find.byType(PlanChangeReviewScreen), findsNothing);
    });

    testWidgets('Plan change review opens on today\'s proposal derived from '
        'the ACTIVE plan (shorten today\'s first pending block)', (
      tester,
    ) async {
      final container = _container(overrides: [_fixtureResolver()]);
      await _activateFixturePlan(container);
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-change-review');

      expect(find.byType(PlanChangeReviewScreen), findsOneWidget);
      final screen = tester.widget<PlanChangeReviewScreen>(
        find.byType(PlanChangeReviewScreen),
      );
      expect(screen.proposal.changeSet.changes, hasLength(1));
      expect(
        screen.proposal.changeSet.changes.single.target,
        'day:day.1:block:day.1.block.1',
      );
    });

    testWidgets('Plan privacy opens with the real delete + export use cases', (
      tester,
    ) async {
      final container = _container();
      await _pumpToday(tester, container);

      await _openMenuItem(tester, 'today-plan-open-privacy');

      expect(find.byType(PlanPrivacyScreen), findsOneWidget);
      final screen = tester.widget<PlanPrivacyScreen>(
        find.byType(PlanPrivacyScreen),
      );
      expect(
        identical(
          screen.deleteUseCase,
          container.read(deletePracticePlanningDataProvider),
        ),
        isTrue,
      );
    });
  });

  group('E17-R06 / A3 — change review accept / reject pop back to Today', () {
    testWidgets('accept activates the confirmed revision and returns to '
        'Today', (tester) async {
      final container = _container(
        overrides: [
          _fixtureResolver(),
          todayPlanChangeProposalProvider.overrideWith(
            (ref) async => _confirmationProposal(),
          ),
        ],
      );
      await _activateFixturePlan(container);
      await _pumpToday(tester, container);
      await _openMenuItem(tester, 'today-plan-open-change-review');
      expect(find.byType(PlanChangeReviewScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-change-review-accept')));
      await tester.pumpAndSettle();

      expect(find.byType(PlanChangeReviewScreen), findsNothing);
      expect(find.byType(TodayPlanScreen), findsOneWidget);
      final active = await container.read(activePracticePlanProvider.future);
      expect(active?.activeRevisionId, RevisionId('revision.2'));
    });

    testWidgets('reject leaves the active plan untouched and returns to '
        'Today', (tester) async {
      final container = _container(
        overrides: [
          _fixtureResolver(),
          todayPlanChangeProposalProvider.overrideWith(
            (ref) async => _confirmationProposal(),
          ),
        ],
      );
      await _activateFixturePlan(container);
      await _pumpToday(tester, container);
      await _openMenuItem(tester, 'today-plan-open-change-review');
      expect(find.byType(PlanChangeReviewScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-change-review-reject')));
      await tester.pumpAndSettle();

      expect(find.byType(PlanChangeReviewScreen), findsNothing);
      expect(find.byType(TodayPlanScreen), findsOneWidget);
      final active = await container.read(activePracticePlanProvider.future);
      expect(active?.activeRevisionId, RevisionId('revision.1'));
    });
  });
}

/// The fixture plan's only day is 2026-08-17 — "today" for every cell.
final DateTime _today = DateTime(2026, 8, 17, 9);

ProviderContainer _container({List<Override> overrides = const <Override>[]}) {
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      practiceGeneratorClockProvider.overrideWithValue(() => _today),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The fixture plan's exercise ids are not in the shipped catalog, so the
/// plan-dependent cells resolve them with the fixture candidate — the same
/// override the composition-root test uses.
Override _fixtureResolver() => exerciseCandidateResolverProvider
    .overrideWithValue((exerciseId) => buildCandidate(exerciseId: exerciseId));

Future<void> _activateFixturePlan(ProviderContainer container) =>
    container.read(localPracticePlanRepositoryProvider).activate(buildPlan());

/// A GoRouter harness, not a bare `MaterialApp`: the weekly plan and the
/// privacy screen have registered addresses and open through
/// `context.push` (so they stay deep-linkable), while the preview and the
/// change review are built in place — they need an `extra` this screen
/// cannot produce. The two routed builders are the router's own shape,
/// reading the SAME composition root the test injects.
Future<void> _pumpToday(
  WidgetTester tester,
  ProviderContainer container,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        initialLocation: AppRoutes.practiceGeneratorToday,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.practiceGeneratorToday,
            builder: (_, _) => TodayPlanScreen(
              controller: TodayPlanController(clock: () => _today),
            ),
          ),
          GoRoute(
            path: AppRoutes.practiceGeneratorWeekly,
            builder: (_, _) => Consumer(
              builder: (context, ref, _) => WeeklyPlanScreen(
                plan: ref.watch(activePracticePlanProvider).value,
                today: ref.watch(practiceGeneratorTodayProvider)(),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.practiceGeneratorPrivacy,
            builder: (_, _) => Consumer(
              builder: (context, ref, _) => PlanPrivacyScreen(
                deleteUseCase: ref.watch(deletePracticePlanningDataProvider),
                exportUseCase: ref.watch(exportPracticePlanningDataProvider),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _openMenuItem(WidgetTester tester, String itemKey) async {
  await tester.tap(find.byKey(const Key('today-plan-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(itemKey)));
  await tester.pumpAndSettle();
}

/// A proposal that REQUIRES confirmation (two changes ≥ the
/// `RevisePracticePlan.confirmationThreshold`), so the review screen shows
/// its accept / reject controls — built through the real use case.
TodayPlanChangeProposal _confirmationProposal() {
  final plan = buildPlan();
  PlanChange change(String key, int before, int after) => PlanChange(
    type: PlanChangeType.updated,
    target: 'day:day.1:block:day.1.block.1',
    before: <String, Object?>{key: before},
    after: <String, Object?>{key: after},
    reason: PlanChangeReason.learnerReschedule,
    evidenceRefs: const <String>[],
    confidence: 1,
    requiresUserConfirmation: false,
    reversible: true,
  );
  final request = RevisePracticePlanRequest(
    previous: PlanRevision(
      id: plan.activeRevisionId,
      planId: plan.id,
      number: 1,
      createdAt: plan.createdAt,
      reason: PlanRevisionReason.initialGeneration,
      snapshot: plan,
    ),
    nextRevisionId: RevisionId('revision.2'),
    candidateSnapshot: plan.copyWith(
      activeRevisionId: RevisionId('revision.2'),
    ),
    changes: <PlanChange>[
      change('activeDurationMicros', 300000000, 240000000),
      change('restDurationMicros', 60000000, 30000000),
    ],
    reason: PlanRevisionReason.learnerReschedule,
    confirmation: PlanChangeConfirmation.pending,
  );
  return TodayPlanChangeProposal(
    request: request,
    proposal: RevisePracticePlan(clock: () => _today)(request),
  );
}
