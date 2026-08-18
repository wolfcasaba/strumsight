/// State, manual-edit boundary, and activation gate for the plan preview
/// screen (SDD Ch8 Kör 21, ADR 0264 / 0263 / 0266).
///
/// The controller is a non-integrated preview component (R21 §0.0 self-heal):
/// it never imports `GenerationOrchestrator` or `PlanGeneratorController`.
/// It accepts an already-assembled [AdaptivePracticePlan] and the
/// [PlanValidationContext] it was assembled against, revalidates every
/// manual edit through the existing [PlanValidator] (ADR 0263 §1), and only
/// asks the injected [GenerationPlanActivation] to confirm a plan after the
/// learner presses the explicit confirm control (§5.1). A no-op
/// `confirm()`/dispose path therefore never activates anything.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../application/service/generation_orchestrator.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/plan_validation_issue.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/service/plan_validator.dart';

const Object _unsetSentinel = Object();

/// Immutable view state for the plan preview screen.
final class PlanPreviewState {
  const PlanPreviewState({
    required this.plan,
    required this.validation,
    required this.pendingChanges,
    required this.confirmed,
    this.confirmationError,
  });

  /// The current plan under preview — every manual edit produces a new
  /// immutable copy.
  final AdaptivePracticePlan plan;

  /// Latest [PlanValidationResult] produced by re-running the
  /// [PlanValidator] after the last edit (or initial load).
  final PlanValidationResult validation;

  /// True when the learner has edited the plan since the last validation
  /// pass. Currently always false because each edit revalidates inline
  /// (kept as an explicit field so future async validators can flip it).
  final bool pendingChanges;

  /// True only after the learner explicitly confirms and
  /// [GenerationPlanActivation.activate] has completed.
  final bool confirmed;

  /// The most recent activation failure, surfaced so the UI can offer a
  /// retry rather than silently no-op.
  final AppFailure? confirmationError;

  bool get hasBlockingError => validation.hasError || validation.hasFatal;

  bool get hasWarning => validation.issues
      .any((issue) => issue.severity == ValidationSeverity.warning);
}

/// Coordinates manual plan edits and explicit-confirm activation.
///
/// Manual edits never bypass [PlanValidator]: every setter mutates the plan
/// immutably and re-runs the validator synchronously (ADR 0263 §1). The
/// activation path is the only place that touches
/// [GenerationPlanActivation]; closing the screen, popping a route, or
/// otherwise disposing the controller without calling [confirmConfirmed]
/// leaves `activation.calls` at zero (A1).
final class PlanPreviewController extends ChangeNotifier {
  PlanPreviewController({
    required AdaptivePracticePlan initialPlan,
    required PlanValidationContext validationContext,
    required this.activation,
    PlanValidator? validator,
  })  : _plan = initialPlan,
        _context = validationContext,
        _validator = validator ?? const PlanValidator(),
        _validation = (validator ?? const PlanValidator())
            .validate(initialPlan, validationContext);

  final PlanValidationContext _context;
  final PlanValidator _validator;
  GenerationPlanActivation activation;

  AdaptivePracticePlan _plan;
  PlanValidationResult _validation;
  bool _pendingChanges = false;
  bool _confirmed = false;
  AppFailure? _confirmationError;
  int _editCount = 0;

  PlanPreviewState get state => PlanPreviewState(
    plan: _plan,
    validation: _validation,
    pendingChanges: _pendingChanges,
    confirmed: _confirmed,
    confirmationError: _confirmationError,
  );

  /// Edits a single block's prescribed active duration (bounded by the
  /// candidate's supported duration window via revalidation — a value that
  /// would invalidate the plan simply produces a new error finding).
  void editBlockActiveDuration(BlockId blockId, Duration newDuration) {
    if (_confirmed) return;
    final nextDays = <PracticeDay>[
      for (final day in _plan.days)
        if (day.blocks.any((block) => block.id == blockId))
          day.replaceContent(
            blocks: <PracticeBlock>[
              for (final block in day.blocks)
                if (block.id == blockId)
                  _withAdjustedDuration(block, newDuration)
                else
                  block,
            ],
          )
        else
          day,
    ];
    _applyPlan(_plan.copyWith(days: nextDays));
  }

