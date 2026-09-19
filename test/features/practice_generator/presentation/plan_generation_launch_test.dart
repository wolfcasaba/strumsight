// R30 (re-audit #2 §1/B3) — where a SUCCESSFUL plan generation lands.
//
// The wizard's finish step used to `context.go` to the Today plan, which
// replaces the whole stack. The Today plan screen's app bar carries a title
// and two actions but no leading, and the screen is not a shell destination,
// so the learner who completed the wizard had nothing to press: the system
// back button left the app. `pushReplacement` drops the finished wizard (a
// generated plan makes returning to it meaningless) while keeping whatever
// opened it underneath.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/practice_generator/presentation/plan_generation_launch.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';
import '../../../support/preference_store.dart';

Future<GoRouter> _pumpWizard(
  WidgetTester tester, {
  required StartPlanGeneration startGeneration,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.practiceCatalog,
    routes: <RouteBase>[
      // Stands in for whatever opened the wizard (the catalog's plan-builder
      // card, the Practice area hub). Its identity does not matter here —
      // only that it is STILL THERE after the plan is generated.
      GoRoute(
        path: AppRoutes.practiceCatalog,
        builder: (_, _) => const Scaffold(key: Key('stub-opener')),
      ),
      GoRoute(
        path: AppRoutes.practiceGeneratorSetup,
        builder: (_, _) => Scaffold(
          key: const Key('stub-wizard'),
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              key: const Key('finish-setup'),
              onPressed: () => unawaited(
                launchPlanGeneration(context, ref, startGeneration, _draft()),
              ),
              child: const Text('finish'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.practiceGeneratorToday,
        builder: (_, _) => const Scaffold(key: Key('stub-today')),
      ),
    ],
  );
  addTearDown(() async {
    // Unmount BEFORE disposing: the failure cell leaves a snackbar (and its
    // auto-dismiss timer) on the tree, and the binding fails a test that
    // ends with a pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appLoggerProvider.overrideWithValue(const NoopAppLogger()),
      ],
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
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('a generated plan REPLACES the wizard, and the surface it was '
      'opened from is still there to go back to', (tester) async {
    final router = await _pumpWizard(tester, startGeneration: _succeeding());

    await tester.tap(find.byKey(const Key('finish-setup')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub-today')), findsOneWidget);
    expect(
      find.byKey(const Key('stub-wizard')),
      findsNothing,
      reason: 'a finished wizard is not a place to return to',
    );
    expect(
      router.canPop(),
      isTrue,
      reason:
          'the plan screen has no back control of its own — a `go` here left '
          'the system back button as the only exit, and that leaves the app',
    );

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stub-opener')), findsOneWidget);
  });

  testWidgets('a FAILED generation still keeps the learner on the wizard, '
      'and says so', (tester) async {
    final router = await _pumpWizard(tester, startGeneration: _failing());

    await tester.tap(find.byKey(const Key('finish-setup')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub-wizard')), findsOneWidget);
    expect(find.byKey(const Key('stub-today')), findsNothing);
    expect(find.text(l10n.planSetupGenerationFailed), findsOneWidget);
    expect(router.canPop(), isTrue);
  });
}

/// A use case whose orchestrator really activates a plan — the same
/// composition `start_plan_generation_test.dart` measures the success path
/// with, so this file adds no generation logic of its own.
StartPlanGeneration _succeeding() {
  final orchestrator = GenerationOrchestrator(activation: _NoopActivation());
  addTearDown(orchestrator.dispose);
  return StartPlanGeneration(orchestrator: orchestrator, buildInput: _input);
}

/// The assembly throws, which the use case turns into an `AppResult`
/// failure — the shape a real generation failure reaches the launcher in.
StartPlanGeneration _failing() {
  final orchestrator = GenerationOrchestrator(activation: _NoopActivation());
  addTearDown(orchestrator.dispose);
  return StartPlanGeneration(
    orchestrator: orchestrator,
    buildInput: (_) => throw StateError('assembly exploded'),
  );
}

PracticeGenerationRequest _draft() => PracticeGenerationRequest(
  id: GenerationRequestId('request.plan-generation-launch'),
  createdAt: DateTime.utc(2026, 8, 18),
  locale: 'en',
  generationMode: GenerationMode.starter,
  planHorizonDays: 1,
  availability: buildAvailability(),
  constraints: LearnerConstraints(const <LearnerConstraint>[]),
  goals: <PracticeGoal>[buildGoal()],
);

GenerationPlanInput _input(PracticeGenerationRequest request) {
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
    planId: PlanId('plan.plan-generation-launch'),
    initialRevisionId: RevisionId('revision.plan-generation-launch'),
  );
}

final class _NoopActivation implements GenerationPlanActivation {
  @override
  Future<void> activate(AdaptivePracticePlan plan) async {}
}
