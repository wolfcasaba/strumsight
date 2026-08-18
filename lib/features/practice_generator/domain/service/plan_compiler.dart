/// Compiles a validated plan block into one exact, executable practice step.
library;

import '../id/planner_ids.dart';
import '../model/exercise_candidate.dart';
import '../model/exercise_prescription.dart';
import '../model/plan_enums.dart';
import '../model/practice_block.dart';

/// The caller-fed current availability facts needed to start an exercise.
///
/// The compiler deliberately does not fetch a catalog. A future wiring layer
/// owns reading a live catalog and supplies its measured revision and
/// capability map at this boundary.
final class PlanCompilerAvailability {
  PlanCompilerAvailability({
    required String exerciseId,
    required String contentRevision,
    required Map<ExerciseCapability, CapabilitySupport> capabilities,
  }) : exerciseId = _requiredText(exerciseId, 'exerciseId'),
       contentRevision = _requiredText(contentRevision, 'contentRevision'),
       capabilities = _completeCapabilities(capabilities);

  final String exerciseId;
  final String contentRevision;
  final ExerciseCapabilities capabilities;
}

/// A successful compilation preserves the exact availability proof used at
/// launch time, so a caller can display why this step was eligible.
final class PlanAvailabilityCheck {
  PlanAvailabilityCheck({
    required String contentRevision,
    required Iterable<ExerciseCapability> requiredCapabilities,
  }) : contentRevision = _requiredText(contentRevision, 'contentRevision'),
       requiredCapabilities = List<ExerciseCapability>.unmodifiable(
         requiredCapabilities,
       );

  final String contentRevision;
  final List<ExerciseCapability> requiredCapabilities;
}

/// The exact part of a Practice Engine launch configuration prescribed by a
/// plan. Fields not represented by the Practice Engine config (repetitions
/// and rest) remain explicit instead of being rounded away.
final class CompiledPracticeSessionConfig {
  const CompiledPracticeSessionConfig({
    required this.activeDuration,
    required this.restDuration,
    required this.tempoBpm,
    required this.repetition,
    required this.loopCount,
    required this.hardElapsedLimit,
  });

  final Duration activeDuration;
  final Duration restDuration;
  final int? tempoBpm;
  final RepetitionPrescription repetition;
  final int loopCount;
  final Duration hardElapsedLimit;

  Duration get elapsed => (activeDuration + restDuration) * loopCount;
}

/// The safe next action for a block that cannot start against current facts.
enum PlanFallbackAction { requestReplan }

/// Stable reason the compiler rejected a block before launching a session.
enum PlanCompilationUnavailableReason {
  staleContentRevision,
  missingCapability,
  unsupportedSource,
  wrongExercise,
}

/// The result of compiling a plan block. Only [CompiledPlanStep] is
/// executable; [UnavailablePlanStep] is an explicit no-launch result.
sealed class PlanCompilationResult {
  const PlanCompilationResult();
}

/// A practice-definition action ready for the application layer to launch.
final class CompiledPlanStep extends PlanCompilationResult {
  CompiledPlanStep({
    required this.blockId,
    required String sourceRevision,
    required String exerciseSnapshotReference,
    required this.config,
    required this.availabilityCheck,
    required this.fallbackAction,
  }) : sourceRevision = _requiredText(sourceRevision, 'sourceRevision'),
       exerciseSnapshotReference = _requiredText(
         exerciseSnapshotReference,
         'exerciseSnapshotReference',
       );

  final BlockId blockId;
  final String sourceRevision;
  final String exerciseSnapshotReference;
  final CompiledPracticeSessionConfig config;
  final PlanAvailabilityCheck availabilityCheck;
  final PlanFallbackAction fallbackAction;
}

/// An explicit stale/unavailable result that must not launch Practice Engine.
final class UnavailablePlanStep extends PlanCompilationResult {
  UnavailablePlanStep({
    required this.blockId,
    required this.reason,
    required this.fallbackAction,
  });

  final BlockId blockId;
  final PlanCompilationUnavailableReason reason;
  final PlanFallbackAction fallbackAction;
}

/// Pure compiler for the Practice Engine subset of plan blocks.
final class PlanCompiler {
  const PlanCompiler();

  PlanCompilationResult compile({
    required PracticeBlock block,
    required PlanCompilerAvailability availability,
  }) {
    final prescription = block.prescription;
    if (prescription.source != CandidateSource.practiceCatalog) {
      return UnavailablePlanStep(
        blockId: block.id,
        reason: PlanCompilationUnavailableReason.unsupportedSource,
        fallbackAction: PlanFallbackAction.requestReplan,
      );
    }
    if (prescription.exerciseId != availability.exerciseId) {
      return UnavailablePlanStep(
        blockId: block.id,
        reason: PlanCompilationUnavailableReason.wrongExercise,
        fallbackAction: PlanFallbackAction.requestReplan,
      );
    }
    if (prescription.contentRevision != availability.contentRevision) {
      return UnavailablePlanStep(
        blockId: block.id,
        reason: PlanCompilationUnavailableReason.staleContentRevision,
        fallbackAction: PlanFallbackAction.requestReplan,
      );
    }

    final missingCapability = prescription.successCriteria.requiredCapabilities
        .any(
          (capability) =>
              availability.capabilities[capability] !=
              CapabilitySupport.supported,
        );
    if (missingCapability) {
      return UnavailablePlanStep(
        blockId: block.id,
        reason: PlanCompilationUnavailableReason.missingCapability,
        fallbackAction: PlanFallbackAction.requestReplan,
      );
    }

    return CompiledPlanStep(
      blockId: block.id,
      sourceRevision: prescription.contentRevision,
      exerciseSnapshotReference: prescription.exerciseId,
      config: CompiledPracticeSessionConfig(
        activeDuration: prescription.activeDuration,
        restDuration: prescription.restDuration,
        tempoBpm: prescription.tempoBpm,
        repetition: prescription.repetition,
        loopCount: prescription.loopCount,
        hardElapsedLimit: prescription.hardElapsedLimit,
      ),
      availabilityCheck: PlanAvailabilityCheck(
        contentRevision: availability.contentRevision,
        requiredCapabilities: prescription.successCriteria.requiredCapabilities,
      ),
      fallbackAction: PlanFallbackAction.requestReplan,
    );
  }
}

ExerciseCapabilities _completeCapabilities(
  Map<ExerciseCapability, CapabilitySupport> capabilities,
) {
  final missing = ExerciseCapability.values
      .where((capability) => !capabilities.containsKey(capability))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw ArgumentError.value(
      capabilities,
      'capabilities',
      'must explicitly include every ExerciseCapability',
    );
  }
  return Map<ExerciseCapability, CapabilitySupport>.unmodifiable(capabilities);
}

String _requiredText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
