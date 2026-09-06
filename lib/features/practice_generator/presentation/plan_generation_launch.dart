// Javító sáv 2026-09-06 (R4): the router's handler for the setup wizard's
// "Finish setup" step. Until now nothing in `lib/` called
// `StartPlanGeneration` — the wizard saved its draft, stepped past its last
// page and stopped; no plan was ever generated or activated, so the Today
// and Weekly screens stayed empty forever.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../application/usecase/start_plan_generation.dart';
import '../domain/model/practice_generation_request.dart';
import 'providers/practice_generator_providers.dart';

/// Generates (and, through the orchestrator, activates) the plan for the
/// finished [request], then lands on Today. A failure is said out loud and
/// logged; the learner stays on the wizard with the draft intact.
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
      context.go(AppRoutes.practiceGeneratorToday);
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
