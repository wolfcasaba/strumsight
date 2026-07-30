import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/data/adapters/legacy_chord_label.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';

void main() {
  group('legacyPracticeChordLabel', () {
    test('returns null for null input', () {
      expect(legacyPracticeChordLabel(null), isNull);
    });

    test('returns null for empty and whitespace-only labels', () {
      expect(legacyPracticeChordLabel(''), isNull);
      expect(legacyPracticeChordLabel('   '), isNull);
      expect(legacyPracticeChordLabel('\t\n'), isNull);
    });

    test('passes canonical labels through unchanged', () {
      expect(legacyPracticeChordLabel('C'), 'C');
      expect(legacyPracticeChordLabel('Cm'), 'Cm');
      expect(legacyPracticeChordLabel('F#'), 'F#');
      expect(legacyPracticeChordLabel('F#m'), 'F#m');
      expect(legacyPracticeChordLabel('G#'), 'G#');
      expect(legacyPracticeChordLabel('A#m'), 'A#m');
      expect(legacyPracticeChordLabel('B'), 'B');
      expect(legacyPracticeChordLabel('Bm'), 'Bm');
    });

    test('reduces 7th / minor variants to their parent majmin', () {
      expect(legacyPracticeChordLabel('Em7'), 'Em');
      expect(legacyPracticeChordLabel('Am7'), 'Am');
      expect(legacyPracticeChordLabel('Emin'), 'Em');
      expect(legacyPracticeChordLabel('Cmaj7'), 'C');
      expect(legacyPracticeChordLabel('C7'), 'C');
      expect(legacyPracticeChordLabel('Cadd9'), 'C');
      expect(legacyPracticeChordLabel('Asus4'), 'A');
      expect(legacyPracticeChordLabel('A7sus4'), 'A');
    });

    test('rewrites flat roots to their sharp enharmonic', () {
      expect(legacyPracticeChordLabel('Bb'), 'A#');
      expect(legacyPracticeChordLabel('Db'), 'C#');
      expect(legacyPracticeChordLabel('Cb'), 'B');
      expect(legacyPracticeChordLabel('E#'), 'F');
      expect(legacyPracticeChordLabel('B#'), 'C');
      expect(legacyPracticeChordLabel('Fb'), 'E');
    });

    test('drops the slash-bass of a slash chord', () {
      expect(legacyPracticeChordLabel('G/B'), 'G');
    });

    test('returns null for unparseable roots', () {
      expect(legacyPracticeChordLabel('H'), isNull);
      expect(legacyPracticeChordLabel('x'), isNull);
      expect(legacyPracticeChordLabel('Ω'), isNull);
      expect(legacyPracticeChordLabel('1'), isNull);
    });

    test('returns null for empty after slash-bass removal', () {
      expect(legacyPracticeChordLabel('/X'), isNull);
      expect(legacyPracticeChordLabel('   /X'), isNull);
    });

    test('trims surrounding whitespace before parsing', () {
      expect(legacyPracticeChordLabel('  Em  '), 'Em');
      expect(legacyPracticeChordLabel(' Em7'), 'Em');
    });

    test('every non-null output is canonical', () {
      const inputs = <String?>[
        '',
        '   ',
        null,
        'C',
        'Cm',
        'F#',
        'F#m',
        'Em7',
        'Am7',
        'Emin',
        'Cmaj7',
        'C7',
        'Cadd9',
        'Asus4',
        'A7sus4',
        'Bb',
        'Db',
        'Cb',
        'E#',
        'G/B',
        'F#m',
        'H',
        'x',
      ];
      for (final input in inputs) {
        final out = legacyPracticeChordLabel(input);
        if (out != null) {
          expect(
            isCanonicalPracticeChordLabel(out),
            isTrue,
            reason:
                'legacyPracticeChordLabel($input) -> $out must be canonical',
          );
        }
      }
    });
  });
}
