import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';

void main() {
  test(
    'property: seeded V1 and stage parity holds for at least 50 clips',
    () async {
      final seed =
          int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
      // ignore: avoid_print
      print('PROPERTY_SEED=$seed');
      final random = Random(seed);

      for (var iteration = 0; iteration < 60; iteration++) {
        final sampleRate = random.nextBool() ? 44100 : 48000;
        final samples = List<double>.generate(
          300 + random.nextInt(1800),
          (_) => random.nextDouble() * 2 - 1,
        );
        final legacy = runClipAnalysis((
          samples,
          sampleRate,
          null,
          false,
          null,
        ));
        final actual = await _run(
          LegacyClipAnalyzerInput(samples: samples, sampleRate: sampleRate),
        );
        final expected = LegacyEvidence.fromAnalyzeResult(
          legacy,
          call: LegacyClipAnalyzerCall(
            sampleRate: sampleRate,
            sampleCount: samples.length,
            labMode: false,
            hasCandidateStrumRefiner: false,
          ),
          provenance: actual.provenance,
        );

        expect(
          actual.chords,
          hasLength(expected.chords.length),
          reason: 'seed=$seed case=$iteration',
        );
        expect(
          actual.strums,
          hasLength(expected.strums.length),
          reason: 'seed=$seed case=$iteration',
        );
        expect(
          (actual.bpm - expected.bpm).abs(),
          lessThanOrEqualTo(1e-9),
          reason: 'seed=$seed case=$iteration',
        );
        for (var index = 0; index < expected.chords.length; index++) {
          expect(
            (actual.chords[index].start - expected.chords[index].start)
                .inMicroseconds
                .abs(),
            lessThanOrEqualTo(1),
            reason: 'seed=$seed case=$iteration chord=$index',
          );
        }
        for (var index = 0; index < expected.strums.length; index++) {
          expect(
            actual.strums[index].direction,
            expected.strums[index].direction,
            reason: 'seed=$seed case=$iteration strum=$index',
          );
          expect(
            (actual.strums[index].time - expected.strums[index].time)
                .inMicroseconds
                .abs(),
            lessThanOrEqualTo(1),
            reason: 'seed=$seed case=$iteration strum=$index',
          );
        }
      }
    },
  );
}

Future<LegacyEvidence> _run(LegacyClipAnalyzerInput input) async {
  final result = await const ClipAnalyzerStage().run(
    input,
    AnalysisStageContext(
      runId: 'legacy-parity-property',
      phase: AnalysisProgressPhase.extractingEvents,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    ),
  );
  return switch (result) {
    Success<LegacyEvidence>(:final value) => value,
    Failure<LegacyEvidence>(:final error) => throw StateError(error.code),
  };
}
