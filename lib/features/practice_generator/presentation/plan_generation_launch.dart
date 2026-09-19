// Javító sáv 2026-09-06 (R4): the router's handler for the setup wizard's
// "Finish setup" step. Until now nothing in `lib/` called
// `StartPlanGeneration` — the wizard saved its draft, stepped past its last
// page and stopped; no plan was ever generated or activated, so the Today
// and Weekly screens stayed empty forever.
//
// M12 (HANDOFF §5.2 (D)) — the two-phase generation entry point
// (`launchPlanPreview`) and the change-review entry point
// (`launchChangeReview`) live in the same file because all three helpers
// share the same Router/WidgetRef plumbing and the same composition root
// providers. Keeping them together preserves the `lib/` invariant that
// the practice generator's launch logic has exactly one home.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../application/service/generation_orchestrator.dart';
import '../application/usecase/revise_practice_plan.dart';
import '../application/usecase/start_plan_generation.dart';
import '../domain/id/planner_ids.dart';
import '../domain/model/adaptive_practice_plan.dart';
import '../domain/model/plan_change_set.dart';
import '../domain/model/plan_revision.dart';
import '../domain/model/practice_generation_request.dart';
import 'plan_preview_args.dart';
import 'providers/practice_generator_providers.dart';

/// Generates (and, through the orchestrator, activates) the plan for the
/// finished [request], then lands on Today IN PLACE OF the wizard, so the
/// surface the wizard was opened from stays reachable underneath. A failure
/// is said out loud and logged; the learner stays on the wizard with the
/// draft intact.
///
/// [startGeneration] is passed in (not read here) because its provider is
/// `autoDispose`: the caller `ref.watch`es it for as long as the wizard is on
/// screen, which is what keeps the orchestrator alive during generation.
Future<void> launchPlanGeneration(
  BuildContext context,
  WidgetRef ref,
  StartPlanGeneration startGeneration,
  PracticeGenerationRequest request,
) async {
  final generated = await startGeneration(request);
  if (!context.mounted) return;
  switch (generated) {
    case Success():
      ref.invalidate(activePracticePlanProvider);
      // R30 (re-audit #2 B3) — `pushReplacement`, NEM `go`: a mai terv a
      // VARÁSLÓ helyére lép (oda visszatérni értelmetlen — a terv már
      // elkészült), de minden, ami a varázsló ALATT volt, marad. A `go`
      // az egész stacket eldobta, és a terv-képernyőnek nincs saját
      // vissza-vezérlője: a varázsló végigvitele az appból vezetett ki.
      context.pushReplacement(AppRoutes.practiceGeneratorToday);
    case Failure(:final error):
      ref
          .read(appLoggerProvider)
          .warning(
            'plan_generation_failed',
            fields: <String, Object?>{'code': error.code},
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).planSetupGenerationFailed),
        ),
      );
  }
}

/// M12 (HANDOFF §5.2 (D)) — TWO-PHASE generation entry point.
///
/// Where [launchPlanGeneration] activates the plan the moment the
/// orchestrator finishes, this helper PUSHES the assembled draft onto the
/// preview screen (route `/practice/generator/preview`) and only activates
/// after the user presses the explicit confirm control there. Closing the
/// preview without confirming leaves the plan unactivated — the same
/// property the preview controller's own `dispose` path guarantees
/// (`plan_preview_controller.dart` §0.0 / A1).
///
/// This is the single `lib/` construction site of [PracticePlanPreviewArgs]
/// the HANDOFF asked for. Building the args here (rather than at every call
/// site) keeps the orchestrator's `preview(input)` result — a plan + the
/// `PlanValidationContext` it was assembled against — packaged exactly as
/// `PlanPreviewScreen.withPlan` expects (the screen's own factory comment
/// points to this exact pairing).
///
/// [startGeneration] is passed in for API parity with [launchPlanGeneration],
/// but the preview path actually reads the orchestrator through its own
/// provider: `startPlanGenerationProvider` already wraps
/// `generationOrchestratorProvider`, and the orchestrator's `preview` method
/// is the dedicated non-activating construction site.
///
/// Failures are said out loud and logged; the learner stays on the wizard
/// with the draft intact, exactly like [launchPlanGeneration].
Future<void> launchPlanPreview(
  BuildContext context,
  WidgetRef ref,
  StartPlanGeneration startGeneration,
  PracticeGenerationRequest request,
) async {
  final GenerationPlanInput input;
  try {
    input = startGeneration.buildInput(request);
  } on Object catch (error) {
    ref
        .read(appLoggerProvider)
        .warning(
          'plan_preview_input_build_failed',
          fields: <String, Object?>{
            'code': 'input_build_exception',
            'errorType': error.runtimeType.toString(),
          },
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).planSetupGenerationFailed),
      ),
    );
    return;
  }
  final orchestrator = startGeneration.orchestrator;
  final previewResult = await orchestrator.preview(input);
  if (!context.mounted) return;
  switch (previewResult) {
    case Success(:final value):
      // `push`, NEM `pushReplacement`: the wizard stays UNDER the preview
      // so "back without confirming" lands the learner on the wizard with
      // the draft intact. Activation only happens when the preview screen's
      // own confirm control fires; here we only place the preview on top.
      context.push<void>(
        AppRoutes.practiceGeneratorPreview,
        extra: PracticePlanPreviewArgs(
          plan: value.plan,
          validationContext: value.validationContext,
        ),
      );
    case Failure(:final error):
      ref
          .read(appLoggerProvider)
          .warning(
            'plan_preview_failed',
            fields: <String, Object?>{'code': error.code},
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).planSetupGenerationFailed),
        ),
      );
  }
}

