import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;

  test('identity calibration is monotonic and bounded', () {
    final table = CalibrationTable.identityV1();
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 7919);
      final left = random.nextDouble();
      final right = left + (1 - left) * random.nextDouble();
      final mappedLeft = table.calibrate(left).confidence;
      final mappedRight = table.calibrate(right).confidence;

      expect(mappedLeft, inInclusiveRange(0, 1), reason: 'seed=$seed');
      expect(mappedRight, inInclusiveRange(0, 1), reason: 'seed=$seed');
      expect(mappedLeft, lessThanOrEqualTo(mappedRight), reason: 'seed=$seed');
    }
  });
}
