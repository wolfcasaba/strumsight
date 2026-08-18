/// Cancellable assembly, validation, repair, and activation of one plan.
library;

import 'dart:async';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../model/generation_state.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/exercise_prescription.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/practice_generation_request.dart';
import '../../domain/model/schedule_decision.dart';
import '../../domain/model/success_criteria.dart';
import '../../domain/policy/scheduling_policy.dart';
import '../../domain/service/plan_repairer.dart';
import '../../domain/service/plan_validator.dart';

/// The activation boundary for a completed plan.
///
/// This round does not implement persistence; a later repository can own this
/// effect. Keeping it behind this contract makes the no-partial-activation
/// rule independently testable now.
abstract interface class GenerationPlanActivation {
  Future<void> activate(AdaptivePracticePlan plan);
}

/// Immutable input assembled by earlier generator stages for this boundary.
final class GenerationPlanInput {
  const GenerationPlanInput({
    required this.request,
    required this.schedule,
    required this.validationContext,
    required this.planId,
    required this.initialRevisionId,
  });

  final PracticeGenerationRequest request;
  final WeeklyScheduleDecision schedule;
  final PlanValidationContext validationContext;
  final PlanId planId;
  final RevisionId initialRevisionId;
}

/// A progress event emitted at an observable cancellation checkpoint.
final class GenerationProgress {
  const GenerationProgress({required this.requestId, required this.stage});

  final GenerationRequestId requestId;
  final GenerationStage stage;
}

/// Coordinates the terminal plan-generation stages without owning storage.
///
/// A request id has at most one in-flight run. Each run gets its own
/// cancellation source and retains no intermediate result after it completes,
/// so retrying begins from its immutable [GenerationPlanInput].
final class GenerationOrchestrator {
  GenerationOrchestrator({
    required this.activation,
    PlanValidator? validator,
    PlanRepairer? repairer,
  }) : validator = validator ?? const PlanValidator(),
       repairer = repairer ?? const PlanRepairer();

  final GenerationPlanActivation activation;
  final PlanValidator validator;
  final PlanRepairer repairer;

  final StreamController<GenerationProgress> _progressController =
      StreamController<GenerationProgress>.broadcast(sync: true);
  final Map<GenerationRequestId, _GenerationRun> _runs =
      <GenerationRequestId, _GenerationRun>{};

  Stream<GenerationProgress> get progress => _progressController.stream;

  /// Starts one run, or returns the existing in-flight run for the same id.
  Future<AppResult<AdaptivePracticePlan>> generate(GenerationPlanInput input) {
    final existing = _runs[input.request.id];
    if (existing != null) return existing.future;

    final source = _GenerationCancellationSource();
    late final Future<AppResult<AdaptivePracticePlan>> future;
    future =
        Future<AppResult<AdaptivePracticePlan>>.microtask(
          () => _run(input, source),
        ).whenComplete(() {
          final current = _runs[input.request.id];
          if (current?.future == future) _runs.remove(input.request.id);
        });
    _runs[input.request.id] = _GenerationRun(source: source, future: future);
    return future;
  }

  /// Requests cooperative cancellation of one in-flight generation.
  ///
  /// A completed run is no longer present in [_runs], making late cancellation
  /// intentionally a no-op.
  void cancel(GenerationRequestId requestId) =>
      _runs[requestId]?.source.cancel();

