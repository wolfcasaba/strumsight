import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/execution/execution_fixtures.dart';

void main() {
  CompiledPlanStep compiledStep() {
    final result = const PlanCompiler().compile(
      block: executionBlock(),
      availability: executionAvailability(),
    );
    return result as CompiledPlanStep;
  }

  group('PlanExecutionCoordinator — normalized outcomes', () {
    test(
      'A1: a technical failure never contributes skill evidence or regression',
      () {
        final coordinator = PlanExecutionCoordinator(
          createExecutionToken: () => 'execution-token-1',
        );
        final launch = coordinator.start(
          context: executionContext(),
          step: compiledStep(),
          sessionConfig: matchingSessionConfig(),
        );

        final ingestion = coordinator.recordOutcome(
          blockExecutionId: launch.blockExecutionId,
          context: outcomeContext(),
          input: TechnicalFailurePracticeOutcome(
            failureCode: 'microphoneUnavailable',
          ),
        );

        expect(
          ingestion.outcome.completionState,
          PracticeCompletionState.failedTechnical,
        );
        expect(ingestion.contributesSkillEvidence, isFalse);
        expect(ingestion.requestsRegression, isFalse);
      },
    );

    test(
      'A4: records a block execution only once when its outcome returns twice',
      () {
        final coordinator = PlanExecutionCoordinator(
          createExecutionToken: () => 'execution-token-1',
        );
        final launch = coordinator.start(
          context: executionContext(),
          step: compiledStep(),
          sessionConfig: matchingSessionConfig(),
        );
        final input = CompletedPracticeSessionOutcome(
          sessionResult: completedSession(),
          metricEvidence: const <String, double>{'overall': 0.9},
        );

        final first = coordinator.recordOutcome(
          blockExecutionId: launch.blockExecutionId,
          context: outcomeContext(),
          input: input,
        );
        final replay = coordinator.recordOutcome(
          blockExecutionId: launch.blockExecutionId,
          context: outcomeContext(outcomeId: 'outcome.execution.replay'),
          input: const CancelledPracticeOutcome(),
        );

        expect(first.isDuplicate, isFalse);
        expect(replay.isDuplicate, isTrue);
        expect(replay.outcome, same(first.outcome));
      },
    );

    test(
      'A6: an interrupted completed session is partial, never a failure',
      () {
        final coordinator = PlanExecutionCoordinator(
          createExecutionToken: () => 'execution-token-1',
        );
        final launch = coordinator.start(
          context: executionContext(),
          step: compiledStep(),
          sessionConfig: matchingSessionConfig(),
        );

        final ingestion = coordinator.recordOutcome(
          blockExecutionId: launch.blockExecutionId,
          context: outcomeContext(),
          input: CompletedPracticeSessionOutcome(
            sessionResult: completedSession(
              finishReason: PracticeFinishReason.interrupted,
            ),
            metricEvidence: const <String, double>{'overall': 0.2},
          ),
        );

        expect(
          ingestion.outcome.completionState,
          PracticeCompletionState.partial,
        );
        expect(ingestion.contributesSkillEvidence, isFalse);
        expect(ingestion.requestsRegression, isFalse);
      },
    );
  });

  test('A7: block execution ids are unique and retain their plan location', () {
    var serial = 0;
    final coordinator = PlanExecutionCoordinator(
      createExecutionToken: () => 'execution-token-${++serial}',
    );

    final first = coordinator.start(
      context: executionContext(),
      step: compiledStep(),
      sessionConfig: matchingSessionConfig(),
    );
    final second = coordinator.start(
      context: executionContext(),
      step: compiledStep(),
      sessionConfig: matchingSessionConfig(),
    );

    expect(first.blockExecutionId, isNot(second.blockExecutionId));
    expect(first.blockExecutionId.planId, PlanId('plan.execution.1'));
    expect(
      first.blockExecutionId.revisionId,
      RevisionId('revision.execution.1'),
    );
    expect(first.blockExecutionId.dayId, DayId('day.execution.1'));
    expect(first.blockExecutionId.blockId, BlockId('block.execution.1'));
  });
}
