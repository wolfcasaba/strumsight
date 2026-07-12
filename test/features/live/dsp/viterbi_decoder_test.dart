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

  // Round 138 (chunk 016 rec #2): onset-aligned updates. A strum onset is the
  // only moment a chord CAN change — right after one, the switch penalty is
  // relaxed for a couple of frames (fast, decisive changes); between onsets
  // the full bonus keeps the track stable.
  group('onset-aligned switch boost', () {
    int framesToFlip(ViterbiChordDecoder d) {
      var n = 0;
      while (n < 60) {
        n++;
        if (d.process(cMaj7[0], cMaj7[1])?.chord.label == 'Cmaj7') break;
      }
      return n;
    }

    test('a marginal change lands faster right after an onset', () {
      final base = ViterbiChordDecoder();
      feed(base, cMaj, 8);
      final baseline = framesToFlip(base);

      final boosted = ViterbiChordDecoder();
      feed(boosted, cMaj, 8);
      boosted.noteOnset();
      expect(framesToFlip(boosted), lessThan(baseline),
          reason: 'the post-onset window must switch sooner than steady-state');
    });

    test('the boost expires — stability returns between onsets', () {
      final d = ViterbiChordDecoder();
      feed(d, cMaj, 8);
      d.noteOnset();
      feed(d, cMaj, 4); // boost window passes while the SAME chord sustains
      // A single marginal frame afterwards must not flip (the r28 flicker
      // guarantee is back in force).
      final blip = d.process(cMaj7[0], cMaj7[1]);
      expect(blip!.chord.label, 'C',
          reason: 'one marginal frame cannot flip once the boost expired');
    });

    test('gated (silent) chord frames do not consume the boost (r142)', () {
      // R2 audit finding: the pipeline feeds zero chroma for sub-tonalness
      // frames — flagged gated, those frames must neither eat the 2-frame
      // boost window nor lower the incumbent's guard on silence.
      final base = ViterbiChordDecoder();
      feed(base, cMaj, 8);
      base.noteOnset();
      var baseline = 0;
      while (baseline < 60) {
        baseline++;
        if (base.process(cMaj7[0], cMaj7[1])?.chord.label == 'Cmaj7') break;
      }

      final d = ViterbiChordDecoder();
      feed(d, cMaj, 8);
      d.noteOnset();
      // Two gated frames land between the onset and the tonal evidence.
      d.process(silence[0], silence[1], gated: true);
      d.process(silence[0], silence[1], gated: true);
      var n = 0;
      while (n < 60) {
        n++;
        if (d.process(cMaj7[0], cMaj7[1])?.chord.label == 'Cmaj7') break;
      }
      expect(n, lessThanOrEqualTo(baseline),
          reason: 'the boost must still cover the first TONAL frames');
    });

    test('an onset on the SAME sustained chord changes nothing', () {
      final d = ViterbiChordDecoder();
      feed(d, cMaj, 8);
      d.noteOnset();
      final m = feed(d, cMaj, 4);
      expect(m!.chord.label, 'C');
    });
  });

  // Round 137 (chunk 016 rec #1): the expected-target prior. During a lesson
  // the target chord is KNOWN — a small per-frame bonus resolves AMBIGUOUS
  // evidence toward the target, but must never mask a genuinely different
  // played chord (the "off-chart" guarantee).
  group('expected-chord prior', () {
    test('ambiguous maj-vs-maj7 evidence resolves to the expected chord', () {
      final d = ViterbiChordDecoder()..setExpected('C');
      feed(d, cMaj, 8);
      // Without the prior this sustained marginal Cmaj7 flips within 25
      // frames (see the flicker test above); expecting C it must hold C.
      final held = feed(d, cMaj7, 25);
      expect(held!.chord.label, 'C',
          reason: 'the prior tips the ambiguous call toward the target');
    });

    test('a clearly different played chord still wins (off-chart safety)', () {
      final d = ViterbiChordDecoder()..setExpected('C');
      final m = feed(d, gMaj, 8);
      expect(m!.chord.label, 'G',
          reason: 'expecting C must never rename a real G');
    });

    test('a NOISY weak-third G still beats an expected C (r142 audit)', () {
      // The clean-G test alone left the safety claim untested on degraded
      // input: a phone-mic G with a weak third and smeared chroma is the
      // realistic "wrong chord" a beginner plays while the lesson expects C.
      final noisyG = [
        chroma({7: 1, 0: 0.25, 5: 0.15}),
        chroma({7: 1, 11: 0.35, 2: 0.7, 0: 0.3, 4: 0.2, 9: 0.15}),
      ];
      final d = ViterbiChordDecoder()..setExpected('C');
      final m = feed(d, noisyG, 8);
      expect(m!.chord.label, startsWith('G'),
          reason: 'the 0.05 prior must stay below a real similarity gap '
              'even on degraded input (got ${m.chord.label})');
    });

    test('clearing the expectation restores baseline behaviour', () {
      final d = ViterbiChordDecoder()..setExpected('C');
      d.setExpected(null);
      feed(d, cMaj, 8);
      final held = feed(d, cMaj7, 25);
      expect(held!.chord.label, 'Cmaj7',
          reason: 'null expectation = the pre-prior switch behaviour');
    });

    test('an unknown label is ignored gracefully', () {
      final d = ViterbiChordDecoder()..setExpected('G/B');
      final m = feed(d, cMaj, 8);
      expect(m!.chord.label, 'C');
    });

    test('expecting a chord never conjures it from silence', () {
      final d = ViterbiChordDecoder()..setExpected('C');
      expect(feed(d, silence, 8), isNull,
          reason: 'the prior must not beat the no-chord floor');
    });

    test('reset clears the prior and the onset boost (r142 audit)', () {
      final d = ViterbiChordDecoder()..setExpected('C');
      d.noteOnset();
      d.reset();
      feed(d, cMaj, 8);
      final held = feed(d, cMaj7, 25);
      expect(held!.chord.label, 'Cmaj7',
          reason: 'a fresh session must not inherit a past lesson bias');
    });
  });
}