  /// Toggles a day's planned inclusion. A completed day is immutable
  /// (§0.0.1), so the controller silently ignores edits to a completed
  /// day instead of trying to "remove" it (which would itself be a fatal
  /// validation finding).
  void editDayAvailability(LocalDate date, bool include) {
    if (_confirmed) return;
    final nextDays = <PracticeDay>[
      for (final day in _plan.days)
        if (day.localDate == date)
          if (day.status == PracticeItemStatus.completed)
            day
          else if (include)
            day
          else
            day.replaceContent(
              blocks: const <PracticeBlock>[],
              primaryFocusSkillIds: const <String>['preview.day.removed'],
            )
        else
          day,
    ];
    _applyPlan(_plan.copyWith(days: nextDays));
  }

  /// Activates the plan only after an explicit user confirmation and only
  /// when no `error`/`fatal` finding blocks activation.
  ///
  /// Returns the [AppResult] of the activation so callers (and tests) can
  /// react to a failure without swallowing it.
  Future<AppResult<AdaptivePracticePlan>> confirmConfirmed() async {
    if (_confirmed) {
      return Success<AdaptivePracticePlan>(_plan);
    }
    // §6.1 below-cell guard: error/fatal must never activate, even after
    // an explicit confirm — this is what makes "I confirmed anyway" a
    // non-bypass.
    if (_validation.hasError || _validation.hasFatal) {
      const failure = ValidationFailure(cause: <PlanValidationIssue>[]);
      _confirmationError = failure;
      notifyListeners();
      return Failure<AdaptivePracticePlan>(failure);
    }
    final activePlan = _plan.copyWith(status: PlanStatus.active);
    try {
      await activation.activate(activePlan);
      _plan = activePlan;
      _confirmed = true;
      _confirmationError = null;
      notifyListeners();
      return Success<AdaptivePracticePlan>(activePlan);
    } on AppFailure catch (failure) {
      _confirmationError = failure;
      notifyListeners();
      return Failure<AdaptivePracticePlan>(failure);
    } catch (error, stackTrace) {
      final failure = UnknownFailure(cause: error, stackTrace: stackTrace);
      _confirmationError = failure;
      notifyListeners();
      return Failure<AdaptivePracticePlan>(failure);
    }
  }

  bool get hasBlockingError => _validation.hasError || _validation.hasFatal;

  bool get hasWarning => _validation.issues
      .any((issue) => issue.severity == ValidationSeverity.warning);

  /// Number of manual edits applied since the controller was built —
  /// surfaced so a test can assert every setter calls back into the
  /// validator (A2).
  int get editCount => _editCount;

  void _applyPlan(AdaptivePracticePlan next) {
    _plan = next;
    _validation = _validator.validate(_plan, _context);
    _pendingChanges = false;
    _editCount += 1;
    notifyListeners();
  }

  PracticeBlock _withAdjustedDuration(
    PracticeBlock block,
    Duration newDuration,
  ) {
    final prescription = block.prescription;
    final clamped = Duration(
      microseconds: newDuration.inMicroseconds.clamp(
        prescription.supportedDurations.minimum.inMicroseconds,
        prescription.supportedDurations.maximum.inMicroseconds,
      ),
    );
    final restDuration = prescription.restDuration;
    final loopCount = prescription.loopCount;
    final elapsed = clamped + restDuration * loopCount;
    return block.replaceContent(
      prescription: ExercisePrescription(
        candidate: prescription.candidate,
        activeDuration: clamped,
        restDuration: restDuration,
        tempoBpm: prescription.tempoBpm,
        repetition: prescription.repetition,
        loopCount: loopCount,
        hardElapsedLimit: prescription.hardElapsedLimit,
        successCriteria: prescription.successCriteria,
        fallbackCandidates: const <ExerciseCandidate>[],
        progressionRule: prescription.progressionRule,
      ),
      estimatedElapsed: elapsed,
    );
  }
}
