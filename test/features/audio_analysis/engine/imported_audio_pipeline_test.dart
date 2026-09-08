// R26 (audit MI4) — an imported file runs the SAME chain a recording runs.
//
// The claim this file measures is the whole point of the import flow: the
// pipeline must not care where the PCM came from. So the cell starts from
// real WAV BYTES (encoded here, decoded by the shipped boundary decoder),
// feeds the result into the same `buildFullAnalysisStages()` chain
// `full_pipeline_composition_test.dart` runs for a captured clip, and then
// checks the document that comes out — including the one piece of
// provenance an import adds and a recording does not.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/wav_decoder_adapter.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_pipeline.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/analysis_stage_phases.dart';

import '../../../support/synth.dart';

const _sampleRate = 44100;

void main() {
  test('an imported WAV produces a normal analysis document', () async {
    final decoded = const WavDecoderAdapter().decodeInput(
      FileAnalysisInput(
        bytes: _encodeWav(_clip()),
        source: AnalysisInputSource.importedFile,
        sourceDisplayName: const SourceDisplayName('practice-take.wav'),
      ),
    );

    expect(decoded, isA<Success<PcmAnalysisInput>>());
    final audio = (decoded as Success<PcmAnalysisInput>).value;

    final pipeline = AnalysisPipeline<AnalysisWorkState>(
      stages: buildFullAnalysisStages(),
      failureClassifier: classifyAnalysisStageFailure,
      stagePhases: analysisStagePhases,
    );
    final run = pipeline.start(
      AnalysisWorkState.seed(
        input: ValidatedPcmAnalysisInput(input: audio),
        mode: AnalysisMode.importedRecording,
      ),
      cancellationToken: AnalysisCancellationSource(),
    );
    final subscription = run.progress.listen((_) {});
    final result = await run.result;
    await subscription.cancel();

    // Not pinned to `complete`: which capabilities a given clip supports is
    // `full_pipeline_composition_test.dart`'s subject, not this one's. What
    // an import must guarantee is that the run REACHES a document at all —
    // a failed or cancelled run has none, and the assertions below would
    // then have nothing to check.
    expect(
      result.completion,
      anyOf(
        AnalysisCompletionStatus.complete,
        AnalysisCompletionStatus.degraded,
      ),
    );
    final document = result.value?.document;
    expect(document, isNotNull);

    // A NORMAL document: the same shape a recorded run produces, with the
    // measured signal-quality report the assembly stage refuses to invent.
    expect(document!.schemaVersion, analysisDocumentSchemaVersion);
    expect(document.mode, AnalysisMode.importedRecording);
    expect(document.signalQuality.measured, isTrue);
    expect(document.metrics, isNotEmpty);
    expect(document.timeline.duration, greaterThan(Duration.zero));

    // …and the import's own provenance: the source is the file boundary, the
    // file NAME is kept, and nothing else about the file is.
    expect(document.input.source, AnalysisInputSource.importedFile);
    expect(document.input.sourceName, 'practice-take.wav');
    expect(document.input.sampleRate, _sampleRate);
    expect(document.input.originalAudioRetained, isFalse);
    expect(document.input.fingerprint, hasLength(64));
  });
}

/// The same clip shape `full_pipeline_composition_test.dart` uses: a clean
/// monophonic passage plus chords and strums, so every ingest stage has real
/// evidence to work with instead of silence.
List<double> _clip() => <double>[
  ..._sine(220, seconds: 0.4),
  ...chordSignal(cMajorFreqs, seconds: 0.8),
  ...chordSignal(gMajorFreqs, seconds: 0.8),
  ...strumPattern(
    lowFirstPerStrum: <bool>[true, false, true, false],
    gapSeconds: 0.5,
  ),
];

List<double> _sine(double frequency, {required double seconds}) =>
    List<double>.generate(
      (seconds * _sampleRate).round(),
      (index) => 0.4 * math.sin(2 * math.pi * frequency * index / _sampleRate),
    );

/// Encodes mono float samples as 16-bit PCM RIFF/WAVE — the format a phone
/// recorder writes and the only one this build can import.
Uint8List _encodeWav(List<double> samples) {
  final dataLength = samples.length * 2;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + dataLength, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(28, _sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    data.setInt16(
      44 + index * 2,
      (samples[index].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}
