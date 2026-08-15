import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

void main() {
  group('Practice Generator feature flags', () {
    test('constructor defaults are off at the rollout boundary', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );

      expect(flags.practiceGeneratorEnabled, isFalse);
      expect(flags.plannerAssistEnabled, isFalse);
      expect(flags.toString(), contains('practiceGeneratorEnabled: false'));
      expect(flags.toString(), contains('plannerAssistEnabled: false'));
    });

    test('factory keeps both flags off in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.practiceGeneratorEnabled, isFalse);
      expect(flags.plannerAssistEnabled, isFalse);
    });

    test('factory keeps both flags off in non-production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.practiceGeneratorEnabled, isFalse);
      expect(flags.plannerAssistEnabled, isFalse);
    });
  });

  group('Recognition recovery feature flags', () {
    test('constructor defaults are off and participate in value semantics', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      const recoveryEnabled = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        recognitionRecoveryEnabled: true,
      );

      expect(defaults.recognitionRecoveryEnabled, isFalse);
      expect(defaults.recognitionShadowModeEnabled, isFalse);
      expect(defaults.newLiveStageEnabled, isFalse);
      expect(
        defaults.toString(),
        contains('recognitionRecoveryEnabled: false'),
      );
      expect(
        defaults.toString(),
        contains('recognitionShadowModeEnabled: false'),
      );
      expect(defaults.toString(), contains('newLiveStageEnabled: false'));
      expect(recoveryEnabled, isNot(equals(defaults)));
      expect(recoveryEnabled.hashCode, isNot(equals(defaults.hashCode)));
    });

    test('factory keeps all flags off in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      _expectRecognitionRecoveryFlagsOff(flags);
    });

    test('factory keeps all flags off in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      _expectRecognitionRecoveryFlagsOff(flags);
    });

    test('factory keeps all flags off in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      _expectRecognitionRecoveryFlagsOff(flags);
    });
  });
}

void _expectRecognitionRecoveryFlagsOff(FeatureFlags flags) {
  expect(flags.recognitionRecoveryEnabled, isFalse);
  expect(flags.recognitionShadowModeEnabled, isFalse);
  expect(flags.newLiveStageEnabled, isFalse);
}
