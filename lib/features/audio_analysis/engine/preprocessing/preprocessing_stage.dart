import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';

import 'preprocessing_config.dart';

/// Native-rate preprocessing stage for the V2 pipeline.
///
/// It accepts only the already-mono boundary input. [MonoDownmix] remains a
/// separately tested policy because applying it again here would duplicate the
/// core WAV codec's channel averaging.
final class PreprocessingStage
    implements AnalysisStage<ValidatedPcmAnalysisInput, PreprocessedAudio> {
  const PreprocessingStage({
    this.config = const PreprocessingConfig.v1(),
    this.experimentalEnabled = false,
  });

  final PreprocessingConfig config;
  final bool experimentalEnabled;

  @override
  String get id => 'preprocessing';

  @override
  int get version => 1;

  @override
  Future<AppResult<PreprocessedAudio>> run(
    ValidatedPcmAnalysisInput input,
    AnalysisStageContext context,
  ) async {
    context.cancellationToken.throwIfCancelled();
    final originalSamples = input.input.samples;
    if (!experimentalEnabled || !config.hasTransformations) {
      return Success<PreprocessedAudio>(
        PreprocessedAudio(
          originalSamples: originalSamples,
          canonicalSamples: originalSamples,
          sampleRate: input.input.sampleRate,
          originalChannelCount: input.input.channelCount,
          normalizationGain: 1,
          preprocessingVersion: config.version,
        ),
      );
    }

    final canonicalSamples = List<double>.from(originalSamples);
    if (config.removeDcOffset && canonicalSamples.isNotEmpty) {
      final offset =
          canonicalSamples.reduce((sum, value) => sum + value) /
          canonicalSamples.length;
      for (var index = 0; index < canonicalSamples.length; index++) {
        canonicalSamples[index] -= offset;
      }
    }

    var normalizationGain = 1.0;
    if (config.normalizePeak) {
      var peak = 0.0;
      for (final sample in canonicalSamples) {
        if (sample.abs() > peak) peak = sample.abs();
      }
      if (peak > 0) {
        normalizationGain = 1 / peak;
        for (var index = 0; index < canonicalSamples.length; index++) {
          canonicalSamples[index] *= normalizationGain;
        }
      }
    }

    context.cancellationToken.throwIfCancelled();
    return Success<PreprocessedAudio>(
      PreprocessedAudio(
        originalSamples: originalSamples,
        canonicalSamples: canonicalSamples,
        sampleRate: input.input.sampleRate,
        originalChannelCount: input.input.channelCount,
        normalizationGain: normalizationGain,
        preprocessingVersion: config.version,
      ),
    );
  }
}
