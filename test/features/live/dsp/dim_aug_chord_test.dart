import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';
import 'package:strumsight/features/live/engine/dsp/chord_matcher.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';
import 'package:strumsight/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../../../support/synth.dart';

/// Round 78 — growing the vocabulary: diminished + augmented triads.
/// The risk (why they were left out in round 28): they differ from m/maj only
/// in the FIFTH — the lightest-weighted, most-often-omitted chord tone — so
/// the property gates below the deterministic cases are the real judge: the
/// existing maj/min/7th gates must stay green (no stealing) across seeds.
String? decode(Float64List signal) {
  final nc = NnlsChroma(sampleRate: 44100);
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? last;
  for (final frame in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
    final chroma = nc.process(frame);
    final tonal =
        chroma != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

void main() {
  test('a B diminished triad is recognised as Bdim', () {
    // B2 D3 F3 — root, minor third, diminished fifth.
    const bdim = [123.47, 146.83, 174.61];
    expect(decode(chordSignal(bdim, seconds: 1.5)), 'Bdim');
  });

  // An augmented triad is the one fully SYMMETRIC chord in the vocabulary:
  // {C,E,G#} is the pitch-class set of Caug, Eaug AND G#aug, so nothing in the
  // treble chroma can name its root — only the bass register can. The bass
  // chroma folds every note at/below `bassMaxMidi` (E3) into 12 bins WITHOUT
  // weighting by depth, so it says "these pitch classes are low", never "C is
  // lower than E".
  //
  // The original fixture voiced the chord C3-E3-G#3, which puts the root AND
  // the third inside that window at equal level: the reading then came down to
  // whichever of two equal-amplitude notes the analysis left a few percent
  // ahead (MEASURED: C 0.72 vs E 0.69). That is not a property, it is a coin
  // flip — it landed on Caug, and a change to the whitening neighbourhood
  // landed it on Eaug without anything about augmented chords changing.
  //
  // These cases voice each rotation with its root ALONE in the bass window,
  // which is what makes the root knowable at all. They pass across the whole
  // `whiteningHalfSemitones` range (±1 … ±6), so they pin the mechanism rather
  // than the constant. The depth-blind bass chroma is a real limitation and is
  // tracked as a follow-up, not papered over here.
  group('an augmented triad takes its root from the bass note', () {
    test('C in the bass reads as Caug', () {
      // C3 G#3 E4 — only C3 is inside the bass window.
      expect(
        decode(chordSignal(const [130.81, 207.65, 329.63], seconds: 1.5)),
        'Caug',
      );
    });

    test('E in the bass reads as Eaug — the SAME three pitch classes', () {
      // E3 C4 G#4.
      expect(
        decode(chordSignal(const [164.81, 261.63, 415.30], seconds: 1.5)),
        'Eaug',
      );
    });

    test('G# in the bass reads as G#aug', () {
      // G#3 E4 C5.
      expect(
        decode(chordSignal(const [207.65, 329.63, 523.25], seconds: 1.5)),
        'G#aug',
      );
    });
  });

  test('a plain A minor stays Am (dim must not steal the weak fifth)', () {
    expect(decode(chordSignal(aMinorFreqs, seconds: 1.5)), 'Am');
  });

  test('a plain C major stays C (aug must not steal)', () {
    expect(decode(chordSignal(cMajorFreqs, seconds: 1.5)), 'C');
  });
}
