import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_dictionary.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';
import 'package:music_theory/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../../../support/synth.dart';

/// Spectral whitening (chunk 012, Chordino stage): flatten the spectral
/// envelope before NNLS so timbre/EQ — a phone mic's steep bass roll-off, a
/// guitar body's resonance — can't outvote the actual notes. The measured
/// round-70 failure: a "thin mic" low-shelf cut (fundamentals below 300 Hz
/// attenuated ×0.15) made a C major read as **Em** — the fundamentals
/// vanished under their own harmonics.
Float64List thinMicChord(List<double> freqs,
        {double cutHz = 300, double atten = 0.15}) =>
    mixNotes([
      for (final f in freqs)
        colouredNote(
          freq: f,
          seconds: 1.5,
          gain: (h, hf) => (0.15 / h) * (hf < cutHz ? atten : 1.0),
        ),
    ]);

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
  test('thin-mic C major (bass rolled off below 300 Hz) still reads as C', () {
    expect(decode(thinMicChord(cMajorFreqs)), 'C');
  });

  test('thin-mic A minor still reads as Am', () {
    expect(decode(thinMicChord(aMinorFreqs)), 'Am');
  });

  test('a body resonance (500 Hz bump) does not change the reading', () {
    final signal = mixNotes([
      for (final f in cMajorFreqs)
        colouredNote(
          freq: f,
          seconds: 1.5,
          gain: (h, hf) =>
              (0.15 / h) * (1 + 4 * math.exp(-math.pow((hf - 500) / 120, 2))),
        ),
    ]);
    expect(decode(signal), 'C');
  });

  test('neutral timbre is unaffected (regression guard)', () {
    expect(decode(chordSignal(cMajorFreqs, seconds: 1.5)), 'C');
  });
}
