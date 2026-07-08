import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_dictionary.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';
import 'package:music_theory/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../../../support/synth.dart';

/// Drive the full chunk-012 chain (NNLS bass/treble → dictionary → Viterbi)
/// over a sustained signal and return the last stable label.
String? decode(Float64List signal) {
  final nc = NnlsChroma(sampleRate: 44100);
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? last;
  const win = DspConfig.nnlsWindow;
  const hop = DspConfig.nnlsHop;
  for (final frame in frames(signal, win, hop)) {
    final chroma = nc.process(frame);
    final tonal = chroma != null &&
        nc.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

// A dominant-7 voicing whose added tone does NOT coincide with a low harmonic
// of another chord tone — so NNLS keeps it (the fair case per chunk 012's
// honest-limits note). G7 = G2 B2 D3 F3.
const g7Freqs = [98.00, 123.47, 146.83, 174.61];
// Plain triads must still read as plain triads (no false 7ths).
const cMajFreqs = cMajorFreqs;

void main() {
  test('plain C major triad still reads as C (no phantom extension)', () {
    expect(decode(chordSignal(cMajFreqs, seconds: 1.5)), 'C');
  });

  test('a G7 voicing with the 7th present is recognised as G7 (round-26 fix)',
      () {
    // The whole point of the dictionary+Viterbi port: the 7th, when it truly
    // sounds and survives NNLS, is now heard as a G7 rather than collapsing to
    // a plain G triad.
    expect(decode(chordSignal(g7Freqs, seconds: 1.5)), 'G7');
  });

  test('silence decodes to no chord', () {
    expect(decode(Float64List(44100)), isNull);
  });
}
