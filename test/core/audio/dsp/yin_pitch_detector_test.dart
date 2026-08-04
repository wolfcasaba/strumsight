import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/dsp/yin_pitch_detector.dart'
    as core_pitch;
import 'package:strumsight/features/tuner/engine/dsp/yin_pitch_detector.dart'
    as tuner_pitch;

const _sampleRate = 44100;

Float64List _sine(double frequency) => Float64List.fromList([
  for (var index = 0; index < 4096; index++)
    0.3 * math.sin(2 * math.pi * frequency * index / _sampleRate),
]);

void main() {
  test(
    'core and legacy YIN contracts return bit-identical pitch and mapping',
    () {
      final buffer = _sine(110);
      final core = core_pitch.YinPitchDetector(sampleRate: _sampleRate);
      final legacy = tuner_pitch.YinPitchDetector(sampleRate: _sampleRate);

      expect(core.detect(buffer), legacy.detect(buffer));
      expect(core.clarity, legacy.clarity);
      expect(
        core_pitch.noteForFrequency(445),
        tuner_pitch.noteForFrequency(445),
      );
    },
  );
}
