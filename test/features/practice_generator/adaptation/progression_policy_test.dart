import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  group('ProgressionPolicy — centralized adaptation bounds', () {
    test('exposes all v1 bounds from one versioned policy', () {
      final policy = ProgressionPolicy.defaultPolicy;

      expect(policy.version, 'progression-policy-v1');
      expect(policy.maximumDifficultyStep, 1);
      expect(policy.minimumSuccessfulEvidence, 3);
      expect(policy.minimumEvidenceConfidence, 0.8);
      expect(policy.maximumEstimateUncertainty, 0.4);
      expect(policy.repeatedStruggleEvidence, 2);
      expect(policy.advanceCooldown, const Duration(days: 7));
      expect(policy.tempoStepBpm, 10);
      expect(policy.minimumTempoBpm, 40);
      expect(policy.maximumTempoBpm, 180);
      expect(policy.minimumDifficultyLevel, 0);
      expect(policy.minimumLoopCount, 1);
      expect(policy.minimumVariationLevel, 0);
      expect(policy.minimumStrictnessLevel, 0);
    });

    test('A6: an advance inside the cooldown is held', () {
      final policy = ProgressionPolicy.defaultPolicy;
      final asOf = DateTime.utc(2026, 8, 16, 12);

      expect(
        policy.isAdvanceInCooldown(
          asOf.subtract(const Duration(days: 6)),
          asOf,
        ),
        isTrue,
      );
      expect(
        policy.isAdvanceInCooldown(
          asOf.subtract(const Duration(days: 7)),
          asOf,
        ),
        isFalse,
      );
    });

    test('A7: tempo is clamped to the supported policy range', () {
      final policy = ProgressionPolicy.defaultPolicy;

      expect(policy.clampTempoBpm(30), 40);
      expect(policy.clampTempoBpm(180), 180);
      expect(policy.clampTempoBpm(220), 180);
    });

    test('rejects invalid or internally inconsistent bounds', () {
      expect(() => ProgressionPolicy(version: ''), throwsArgumentError);
      expect(
        () => ProgressionPolicy(maximumDifficultyStep: 2),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(minimumSuccessfulEvidence: 0),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(minimumEvidenceConfidence: 1.1),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(maximumEstimateUncertainty: -0.1),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(repeatedStruggleEvidence: 1),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(advanceCooldown: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(minimumTempoBpm: 181, maximumTempoBpm: 180),
        throwsArgumentError,
      );
      expect(() => ProgressionPolicy(minimumLoopCount: 0), throwsArgumentError);
      expect(
        () => ProgressionPolicy(minimumDifficultyLevel: -1),
        throwsArgumentError,
      );
      expect(
        () => ProgressionPolicy(minimumVariationLevel: -1),
        throwsArgumentError,
      );
    });
  });
}
