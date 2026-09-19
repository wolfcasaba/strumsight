/// Route hosts for the Practice Generator flow (2026-09-06).
///
/// The router table registers these widgets instead of building the screens
/// inline. Two reasons, both measured:
///
///   * **The flow needs producers, not just screens.** `/practice/generator/
///     preview` and `/practice/generator/change-review` both redirect away
///     unless their `extra` is present, and nothing in the shipped app ever
///     produced one. Producing them means calling use cases
///     ([StartPlanGeneration.prepareDraft], [ProposePlanCatchUp]) and
///     reacting to their [AppResult] — logic that does not belong in a route
///     table.
///   * **A route builder runs on every rebuild.** `PlanPreviewController`
///     holds the plan under edit; rebuilding it inside a `builder` would
///     silently discard the learner's manual edits. [PlanPreviewRoute] owns
///     it for the lifetime of the route and disposes it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/usecase/propose_plan_catch_up.dart';
import '../../application/usecase/revise_practice_plan.dart';
import '../../application/usecase/start_plan_generation.dart';
import '../../domain/model/practice_generation_request.dart';
import '../controller/plan_preview_controller.dart';
import '../plan_preview_args.dart';
import '../providers/practice_generator_providers.dart';
import '../screens/plan_change_review_screen.dart';
import '../screens/plan_preview_screen.dart';
import '../screens/plan_setup_screen.dart';
import '../screens/today_plan_screen.dart';
import '../screens/weekly_plan_screen.dart';

/// `/practice/generator/setup` — the wizard plus the generation it feeds.
class PlanSetupRoute extends ConsumerStatefulWidget {
  const PlanSetupRoute({super.key});

  @override
  ConsumerState<PlanSetupRoute> createState() => _PlanSetupRouteState();
}

class _PlanSetupRouteState extends ConsumerState<PlanSetupRoute> {
  @override
  Widget build(BuildContext context) {
    // WATCHED, not read-on-tap: `startPlanGenerationProvider` is
    // `autoDispose` and owns the orchestrator's broadcast progress
    // controller. A `ref.read` inside the callback would hand back an
    // orchestrator that is disposed again the moment the read returns, and
    // its first progress event would then be added to a closed stream.
    final startGeneration = ref.watch(startPlanGenerationProvider);
    return PlanSetupScreen(
      controller: ref.watch(planSetupControllerProvider),
      onGenerate: (request) => _generate(startGeneration, request),
    );
  }

  Future<void> _generate(
    StartPlanGeneration startGeneration,
    PracticeGenerationRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await startGeneration.prepareDraft(request);
    if (!mounted) return;
    switch (result) {
      case Success<PreparedPracticePlanDraft>(:final value):
        router.push(
          AppRoutes.practiceGeneratorPreview,
          extra: PracticePlanPreviewArgs(
            plan: value.plan,
            validationContext: value.validationContext,
          ),
        );
      case Failure<PreparedPracticePlanDraft>():
        // The failure is SHOWN, never swallowed: an empty availability or a
        // plan the repairer could not fix is a real answer the learner has
        // to see, not a silent no-op on the finish button.
        messenger.showSnackBar(
          SnackBar(
            key: const Key('plan-setup-generate-error'),
            content: Text(l10n.planSetupGenerateFailed),
          ),
        );
    }
  }
}

/// `/practice/generator/preview` — the generated draft, before activation.
class PlanPreviewRoute extends ConsumerStatefulWidget {
  const PlanPreviewRoute({required this.args, super.key});

  final PracticePlanPreviewArgs args;

  @override
  ConsumerState<PlanPreviewRoute> createState() => _PlanPreviewRouteState();
}

class _PlanPreviewRouteState extends ConsumerState<PlanPreviewRoute> {
  PlanPreviewController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        _controller ??= ref.read(planPreviewControllerFactoryProvider)(
          initialPlan: widget.args.plan,
          validationContext: widget.args.validationContext,
        );
    return PlanPreviewScreen(
      controller: controller,
      onConfirmed: () {
        // The plan is persisted by now (the controller activated it through
        // the real repository), so the Today projection must re-read it.
        ref.invalidate(activePracticePlanProvider);
        GoRouter.of(context).go(AppRoutes.practiceGeneratorToday);
      },
    );
  }
}

/// `/practice/generator/today`.
class TodayPlanRoute extends ConsumerStatefulWidget {
  const TodayPlanRoute({super.key});

  @override
  ConsumerState<TodayPlanRoute> createState() => _TodayPlanRouteState();
}

class _TodayPlanRouteState extends ConsumerState<TodayPlanRoute> {
  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(activePracticePlanProvider);
    return TodayPlanScreen(
      controller: ref.watch(todayPlanControllerProvider),
      plan: plan.value,
      onAdjustPlan: plan.value == null
          ? null
          : () => adjustPracticePlan(context: context, ref: ref),
    );
  }
}

/// `/practice/generator/weekly`.
class WeeklyPlanRoute extends ConsumerStatefulWidget {
  const WeeklyPlanRoute({super.key});

