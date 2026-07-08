import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_dictionary.dart';

/// Build an L2-normalised 12-bin chroma from pitch-class → weight (0..11 = C..B).
Float64List chroma(Map<int, double> weights) {
  final v = Float64List(12);
  weights.forEach((pc, w) => v[pc % 12] = w);
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  if (n > 0) {
    for (var i = 0; i < 12; i++) {
      v[i] /= n;
    }
  }
  return v;
}

/// The label of the highest-scoring profile for an observed (bass, treble) pair.
String winner(ChordDictionary d, Float64List bass, Float64List treble) {
  final s = d.score(bass, treble);
  var bi = 0;
  for (var i = 1; i < s.length; i++) {
    if (s[i] > s[bi]) bi = i;
  }
  return d.profiles[bi].label;
}

const c = 0, e = 4, g = 7, b = 11, a = 9, d = 2, f = 5;

void main() {
  final dict = ChordDictionary();

  test('vocabulary: N.C. first, and the six qualities × 12 roots present', () {
    expect(dict.profiles.first.label, 'N.C.');
    expect(dict.profiles.first.isNoChord, isTrue);
    final labels = dict.profiles.map((p) => p.label).toSet();
    expect(labels, containsAll(['C', 'Am', 'G7', 'Cmaj7', 'Dm7', 'Asus4']));
    // Power-5 and sus2 are deliberately excluded (they steal weak-third triads).
    expect(labels.any((l) => l.endsWith('5') || l.contains('sus2')), isFalse);
    expect(dict.length, 1 + 6 * 12); // 73
  });

  test('a plain C major triad is C — NOT Cmaj7 (the round-26 superset fix)', () {
    // Observed: C E G in the treble, C in the bass. No B present.
    final treble = chroma({c: 1, e: 1, g: 1});
    final bass = chroma({c: 1});
    final s = dict.score(bass, treble);
    final byLabel = {
      for (var i = 0; i < dict.length; i++) dict.profiles[i].label: s[i]
    };
    expect(winner(dict, bass, treble), 'C');
    // The crux: with note-templates Cmaj7 ⊇ C would tie/beat C; with profiles
    // the absent B makes Cmaj7 score strictly LOWER than C.
    expect(byLabel['Cmaj7']!, lessThan(byLabel['C']!));
    expect(byLabel['C7']!, lessThan(byLabel['C']!));
  });

  test('an actual Cmaj7 (B present) is recognised as Cmaj7, beating C', () {
    final treble = chroma({c: 1, e: 1, g: 0.9, b: 0.9});
    final bass = chroma({c: 1});
    final s = dict.score(bass, treble);
    final byLabel = {
      for (var i = 0; i < dict.length; i++) dict.profiles[i].label: s[i]
    };
    expect(winner(dict, bass, treble), 'Cmaj7');
    expect(byLabel['Cmaj7']!, greaterThan(byLabel['C']!));
  });

  test('G7 (dominant 7, F present) beats plain G', () {
    // G B D F
    final treble = chroma({g: 1, b: 1, d: 0.9, f: 0.9});
    final bass = chroma({g: 1});
    final s = dict.score(bass, treble);
    final byLabel = {
      for (var i = 0; i < dict.length; i++) dict.profiles[i].label: s[i]
    };
    expect(winner(dict, bass, treble), 'G7');
    expect(byLabel['G7']!, greaterThan(byLabel['G']!));
  });

  test('major vs minor is decided by the third', () {
    expect(winner(dict, chroma({c: 1}), chroma({c: 1, e: 1, g: 1})), 'C');
    expect(winner(dict, chroma({c: 1}), chroma({c: 1, 3: 1, g: 1})), 'Cm');
  });

  test('sus4 (no third, a fourth instead) is Csus4, not C or Cm', () {
    // C F G
    expect(winner(dict, chroma({c: 1}), chroma({c: 1, f: 1, g: 1})), 'Csus4');
  });

  test('the bass note disambiguates: same treble, A bass → Am7 not C6-ish', () {
    // A C E G in the treble is shared by Am7 and C6; the bass A picks Am7.
    final treble = chroma({a: 1, c: 1, e: 0.9, g: 0.9});
    expect(winner(dict, chroma({a: 1}), treble), 'Am7');
  });

  test('a flat/diffuse frame resolves to N.C. via the no-chord floor', () {
    final flat = chroma({for (var i = 0; i < 12; i++) i: 1});
    expect(winner(dict, flat, flat), 'N.C.');
    // Zero input (silence) also can never beat the floor.
    expect(winner(dict, Float64List(12), Float64List(12)), 'N.C.');
  });

  test('no-chord floor is tunable and gates weak matches', () {
    final strict = ChordDictionary(noChordScore: 0.99);
    // A clean C triad no longer clears a near-1.0 floor.
    expect(winner(strict, chroma({c: 1}), chroma({c: 1, e: 1, g: 1})), 'N.C.');
  });
}
