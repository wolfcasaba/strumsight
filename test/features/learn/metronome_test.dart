import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/audio/metronome.dart';
import 'package:music_theory/features/learn/lesson_timing.dart';

String _tag(Uint8List b, int o) =>
    String.fromCharCodes(b.sublist(o, o + 4));

void main() {
  group('beatsCrossed', () {
    test('no crossing when the playhead does not advance past an integer', () {
      expect(LessonTiming.beatsCrossed(0.1, 0.4), isEmpty);
      expect(LessonTiming.beatsCrossed(2.0, 2.0), isEmpty);
      expect(LessonTiming.beatsCrossed(2.5, 2.0), isEmpty); // backwards
    });

    test('crosses the beat as the playhead passes it (count-in included)', () {
      expect(LessonTiming.beatsCrossed(-0.1, 0.1), [0]);
      expect(LessonTiming.beatsCrossed(-4.0, -2.5), [-3]);
      expect(LessonTiming.beatsCrossed(0.9, 2.1), [1, 2]);
    });

    test('an exactly-integer start is not re-clicked', () {
      expect(LessonTiming.beatsCrossed(1.0, 2.0), [2]);
    });
  });

  group('buildClickWav', () {
    test('produces a well-formed, non-silent PCM WAV', () {
      final wav = Metronome.buildClickWav(ms: 35, sampleRate: 44100);
      // RIFF/WAVE/fmt /data headers.
      expect(_tag(wav, 0), 'RIFF');
      expect(_tag(wav, 8), 'WAVE');
      expect(_tag(wav, 12), 'fmt ');
      expect(_tag(wav, 36), 'data');
      // Length = 44-byte header + 16-bit mono samples.
      final n = (44100 * 35 / 1000).round();
      expect(wav.length, 44 + n * 2);
      // Not all-zero (there is an actual click in there).
      expect(wav.sublist(44).any((b) => b != 0), isTrue);
    });

    test('accent click uses a different waveform than the normal click', () {
      final click = Metronome.buildClickWav(freq: 1000);
      final accent = Metronome.buildClickWav(freq: 1600);
      expect(click, isNot(equals(accent)));
    });
  });

  // Note: actual playback (Metronome.tick) goes through audioplayers' platform
  // channel and is verified on-device — the WAV generator + beat scheduling
  // above are the unit-testable surface.
}
