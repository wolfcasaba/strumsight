/// Setup-wizard draft → generation entry point (E15-R14, ADR 0482).
library;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_generation_request.dart';
import '../service/generation_orchestrator.dart';

/// Assembles the [GenerationPlanInput] a completed Setup-wizard [draft]
/// needs.
///
/// Composing that input needs a real catalog + evidence pipeline — reading
/// the current candidate catalog, ranking skill priorities, and running the
/// scheduler — none of which is this round's scope (ADR 0482 §Kontextus,
/// round brief §0.0/STOP-protocol: "nem ír új generálási logikát"). The
/// concrete production builder is a later round's composition; this seam
/// keeps [StartPlanGeneration] itself free of any assembly logic.
typedef GenerationPlanInputBuilder =
    GenerationPlanInput Function(PracticeGenerationRequest draft);

/// Starts (or joins) plan generation for a completed Setup-wizard draft.
///
/// This use case owns **no generation logic of its own** — the STOP-bound
/// boundary of E15-R14 (round brief §0). It only:
///
///   1. turns the [draft] into a [GenerationPlanInput] through the injected
///      [buildInput] seam, and
///   2. hands that input to the already-existing [GenerationOrchestrator],
///      whose `activate` call is wired to the real
///      `LocalPracticePlanRepository` by the composition root
///      (`practice_generator_providers.dart`, ADR 0482 / D4) — never a
///      no-op activation.
///
/// The returned [AppResult] is exactly [GenerationOrchestrator.generate]'s:
/// a validation, cancellation, or activation failure surfaces as a
/// [Failure], never a thrown exception.
final class StartPlanGeneration {
  StartPlanGeneration({required this.orchestrator, required this.buildInput});

  final GenerationOrchestrator orchestrator;
  final GenerationPlanInputBuilder buildInput;

  /// MINOR-4 fix (E15-R14 fix1): [buildInput] is called from inside the
  /// `try` below, so a builder that throws (rather than merely producing
  /// an input the orchestrator later rejects) still surfaces as an
  /// [AppResult] [Failure] — matching this class's own doc-contract
  /// above ("never a thrown exception"), which the un-guarded call
  /// previously made too broad a claim for.
  Future<AppResult<AdaptivePracticePlan>> call(
    PracticeGenerationRequest draft,
  ) async {
    final GenerationPlanInput input;
    try {
      input = buildInput(draft);
    } on Object catch (error, stackTrace) {
      return Failure<AdaptivePracticePlan>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
    return orchestrator.generate(input);
  }
}
