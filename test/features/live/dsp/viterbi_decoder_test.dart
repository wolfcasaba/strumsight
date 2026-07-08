import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/chord_matcher.dart';
import 'package:music_theory/features/live/engine/dsp/viterbi_chord_decoder.dart';

Float64List chroma(Map<int, double> weights) {
  final v = Float64List(12);
  weights.forEach((pc, w) => v[pc % 12] = w);
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  if (n > 0) {
    for (var i = 0; i < 12; i++) {
      v[i] /= n;
    }
  }
  return v;
}

// Observed (bass, treble) pairs for a few chords.
final cMaj = [chroma({0: 1}), chroma({0: 1, 4: 1, 7: 1})];
final gMaj = [chroma({7: 1}), chroma({7: 1, 11: 1, 2: 1})];
// Cmaj7 = C E G B — a *marginal* competitor to C (C explains it almost as well),
// exactly the maj↔maj7 flicker case the self-transition bonus must damp.
final cMaj7 = [chroma({0: 1}), chroma({0: 1, 4: 1, 7: 0.9, 11: 0.9})];
final silence = [Float64List(12), Float64List(12)];

ChordMatch? feed(ViterbiChordDecoder d, List<Float64List> obs, int times) {
  ChordMatch? m;
  for (var i = 0; i < times; i++) {
    m = d.process(obs[0], obs[1]);
  }
  return m;
}

void main() {
  test('a sustained chord is decoded with confidence', () {
    final d = ViterbiChordDecoder();
    final m = feed(d, cMaj, 8);
    expect(m, isNotNull);
    expect(m!.chord.label, 'C');
    expect(m.confidence, greaterThan(0.5));
  });

  test('silence (zero chroma) resolves to no-chord (null)', () {
    final d = ViterbiChordDecoder();
    expect(feed(d, silence, 8), isNull);
  });

  test('self-transition bonus damps the maj↔maj7 flicker', () {
    final d = ViterbiChordDecoder();
    feed(d, cMaj, 8); // lock onto C
    // A single Cmaj7-looking frame (a stray B) must NOT rename the chord —
    // this is the round-4 hysteresis win, now principled.
    final blip = d.process(cMaj7[0], cMaj7[1]);
    expect(blip!.chord.label, 'C', reason: 'one marginal frame cannot flip');
    // But a genuinely sustained Cmaj7 does resolve to Cmaj7. The maj7 Occam
    // bias (which suppresses phantom-7th false positives) deliberately makes
    // this switch deliberate rather than instant, so allow it time to build.
    final held = feed(d, cMaj7, 25);
    expect(held!.chord.label, 'Cmaj7');
  });

  test('a fully different sustained chord switches over', () {
    final d = ViterbiChordDecoder();
    feed(d, cMaj, 8);
    expect(feed(d, gMaj, 8)!.chord.label, 'G');
  });

  test('a held chord decays to no-chord after sustained silence', () {
    final d = ViterbiChordDecoder();
    feed(d, cMaj, 8);
    // Feed silence until the path leaves the chord.
    ChordMatch? m;
    for (var i = 0; i < 10; i++) {
      m = d.process(silence[0], silence[1]);
    }
    expect(m, isNull, reason: 'no-chord floor takes over once the chord stops');
  });

  test('a lower bonus switches a marginal rival faster than a higher one', () {
    int framesToSwitch(double bonus) {
      final d = ViterbiChordDecoder(selfBonus: bonus);
      feed(d, cMaj, 8);
      var n = 0;
      while (n < 60) {
        n++;
        final m = d.process(cMaj7[0], cMaj7[1]);
        if (m?.chord.label == 'Cmaj7') break;
      }
      return n;
    }

    expect(framesToSwitch(0.05), lessThan(framesToSwitch(0.4)));
  });

  test('reset clears the trellis', () {
    final d = ViterbiChordDecoder();
    feed(d, cMaj, 8);
    d.reset();
    // First frame after reset is seeded fresh — G is reported immediately.
    final m = d.process(gMaj[0], gMaj[1]);
    expect(m!.chord.label, 'G');
  });
}
