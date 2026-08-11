// Randomized property gate (anti-reward-hacking — HORIZON pattern).
//
// The fixture-matrix tests in signal_quality_stage_test.dart are the dev
// loop's visible harness; this suite re-checks the finite/range invariants
// on RANDOMIZED PCM so the stage cannot be (even accidentally) tuned to the
// fixed fixtures. See docs/rag/chunks/019-signal-quality-metrics.md.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

const _sampleRate = 44100;

void main() {
  test(
    'seeded random PCM never produces a NaN/Infinity or out-of-range field',
    () async {
      final seed =
          int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
      // Always visible in logs so any failure is reproducible.
      // ignore: avoid_print
      print('PROPERTY_SEED=$seed');
      final random = Random(seed);
      const stage = SignalQualityStage();

      for (var index = 0; index < 60; index++) {
        final length = 200 + random.nextInt(_sampleRate * 2);
        final samples = _randomSamples(random, length, index);

        final context = AnalysisStageContext(
          runId: 'property-run-$index',
          phase: AnalysisProgressPhase.preprocessing,
          cancellationToken: AnalysisCancellationSource(),
          eventSink: (_) {},
        );
        final result = await stage.run(
          PcmAnalysisInput(
            samples: samples,
            sampleRate: _sampleRate,
            channelCount: 1,
            source: AnalysisInputSource.microphone,
          ),
          context,
        );

        expect(result.isSuccess, isTrue, reason: 'seed=$seed case=$index');
        final report = result.valueOrNull!;

        expect(
          report.overall.isFinite,
          isTrue,
          reason: 'seed=$seed case=$index overall',
        );
        expect(
          report.peakDbfs.isFinite,
          isTrue,
          reason: 'seed=$seed case=$index peakDbfs',
        );
        expect(
          report.rmsDbfs.isFinite,
          isTrue,
          reason: 'seed=$seed case=$index rmsDbfs',
        );
        expect(
          report.noiseFloorDbfs.isFinite,
          isTrue,
          reason: 'seed=$seed case=$index noiseFloorDbfs',
        );
        expect(
          report.tonalness.isFinite,
          isTrue,
          reason: 'seed=$seed case=$index tonalness',
        );
        expect(
          report.overall,
          inInclusiveRange(0.0, 1.0),
          reason: 'seed=$seed case=$index',
        );
        expect(
          report.clippedSampleRatio,
          inInclusiveRange(0.0, 1.0),
          reason: 'seed=$seed case=$index',
        );
        expect(
          report.silentRatio,
          inInclusiveRange(0.0, 1.0),
          reason: 'seed=$seed case=$index',
        );
        expect(
          report.tonalness,
          inInclusiveRange(0.0, 1.0),
          reason: 'seed=$seed case=$index',
        );
        for (final dbfs in <double>[
          report.peakDbfs,
          report.rmsDbfs,
          report.noiseFloorDbfs,
        ]) {
          expect(
            dbfs,
            inInclusiveRange(
              QualityThresholds.silenceFloorDbfs,
              QualityThresholds.maxDbfs,
            ),
            reason: 'seed=$seed case=$index',
          );
        }
        for (final warning in report.warnings) {
          expect(
            warning.messageKey.trim(),
            isNotEmpty,
            reason: 'seed=$seed case=$index',
          );
        }
      }
    },
  );
}

List<double> _randomSamples(Random random, int length, int caseIndex) {
  switch (caseIndex % 5) {
    case 0:
      return List<double>.filled(length, 0.0);
    case 1:
      return List<double>.filled(length, 1.0);
    case 2:
      return List<double>.filled(length, -1.0);
    case 3:
      // Extreme dynamics: alternating full-scale spikes and digital silence.
      return List<double>.generate(
        length,
        (i) => i.isEven ? (random.nextBool() ? 1.0 : -1.0) : 0.0,
      );
    default:
      return List<double>.generate(
        length,
        (_) => (random.nextDouble() * 2 - 1) * random.nextDouble(),
      );
  }
}
