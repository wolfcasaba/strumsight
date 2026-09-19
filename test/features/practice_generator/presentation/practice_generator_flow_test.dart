/// The two Practice Generator flows that had NO caller before 2026-09-06
/// (WP-H3): setup → preview → Today, and Today/Weekly → change review.
///
/// Every cell drives the REAL router table (`routerProvider`), so a cell can
/// only pass if the route, its redirect guard, its `extra` contract and the
/// producer behind it all agree — a hand-rolled `GoRouter` in the test would
/// prove the hosts work while the shipped table stayed dead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';
import '../../../support/fake_audio.dart';
import '../../../support/fake_auth.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

/// A fixed local Monday: the wizard's availability editor offers "this
/// week's Monday", so pinning the clock makes the generated day today's day.
final DateTime _fixedNow = DateTime(2026, 9, 7, 9);
final LocalDate _today = LocalDate(2026, 9, 7);

class _FlowApp extends ConsumerWidget {
  const _FlowApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: SsLightTheme.data(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: ref.watch(routerProvider),
  );
}

final class _Harness {
  const _Harness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;

  LocalPracticePlanRepository get repository =>
      container.read(localPracticePlanRepositoryProvider);

  Future<AdaptivePracticePlan?> readActivePlan() async {
    final result = await repository.readActivePlan();
    return switch (result) {
      Success<AdaptivePracticePlan?>(:final value) => value,
      Failure<AdaptivePracticePlan?>(:final error) => throw StateError('$error'),
    };
  }
}

Future<_Harness> _pumpFlow(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  var nextId = 0;
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      accountEnabledProvider.overrideWithValue(false),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      practiceGeneratorClockProvider.overrideWithValue(() => _fixedNow),
      practiceGeneratorIdGeneratorProvider.overrideWithValue(
        () => 'flow-${nextId++}',
      ),
      // The seeded fixture plans reference fixture exercise ids; the builtin
      // catalog does not know them, so reading a seeded plan back needs this
      // resolver. The generated plan's own blocks are resolved by the same
      // seam, so the override never hides a broken catalog.
      exerciseCandidateResolverProvider.overrideWithValue(
        (exerciseId) => buildCandidate(exerciseId: exerciseId),
      ),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            practiceGeneratorEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const _FlowApp()),
  );
  await tester.pumpAndSettle();
  return _Harness(container: container, router: router);
}

/// A plan whose [missedDates] days each carry a PLANNED primary-focus block
/// — exactly what `MissedDayPolicy` counts as a missed practice day.
AdaptivePracticePlan _planWithDays({
  required List<LocalDate> missedDates,
  List<LocalDate> futureDates = const <LocalDate>[],
}) {
  final days = <PracticeDay>[
    for (final date in missedDates)
      buildDay(id: 'day.$date', localDate: date),
    for (final date in futureDates)
      buildDay(id: 'day.$date', localDate: date),
  ];
  final ordered = [...missedDates, ...futureDates]..sort(
    (left, right) => left.compareTo(right),
  );
  return AdaptivePracticePlan(
    id: PlanId('plan.flow'),
    schemaVersion: 1,
    status: PlanStatus.active,
    title: 'Flow plan',
    createdAt: DateTime.utc(2026, 8, 31),
    startDate: ordered.first,
    endDate: ordered.last,
    goals: <PracticeGoal>[buildGoal()],
    days: days,
    activeRevisionId: RevisionId('revision.flow.1'),
    generationProvenance: GenerationRequestId('request.flow'),
    policyVersions: const <String, String>{
      'catalog': catalogRevision,
      'content': defaultContentRevision,
    },
  );
}

