import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

bool _aiTutorEnabled(Object flags) {
  final dynamic dynamicFlags = flags;
  return dynamicFlags.aiTutorEnabled as bool;
}

bool _aiTutorCloudEnabled(Object flags) {
  final dynamic dynamicFlags = flags;
  return dynamicFlags.aiTutorCloudEnabled as bool;
}

List<bool> _visionFlags(FeatureFlags flags) => <bool>[
  flags.visionEnabled,
  flags.visionSetupEnabled,
  flags.visionHandTrackingEnabled,
  flags.visionPoseTrackingEnabled,
  flags.visionGuitarGeometryEnabled,
  flags.visionPracticeIntegrationEnabled,
  flags.visionSongIntegrationEnabled,
  flags.visionTutorIntegrationEnabled,
  flags.visionAnalysisIntegrationEnabled,
  flags.visionExperimentalFineFretEnabled,
  flags.visionLabCaptureEnabled,
];

List<bool> _audioAnalysisFlags(FeatureFlags flags) => <bool>[
  flags.audioAnalysisV2Enabled,
  flags.analysisBeatGridEnabled,
  flags.analysisPitchEnabled,
  flags.analysisPreprocessingExperimentalEnabled,
  flags.analysisExperimentalFusionEnabled,
  flags.analysisComparisonEnabled,
];

FeatureFlags _withAiTutorFlags({
  required bool aiTutorEnabled,
  required bool aiTutorCloudEnabled,
}) {
  return Function.apply(FeatureFlags.new, const <Object?>[], <Symbol, Object?>{
        #accountEnabled: false,
        #diagnosticsEnabled: false,
        #labModeAvailable: false,
        #aiTutorEnabled: aiTutorEnabled,
        #aiTutorCloudEnabled: aiTutorCloudEnabled,
      })
      as FeatureFlags;
}

void _expectAiTutorFlagsOff(Object flags) {
  expect(
    () => _aiTutorEnabled(flags),
    returnsNormally,
    reason: 'FeatureFlags must expose aiTutorEnabled.',
  );
  expect(
    () => _aiTutorCloudEnabled(flags),
    returnsNormally,
    reason: 'FeatureFlags must expose aiTutorCloudEnabled.',
  );
  expect(_aiTutorEnabled(flags), isFalse);
  expect(_aiTutorCloudEnabled(flags), isFalse);
}

