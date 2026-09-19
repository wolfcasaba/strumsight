// The bass chroma weights by DEPTH (ADR 0541).
//
// `NnlsChroma` folds note activations into a bass chroma (the root) and a
// treble chroma (the harmony). Those folds used a HARD cut — every note at or
// below `bassMaxMidi` counted equally — so the bass chroma could say "these
// pitch classes are low" but never "C is lower than E". For chords whose root
// and third both sit in the low register that left the root undecided, and it
// was the reason a narrower whitening span eroded root identification: once
// peak levels are equalised there was nothing else naming the root.
//
// The reference implementation (Mauch & Dixon, NNLS-Chroma / Chordino, ISMIR
// 2010) does not cut; it multiplies the semitone spectrum by smooth
// raised-cosine register windows before folding to 12 bins — its `basswindow`
// is a hump over the 37 semitones from A0 that peaks around E♭2 and reaches
// zero at A3, so E2 counts about 4.5× what E3 counts. `referenceRegisterWindows`
// reproduces that shape (clean-room: the reference is GPL, its tables are NOT
// copied; the Hann form matches the published `treblewindow` to 5e-7 and
// `basswindow` to 2e-2).
//
// These cells pin the property the weighting buys, and they are written so the
// hard-cut behaviour is stated alongside it rather than merely asserted away.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';
import 'package:strumsight/features/live/engine/dsp/chord_matcher.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';
import 'package:strumsight/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../../../support/synth.dart';

const _pitchClasses = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

double _midiToFreq(int midi) => 440 * _pow2((midi - 69) / 12.0);

/// 2^x without a `dart:math` import in a file that needs nothing else from it.
double _pow2(double x) {
  const ln2 = 0.6931471805599453;
  final y = x * ln2;
  var term = 1.0;
  var sum = 1.0;
  for (var k = 1; k < 32; k++) {
    term *= y / k;
    sum += term;
  }
  return sum;
}

