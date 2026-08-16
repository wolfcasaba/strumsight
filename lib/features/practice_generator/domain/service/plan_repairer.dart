/// Bounded, deterministic plan repair (ADR 0263 §2-6, SDD Ch8 Kör 11).
///
/// The repairer never adds time, never touches a completed day/block, never
/// reads the clock, and never uses randomness. Every step is logged with a
/// reason in the returned [PlanChangeSet] (ADR 0263 §4). Repair terminates
/// within [PlanRepairer.maxIterations] steps — failure inside that bound is
/// reported, never retried indefinitely (ADR 0263 §2).
library;

import '../model/adaptive_practice_plan.dart';
import '../model/plan_change_set.dart';
import '../model/plan_enums.dart';
import '../model/plan_validation_issue.dart';
import '../model/practice_block.dart';
import '../model/practice_day.dart';
import 'plan_validator.dart';

/// The outcome of one `PlanRepairer.repair` call.
///
/// Exactly one of [succeeded] outcomes is possible: a repaired plan (with an
/// optional [changeSet] — `null` only when the input already had no blocking
/// issue and nothing was changed), or a failure carrying the
/// [remainingIssues] that made repair give up.
final class PlanRepairOutcome {
  PlanRepairOutcome.repaired({
    required this.plan,
    required this.changeSet,
    required this.iterationsUsed,
  }) : succeeded = true,
       remainingIssues = const <PlanValidationIssue>[];

  PlanRepairOutcome.failed({
    required Iterable<PlanValidationIssue> remainingIssues,
    required this.iterationsUsed,
  }) : succeeded = false,
       plan = null,
       changeSet = null,
       remainingIssues = List<PlanValidationIssue>.unmodifiable(
         remainingIssues,
       );

  final bool succeeded;
  final AdaptivePracticePlan? plan;
  final PlanChangeSet? changeSet;
  final List<PlanValidationIssue> remainingIssues;

  /// How many validate-then-fix iterations were spent. Always
  /// `<= PlanRepairer.maxIterations` (ADR 0263 §2, A2).
  final int iterationsUsed;
}

typedef _FixStep = ({AdaptivePracticePlan plan, PlanChange change});

/// Attempts a bounded, deterministic repair of every `error`-severity
/// finding a [PlanValidator] reports.
///
/// A `fatal` finding (including a completed-history violation) is never
/// attempted — repair fails immediately (ADR 0263 §6, §0.0.1 mérce). Every
/// applied step removes exactly one non-completed [PracticeBlock]; the
/// repairer never lengthens a block or a day's schedule, so it can never
/// push a day above its hard maximum (ADR 0263 §3).
final class PlanRepairer {
  const PlanRepairer({
    this.validator = const PlanValidator(),
    this.maxIterations = 25,
  });

  final PlanValidator validator;

  /// The upper bound on validate-then-fix cycles (ADR 0263 §2). Repair gives
  /// up and reports failure rather than iterating past this bound.
  final int maxIterations;

  PlanRepairOutcome repair(
    AdaptivePracticePlan plan,
    PlanValidationContext context,
  ) {
    if (maxIterations < 1) {
      throw StateError('maxIterations must be at least one');
    }
    var current = plan;
    final changes = <PlanChange>[];
    for (var iteration = 1; iteration <= maxIterations; iteration++) {
      final result = validator.validate(current, context);
      if (result.hasFatal) {
        return PlanRepairOutcome.failed(
          remainingIssues: result.issues,
          iterationsUsed: iteration - 1,
        );
      }
      if (!result.hasError) {
        return _succeed(plan, current, changes, context, iteration - 1);
      }
      final step = _applyFirstFix(current, result);
      if (step == null) {
        return PlanRepairOutcome.failed(
          remainingIssues: result.issues,
          iterationsUsed: iteration - 1,
        );
      }
      current = step.plan;
      changes.add(step.change);
    }
    final finalResult = validator.validate(current, context);
    return PlanRepairOutcome.failed(
      remainingIssues: finalResult.issues,
      iterationsUsed: maxIterations,
    );
  }

  PlanRepairOutcome _succeed(
    AdaptivePracticePlan original,
    AdaptivePracticePlan current,
    List<PlanChange> changes,
    PlanValidationContext context,
    int iterationsUsed,
  ) {
    if (changes.isEmpty) {
      return PlanRepairOutcome.repaired(
        plan: current,
        changeSet: null,
        iterationsUsed: iterationsUsed,
      );
    }
    final repairedPlan = current.copyWith(
      activeRevisionId: context.repairRevisionId,
    );
    return PlanRepairOutcome.repaired(
      plan: repairedPlan,
      changeSet: PlanChangeSet(
        fromRevisionId: original.activeRevisionId,
        toRevisionId: context.repairRevisionId,
        changes: changes,
      ),
      iterationsUsed: iterationsUsed,
    );
  }

  /// Picks the first (deterministically ordered) `error` finding and applies
  /// its fix. Returns `null` when no error finding can be fixed — e.g. every
  /// remaining error lives on a completed day/block (ADR 0263 §6).
  _FixStep? _applyFirstFix(
    AdaptivePracticePlan plan,
    PlanValidationResult result,
  ) {
    for (final issue in result.issues) {
      if (issue.severity != ValidationSeverity.error) continue;
      final step = _fixIssue(plan, issue);
      if (step != null) return step;
    }
    return null;
  }

  _FixStep? _fixIssue(AdaptivePracticePlan plan, PlanValidationIssue issue) {
    final dayId = issue.dayId;
    if (dayId == null) return null;
    PracticeDay? targetDay;
    for (final day in plan.days) {
      if (day.id == dayId) {
        targetDay = day;
        break;
      }
    }
    if (targetDay == null || targetDay.status == PracticeItemStatus.completed) {
      return null;
    }

    PracticeBlock? removalTarget;
    if (issue.code == PlanValidationCode.hardMaximumExceeded) {
      final descendingByOrder = [...targetDay.blocks]
        ..sort((a, b) => b.order.compareTo(a.order));
      for (final block in descendingByOrder) {
        if (block.status != PracticeItemStatus.completed) {
          removalTarget = block;
          break;
        }
      }
    } else if (issue.blockId != null) {
      for (final block in targetDay.blocks) {
        if (block.id == issue.blockId) {
          removalTarget = block.status == PracticeItemStatus.completed
              ? null
              : block;
          break;
        }
      }
    }
    if (removalTarget == null) return null;

    final remainingBlocks = [
      for (final block in targetDay.blocks)
        if (block.id != removalTarget.id) block,
    ];
    final updatedDay = targetDay.replaceContent(blocks: remainingBlocks);
    final updatedDays = [
      for (final day in plan.days) day.id == dayId ? updatedDay : day,
    ];
    final change = PlanChange(
      type: PlanChangeType.removed,
      target: 'block:${removalTarget.id.value}',
      before: removalTarget.toJson(),
      after: const <String, Object?>{},
      reason: PlanChangeReason.systemAdaptation,
      evidenceRefs: <String>[issue.code],
      confidence: 1.0,
      requiresUserConfirmation: false,
      reversible: false,
    );
    return (plan: plan.copyWith(days: updatedDays), change: change);
  }
}
