import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_dictionary.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';
import 'package:music_theory/features/live/engine/dsp/viterbi_chord_decoder.dart';

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
  for (final frame
      in frames(signal, DspConfig.nnlsWindow, DspConfig.nnlsHop)) {
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

  test('a C augmented triad is recognised as Caug', () {
    // C3 E3 G#3 — root, major third, augmented fifth.
    const caug = [130.81, 164.81, 207.65];
    expect(decode(chordSignal(caug, seconds: 1.5)), 'Caug');
  });

  test('a plain A minor stays Am (dim must not steal the weak fifth)', () {
    expect(decode(chordSignal(aMinorFreqs, seconds: 1.5)), 'Am');
  });

  test('a plain C major stays C (aug must not steal)', () {
    expect(decode(chordSignal(cMajorFreqs, seconds: 1.5)), 'C');
  });
}