Future<void> _runWizard(WidgetTester tester) async {
  // Step 1 — goal. The picker's first option is enough; the wizard accepts
  // "unknown" too, but a goal keeps the request closest to a real run.
  await tester.tap(find.byKey(const Key('plan-setup-next')));
  await tester.pumpAndSettle();
  // Step 2 — availability: switch this week's Monday on.
  await tester.tap(find.byKey(const Key('plan-availability-monday')));
  await tester.pumpAndSettle();
  for (var step = 0; step < 4; step++) {
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('redirect guards (unchanged)', () {
    testWidgets('preview without PracticePlanPreviewArgs falls back to Today', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);

      harness.router.go(AppRoutes.practiceGeneratorPreview);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      expect(find.byType(PlanPreviewScreen), findsNothing);
    });

    testWidgets(
      'change review without PlanRevisionProposal falls back to Today',
      (tester) async {
        final harness = await _pumpFlow(tester);

        harness.router.go(AppRoutes.practiceGeneratorChangeReview);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
        expect(find.byType(PlanChangeReviewScreen), findsNothing);
      },
    );
  });

  group('setup → preview → Today', () {
    testWidgets('finishing the wizard opens the preview with REAL args', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);
      harness.router.go(AppRoutes.practiceGeneratorSetup);
      await tester.pumpAndSettle();
      expect(find.byType(PlanSetupScreen), findsOneWidget);

      await _runWizard(tester);

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorPreview);
      final extra = harness.router.state.extra;
      expect(extra, isA<PracticePlanPreviewArgs>());
      final args = extra! as PracticePlanPreviewArgs;
      // The plan is the pipeline's own output — a DRAFT, not something the
      // wizard already activated behind the learner's back.
      expect(args.plan.status, PlanStatus.draft);
      expect(args.plan.days, isNotEmpty);
      expect(args.plan.days.first.localDate, _today);
      // MEASURED 2026-09-06, pinned deliberately: the generated week is a
      // real pipeline output but carries NO blocks yet. Every builtin
      // candidate declares `requiresMicrophone` and the `guitar.tuned`
      // prerequisite, while `GenerationPlanInputAssembler` supplies EMPTY
      // `confirmed*Identities` sets — so `PlanValidator` reports every block
      // as unconfirmed and `PlanRepairer` removes it. No producer for that
      // execution truth exists anywhere under `lib/` (grep:
      // `confirmedTuningIdentities`), and this flow must NOT invent one — a
      // fabricated confirmation is exactly the optimistic fallback
      // `PlanValidationContext`'s contract forbids. The expectation is
      // pinned so the round that wires the confirmation seam fails here and
      // has to update it.
      expect(args.plan.days.single.blocks, isEmpty);
      expect(find.byType(PlanPreviewScreen), findsOneWidget);
    });

    testWidgets('nothing is persisted before the learner confirms', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);
      harness.router.go(AppRoutes.practiceGeneratorSetup);
      await tester.pumpAndSettle();

      await _runWizard(tester);

      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorPreview);
      expect(await harness.readActivePlan(), isNull);
    });

    testWidgets('confirming persists the plan and lands on Today', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);
      harness.router.go(AppRoutes.practiceGeneratorSetup);
      await tester.pumpAndSettle();
      await _runWizard(tester);
      final args =
          harness.router.state.extra! as PracticePlanPreviewArgs;

      await tester.tap(find.byKey(const Key('plan-preview-confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      expect(find.byType(TodayPlanScreen), findsOneWidget);
      final stored = await harness.readActivePlan();
      expect(stored, isNotNull);
      expect(stored!.id, args.plan.id);
      expect(stored.status, PlanStatus.active);
    });
  });

  group('Today / Weekly → change review', () {
    testWidgets('adjusting a plan with two missed days opens the review', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);
      await harness.repository.activate(
        _planWithDays(
          missedDates: <LocalDate>[LocalDate(2026, 9, 1), LocalDate(2026, 9, 2)],
          futureDates: <LocalDate>[LocalDate(2026, 9, 10)],
        ),
      );
      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('today-plan-adjust')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        harness.router.state.uri.path,
        AppRoutes.practiceGeneratorChangeReview,
      );
      final extra = harness.router.state.extra;
      expect(extra, isA<PlanRevisionProposal>());
      final proposal = extra! as PlanRevisionProposal;
      expect(proposal.requiresUserConfirmation, isTrue);
      expect(proposal.changeSet.changes, hasLength(2));
      // Pending, not pre-accepted: the revision is withheld until the tap.
      expect(proposal.confirmation, PlanChangeConfirmation.pending);
      expect(proposal.revision, isNull);
      expect(find.byType(PlanChangeReviewScreen), findsOneWidget);
    });

    testWidgets('the weekly view reaches the same review', (tester) async {
      final harness = await _pumpFlow(tester);
      await harness.repository.activate(
        _planWithDays(
          missedDates: <LocalDate>[LocalDate(2026, 9, 1), LocalDate(2026, 9, 2)],
        ),
      );
      harness.router.go(AppRoutes.practiceGeneratorWeekly);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('weekly-plan-adjust')));
      await tester.pumpAndSettle();

      expect(
        harness.router.state.uri.path,
        AppRoutes.practiceGeneratorChangeReview,
      );
      expect(harness.router.state.extra, isA<PlanRevisionProposal>());
    });

    testWidgets('accepting APPLIES the revision to the stored plan', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);
      await harness.repository.activate(
        _planWithDays(
          missedDates: <LocalDate>[LocalDate(2026, 9, 1), LocalDate(2026, 9, 2)],
          futureDates: <LocalDate>[LocalDate(2026, 9, 10)],
        ),
      );
      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('today-plan-adjust')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan-change-review-accept')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      final stored = await harness.readActivePlan();
      expect(stored, isNotNull);
      expect(stored!.activeRevisionId, isNot(RevisionId('revision.flow.1')));
      final byDate = <LocalDate, PracticeItemStatus>{
        for (final day in stored.days) day.localDate: day.status,
      };
      expect(byDate[LocalDate(2026, 9, 1)], PracticeItemStatus.expired);
      expect(byDate[LocalDate(2026, 9, 2)], PracticeItemStatus.expired);
      // The untouched future day is still open — the revision expires the
      // missed days, it does not cancel the plan.
      expect(byDate[LocalDate(2026, 9, 10)], PracticeItemStatus.planned);
    });

    testWidgets('rejecting writes nothing', (tester) async {
      final harness = await _pumpFlow(tester);
      final original = _planWithDays(
        missedDates: <LocalDate>[LocalDate(2026, 9, 1), LocalDate(2026, 9, 2)],
      );
      await harness.repository.activate(original);
      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('today-plan-adjust')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan-change-review-reject')));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      final stored = await harness.readActivePlan();
      expect(stored!.activeRevisionId, RevisionId('revision.flow.1'));
      expect(
        stored.days.every(
          (day) => day.status == PracticeItemStatus.planned,
        ),
        isTrue,
      );
    });

    testWidgets('a plan with nothing missed says so and stays put', (
      tester,
    ) async {
      final harness = await _pumpFlow(tester);
      await harness.repository.activate(
        _planWithDays(
          missedDates: const <LocalDate>[],
          futureDates: <LocalDate>[LocalDate(2026, 9, 10)],
        ),
      );
      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('today-plan-adjust')));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      expect(find.byKey(const Key('plan-adjust-up-to-date')), findsOneWidget);
    });
  });
}
