import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/engine/harmony/chord_label_normalizer.dart';

void main() {
  const normalizer = ChordLabelNormalizer();

  group('ChordLabelNormalizer', () {
    test('reduces major and minor aliases to canonical internal labels', () {
      expect(normalizer.normalize('Cmaj'), 'C');
      expect(normalizer.normalize('C'), 'C');
      expect(normalizer.normalize('CM'), 'C');
      expect(normalizer.normalize('Cmin'), 'Cm');
      expect(normalizer.normalize('Cm'), 'Cm');
    });

    test('uses sharps as the canonical enharmonic spelling', () {
      expect(normalizer.normalize('C#'), 'C#');
      expect(normalizer.normalize('Db'), 'C#');
    });

    test('is idempotent', () {
      const labels = <String>[
        'Cmaj',
        'C',
        'CM',
        'Cmin',
        'Cm',
        'C#',
        'Db',
        'Bbmin7',
      ];

      for (final label in labels) {
        final normalized = normalizer.normalize(label);
        expect(normalizer.normalize(normalized), normalized, reason: label);
      }
    });
  });
}