void main() {
  group('Song Trainer V2 rollout boundary', () {
    test('is enabled in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.songTrainerV2Enabled, isTrue);
    });

    test('is enabled in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(flags.songTrainerV2Enabled, isTrue);
    });

    test('remains disabled in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.songTrainerV2Enabled, isFalse);
    });

    test('keeps unrelated rollout flags disabled in every environment', () {
      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        expect(flags.aiTutorEnabled, isFalse);
        expect(flags.aiTutorCloudEnabled, isFalse);
        expect(flags.visionEnabled, isFalse);
      }
    });
  });

  group('Adaptive shell feature flag (E15-R02, ADR 0467, A1)', () {
    test('is enabled in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.adaptiveShellEnabled, isTrue);
    });

    test('is enabled in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(flags.adaptiveShellEnabled, isTrue);
    });

    test('remains disabled in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.adaptiveShellEnabled, isFalse);
    });
  });

  group('Migrated Learn rollout boundary', () {
    test('is enabled in development', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isTrue);
    });

    test('is enabled in lab', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isTrue);
    });

    test('remains disabled in production', () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isFalse);
    });
  });

  group('AI Tutor feature flags', () {
    test('const constructor defaults both flags to off', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );

      _expectAiTutorFlagsOff(flags);
    });

    test('forEnvironment leaves both flags off in every environment', () {
      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        _expectAiTutorFlagsOff(flags);
      }
    });

    test('new flags participate in value semantics but not network use', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(
        () =>
            _withAiTutorFlags(aiTutorEnabled: true, aiTutorCloudEnabled: false),
        returnsNormally,
        reason: 'FeatureFlags must accept both AI Tutor flags.',
      );
      final tutorEnabled = _withAiTutorFlags(
        aiTutorEnabled: true,
        aiTutorCloudEnabled: false,
      );
      final cloudEnabled = _withAiTutorFlags(
        aiTutorEnabled: false,
        aiTutorCloudEnabled: true,
      );
      final tutorEnabledCopy = _withAiTutorFlags(
        aiTutorEnabled: true,
        aiTutorCloudEnabled: false,
      );
      final cloudEnabledCopy = _withAiTutorFlags(
        aiTutorEnabled: false,
        aiTutorCloudEnabled: true,
      );

      expect(tutorEnabled, isNot(defaults));
      expect(cloudEnabled, isNot(defaults));
      expect(tutorEnabledCopy, tutorEnabled);
      expect(tutorEnabledCopy.hashCode, tutorEnabled.hashCode);
      expect(cloudEnabledCopy, cloudEnabled);
      expect(cloudEnabledCopy.hashCode, cloudEnabled.hashCode);
      expect(tutorEnabled.usesNetwork, isFalse);
      expect(cloudEnabled.usesNetwork, isFalse);
      expect(tutorEnabled.toString(), contains('aiTutorEnabled: true'));
      expect(cloudEnabled.toString(), contains('aiTutorCloudEnabled: true'));
    });
  });

  group('Computer Vision feature flags', () {
    test('all eleven flags default to off in every environment', () {
      const constructorDefaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(_visionFlags(constructorDefaults), everyElement(isFalse));

      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );

        expect(
          _visionFlags(flags),
          everyElement(isFalse),
          reason: '$environment must not implicitly enable Computer Vision.',
        );
      }
    });

    test('vision flags are offline and participate in value semantics', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      const enabled = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: true,
      );
      const enabledCopy = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: true,
      );

      expect(enabled, isNot(defaults));
      expect(enabledCopy, enabled);
      expect(enabledCopy.hashCode, enabled.hashCode);
      expect(enabled.usesNetwork, isFalse);
      expect(enabled.toString(), contains('visionEnabled: true'));
    });
  });

  group('Audio Analysis V2 rollout boundary', () {
    test('all audio analysis flags remain off in every environment', () {
      const constructorDefaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(_audioAnalysisFlags(constructorDefaults), everyElement(isFalse));

      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );
        expect(
          _audioAnalysisFlags(flags),
          everyElement(isFalse),
          reason: '$environment must not implicitly enable Audio Analysis V2.',
        );
        expect(flags.toString(), contains('audioAnalysisV2Enabled: false'));
        expect(flags.toString(), contains('analysisBeatGridEnabled: false'));
        expect(flags.toString(), contains('analysisPitchEnabled: false'));
        expect(
          flags.toString(),
          contains('analysisPreprocessingExperimentalEnabled: false'),
        );
        expect(
          flags.toString(),
          contains('analysisExperimentalFusionEnabled: false'),
        );
        expect(flags.toString(), contains('analysisComparisonEnabled: false'));
      }
    });

    test('analysisComparisonEnabled defaults to false and remains off for '
        'every environment', () {
      const constructorDefaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(constructorDefaults.analysisComparisonEnabled, isFalse);

      for (final environment in AppEnvironment.values) {
        final flags = FeatureFlags.forEnvironment(
          environment,
          accountEnabled: false,
        );
        expect(
          flags.analysisComparisonEnabled,
          isFalse,
          reason: '$environment must not implicitly enable comparison.',
        );
      }
    });

    test(
      'audio analysis flags participate in value semantics and remain offline',
      () {
        const defaults = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
        );
        const enabled = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          audioAnalysisV2Enabled: true,
          analysisExperimentalFusionEnabled: true,
        );
        const enabledCopy = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          audioAnalysisV2Enabled: true,
          analysisExperimentalFusionEnabled: true,
        );
        expect(enabled, isNot(defaults));
        expect(enabledCopy, enabled);
        expect(enabledCopy.hashCode, enabled.hashCode);
        expect(enabled.hashCode, isNot(defaults.hashCode));
        expect(enabled.usesNetwork, isFalse);
      },
    );
  });
}
