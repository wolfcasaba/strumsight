// Javító sáv 2026-09-06 (R4, `docs/ui/apk-functionality-audit-2026-09-06.md`):
// the shipped Today plan screen was built by the router WITHOUT a plan and
// WITHOUT action callbacks — it always rendered "no active plan", and its
// Start / Skip / Shorten / Pause buttons were disabled. The learner-side
// reschedule logic (`ActivePlanController`) and the persistence
// (`LocalPracticePlanRepository.activate`) both existed; nothing composed
// them. This file is that composition.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../application/controller/active_plan_controller.dart';
import '../domain/model/practice_block.dart';
import 'providers/practice_generator_providers.dart';

/// The learner-side reschedules the Today screen offers on the ACTIVE plan.
/// `swap` is deliberately absent: the merged [ActivePlanController] has no
/// swap operation, so the screen keeps that button disabled rather than
/// pretending (the honest-unavailability rule of ADR 0496).
enum TodayPlanAction { skip, shorten, pause }

/// What [TodayPlanActions.apply] did.
enum TodayPlanActionOutcome {
  /// The revised plan is active and the active-plan view was invalidated.
  applied,

  /// There is no active plan, or the day has nothing left to reschedule —
  /// nothing was written.
  nothingToChange,

  /// The repository refused the activation; the previous revision stays.
  failed,
}

/// Applies a [TodayPlanAction] to the active plan through the merged
/// reschedule + activation chain, then invalidates the active-plan view so
/// every consumer (Today, Weekly) re-reads the new revision.
final class TodayPlanActions {
  const TodayPlanActions(this._ref);

  final Ref _ref;

  Future<TodayPlanActionOutcome> apply(TodayPlanAction action) async {
    final plan = await _ref.read(activePracticePlanProvider.future);
    if (plan == null) return TodayPlanActionOutcome.nothingToChange;
    final controller = _ref.read(activePlanControllerProvider);
    final today = _ref.read(todayPlanControllerProvider).resolve(plan);
    final day = today.day;
    final ActivePlanUpdate update;
    switch (action) {
      case TodayPlanAction.skip:
        if (day == null) return TodayPlanActionOutcome.nothingToChange;
        update = controller.skip(plan: plan, day: day);
      case TodayPlanAction.shorten:
        if (day == null) return TodayPlanActionOutcome.nothingToChange;
        update = controller.shorten(plan: plan, day: day);
      case TodayPlanAction.pause:
        update = controller.pause(plan);
    }
    if (update.changeSet.changes.isEmpty) {
      return TodayPlanActionOutcome.nothingToChange;
    }
    final activation = await _ref
        .read(localPracticePlanRepositoryProvider)
        .activateAndReport(update.plan);
    if (activation.isFailure) {
      _ref
          .read(appLoggerProvider)
          .warning(
            'today_plan_action_failed',
            fields: <String, Object?>{
              'action': action.name,
              'code': activation.failureOrNull?.code,
            },
          );
      return TodayPlanActionOutcome.failed;
    }
    if (_ref.mounted) _ref.invalidate(activePracticePlanProvider);
    return TodayPlanActionOutcome.applied;
  }
}

final todayPlanActionsProvider = Provider<TodayPlanActions>(
  (ref) => TodayPlanActions(ref),
);

/// Route-side wrapper: applies the action and says a failure out loud.
Future<void> runTodayPlanAction(
  BuildContext context,
  WidgetRef ref,
  TodayPlanAction action,
) async {
  final outcome = await ref.read(todayPlanActionsProvider).apply(action);
  if (outcome != TodayPlanActionOutcome.failed || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AppLocalizations.of(context).todayPlanActionFailed)),
  );
}

/// "Start" on a planned block opens the Practice setup for the block's
/// exercise — the catalog adapter stamps `exerciseId` with the
/// `PracticeDefinition.id`, and the setup route reads that id from its
/// `?id=` query (the same shape the Practice Area Hub's CTA uses).
void openPracticeForBlock(BuildContext context, PracticeBlock block) {
  final uri = Uri(
    path: AppRoutes.practiceSetup,
    queryParameters: <String, String>{'id': block.prescription.exerciseId},
  );
  unawaited(context.push<void>(uri.toString()));
}
