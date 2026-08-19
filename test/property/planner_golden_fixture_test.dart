import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/application/service/shadow_plan_generator.dart';

import '../fixtures/practice_planner/golden_profiles.dart';

void main() {
  test('E07-R30 A1: every golden learner profile has zero hard invariant '
      'violations and its expected executable candidates', () async {
    final generator = ShadowPlanGenerator();

    for (final profile in goldenProfiles()) {
      final run = await generator.generate(profile.input);
      final plan = run.result.valueOrNull;

      expect(run.result, isA<Success>(), reason: profile.id);
      expect(plan, isNotNull, reason: profile.id);
      expect(
        run.hardViolationCount,
        isZero,
        reason: '${profile.id}: hard validation findings are never tolerated',
      );
      expect(
        <String>[
          for (final day in plan!.days)
            for (final block in day.blocks) block.prescription.exerciseId,
        ],
        profile.expectedCandidateIds,
        reason: '${profile.id}: golden executable candidate expectation',
      );
    }
  });
}
