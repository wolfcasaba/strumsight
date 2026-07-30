import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_value_equality.dart'
    as equality;

void main() {
  group('Practice value equality helpers', () {
    test('compares lists structurally and hashes equal lists equally', () {
      final left = [1, 2, 3];
      final sameValue = [1, 2, 3];
      final differentOrder = [3, 2, 1];

      expect(identical(left, sameValue), isFalse);
      expect(equality.listEquals(left, sameValue), isTrue);
      expect(equality.listHash(left), equality.listHash(sameValue));
      expect(equality.listEquals(left, differentOrder), isFalse);
      expect(equality.listEquals(left, const [1, 2]), isFalse);
    });

    test('compares maps structurally independent of insertion order', () {
      final left = {'rhythm': 55, 'direction': 45};
      final sameValue = {'direction': 45, 'rhythm': 55};
      final differentValue = {'rhythm': 60, 'direction': 40};

      expect(equality.mapEquals(left, sameValue), isTrue);
      expect(equality.mapHash(left), equality.mapHash(sameValue));
      expect(equality.mapEquals(left, differentValue), isFalse);
      expect(equality.mapEquals(left, {'rhythm': 55}), isFalse);
    });
  });
}
