import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart';

/// The seven Audio Analysis V2 flags that follow the `nonProd` boundary
/// since the owner decision of 2026-09-15.
List<bool> _nonProdAnalysisFlags(FeatureFlags flags) => <bool>[
  flags.audioAnalysisV2Enabled,
  flags.analysisBeatGridEnabled,
  flags.analysisPitchEnabled,
  flags.analysisTechniqueProxiesEnabled,
  flags.analysisComparisonEnabled,
  flags.analysisPracticeIntegrationEnabled,
  flags.analysisTutorIntegrationEnabled,
];

/// The two experimental flags that stay off in every environment.
List<bool> _experimentalAnalysisFlags(FeatureFlags flags) => <bool>[
  flags.analysisPreprocessingExperimentalEnabled,
  flags.analysisExperimentalFusionEnabled,
];

void main() {
  test('the seven non-experimental Audio Analysis V2 flags are on outside '
      'production and the rollout stage is v2OptIn there', () {
    for (final environment in [
      AppEnvironment.development,
      AppEnvironment.lab,
    ]) {
      final flags = FeatureFlags.forEnvironment(
        environment,
        accountEnabled: false,
      );

      expect(
        _nonProdAnalysisFlags(flags),
        everyElement(isTrue),
        reason: '$environment',
      );
      expect(flags.analysisRolloutStage, AnalysisRolloutStage.v2OptIn);
    }
  });

  test('the two experimental Audio Analysis flags stay off in every '
      'environment', () {
    for (final environment in AppEnvironment.values) {
      final flags = FeatureFlags.forEnvironment(
        environment,
        accountEnabled: false,
      );

      expect(
        _experimentalAnalysisFlags(flags),
        everyElement(isFalse),
        reason: '$environment',
      );
    }
  });

  test('all nine Audio Analysis V2 flags stay off in production and the '
      'rollout stage stays v1Default there', () {
    final flags = FeatureFlags.forEnvironment(
      AppEnvironment.production,
      accountEnabled: false,
    );

    expect(_nonProdAnalysisFlags(flags), everyElement(isFalse));
    expect(_experimentalAnalysisFlags(flags), everyElement(isFalse));
    expect(flags.analysisRolloutStage, AnalysisRolloutStage.v1Default);
  });
}