/// M12 (HANDOFF §5.2 (D)) — the CHANGE-REVIEW entry point.
///
/// Before this round the `PlanRevisionProposal` had no construction site
/// at all (`appendRevision` had zero `lib/` callers, R34 measured). This
/// helper is that single construction site: it takes the current
/// [activePlan] and the learner-side [changes] a re-plan produced, builds
/// a fresh [PlanRevision] + [RevisePracticePlanRequest], runs the existing
/// [RevisePracticePlan] use case, and pushes the resulting
/// [PlanRevisionProposal] onto `/practice/generator/change-review`. The
/// route's redirect (`state.extra is PlanRevisionProposal`) and the
/// screen's `onAccepted`/`onRejected` callbacks together decide what
/// happens next — this helper does NOT persist anything, because a
/// confirmed revision is the calling process's job (R30: "a route must
/// not write the plan, otherwise the decision lives in two places").
///
/// The optional [previous] revision defaults to a synthetic one-numbered
/// predecessor derived from the active plan's own `activeRevisionId`, so
/// callers that don't carry a `PlanRevision` in their hand (e.g. an
/// upcoming adaptation-decider UI) can still produce an auditable
/// proposal without re-walking history. The actual `createdAt` is
/// deliberately not stamped here — the use case owns that clock, so the
/// audit trail stays single-sourced.
Future<void> launchChangeReview(
  BuildContext context,
  WidgetRef ref, {
  required AdaptivePracticePlan activePlan,
  required AdaptivePracticePlan candidateSnapshot,
  required Iterable<PlanChange> changes,
  required PlanRevisionReason reason,
  required PlanChangeConfirmation confirmation,
  PlanRevision? previous,
}) async {
  final revise = ref.read(revisePracticePlanProvider);
  final generateId = ref.read(practiceGeneratorIdGeneratorProvider);
  final baseRevision =
      previous ??
      PlanRevision(
        id: activePlan.activeRevisionId,
        planId: activePlan.id,
        // `number` is strictly positive (`plan_revision.dart`'s `_positive`
        // guard). The active plan's first revision is `1`; passing `1` here
        // lets the use case's `previous.number + 1` math produce a valid
        // successor (`2`) when no caller-supplied `previous` is provided.
        number: 1,
        createdAt: activePlan.createdAt,
        reason: PlanRevisionReason.learnerReschedule,
        changeSet: PlanChangeSet(
          fromRevisionId: activePlan.activeRevisionId,
          toRevisionId: activePlan.activeRevisionId,
          changes: const <PlanChange>[],
        ),
        snapshot: activePlan,
        previous: null,
      );
  final nextRevisionId = RevisionId.generate(generateId);
  final proposal = revise(
    RevisePracticePlanRequest(
      previous: baseRevision,
      nextRevisionId: nextRevisionId,
      candidateSnapshot: candidateSnapshot,
      changes: changes,
      reason: reason,
      confirmation: confirmation,
    ),
  );
  if (!context.mounted) return;
  // `push`, NEM `pushReplacement`: the source surface (today, weekly) stays
  // UNDER the change-review so the user can return to it after accepting or
  // rejecting. The route's redirect (`state.extra is PlanRevisionProposal`)
  // keeps a missing or wrong-typed extra from landing on this screen, so
  // deep-linking the route without a real proposal bounces to today rather
  // than rendering a half-built proposal widget.
  context.push<void>(AppRoutes.practiceGeneratorChangeReview, extra: proposal);
}
