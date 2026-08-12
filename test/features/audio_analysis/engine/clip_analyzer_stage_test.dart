import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';

import '../../../support/synth.dart';

void main() {
  group('ClipAnalyzerStage provenance', () {
    test(
      'records the effective legacy parameters and immutable call evidence',
      () async {
        final input = LegacyClipAnalyzerInput(
          samples: strumPattern(lowFirstPerStrum: [true, false]),
          sampleRate: 44100,
        );
        final evidence = await _run(const ClipAnalyzerStage(), input);

        expect(evidence.call.sampleRate, 44100);
        expect(evidence.call.sampleCount, input.samples.length);
        expect(evidence.call.labMode, isFalse);
        expect(evidence.call.hasCandidateStrumRefiner, isFalse);
        expect(evidence.provenance.chunkSize, 2048);
        expect(evidence.provenance.chromaMedianWindow, 1);
        expect(evidence.provenance.bassWeight, 0.35);
        expect(evidence.provenance.nnlsWindow, 16384);
        expect(evidence.provenance.nnlsHop, 4096);
        expect(evidence.provenance.strumRefinerSource, StrumRefinerSource.none);
        expect(evidence.provenance.fallbackReason, isNull);
        expect(evidence.provenance.modelManifestIds, isEmpty);

        expect(
          () => evidence.chords.add(
            const LegacyChordEvidence(
              label: 'C',
              start: Duration.zero,
              end: Duration.zero,
            ),
          ),
          throwsUnsupportedError,
        );
        expect(
          () => evidence.call.modelManifestIds.add('mutated'),
          throwsUnsupportedError,
        );
      },
    );

    test('uses round half away from zero for V1 seconds time conversion', () {
      expect(
        LegacyEvidence.durationFromSeconds(0.0000005),
        const Duration(microseconds: 1),
      );
      expect(
        LegacyEvidence.durationFromSeconds(0.0000015),
        const Duration(microseconds: 2),
      );
      expect(
        LegacyEvidence.durationFromSeconds(0.0000025),
        const Duration(microseconds: 3),
      );
    });

    test(
      'distinguishes no refiner, inferred fallback, and active CRNN',
      () async {
        final clip = strumPattern(lowFirstPerStrum: [true, false, true, false]);
        final stage = const ClipAnalyzerStage();

        final none = await _run(
          stage,
          LegacyClipAnalyzerInput(samples: clip, sampleRate: 44100),
        );
        expect(none.provenance.strumRefinerSource, StrumRefinerSource.none);
        expect(none.provenance.fallbackReason, isNull);

        final fallback = await _run(
          stage,
          LegacyClipAnalyzerInput(
            samples: clip,
            sampleRate: 44100,
            strumRefinerWeights: Uint8List(16),
          ),
        );
        expect(
          fallback.provenance.strumRefinerSource,
          StrumRefinerSource.heuristic,
        );
        expect(fallback.provenance.fallbackReason, isNotNull);

        final crnn = await _run(
          stage,
          LegacyClipAnalyzerInput(
            samples: clip,
            sampleRate: 44100,
            strumRefinerWeights: Uint8List.fromList(
              File('assets/ml/strum_crnn.bin').readAsBytesSync(),
            ),
          ),
        );
        expect(crnn.strums, isNotEmpty);
        expect(crnn.provenance.strumRefinerSource, StrumRefinerSource.crnn);
        expect(crnn.provenance.fallbackReason, isNull);
        expect(crnn.provenance.modelManifestIds, isNotEmpty);
      },
    );
  });
}

Future<LegacyEvidence> _run(
  ClipAnalyzerStage stage,
  LegacyClipAnalyzerInput input,
) async {
  final result = await stage.run(
    input,
    AnalysisStageContext(
      runId: 'clip-analyzer-stage-test',
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
