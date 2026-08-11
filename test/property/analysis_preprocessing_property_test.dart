import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/preprocessing/preprocessing_stage.dart';

void main() {
  test(
    'seeded native-rate preprocessing preserves timebase and input samples',
    () async {
      final seed =
          int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
      // ignore: avoid_print
      print('PROPERTY_SEED=$seed');
      final random = Random(seed);
      const stage = PreprocessingStage();

      for (var iteration = 0; iteration < 80; iteration++) {
        final sampleRate = random.nextBool() ? 44100 : 48000;
        final length = sampleRate + random.nextInt(2048) + 2;
        final samples = List<double>.generate(
          length,
          (_) => random.nextDouble() * 2 - 1,
        );
        final snapshot = List<double>.from(samples);
        final output = await _run(stage, samples, sampleRate);
        final index = random.nextInt(length);
        final duration = output.sampleIndexToDuration(index);

        expect(
          output.originalSamples,
          snapshot,
          reason: 'seed=$seed case=$iteration',
        );
        expect(
          identical(output.originalSamples, output.canonicalSamples),
          isTrue,
        );
        expect(output.durationToSampleIndex(duration), index);
      }
    },
  );
}

Future<PreprocessedAudio> _run(
  PreprocessingStage stage,
  List<double> samples,
  int sampleRate,
) async {
  final result = await stage.run(
    ValidatedPcmAnalysisInput(
      input: PcmAnalysisInput(
        samples: samples,
        sampleRate: sampleRate,
        channelCount: 1,
        source: AnalysisInputSource.microphone,
      ),
    ),
    AnalysisStageContext(
      runId: 'preprocessing-property',
      phase: AnalysisProgressPhase.preprocessing,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    ),
  );
  return switch (result) {
    Success<PreprocessedAudio>(:final value) => value,
    Failure<PreprocessedAudio>(:final error) => throw StateError(error.code),
  };
}
