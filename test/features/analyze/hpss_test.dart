import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/hpss.dart';

/// A T×F magnitude spectrogram = small broadband base + a HORIZONTAL ridge
/// (one bin [f0] strong across ALL frames = a held harmonic) + a VERTICAL
/// ridge (one frame [t0] strong across ALL bins = a broadband drum hit).
List<Float64List> _synthetic({
  required int t,
  required int f,
  required int f0,
  required int t0,
  double base = 0.05,
  double harmonic = 1.0,
  double percussive = 1.0,
}) {
  final s = List<Float64List>.generate(
      t, (_) => Float64List(f)..fillRange(0, f, base));
  for (var i = 0; i < t; i++) {
    s[i][f0] += harmonic; // horizontal harmonic ridge
  }
  for (var j = 0; j < f; j++) {
    s[t0][j] += percussive; // vertical percussive ridge (drum hit)
  }
  return s;
}

void main() {
  group('Hpss.harmonicEnhance', () {
    const t = 40, f = 40, f0 = 12, t0 = 25;
    const base = 0.05, harmonic = 1.0, percussive = 1.0;

    test('preserves the harmonic ridge, suppresses the percussive ridge', () {
      final s = _synthetic(
        t: t,
        f: f,
        f0: f0,
        t0: t0,
        base: base,
        harmonic: harmonic,
        percussive: percussive,
      );
      final out = Hpss.harmonicEnhance(s);

      // --- Harmonic ridge (bin f0), away from the crossing frame t0 --------
      var harmIn = 0.0, harmOut = 0.0;
      for (var i = 0; i < t; i++) {
        if (i == t0) continue; // skip the crossing cell
        harmIn += s[i][f0];
        harmOut += out[i][f0];
      }
      // The held note is horizontally smooth → mask ≈ 1 → energy preserved.
      expect(harmOut / harmIn, greaterThan(0.9),
          reason: 'harmonic ridge energy must be largely preserved');

      // A single interior harmonic cell keeps essentially all its value.
      expect(out[5][f0] / s[5][f0], greaterThan(0.9));

      // --- Percussive ridge (frame t0), away from the crossing bin f0 ------
      var percIn = 0.0, percOut = 0.0;
      for (var j = 0; j < f; j++) {
        if (j == f0) continue; // skip the crossing cell
        percIn += s[t0][j];
        percOut += out[t0][j];
      }
      // The drum hit is vertically smooth → mask ≈ 0 → energy killed.
      expect(percOut / percIn, lessThan(0.05),
          reason: 'percussive ridge energy must be strongly attenuated');

      // A single interior percussive cell is knocked down to a tiny fraction.
      expect(out[t0][5] / s[t0][5], lessThan(0.05));
    });

    test('does not mutate the input and preserves dimensions', () {
      final s = _synthetic(t: t, f: f, f0: f0, t0: t0);
      // Snapshot the input.
      final before = [for (final row in s) Float64List.fromList(row)];

      final out = Hpss.harmonicEnhance(s);

      expect(out.length, s.length);
      for (var i = 0; i < t; i++) {
        expect(out[i].length, f);
        for (var j = 0; j < f; j++) {
          expect(s[i][j], before[i][j], reason: 'input must be untouched');
        }
      }
      // The result is a distinct object, not the same backing list.
      expect(identical(out, s), isFalse);
      expect(identical(out[0], s[0]), isFalse);
    });

    test('handles empty, single-frame and single-bin input without crashing',
        () {
      expect(Hpss.harmonicEnhance(const []), isEmpty);

      // Single frame: nothing to separate along time → a faithful copy.
      final oneFrame = [Float64List.fromList([0.1, 0.9, 0.3, 0.7])];
      final r1 = Hpss.harmonicEnhance(oneFrame);
      expect(r1.length, 1);
      expect(r1[0], orderedEquals(oneFrame[0]));

      // Single bin per frame: nothing to separate along frequency → copy.
      final oneBin = [
        Float64List.fromList([0.2]),
        Float64List.fromList([0.8]),
        Float64List.fromList([0.5]),
      ];
      final r2 = Hpss.harmonicEnhance(oneBin);
      expect(r2.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(r2[i][0], oneBin[i][0]);
      }

      // Zero-width frames.
      final zeroWide = [Float64List(0), Float64List(0)];
      final r3 = Hpss.harmonicEnhance(zeroWide);
      expect(r3.length, 2);
      expect(r3[0], isEmpty);
    });
  });

  group('Hpss.harmonicMask / hardHarmonicMask', () {
    const t = 40, f = 40, f0 = 12, t0 = 25;

    test('soft mask is ~1 on the harmonic ridge and ~0 on the drum hit', () {
      final s = _synthetic(t: t, f: f, f0: f0, t0: t0);
      final mask = Hpss.harmonicMask(s);

      expect(mask.length, t);
      expect(mask[0].length, f);
      expect(mask[5][f0], greaterThan(0.9)); // harmonic cell
      expect(mask[t0][5], lessThan(0.05)); // percussive cell
    });

    test('hard mask is a clean 1/0 harmonic decision', () {
      final s = _synthetic(t: t, f: f, f0: f0, t0: t0);
      final mask = Hpss.hardHarmonicMask(s);

      expect(mask[5][f0], 1.0); // H > P on the harmonic ridge
      expect(mask[t0][5], 0.0); // H < P on the drum hit
      // Only 0/1 values ever appear.
      for (final row in mask) {
        for (final v in row) {
          expect(v == 0.0 || v == 1.0, isTrue);
        }
      }
    });
  });
}
