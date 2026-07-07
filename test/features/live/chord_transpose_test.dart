import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/chord.dart';

void main() {
  group('Chord.transposeLabel — capo transposition', () {
    test('capo 0 is a no-op', () {
      expect(Chord.transposeLabel('C', 0), 'C');
      expect(Chord.transposeLabel('F#m', 0), 'F#m');
    });

    test('shifts a major root down (capo N ⇒ −N)', () {
      // Capo 2, fretting a C shape sounds D; the detector hears D and we show C.
      expect(Chord.transposeLabel('D', -2), 'C');
      expect(Chord.transposeLabel('E', -2), 'D');
      expect(Chord.transposeLabel('G', -2), 'F');
    });

    test('keeps the quality suffix', () {
      expect(Chord.transposeLabel('Am', -2), 'Gm');
      expect(Chord.transposeLabel('F#m', -2), 'Em');
    });

    test('wraps around the octave', () {
      expect(Chord.transposeLabel('C', -1), 'B');
      expect(Chord.transposeLabel('C', -2), 'A#');
      expect(Chord.transposeLabel('D', -3), 'B');
    });

    test('a full octave (±12) is identity', () {
      expect(Chord.transposeLabel('C', -12), 'C');
      expect(Chord.transposeLabel('Am', 12), 'Am');
    });

    test('accepts sharp roots and normalises output to sharps', () {
      expect(Chord.transposeLabel('A#', -2), 'G#');
      expect(Chord.transposeLabel('F#', 1), 'G');
    });

    test('tolerates flat spelling on input', () {
      expect(Chord.transposeLabel('Bb', -2), 'G#'); // Bb = A#, −2 = G#
    });

    test('unparseable / empty labels pass through untouched', () {
      expect(Chord.transposeLabel('—', -2), '—');
      expect(Chord.transposeLabel('', -2), '');
      expect(Chord.transposeLabel('N.C.', -2), 'N.C.');
    });

    test('Chord.transposed wraps the same logic', () {
      expect(const Chord('D').transposed(-2), const Chord('C'));
      expect(const Chord('Em').transposed(2), const Chord('F#m'));
    });
  });

  group('Chord.transposeSummary — saved-session titles', () {
    test('transposes every chord token in a summary', () {
      expect(Chord.transposeSummary('D · A · Bm · G', -2), 'C · G · Am · F');
    });

    test('capo 0 is a no-op', () {
      expect(Chord.transposeSummary('D · A · Bm', 0), 'D · A · Bm');
    });

    test('a non-chord fallback title passes through', () {
      expect(Chord.transposeSummary('New recording', -2), 'New recording');
    });

    test('empty summary stays empty', () {
      expect(Chord.transposeSummary('', -3), '');
    });
  });
}
