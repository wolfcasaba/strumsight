import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/direction/string_arrival_cue.dart';

import '../../../support/synth.dart';

void main() {
  const sr = 44100;
  // strumSignal uses the open strings E2..E4 → the all-open voicing.
  final open = StringArrivalCue.voicingHz([0, 0, 0, 0, 0, 0]);
  final cue = StringArrivalCue(sampleRate: sr);

  test('attributable partials are pairwise separated across strings', () {
    final parts = cue.attributablePartials(open);
    // E4's fundamental (329.6) collides with E2's 4th harmonic → excluded.
    expect(parts.any((p) => (p.hz - 329.6).abs() < 1), false);
    for (final p in parts) {
      for (final q in parts) {
        if (p.string == q.string) continue;
        expect(
          (p.hz - q.hz).abs(),
          greaterThanOrEqualTo(cue.uniqueSeparationHz),
        );
      }
    }
    expect(parts.map((p) => p.string).toSet().length, greaterThanOrEqualTo(4));
  });

  for (final stagger in [4.0, 8.0, 12.0]) {
    test('down-stroke with ${stagger}ms stagger reads DOWN', () {
      final pcm = strumSignal(lowFirst: true, staggerMs: stagger);
      final r = cue.analyze(pcm, (0.1 * sr).round(), open);
      expect(r.direction, StrumDirection.down, reason: 'tau=${r.tau}');
      expect(r.stringsUsed, greaterThanOrEqualTo(4));
      expect(r.confidence, greaterThan(0.6));
    });

    test('up-stroke with ${stagger}ms stagger reads UP', () {
      final pcm = strumSignal(lowFirst: false, staggerMs: stagger);
      final r = cue.analyze(pcm, (0.1 * sr).round(), open);
      expect(r.direction, StrumDirection.up, reason: 'tau=${r.tau}');
      expect(r.confidence, greaterThan(0.6));
    });
  }

  test('an onset estimate 15 ms late still reads the direction', () {
    final pcm = strumSignal(lowFirst: true, staggerMs: 8);
    final r = cue.analyze(pcm, (0.115 * sr).round(), open);
    expect(r.direction, StrumDirection.down);
  });

  test('a simultaneous chord (no stagger) is ambiguous, not guessed', () {
    final pcm = strumSignal(lowFirst: true, staggerMs: 0);
    final r = cue.analyze(pcm, (0.1 * sr).round(), open);
    expect(r.direction, isNull);
  });

  test('silence is ambiguous', () {
    final r = cue.analyze(Float64List(sr ~/ 2), sr ~/ 4, open);
    expect(r.direction, isNull);
    expect(r.stringsUsed, 0);
  });
}
