import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/ml_chord_decoder.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/analyze/providers/analyze_providers.dart';
import 'package:music_theory/features/live/engine/dsp/cqt_extractor.dart';
import 'package:music_theory/features/live/engine/ml/chord_crnn.dart';

import '../../support/synth.dart';

/// Ship-path step 4 (r197): the pure-Dart full-band CHORD model wired into the
/// Analyze batch path behind Lab mode, producing an ML chord timeline ALONGSIDE
/// the DSP one. These tests exercise the ML path end-to-end on deterministic
/// synth PCM, loading the REAL `assets/ml/chord_crnn.bin` asset.
void main() {
  const sr = 44100;
  final binFile = File('assets/ml/chord_crnn.bin');

  ChordCrnn loadNet() => ChordCrnn.parse(
        Uint8List.fromList(binFile.readAsBytesSync()).buffer.asByteData(),
      );

  test('the chord model asset loads with the expected 25-class majmin head',
      () {
    final net = loadNet();
    expect(net.nBins, CqtExtractor.nBins); // 144
    expect(net.nClasses, MlChordDecoder.majmin25Labels.length); // 25
  });

  test('a sustained single-chord clip yields that chord as the dominant ML '
      'label, over a timeline of ~the CQT frame length', () {
    final dec = MlChordDecoder(loadNet());
    const seconds = 3.0;
    final clip = chordSignal(cMajorFreqs, seconds: seconds); // a clean C major
    final duration = clip.length / sr;

    final timeline = dec.decode(clip, sr, duration);

    expect(timeline, isNotEmpty, reason: 'the ML path must produce chords');

    // Dominant label (by total duration) is the played chord.
    final byLabel = <String, double>{};
    for (final c in timeline) {
      byLabel[c.label] = (byLabel[c.label] ?? 0) + c.durationSec;
    }
    final dominant =
        byLabel.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    expect(dominant, 'C', reason: 'a C-major triad should decode to C');

    // The timeline spans roughly the whole clip and stamps times on the CQT
    // frame grid (hop = 2048/22050 s), NOT the DSP nnls hop.
    expect(timeline.first.startSec, 0.0);
    expect(timeline.last.endSec, closeTo(duration, 1e-9));
    final expectedFrames = CqtExtractor.nFrames(
        (clip.length * CqtExtractor.sr / sr).round());
    expect(expectedFrames, greaterThan(10),
        reason: 'a 3 s clip is many CQT frames');
  });

  test('agreementFraction reduces DSP richer labels to majmin before diffing',
      () {
    // DSP timeline uses a rich label; ML uses plain majmin. They should agree.
    final dsp = [
      const TimelineChord(label: 'Cmaj7', startSec: 0, endSec: 1.0),
      const TimelineChord(label: 'G7', startSec: 1.0, endSec: 2.0),
    ];
    final ml = [
      const TimelineChord(label: 'C', startSec: 0, endSec: 1.0),
      const TimelineChord(label: 'G', startSec: 1.0, endSec: 2.0),
    ];
    expect(MlChordDecoder.agreementFraction(dsp, ml, 2.0), 1.0);

    // A genuine disagreement (Dm vs D) drops the fraction.
    final ml2 = [
      const TimelineChord(label: 'Dm', startSec: 0, endSec: 2.0),
    ];
    expect(MlChordDecoder.agreementFraction(dsp, ml2, 2.0), lessThan(1.0));
  });

  test('majminReduce mirrors the labels.py reduction rules', () {
    expect(MlChordDecoder.majminReduce('Cmaj7'), 'C');
    expect(MlChordDecoder.majminReduce('G7'), 'G');
    expect(MlChordDecoder.majminReduce('Am7'), 'Am');
    expect(MlChordDecoder.majminReduce('Bdim'), 'Bm');
    expect(MlChordDecoder.majminReduce('Asus4'), 'A');
    expect(MlChordDecoder.majminReduce('F#m'), 'F#m');
    expect(MlChordDecoder.majminReduce('Db'), 'C#');
    expect(MlChordDecoder.majminReduce('N.C.'), 'N.C.');
    expect(MlChordDecoder.majminReduce(null), 'N.C.');
  });

  test('runClipAnalysis attaches ML diagnostics ONLY when Lab mode is on', () {
    final clip = chordSignal(cMajorFreqs, seconds: 2.0);
    final pcm = clip.toList();
    final chordWeights = Uint8List.fromList(binFile.readAsBytesSync());

    // Flag OFF → no diagnostics, default result shape unchanged.
    final off = runClipAnalysis((pcm, sr, null, false, chordWeights));
    expect(off.diagnostics, isNull);

    // Flag ON → diagnostics with an ML timeline + an agreement fraction.
    final on = runClipAnalysis((pcm, sr, null, true, chordWeights));
    expect(on.diagnostics, isNotNull);
    expect(on.diagnostics!.mlChords, isNotEmpty);
    expect(on.diagnostics!.agreement, inInclusiveRange(0.0, 1.0));
    // The DSP timeline is untouched by the ML path.
    expect(on.chords.map((c) => c.label).toList(),
        off.chords.map((c) => c.label).toList());
  });

  test('flag-off result serializes without the diag key (r197 compat)', () {
    final base = AnalyzeResult(
      durationSec: 2.0,
      bpm: 100,
      chords: const [TimelineChord(label: 'C', startSec: 0, endSec: 2)],
      strums: const [],
    );
    expect(base.toJson().containsKey('diag'), isFalse);
    // Round-trips cleanly with a null diagnostics.
    expect(AnalyzeResult.fromJson(base.toJson()).diagnostics, isNull);

    // With diagnostics, the key is present and round-trips.
    final withDiag = base.withDiagnostics(const MlChordDiagnostics(
      mlChords: [TimelineChord(label: 'C', startSec: 0, endSec: 2)],
      agreement: 0.75,
    ));
    expect(withDiag.toJson().containsKey('diag'), isTrue);
    final rt = AnalyzeResult.fromJson(withDiag.toJson());
    expect(rt.diagnostics, isNotNull);
    expect(rt.diagnostics!.agreement, 0.75);
    expect(rt.diagnostics!.mlChords.single.label, 'C');
  });
}