String? _decode(
  Float64List signal, {
  required bool depthWeighted,
  double halfSemitones = 3.0,
  bool? hammingKernel,
}) {
  final chroma = NnlsChroma(
    sampleRate: 44100,
    whiteningHalfSemitones: halfSemitones,
    referenceRegisterWindows: depthWeighted,
    whiteningHammingKernel:
        hammingKernel ?? NnlsChroma.defaultWhiteningHammingKernel,
  );
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? last;
  for (final frame in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
    final c = chroma.process(frame);
    final tonal =
        c != null && chroma.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(chroma.lastBassChroma, chroma.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

/// A dominant 7th voiced low, the shape `dsp_property_test.dart` draws from.
Float64List _lowDom7(int rootMidi) => chordSignal([
  _midiToFreq(rootMidi),
  _midiToFreq(rootMidi + 4 + (rootMidi < 45 ? 12 : 0)),
  _midiToFreq(rootMidi + 7),
  _midiToFreq(rootMidi + 10),
], seconds: 1.2);

void main() {
  test('the bass window weights by depth: lower notes count for more', () {
    final chroma = NnlsChroma(sampleRate: 44100);
    // E2 is the guitar's lowest note and E3 an octave up; both used to count
    // the same, because both were simply "at or below bassMaxMidi".
    final e2 = chroma.debugBassWeightForMidi(40);
    final e3 = chroma.debugBassWeightForMidi(52);
    expect(e2, greaterThan(e3 * 3), reason: 'E2 must dominate E3 in the bass');
    // And the window closes: nothing up in the harmony register leaks into the
    // bass chroma at all.
    expect(chroma.debugBassWeightForMidi(60), 0); // C4
    expect(chroma.debugBassWeightForMidi(72), 0); // C5
    // Monotone down the guitar's root range — no ordering surprises.
    for (var midi = 40; midi < 57; midi++) {
      expect(
        chroma.debugBassWeightForMidi(midi),
        greaterThan(chroma.debugBassWeightForMidi(midi + 1)),
        reason: 'bass weight must fall with pitch at MIDI $midi',
      );
    }
  });

  test('a chord whose root and third are BOTH low is named from the root', () {
    // C3 E3 G#3 at one level. {C,E,G#} is equally Caug, Eaug and G#aug, so only
    // the bass can name the root — and with a depth-blind fold it could not:
    // MEASURED bass C 0.68 vs E 0.73, returning `Eaug`. Depth weighting gives
    // C 0.87 vs E 0.47.
    const closeVoicing = [130.81, 164.81, 207.65];
    expect(
      _decode(chordSignal(closeVoicing, seconds: 1.5), depthWeighted: false),
      isNot('Caug'),
      reason: 'the hard cut must still show the ambiguity this fixes',
    );
    expect(
      _decode(chordSignal(closeVoicing, seconds: 1.5), depthWeighted: true),
      'Caug',
    );
  });

  test('depth weighting holds the root when the whitening span is narrowed', () {
    // The span is bounded from below because equalising peak levels erodes the
    // root's loudness, which was the bass chroma's only cue. With the root
    // named by REGISTER instead, that bound lifts: low dominant 7ths survive a
    // span well below the shipped ±3, where the depth-blind fold loses them to
    // a diminished triad on their own third (the chord minus its root).
    //
    // The CONTROL below is pinned to the flat box kernel, and that is the whole
    // point of this comment. It used to run on the shipped kernel and assert
    // `blindLosses > 0` — "the hard cut must still show the erosion this
    // lifts". E18-R12 shipped the Hamming kernel and the assertion went red,
    // with `blindLosses == 0`: not because depth weighting stopped working, but
    // because the Hamming kernel independently removes the erosion the control
    // was there to exhibit. MEASURED over roots 40-47 at several spans:
    //
    //   box      ±2   blind 2/8 lost, depth-weighted 0/8
    //   box      ±1.5 … ±0.5   blind 0/8   (so ±2 is a specific break, not a trend)
    //   hamming  ±2 … ±0.5     blind 0/8, depth-weighted 0/8
    //
    // Rewriting the control to pass on the new kernel would have deleted a real
    // guard to make a change green. Pinning it to `hammingKernel: false` keeps
    // its teeth on the configuration where the phenomenon exists — the box is
    // still shipped code, every sweep compares against it — while the cell below
    // records what the new kernel does to it.
    var blindLosses = 0;
    for (var rootMidi = 40; rootMidi < 48; rootMidi++) {
      final root = _pitchClasses[rootMidi % 12];
      final signal = _lowDom7(rootMidi);
      if (_decode(
            signal,
            depthWeighted: false,
            halfSemitones: 2.0,
            hammingKernel: false,
          ) !=
          '${root}7') {
        blindLosses++;
      }
      expect(
        _decode(
          signal,
          depthWeighted: true,
          halfSemitones: 2.0,
          hammingKernel: false,
        ),
        '${root}7',
        reason: 'depth-weighted $root 7 at a ±2 semitone whitening span',
      );
      // And on the SHIPPED kernel, which is what actually has to hold.
      expect(
        _decode(signal, depthWeighted: true, halfSemitones: 2.0),
        '${root}7',
        reason: 'depth-weighted $root 7 at ±2, shipped kernel',
      );
    }
    expect(
      blindLosses,
      greaterThan(0),
      reason:
          'with the BOX kernel the hard cut must still show the erosion this '
          'lifts — if this goes quiet the control has lost its meaning and the '
          'measurement above needs redoing, not the assertion relaxing',
    );
  });

  test('the Hamming kernel removes the narrow-span root erosion as well', () {
    // The finding that made the control above need pinning, stated as its own
    // cell rather than left implicit in a comment. ADR 0540 bounded the
    // whitening span from below on the strength of that erosion; with the
    // shipped kernel the depth-BLIND fold no longer loses a single low dominant
    // 7th at ±2, so that particular argument for the bound no longer applies.
    //
    // This does NOT say the depth weighting is redundant: it still carries the
    // root in the both-low voicing cell above, and that control still shows
    // contrast on the shipped kernel.
    var blindLosses = 0;
    for (var rootMidi = 40; rootMidi < 48; rootMidi++) {
      final root = _pitchClasses[rootMidi % 12];
      if (_decode(
            _lowDom7(rootMidi),
            depthWeighted: false,
            halfSemitones: 2.0,
            hammingKernel: true,
          ) !=
          '${root}7') {
        blindLosses++;
      }
    }
    expect(
      blindLosses,
      0,
      reason:
          'MEASURED in E18-R12: the Hamming kernel alone holds all eight low '
          'dominant 7ths at ±2 where the box kernel lost two',
    );
  });

  test('the shipped span keeps low dominant 7ths too (no trade made)', () {
    for (var rootMidi = 40; rootMidi < 48; rootMidi++) {
      final root = _pitchClasses[rootMidi % 12];
      expect(_decode(_lowDom7(rootMidi), depthWeighted: true), '${root}7');
    }
  });

  test('ordinary triads are unmoved by the weighting', () {
    for (final (freqs, label) in <(List<double>, String)>[
      (cMajorFreqs, 'C'),
      (aMinorFreqs, 'Am'),
      (fMajorFreqs, 'F'),
      (gMajorFreqs, 'G'),
    ]) {
      expect(
        _decode(chordSignal(freqs, seconds: 1.5), depthWeighted: true),
        label,
      );
    }
  });
}