  Future<AppResult<AdaptivePracticePlan>> _run(
    GenerationPlanInput input,
    _GenerationCancellationSource cancellation,
  ) async {
    try {
      await _checkpoint(
        input.request.id,
        GenerationStage.assembling,
        cancellation,
      );
      var plan = _assemblePlan(input);

      await _checkpoint(
        input.request.id,
        GenerationStage.validating,
        cancellation,
      );
      var validation = validator.validate(plan, input.validationContext);
      if (!validation.isActivatable) {
        await _checkpoint(
          input.request.id,
          GenerationStage.repairing,
          cancellation,
        );
        final repaired = repairer.repair(plan, input.validationContext);
        if (!repaired.succeeded || repaired.plan == null) {
          return Failure<AdaptivePracticePlan>(
            ValidationFailure(cause: repaired.remainingIssues),
          );
        }
        plan = repaired.plan!;
        validation = validator.validate(plan, input.validationContext);
        if (!validation.isActivatable) {
          return Failure<AdaptivePracticePlan>(
            ValidationFailure(cause: validation.issues),
          );
        }
      }

      await _checkpoint(
        input.request.id,
        GenerationStage.activating,
        cancellation,
      );
      final activePlan = plan.copyWith(status: PlanStatus.active);
      // Do not checkpoint after this await: once activation began it is a
      // completed effect, so a late cancel must not relabel an active plan as
      // cancelled or imply that the effect can be rolled back.
      await activation.activate(activePlan);
      return Success<AdaptivePracticePlan>(activePlan);
    } on _GenerationCancelledException {
      return const Failure<AdaptivePracticePlan>(CancelledFailure());
    } catch (error, stackTrace) {
      if (error is AppFailure) return Failure<AdaptivePracticePlan>(error);
      return Failure<AdaptivePracticePlan>(
        UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<void> _checkpoint(
    GenerationRequestId requestId,
    GenerationStage stage,
    _GenerationCancellationSource cancellation,
  ) async {
    cancellation.throwIfCancelled();
    _progressController.add(
      GenerationProgress(requestId: requestId, stage: stage),
    );
    // Yield each stage to the event queue. The controller/UI sees progress and
    // cancellation before the next potentially expensive stage starts.
    await Future<void>.delayed(Duration.zero);
    cancellation.throwIfCancelled();
  }

  AdaptivePracticePlan _assemblePlan(GenerationPlanInput input) {
    final decisions = input.schedule.dayDecisions;
    if (decisions.isEmpty) {
      throw ArgumentError.value(
        decisions,
        'schedule.dayDecisions',
        'must contain at least one scheduled day',
      );
    }
    final days = <PracticeDay>[
      for (final decision in decisions) _assembleDay(input, decision),
    ];
    return AdaptivePracticePlan(
      id: input.planId,
      schemaVersion: 1,
      status: PlanStatus.draft,
      title: 'practice.plan.adaptive',
      createdAt: input.request.createdAt,
      startDate: decisions.first.date,
      endDate: decisions.last.date,
      goals: input.request.goals,
      days: days,
      activeRevisionId: input.initialRevisionId,
      generationProvenance: input.request.id,
      policyVersions: <String, String>{
        'catalog': input.validationContext.catalog.catalogRevision,
        'content': input.validationContext.catalog.contentRevision,
        'scheduling': input.schedule.policyVersion,
      },
    );
  }

  PracticeDay _assembleDay(
    GenerationPlanInput input,
    DaySchedulingDecision decision,
  ) {
    final dayId = DayId('${input.planId.value}.day.${decision.date}');
    final blocks = <PracticeBlock>[
      for (var index = 0; index < decision.selectedCandidates.length; index++)
        _assembleBlock(
          dayId: dayId,
          order: index + 1,
          scheduled: decision.selectedCandidates[index],
          context: input.validationContext,
        ),
    ];
    final focusSkills = <String>{
      for (final candidate in decision.selectedCandidates)
        ...candidate.skillTargets,
    };
    return PracticeDay(
      id: dayId,
      localDate: decision.date,
      status: PracticeItemStatus.planned,
      timeBudget: decision.totalActiveMinutes > Duration.zero
          ? decision.totalActiveMinutes
          : const Duration(microseconds: 1),
      blocks: blocks,
      primaryFocusSkillIds: focusSkills.isEmpty
          ? const <String>['schedule.noFocus']
          : focusSkills,
      reasonCodes: decision.reasonCodes,
    );
  }

  PracticeBlock _assembleBlock({
    required DayId dayId,
    required int order,
    required ScheduleCandidate scheduled,
    required PlanValidationContext context,
  }) {
    final candidate = _candidateFor(scheduled, context);
    final activeDuration = scheduled.duration;
    if (activeDuration < candidate.supportedDurations.minimum ||
        activeDuration > candidate.supportedDurations.maximum) {
      throw ArgumentError.value(
        activeDuration,
        'scheduled.duration',
        'must fit ${candidate.exerciseId} supported durations',
      );
    }
    final capability = candidate.capabilities.entries
        .where((entry) => entry.value == CapabilitySupport.supported)
        .map((entry) => entry.key)
        .firstOrNull;
    if (capability == null) {
      throw ArgumentError.value(
        candidate.exerciseId,
        'candidate',
        'must support one measurable success capability',
      );
    }
    return PracticeBlock(
      id: BlockId('${dayId.value}.block.$order'),
      kind: _blockKindFor(scheduled),
      order: order,
      prescription: ExercisePrescription(
        candidate: candidate,
        activeDuration: activeDuration,
        restDuration: Duration.zero,
        repetition: RepetitionPrescription(target: 1, maximum: 1),
        loopCount: 1,
        hardElapsedLimit: activeDuration,
        successCriteria: SuccessCriteria(
          kind: SuccessCriterionKind.completion,
          description: 'completion.required',
          requiredCapabilities: <ExerciseCapability>{capability},
        ),
      ),
      reasonCodes: const <String>['schedule.decision.selected'],
      evidenceRefs: <String>['schedule.candidate:${scheduled.identity}'],
      status: PracticeItemStatus.planned,
      estimatedElapsed: activeDuration,
    );
  }

  ExerciseCandidate _candidateFor(
    ScheduleCandidate scheduled,
    PlanValidationContext context,
  ) {
    for (final candidate in context.catalog.candidates) {
      if (candidate.sortKey == scheduled.identity) return candidate;
    }
    throw StateError('No catalog candidate matches ${scheduled.identity}');
  }

  // Review material is maintenance. New material follows the scheduler's
  // primary/secondary focus classification; supporting new material remains
  // maintenance to avoid inventing a third focus role in PracticeBlock.
  BlockKind _blockKindFor(ScheduleCandidate scheduled) {
    if (scheduled.materialKind == CandidateMaterialKind.review) {
      return BlockKind.maintenance;
    }
    return switch (scheduled.focus) {
      CandidateFocus.primaryFocus => BlockKind.primaryFocus,
      CandidateFocus.secondaryFocus => BlockKind.secondaryFocus,
      CandidateFocus.supporting => BlockKind.maintenance,
    };
  }

  Future<void> dispose() => _progressController.close();
}

final class _GenerationRun {
  const _GenerationRun({required this.source, required this.future});

  final _GenerationCancellationSource source;
  final Future<AppResult<AdaptivePracticePlan>> future;
}

final class _GenerationCancellationSource {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const _GenerationCancelledException();
  }
}

final class _GenerationCancelledException implements Exception {
  const _GenerationCancelledException();
}

extension on Iterable<ExerciseCapability> {
  ExerciseCapability? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
