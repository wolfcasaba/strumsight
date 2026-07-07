import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/nnls_chroma.dart';

import '../../../support/synth.dart';

int _argmax(List<double> xs) {
  var bi = 0;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] > xs[bi]) bi = i;
  }
  return bi;
}

void main() {
  test('silence yields null', () {
    final nc = NnlsChroma(sampleRate: 44100);
    expect(nc.process(Float64List(nc.window)), isNull);
  });

  test('a harmonic-rich single note maps to ONE pitch class (overtones '
      'suppressed)', () {
    final nc = NnlsChroma(sampleRate: 44100);
    // A3 = 220 Hz. Its 3rd harmonic (660 Hz) is E5 and 5th (1100 Hz) is C#6 —
    // in a raw chromagram those leak into E and C#. NNLS must explain them as
    // A's overtones.
    final note = harmonicNote(freq: 220, seconds: 0.5, amp: 0.3, harmonics: 6);
    final chroma = nc.process(Float64List.sublistView(note, 0, nc.window));
    expect(chroma, isNotNull);
    expect(_argmax(chroma!), 9); // A
    // The overtone pitch classes E (4) and C# (1) stay well below the peak.
    expect(chroma[4], lessThan(0.5 * chroma[9]));
    expect(chroma[1], lessThan(0.5 * chroma[9]));
  });

  test('C major triad → the three strongest pitch classes are C, E, G', () {
    final nc = NnlsChroma(sampleRate: 44100);
    final chord = chordSignal(cMajorFreqs, seconds: 0.5, amp: 0.2);
    final chroma = nc.process(Float64List.sublistView(chord, 0, nc.window));
    expect(chroma, isNotNull);
    final ranked = List.generate(12, (i) => i)
      ..sort((a, b) => chroma![b].compareTo(chroma[a]));
    expect(ranked.take(3).toSet(), {0, 4, 7}); // C E G
  });

  test('A minor triad → the three strongest pitch classes are A, C, E', () {
    final nc = NnlsChroma(sampleRate: 44100);
    final chord = chordSignal(aMinorFreqs, seconds: 0.5, amp: 0.2);
    final chroma = nc.process(Float64List.sublistView(chord, 0, nc.window));
    expect(chroma, isNotNull);
    final ranked = List.generate(12, (i) => i)
      ..sort((a, b) => chroma![b].compareTo(chroma[a]));
    expect(ranked.take(3).toSet(), {9, 0, 4}); // A C E
  });
}
