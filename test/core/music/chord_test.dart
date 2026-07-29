import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';

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
      // Extended-chord labels from the chunk-012 engine transpose too (capo).
      expect(Chord.transposeLabel('G7', -2), 'F7');
      expect(Chord.transposeLabel('Cmaj7', 2), 'Dmaj7');
      expect(Chord.transposeLabel('Dm7', -2), 'Cm7');
      expect(Chord.transposeLabel('Asus4', 3), 'Csus4');
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

    test('slash chords transpose the bass note too (round 129)', () {
      // "G/B" is a real vocabulary chord (library + Song Builder chip); a
      // capo user sharing a song with it must see BOTH parts shifted, not a
      // stale bass. Bug was: only the root moved → "A/B".
      expect(Chord.transposeLabel('G/B', 2), 'A/C#');
      expect(Chord.transposeLabel('D/F#', -2), 'C/E');
      expect(Chord.transposeLabel('C/E', 0), 'C/E'); // capo 0 identity
      // An unparseable bass leaves that part alone, still shifts the root.
      expect(Chord.transposeLabel('G/x', 2), 'A/x');
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

  group('Chord — value identity (the canonical domain contract)', () {
    test('two chords with the same label are equal and hash alike', () {
      expect(const Chord('Am'), const Chord('Am'));
      expect(const Chord('Am').hashCode, const Chord('Am').hashCode);
    });

    test('different labels are not equal', () {
      expect(const Chord('Am') == const Chord('A'), isFalse);
      expect(const Chord('C') == const Chord('Cm'), isFalse);
    });

    test('a Chord is never equal to its bare label', () {
      // Guards the `==` override against an accidental dynamic comparison:
      // Set/Map lookups across features rely on this staying type-strict.
      const Object bareLabel = 'C';
      expect(const Chord('C') == bareLabel, isFalse);
    });

    test('works as a Set/Map key across features', () {
      // Built from labels (not const literals) so the de-duplication is done
      // by `==`/hashCode at runtime, which is what consumers rely on.
      final seen = ['C', 'G', 'C'].map(Chord.new).toSet();
      expect(seen, hasLength(2));
      expect(seen.contains(const Chord('G')), isTrue);
    });

    test('toString is the label — timeline summaries depend on it', () {
      expect(const Chord('F#m').toString(), 'F#m');
    });
  });
}
