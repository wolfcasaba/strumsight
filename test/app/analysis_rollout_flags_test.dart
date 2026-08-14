import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart';

List<bool> _audioAnalysisFlags(FeatureFlags flags) => <bool>[
  flags.audioAnalysisV2Enabled,
  flags.analysisBeatGridEnabled,
  flags.analysisPitchEnabled,
  flags.analysisPreprocessingExperimentalEnabled,
  flags.analysisExperimentalFusionEnabled,
  flags.analysisTechniqueProxiesEnabled,
  flags.analysisComparisonEnabled,
  flags.analysisPracticeIntegrationEnabled,
  flags.analysisTutorIntegrationEnabled,
];

void main() {
  test('all nine Audio Analysis V2 flags stay off in every environment', () {
    for (final environment in AppEnvironment.values) {
      final flags = FeatureFlags.forEnvironment(
        environment,
        accountEnabled: false,
      );

      expect(_audioAnalysisFlags(flags), everyElement(isFalse));
      expect(flags.analysisRolloutStage, AnalysisRolloutStage.v1Default);
    }
  });
}