  @override
  ConsumerState<WeeklyPlanRoute> createState() => _WeeklyPlanRouteState();
}

class _WeeklyPlanRouteState extends ConsumerState<WeeklyPlanRoute> {
  @override
  Widget build(BuildContext context) {
    // A `plan` a képernyő szerződésében NULLAZHATÓ, és a `null` ott a „még
    // nincs terv" állapot — nem hiányzó adat. Betöltés közben tehát nem
    // hazudunk üres tervet: ugyanaz a `null` megy be, amit a képernyő maga
    // is kezel.
    final plan = ref.watch(activePracticePlanProvider);
    return WeeklyPlanScreen(
      plan: plan.value,
      today: ref.watch(practiceGeneratorTodayProvider)(),
      onAdjustPlan: plan.value == null
          ? null
          : () => adjustPracticePlan(context: context, ref: ref),
    );
  }
}

/// `/practice/generator/change-review` — decide on a produced proposal.
class PlanChangeReviewRoute extends ConsumerStatefulWidget {
  const PlanChangeReviewRoute({required this.proposal, super.key});

  final PlanRevisionProposal proposal;

  @override
  ConsumerState<PlanChangeReviewRoute> createState() =>
      _PlanChangeReviewRouteState();
}

class _PlanChangeReviewRouteState extends ConsumerState<PlanChangeReviewRoute> {
  @override
  Widget build(BuildContext context) {
    return PlanChangeReviewScreen(
      proposal: widget.proposal,
      onAccepted: _accept,
      onRejected: () {
        // Rejecting writes NOTHING. The pending request is dropped so a
        // later accept cannot resurrect a decision the learner declined.
        ref.read(pendingPlanRevisionProvider.notifier).clear();
        GoRouter.of(context).go(AppRoutes.practiceGeneratorToday);
      },
    );
  }

  Future<void> _accept() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final l10n = AppLocalizations.of(context);
    final request = ref.read(pendingPlanRevisionProvider);
    final apply = ref.read(applyPlanRevisionProvider);
    if (request == null) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('plan-change-review-error'),
          content: Text(l10n.planAdjustFailed),
        ),
      );
      return;
    }
    final result = await apply(request);
    if (!mounted) return;
    ref.read(pendingPlanRevisionProvider.notifier).clear();
    if (result.isFailure) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('plan-change-review-error'),
          content: Text(l10n.planAdjustFailed),
        ),
      );
      return;
    }
    ref.invalidate(activePracticePlanProvider);
    messenger.showSnackBar(
      SnackBar(
        key: const Key('plan-change-review-applied'),
        content: Text(l10n.planAdjustApplied),
      ),
    );
    router.go(AppRoutes.practiceGeneratorToday);
  }
}

/// Produces a revision proposal for the active plan and routes the learner
/// to the decision that proposal actually needs.
///
/// Three outcomes, all real:
///   * nothing missed → "your plan is up to date", nothing is written;
///   * a change set the domain lets through without a decision (one local
///     adjustment) → applied straight away;
///   * a change set that [RevisePracticePlan] refuses to activate without an
///     explicit decision → the change-review screen, with the proposal as
///     the route's `extra`.
Future<void> adjustPracticePlan({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final l10n = AppLocalizations.of(context);
  final plan = ref.read(activePracticePlanProvider).value;
  if (plan == null) {
    messenger.showSnackBar(
      SnackBar(
        key: const Key('plan-adjust-no-plan'),
        content: Text(l10n.planAdjustNoPlan),
      ),
    );
    return;
  }
  final propose = ref.read(proposePlanCatchUpProvider);
  final apply = ref.read(applyPlanRevisionProvider);
  final pending = ref.read(pendingPlanRevisionProvider.notifier);
  final result = await propose(plan);
  if (!context.mounted) return;
  switch (result) {
    case Failure<PlanCatchUpProposal?>():
      messenger.showSnackBar(
        SnackBar(
          key: const Key('plan-adjust-error'),
          content: Text(l10n.planAdjustFailed),
        ),
      );
    case Success<PlanCatchUpProposal?>(:final value):
      if (value == null) {
        messenger.showSnackBar(
          SnackBar(
            key: const Key('plan-adjust-up-to-date'),
            content: Text(l10n.planAdjustUpToDate),
          ),
        );
        return;
      }
      if (value.requiresReview) {
        pending.remember(value.request);
        router.push(
          AppRoutes.practiceGeneratorChangeReview,
          extra: value.proposal,
        );
        return;
      }
      final applied = await apply(value.request);
      if (!context.mounted) return;
      if (applied.isFailure) {
        messenger.showSnackBar(
          SnackBar(
            key: const Key('plan-adjust-error'),
            content: Text(l10n.planAdjustFailed),
          ),
        );
        return;
      }
      ref.invalidate(activePracticePlanProvider);
      messenger.showSnackBar(
        SnackBar(
          key: const Key('plan-adjust-applied'),
          content: Text(l10n.planAdjustApplied),
        ),
      );
  }
}
