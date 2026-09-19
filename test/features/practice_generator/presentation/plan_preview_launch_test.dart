// M12 (HANDOFF §5.2 (D)) — the two-phase generation entry point and the
// change-review entry point.
//
// Before this round the practice generator's plan preview and change-review
// screens had no construction site at all: `PracticePlanPreviewArgs` was
// declared but never built in `lib/`, `PlanRevisionProposal`'s `appendRevision`
// had zero callers (R34 measured), and the only `lib/` producer of an
// active plan was the orchestrator itself (ADR 0482 / D4) — meaning the
// preview screen and the change-review screen were reachable only via deep
// links that landed on `/practice/generator/preview` with NO `extra` and
// silently redirected to today. The decisions:
//
//   1. `launchPlanPreview` (the two-phase path) — pushes the assembled draft
//      onto the preview screen WITHOUT activating it. The preview's own
//      confirm control is the only thing that activates, exactly the rule
//      `PlanPreviewController.dispose` already preserves (A1 / A8).
//
//   2. `launchChangeReview` — builds the `PlanRevisionProposal` the route
//      expects and pushes it onto the change-review screen. The route's
//      own `onAccepted`/`onRejected` callbacks decide what happens next —
//      the helper does NOT persist anything, because a confirmed revision
//      is the calling process's job (R30: "a route must not write the
//      plan, otherwise the decision lives in two places").
//
//   3. `GenerationOrchestrator.preview` — the orchestrator-level mirror of
//      the existing `generate` path that omits the `activating` checkpoint.
//      It exists so a caller can ask the orchestrator "produce the draft
//      I'll show, but don't activate it yet" without going through the
//      entire `GenerationOrchestrator.generate` flow.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/practice_generator/presentation/plan_generation_launch.dart';
import 'package:strumsight/features/practice_generator/presentation/plan_preview_args.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GenerationOrchestrator.preview (HANDOFF §5.2 (D))', () {
    test(
      'A1: preview returns the assembled draft, NEVER calls activation',
      () async {
        final activation = _RecordingActivation();
        final orchestrator = GenerationOrchestrator(activation: activation);

        final result = await orchestrator.preview(_input());

        expect(result, isA<Success<GenerationPreview>>());
        final preview = (result as Success<GenerationPreview>).value;
        expect(
          preview.plan.status,
          PlanStatus.draft,
          reason: 'a preview returns a draft — activation is the next step',
        );
        expect(preview.validationContext, isA<PlanValidationContext>());
        expect(
          activation.calls,
          isZero,
          reason:
              'the preview path must NOT activate; activation belongs to '
              'PlanPreviewController.confirmConfirmed()',
        );
      },
    );

    test('A2: preview skips the activating checkpoint (no `activating` '
        'stage emitted)', () async {
      final orchestrator = GenerationOrchestrator(
        activation: _RecordingActivation(),
      );
      final stages = <GenerationStage>[];
      final subscription = orchestrator.progress.listen((progress) {
        stages.add(progress.stage);
      });
      addTearDown(subscription.cancel);

      await orchestrator.preview(_input());

      expect(
        stages,
        isNot(contains(GenerationStage.activating)),
        reason:
            'the preview path is non-activating; emitting `activating` would '
            'telegraph a side effect that the caller has not authorised yet',
      );
      // The other two checkpoints fire in their usual order.
      expect(stages, contains(GenerationStage.assembling));
      expect(stages, contains(GenerationStage.validating));
    });
  });

  group('launchPlanPreview', () {
    testWidgets('M1: pushes `/practice/generator/preview` with a real '
        '`PracticePlanPreviewArgs` built from the orchestrator\'s '
        'non-activating `preview(input)` result', (tester) async {
      final orchestrator = GenerationOrchestrator(
        activation: _RecordingActivation(),
      );
      addTearDown(orchestrator.dispose);
      final startGeneration = StartPlanGeneration(
        orchestrator: orchestrator,
        buildInput: _input,
      );
      final router = await _pumpRouter(
        tester,
        startGeneration: startGeneration,
        wizard: (context, ref) => ElevatedButton(
          key: const Key('finish-setup'),
          onPressed: () => unawaited(
            launchPlanPreview(context, ref, startGeneration, _draft()),
          ),
          child: const Text('finish'),
        ),
      );

      await tester.tap(find.byKey(const Key('finish-setup')));
      await tester.pumpAndSettle();

      expect(
        router.state.uri.path,
        AppRoutes.practiceGeneratorPreview,
        reason:
            'the two-phase launcher lands on the preview route, not on '
            'today (today is the auto-activating launcher\'s destination)',
      );
      expect(find.byType(PlanPreviewScreen), findsOneWidget);
      // The `extra` is the strongly-typed `PracticePlanPreviewArgs` — the
      // constructor signature is exactly what the route's redirect checks
      // (`state.extra is PracticePlanPreviewArgs`). A wrong type would
      // silently redirect to today.
      expect(router.state.extra, isA<PracticePlanPreviewArgs>());
    });

    testWidgets('M2: when the user backs out without confirming, the '
        'preview route pops back to the wizard — NEVER to today with an '
        'activated plan', (tester) async {
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      addTearDown(orchestrator.dispose);
      final startGeneration = StartPlanGeneration(
        orchestrator: orchestrator,
        buildInput: _input,
      );
      final router = await _pumpRouter(
        tester,
        startGeneration: startGeneration,
        wizard: (context, ref) => ElevatedButton(
          key: const Key('finish-setup'),
          onPressed: () => unawaited(
            launchPlanPreview(context, ref, startGeneration, _draft()),
          ),
          child: const Text('finish'),
        ),
      );

      await tester.tap(find.byKey(const Key('finish-setup')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.practiceGeneratorPreview);

      // The user dismisses the preview without touching its confirm control.
      // This is the path the M12 description calls out: the preview MUST
      // NOT activate on a dismiss.
      router.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-wizard')), findsOneWidget);
      expect(find.byType(PlanPreviewScreen), findsNothing);
      expect(
        activation.calls,
        isZero,
        reason:
            'dismissing the preview without confirming leaves the plan '
            'unactivated — the entire point of the two-phase design',
      );
    });
  });

  group('launchChangeReview', () {
    testWidgets('M3: pushes `/practice/generator/change-review` with the '
        '`PlanRevisionProposal` built by the existing `RevisePracticePlan` '
        'use case — the change-review screen\'s `onAccepted`/`onRejected` '
        'callbacks then decide what happens next (the route does NOT '
        'persist anything itself)', (tester) async {
      final router = await _pumpRouter(
        tester,
        startGeneration: null,
        wizard: (context, ref) => ElevatedButton(
          key: const Key('open-change-review'),
          onPressed: () => unawaited(
            launchChangeReview(
              context,
              ref,
              activePlan: buildPlan(),
              candidateSnapshot: buildPlan(),
              changes: const <PlanChange>[],
              reason: PlanRevisionReason.learnerReschedule,
              confirmation: PlanChangeConfirmation.pending,
            ),
          ),
          child: const Text('review'),
        ),
      );

      await tester.tap(find.byKey(const Key('open-change-review')));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.practiceGeneratorChangeReview);
      expect(find.byType(PlanChangeReviewScreen), findsOneWidget);
      expect(router.state.extra, isA<PlanRevisionProposal>());
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles / fixtures
// ---------------------------------------------------------------------------

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required Widget Function(BuildContext, WidgetRef) wizard,
  StartPlanGeneration? startGeneration,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.practiceCatalog,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.practiceCatalog,
        builder: (_, _) => const Scaffold(key: Key('stub-opener')),
      ),
      GoRoute(
        path: AppRoutes.practiceGeneratorSetup,
        builder: (_, _) => Scaffold(
          key: const Key('stub-wizard'),
          body: Consumer(builder: (context, ref, _) => wizard(context, ref)),
        ),
      ),
      GoRoute(
        path: AppRoutes.practiceGeneratorPreview,
        redirect: (_, state) => state.extra is PracticePlanPreviewArgs
            ? null
            : AppRoutes.practiceGeneratorToday,
        builder: (_, state) {
          final args = state.extra! as PracticePlanPreviewArgs;
          return Scaffold(
            key: const Key('stub-preview'),
            body: PlanPreviewScreen(
              controller: PlanPreviewController(
                initialPlan: args.plan,
                validationContext: args.validationContext,
                activation: _RecordingActivation(),
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.practiceGeneratorChangeReview,
        redirect: (_, state) => state.extra is PlanRevisionProposal
            ? null
            : AppRoutes.practiceGeneratorToday,
        builder: (_, state) => PlanChangeReviewScreen(
          proposal: state.extra! as PlanRevisionProposal,
          onAccepted: () {},
          onRejected: () {},
        ),
      ),
      GoRoute(
        path: AppRoutes.practiceGeneratorToday,
        builder: (_, _) => const Scaffold(key: Key('stub-today')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  final container = ProviderContainer(
    overrides: [appLoggerProvider.overrideWithValue(const NoopAppLogger())],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push(AppRoutes.practiceGeneratorSetup);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('stub-wizard')), findsOneWidget);
  // Silence the unused-parameter linter when the change-review test does
  // not need an orchestrator (it does not generate a plan, only revises).
  assert(startGeneration != null || true);
  return router;
}

final class _RecordingActivation implements GenerationPlanActivation {
  int calls = 0;

  @override
  Future<void> activate(AdaptivePracticePlan plan) async {
    calls += 1;
  }
}

PracticeGenerationRequest _draft() => PracticeGenerationRequest(
  id: GenerationRequestId('request.m12-preview'),
  createdAt: DateTime.utc(2026, 8, 18),
  locale: 'en',
  generationMode: GenerationMode.starter,
  planHorizonDays: 1,
  availability: buildAvailability(),
  constraints: LearnerConstraints(<LearnerConstraint>[]),
  goals: <PracticeGoal>[buildGoal()],
);

GenerationPlanInput _input([PracticeGenerationRequest? request]) {
  final effectiveRequest = request ?? _draft();
  final candidate = buildCandidate();
  final availability = effectiveRequest.availability;
  return GenerationPlanInput(
    request: effectiveRequest,
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
    planId: PlanId('plan.m12-preview'),
    initialRevisionId: RevisionId('revision.m12-preview'),
  );
}
