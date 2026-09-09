// E14-R27 (ADR 0539): the REAL two-engine harness.
//
// Runs the shipped NNLS-chroma + Viterbi decoder (`ClipAnalyzer`, the Live
// and Analyze chord path) and the shipped chord CRNN
// (`assets/ml/chord_crnn.bin` through `MlChordDecoder`) over the SAME
// synthetic fixtures, scores both with the merged `computeRecognitionMetrics`
// contract, and prints the comparison table.
//
// It asserts INVARIANTS ONLY:
//   * both engines ran on byte-identical input (same sha256);
//   * both engines were scored on every fixture;
//   * the table renders deterministically and declares NEEDS-MEASUREMENT.
//
// It deliberately asserts NOTHING about which engine is better. The fixtures
// are SYNTHETIC (`generateSyntheticChordCorpus`), and SDD Ch14 §12/2 forbids
// treating synthetic audio as ground truth; the engine choice needs the real
// corpus of §7.1 (`docs/eval/chord-corpus-plan.md`). A cell here that
// preferred one engine would be exactly the fabricated evidence Ch14 §9
// forbids.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/analyze/engine/ml_chord_decoder.dart';
import 'package:strumsight/features/live/domain/evaluation/chord_corpus_manifest.dart';
import 'package:strumsight/features/live/domain/evaluation/chord_engine_comparison.dart';
import 'package:strumsight/features/live/engine/ml/chord_crnn.dart';

import 'support/synthetic_chord_corpus.dart';

const _sampleRate = 44100;
const _chordSeconds = 1.5;

void main() {
  test('NNLS+Viterbi and the chord CRNN are scored on the same fixtures, '
      'and the verdict stays NEEDS-MEASUREMENT', () {
    final fixtures = <ChordComparisonFixture>[];
    final pcmByFixture = <String, Float64List>{};
    for (final progression in const <List<String>>[
      <String>['C', 'Am'],
      <String>['G', 'Em'],
    ]) {
      final built = _buildFixture(progression);
      fixtures.add(built.fixture);
      pcmByFixture[built.fixture.fixtureId] = built.pcm;
    }

    final crnn = ChordCrnn.parse(_readChordWeights());
    final mlDecoder = MlChordDecoder(crnn);
    const dspAnalyzer = ClipAnalyzer();

    final runs = <ChordEngineRun>[];
    for (final fixture in fixtures) {
      final pcm = pcmByFixture[fixture.fixtureId]!;
      final duration = pcm.length / _sampleRate;

      final dspChords = dspAnalyzer.analyze(pcm, _sampleRate).chords;
      runs.add(
        ChordEngineRun(
          engineId: 'nnls-viterbi',
          fixtureId: fixture.fixtureId,
          inputSha256: fixture.inputSha256,
          segments: <ChordTimelineSegment>[
            for (final chord in dspChords)
              ChordTimelineSegment(
                label: chord.label,
                startSec: chord.startSec,
                endSec: chord.endSec,
              ),
          ],
        ),
      );

      final mlChords = mlDecoder.decode(pcm, _sampleRate, duration);
      runs.add(
        ChordEngineRun(
          engineId: 'chord-crnn',
          fixtureId: fixture.fixtureId,
          inputSha256: fixture.inputSha256,
          segments: <ChordTimelineSegment>[
            for (final chord in mlChords)
              ChordTimelineSegment(
                label: chord.label,
                startSec: chord.startSec,
                endSec: chord.endSec,
              ),
          ],
        ),
      );
    }

    final report = compareChordEngines(fixtures: fixtures, runs: runs);

    expect(report.engineIds, <String>['chord-crnn', 'nnls-viterbi']);
    expect(report.fixtureIds, hasLength(2));
    expect(report.decision, 'NEEDS-MEASUREMENT');
    for (final engineId in report.engineIds) {
      expect(
        report.metricsByEngine[engineId],
        isNotNull,
        reason: '$engineId must be scored',
      );
    }

    final markdown = report.renderMarkdown();
    expect(report.renderMarkdown(), markdown);
    // Visible in the test log so drift stays observable between rounds; no
    // cell asserts a value, because none of these numbers is evidence.
    // ignore: avoid_print
    print(markdown);
  });
}

final class _BuiltFixture {
  const _BuiltFixture(this.fixture, this.pcm);

  final ChordComparisonFixture fixture;
  final Float64List pcm;
}

/// Renders one chord per entry of [progression], back to back, and returns
/// the fixture (ground truth + input hash) alongside the PCM.
_BuiltFixture _buildFixture(List<String> progression) {
  final corpus = generateSyntheticChordCorpus(
    seed: 42,
    sampleRate: _sampleRate,
    secondsPerItem: _chordSeconds,
    labels: progression,
    voicings: const <ChordVoicing>[ChordVoicing.open],
    tempos: const <int>[90],
  );
  final perChord = corpus.items.length ~/ progression.length;
  final samplesPerChord = (_chordSeconds * _sampleRate).round();
  final pcm = Float64List(samplesPerChord * progression.length);
  final expected = <ChordTimelineSegment>[];
  for (var i = 0; i < progression.length; i++) {
    final source = corpus.items[i * perChord].pcm;
    final offset = i * samplesPerChord;
    for (var n = 0; n < samplesPerChord && n < source.length; n++) {
      pcm[offset + n] = source[n];
    }
    expected.add(
      ChordTimelineSegment(
        label: progression[i],
        startSec: i * _chordSeconds,
        endSec: (i + 1) * _chordSeconds,
      ),
    );
  }
  return _BuiltFixture(
    ChordComparisonFixture(
      fixtureId: progression.join('-'),
      inputSha256: _sha256OfPcm(pcm),
      durationSec: progression.length * _chordSeconds,
      expected: expected,
    ),
    pcm,
  );
}

String _sha256OfPcm(Float64List pcm) =>
    crypto.sha256.convert(pcm.buffer.asUint8List()).toString();

ByteData _readChordWeights() {
  final bytes = File('assets/ml/chord_crnn.bin').readAsBytesSync();
  return Uint8List.fromList(bytes).buffer.asByteData();
}
