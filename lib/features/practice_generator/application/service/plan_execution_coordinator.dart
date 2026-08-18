/// Launches compiled Practice Engine steps and idempotently receives outcomes.
library;

import 'package:strumsight/features/practice/public.dart' as practice;

import '../../data/adapter/practice_outcome_adapter.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/service/plan_compiler.dart';

/// The plan location that a launched block execution must retain.
final class PlanExecutionContext {
  const PlanExecutionContext({
    required this.planId,
    required this.revisionId,
    required this.dayId,
    required this.blockId,
  });

  final PlanId planId;
  final RevisionId revisionId;
  final DayId dayId;
  final BlockId blockId;
}

/// A unique, traceable execution identity for exactly one launched block.
final class BlockExecutionId {
  BlockExecutionId._({
    required this.planId,
    required this.revisionId,
    required this.dayId,
    required this.blockId,
    required String token,
  }) : token = _requiredText(token, 'token');

  final PlanId planId;
  final RevisionId revisionId;
  final DayId dayId;
  final BlockId blockId;
  final String token;

  String get value => [
    planId.value,
    revisionId.value,
    dayId.value,
    blockId.value,
    token,
  ].join('/');

  @override
  bool operator ==(Object other) =>
      other is BlockExecutionId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The exact Practice Engine launch prepared from a compiled step.
final class PlanExecutionLaunch {
  const PlanExecutionLaunch({
    required this.blockExecutionId,
    required this.step,
    required this.sessionConfig,
  });

  final BlockExecutionId blockExecutionId;
  final CompiledPlanStep step;
  final practice.PracticeSessionConfig sessionConfig;
}

/// Result of receiving an outcome. A replay retains the first outcome and
/// never causes a second downstream accounting decision.
final class PlanOutcomeIngestion {
  const PlanOutcomeIngestion({
    required this.outcome,
    required this.isDuplicate,
    required this.contributesSkillEvidence,
    required this.requestsRegression,
  });

  final PracticeOutcome outcome;
  final bool isDuplicate;
  final bool contributesSkillEvidence;
  final bool requestsRegression;

  PlanOutcomeIngestion asDuplicate() => PlanOutcomeIngestion(
    outcome: outcome,
    isDuplicate: true,
    contributesSkillEvidence: contributesSkillEvidence,
    requestsRegression: requestsRegression,
  );
}

/// Coordinates the caller-owned Practice Engine launch and terminal outcome.
///
/// This object deliberately owns only in-process idempotence. Persisting
/// outcomes and applying adaptation are later wiring responsibilities.
final class PlanExecutionCoordinator {
  factory PlanExecutionCoordinator({
    required String Function() createExecutionToken,
    PracticeOutcomeAdapter outcomeAdapter = const PracticeOutcomeAdapter(),
  }) => PlanExecutionCoordinator._(createExecutionToken, outcomeAdapter);

  PlanExecutionCoordinator._(this._createExecutionToken, this._outcomeAdapter);

  final String Function() _createExecutionToken;
  final PracticeOutcomeAdapter _outcomeAdapter;
  final Set<String> _issuedExecutionIds = <String>{};
  final Map<String, PlanOutcomeIngestion> _ingestionsByExecutionId =
      <String, PlanOutcomeIngestion>{};

  PlanExecutionLaunch start({
    required PlanExecutionContext context,
    required CompiledPlanStep step,
    required practice.PracticeSessionConfig sessionConfig,
  }) {
    _validateLaunch(context: context, step: step, sessionConfig: sessionConfig);
    final executionId = BlockExecutionId._(
      planId: context.planId,
      revisionId: context.revisionId,
      dayId: context.dayId,
      blockId: context.blockId,
      token: _createExecutionToken(),
    );
    if (!_issuedExecutionIds.add(executionId.value)) {
      throw StateError('Duplicate block execution id ${executionId.value}');
    }
    return PlanExecutionLaunch(
      blockExecutionId: executionId,
      step: step,
      sessionConfig: sessionConfig,
    );
  }

  PlanOutcomeIngestion recordOutcome({
    required BlockExecutionId blockExecutionId,
    required PracticeOutcomeContext context,
    required PracticeOutcomeInput input,
  }) {
    _validateOutcomeContext(blockExecutionId, context);
    final existing = _ingestionsByExecutionId[blockExecutionId.value];
    if (existing != null) return existing.asDuplicate();

    final outcome = _outcomeAdapter.adapt(context: context, input: input);
    final contributesSkillEvidence =
        outcome.completionState == PracticeCompletionState.completed &&
        outcome.metricEvidence.isNotEmpty;
    final ingestion = PlanOutcomeIngestion(
      outcome: outcome,
      isDuplicate: false,
      contributesSkillEvidence: contributesSkillEvidence,
      // R23 only normalizes an outcome. It must never request a regression;
      // the bounded adaptation policy is applied by its dedicated later round.
      requestsRegression: false,
    );
    _ingestionsByExecutionId[blockExecutionId.value] = ingestion;
    return ingestion;
  }

  void _validateLaunch({
    required PlanExecutionContext context,
    required CompiledPlanStep step,
    required practice.PracticeSessionConfig sessionConfig,
  }) {
    if (context.blockId != step.blockId) {
      throw ArgumentError.value(
        context.blockId,
        'context.blockId',
        'must match the compiled step blockId',
      );
    }
    if (sessionConfig.validate().isNotEmpty) {
      throw ArgumentError.value(
        sessionConfig,
        'sessionConfig',
        'must satisfy Practice Engine validation',
      );
    }
    if (sessionConfig.definitionId != step.exerciseSnapshotReference ||
        sessionConfig.loopCount != step.config.loopCount ||
        sessionConfig.sessionTimeout != step.config.elapsed ||
        (step.config.tempoBpm != null &&
            sessionConfig.effectiveTempo.bpm != step.config.tempoBpm)) {
      throw ArgumentError.value(
        sessionConfig,
        'sessionConfig',
        'must exactly match the compiled prescription',
      );
    }
  }

  void _validateOutcomeContext(
    BlockExecutionId blockExecutionId,
    PracticeOutcomeContext context,
  ) {
    if (context.planId != blockExecutionId.planId ||
        context.revisionId != blockExecutionId.revisionId ||
        context.dayId != blockExecutionId.dayId ||
        context.blockId != blockExecutionId.blockId) {
      throw ArgumentError.value(
        context,
        'context',
        'must match the block execution location',
      );
    }
  }
}

String _requiredText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
