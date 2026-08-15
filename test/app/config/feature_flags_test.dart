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
}
