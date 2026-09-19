/// Route argument for the tutor's practice-plan preview (WP-H2, 2026-09-06).
///
/// `PracticePlanPreviewScreen` needs a `PracticePlanDraft` + a
/// `PracticePlanValidationContext`, and the accept action needs the FULL
/// `PracticePlanCompilationContext` so a user-edited draft can be recompiled
/// against the same inventory. All three travel together in one `extra` — the
/// precedent is `practice_generator/presentation/plan_preview_args.dart`,
/// where splitting them across two `extra`s would let one go missing.
library;

import '../application/planning/practice_plan_compiler.dart';
import '../domain/models/practice_plan_draft.dart';
import '../domain/services/practice_plan_validator.dart';

final class TutorPracticePlanPreviewArgs {
  TutorPracticePlanPreviewArgs({
    required this.draft,
    required this.compilationContext,
    Set<String> absentInputs = const <String>{},
  }) : absentInputs = Set<String>.unmodifiable(absentInputs);

  final PracticePlanDraft draft;
  final PracticePlanCompilationContext compilationContext;

  /// `PracticePlanInputCode` values measured as absent when the plan was
  /// compiled. Carried so a later surface can report them without recompiling.
  final Set<String> absentInputs;

  PracticePlanValidationContext get validationContext =>
      compilationContext.validationContext;
}
