import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_dictionary.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';
import 'package:music_theory/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../../../support/synth.dart';

/// Real guitars are never perfectly tuned: strings drift, capos bend, whole
/// instruments sit 10–40 cents off concert pitch. Chunk 012 carries Chordino's
/// answer — per-frame TUNING ESTIMATION shifting the log-freq mapping — so a
/// uniformly detuned chord still lands on its note centres.
List<double> detuneCents(List<double> freqs, double cents) =>
    [for (final f in freqs) f * math.pow(2, cents / 1200)];

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
    final tonal =
        chroma != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

void main() {
  test('a C major detuned 35 cents FLAT still reads as C', () {
    final signal = chordSignal(detuneCents(cMajorFreqs, -35), seconds: 1.5);
    expect(decode(signal), 'C');
  });

  test('a C major detuned 35 cents SHARP still reads as C', () {
    final signal = chordSignal(detuneCents(cMajorFreqs, 35), seconds: 1.5);
    expect(decode(signal), 'C');
  });

  test('a G7 detuned 30 cents flat keeps its 7th (stays G7)', () {
    const g7 = [98.00, 123.47, 146.83, 174.61];
    final signal = chordSignal(detuneCents(g7, -30), seconds: 1.5);
    expect(decode(signal), 'G7');
  });

  test('an in-tune chord is unaffected (regression guard)', () {
    expect(decode(chordSignal(cMajorFreqs, seconds: 1.5)), 'C');
  });
}
