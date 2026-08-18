import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/execution/execution_fixtures.dart';

void main() {
  const compiler = PlanCompiler();

  group('PlanCompiler — availability checks', () {
    test('A2: refuses an exercise whose content revision is stale', () {
      final result = compiler.compile(
        block: executionBlock(),
        availability: executionAvailability(contentRevision: 'content.v2'),
      );

      expect(result, isA<UnavailablePlanStep>());
      expect(
        (result as UnavailablePlanStep).reason,
        PlanCompilationUnavailableReason.staleContentRevision,
      );
    });

    test('A3: refuses an exercise when a required capability disappeared', () {
      final result = compiler.compile(
        block: executionBlock(),
        availability: executionAvailability(
          capabilityOverrides: const <ExerciseCapability, CapabilitySupport>{
            ExerciseCapability.supportsTempo: CapabilitySupport.unsupported,
          },
        ),
      );

      expect(result, isA<UnavailablePlanStep>());
      expect(
        (result as UnavailablePlanStep).reason,
        PlanCompilationUnavailableReason.missingCapability,
      );
    });
  });

  test('A5: retains every prescribed session value exactly', () {
    final result = compiler.compile(
      block: executionBlock(),
      availability: executionAvailability(),
    );

    expect(result, isA<CompiledPlanStep>());
    final step = result as CompiledPlanStep;
    expect(step.sourceRevision, 'content.v1');
    expect(step.exerciseSnapshotReference, 'practice.strum.v1');
    expect(step.config.activeDuration, const Duration(minutes: 5));
    expect(step.config.restDuration, const Duration(minutes: 1));
    expect(step.config.tempoBpm, 72);
    expect(
      step.config.repetition,
      RepetitionPrescription(target: 4, maximum: 6),
    );
    expect(step.config.loopCount, 1);
    expect(step.config.hardElapsedLimit, const Duration(minutes: 6));
  });
}
