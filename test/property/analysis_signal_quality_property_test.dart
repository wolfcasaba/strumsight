import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/signal_quality_stage.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;

  test(
    'property: signal quality report is finite and bounded (PROPERTY_SEED=$seed)',
    () async {
      final random = math.Random(seed);
      final cases = <List<double>>[
        List<double>.filled(4096, 0),
        List<double>.filled(4096, 1),
        List<double>.filled(4096, -1),
        List<double>.generate(4096, (index) => index.isEven ? 1 : 1e-12),
      ];
      for (var index = 0; index < 32; index++) {
        cases.add(
          List<double>.generate(
            128 + random.nextInt(8192),
            (_) =>
                (random.nextDouble() * 2 - 1) *
                math.pow(10, -random.nextDouble() * 10),
          ),
        );
      }

      final stage = SignalQualityStage();
      for (var index = 0; index < cases.length; index++) {
        final result = await _run(stage, cases[index]);
        final report = result.report;
        for (final value in <double>[
          report.overall,
          report.peakDbfs,
          report.rmsDbfs,
          report.noiseFloorDbfs,
          report.tonalness,
        ]) {
          expect(
            value.isFinite,
            isTrue,
            reason: 'seed=$seed case=$index value=$value',
          );
        }
        expect(report.overall, inInclusiveRange(0, 1));
        expect(report.peakDbfs, inInclusiveRange(-120, 6));
        expect(report.rmsDbfs, inInclusiveRange(-120, 6));
        expect(report.noiseFloorDbfs, inInclusiveRange(-120, 6));
        expect(report.tonalness, inInclusiveRange(0, 1));
        expect(report.clippedSampleRatio, inInclusiveRange(0, 1));
        expect(report.silentRatio, inInclusiveRange(0, 1));
        expect(result.activeRegionRatio, inInclusiveRange(0, 1));
      }
    },
  );
}

Future<SignalQualityStageResult> _run(
  SignalQualityStage stage,
  List<double> samples,
) async {
  final result = await stage.run(
    ValidatedPcmAnalysisInput(
      input: PcmAnalysisInput(
        samples: samples,
        sampleRate: 44100,
        channelCount: 1,
        source: AnalysisInputSource.microphone,
      ),
    ),
    AnalysisStageContext(
      runId: 'quality-property',
      phase: AnalysisProgressPhase.computingMetrics,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    ),
  );
  return switch (result) {
    Success<SignalQualityStageResult>(:final value) => value,
    Failure<SignalQualityStageResult>(:final error) => throw StateError(
      error.code,
    ),
  };
}
