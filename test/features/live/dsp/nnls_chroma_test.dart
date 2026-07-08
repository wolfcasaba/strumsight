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

  test('bass+treble split (chunk 012): treble carries the harmony, bass the '
      'root, and both are zero on silence', () {
    final nc = NnlsChroma(sampleRate: 44100);
    // Silence leaves both split chromas at zero.
    nc.process(Float64List(nc.window));
    expect(nc.lastBassChroma.every((v) => v == 0), isTrue);
    expect(nc.lastTrebleChroma.every((v) => v == 0), isTrue);

    // C major (C3 E3 G3): the treble register spans all three chord tones.
    final chord = chordSignal(cMajorFreqs, seconds: 0.5, amp: 0.2);
    nc.process(Float64List.sublistView(chord, 0, nc.window));
    final trebleRank = List.generate(12, (i) => i)
      ..sort((a, b) => nc.lastTrebleChroma[b].compareTo(nc.lastTrebleChroma[a]));
    expect(trebleRank.take(3).toSet(), {0, 4, 7}); // C E G
    // The bass register carries the root C (lowest note = C3) prominently.
    final bassRank = List.generate(12, (i) => i)
      ..sort((a, b) => nc.lastBassChroma[b].compareTo(nc.lastBassChroma[a]));
    expect(bassRank.take(2), contains(0)); // C among the two loudest bass PCs
  });
}
