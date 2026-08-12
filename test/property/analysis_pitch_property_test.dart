import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('pitch contracts remain finite across randomized valid evidence', () {
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 313);
      final frequency = 40 + random.nextDouble() * 4900;
      final confidence = random.nextDouble();
      final frame = PitchFrame(
        time: Duration(milliseconds: trial),
        frequencyHz: frequency,
        midiNote: (random.nextDouble() * 127).floor(),
        confidence: confidence,
      );
      expect(frame.frequencyHz, allOf(isNotNull, isA<double>()));
      expect(frame.frequencyHz!, inInclusiveRange(0.000001, 5000));
      expect(frame.confidence, inInclusiveRange(0, 1));

      final segment = MonophonicPitchSegment(
        start: Duration.zero,
        end: const Duration(milliseconds: 100),
        medianHz: frequency,
        medianMidi: frame.midiNote!,
        centsOffset: random.nextDouble() * 100 - 50,
        stabilityCents: random.nextDouble() * 100,
        confidence: confidence,
      );
      expect(segment.centsOffset.isFinite, isTrue);
      expect(segment.stabilityCents.isFinite, isTrue);
    }
  });
}
