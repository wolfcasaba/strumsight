import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/pcm_ring_buffer.dart';

void main() {
  group('PcmRingBuffer (Lab-mode rolling capture, r199)', () {
    test('does nothing until enabled — zero overhead on the default path', () {
      final buf = PcmRingBuffer(maxSeconds: 30)..sampleRate = 8000;
      buf.add(List<double>.filled(1000, 0.1)); // disabled → dropped
      expect(buf.length, 0);
      final (pcm, sr) = buf.recent();
      expect(pcm, isEmpty);
      expect(sr, 8000);
    });

    test('does nothing while the sample rate is unknown', () {
      final buf = PcmRingBuffer()..enabled = true; // no rate yet
      buf.add(List<double>.filled(1000, 0.2));
      expect(buf.length, 0);
    });

    test('retains appended PCM when enabled and returns a copy', () {
      final buf = PcmRingBuffer(maxSeconds: 30)
        ..sampleRate = 8000
        ..enabled = true;
      buf.add([0.1, 0.2, 0.3]);
      buf.add([0.4, 0.5]);
      final (pcm, sr) = buf.recent();
      expect(pcm, [0.1, 0.2, 0.3, 0.4, 0.5]);
      expect(sr, 8000);
      // recent() returns a COPY — mutating it must not touch the buffer.
      pcm[0] = 9.9;
      expect(buf.recent().$1[0], 0.1);
    });

    test('caps at ~maxSeconds and drops the oldest samples', () {
      const rate = 1000;
      const maxSeconds = 2; // cap 2000, trim once past 2000 + 1000 slack
      final buf = PcmRingBuffer(maxSeconds: maxSeconds)
        ..sampleRate = rate
        ..enabled = true;

      // Push 10 s of a rising ramp in 1 s chunks; each sample encodes its index.
      var idx = 0;
      for (var s = 0; s < 10; s++) {
        final chunk = List<double>.generate(rate, (_) => (idx++).toDouble());
      buf.add(chunk);
      }

      final (pcm, _) = buf.recent();
      // Never exceeds the cap + slack, and holds AT LEAST the cap.
      expect(pcm.length, lessThanOrEqualTo(maxSeconds * rate + rate));
      expect(pcm.length, greaterThanOrEqualTo(maxSeconds * rate));
      // It kept the MOST RECENT samples: the last one is the final index.
      expect(pcm.last, (idx - 1).toDouble());
      // ...and dropped the oldest: the first retained index is well past 0.
      expect(pcm.first, greaterThan(0));
    });

    test('clear() drops audio but keeps rate + enabled; reset() clears all',
        () {
      final buf = PcmRingBuffer()
        ..sampleRate = 8000
        ..enabled = true;
      buf.add([0.1, 0.2]);
      buf.clear();
      expect(buf.length, 0);
      expect(buf.sampleRate, 8000);
      expect(buf.enabled, isTrue);
      buf.add([0.3]); // still enabled → keeps capturing
      expect(buf.length, 1);

      buf.reset();
      expect(buf.length, 0);
      expect(buf.sampleRate, 0);
    });
  });
}
