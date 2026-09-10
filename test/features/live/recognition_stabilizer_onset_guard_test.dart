// ADR 0539 D2 — the RecognitionStabilizer's onset-transient guard. The
// decoder lowers its switch guard for ~186 ms after every strum onset, which
// is exactly where the attack transient makes the chroma least reliable; a
// wrong label confined to that window is the "C → other chord → C" blip the
// user measured on EVERY chord (2026-09-09). Frames inside the guard window
// never COUNT toward displacing the confirmed label; a genuine change is
// confirmed by the frames that follow the attack.
//
// Hand-built frames, no audio, no wall-clock (ADR 0518 D3). The randomized
// property (HORIZON) re-checks the guarantee on random blip placements.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/engine/recognition_stabilizer.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

/// A decided frame at engine time [t], carrying the latest onset at [onset].
LiveFrame _frame(String label, {required double t, required double onset}) {
  return LiveFrame(
    current: Chord(label),
    next: null,
    latestStrum: const Strum(direction: StrumDirection.down, confidence: 0.8),
    bar: const <BeatSlot>[],
    bpm: 0,
    inputLevel: 0,
    tuningHz: 440,
    listening: true,
    latestStrumTime: onset,
    engineTimeSec: t,
  );
}

/// ~15 Hz emit cadence, as the pipeline's frames arrive.
const double _hop = 1 / 15;

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  RecognitionStabilizer confirmedC() {
    final s = RecognitionStabilizer();
    // Cold start confirms on sight (ADR 0518 D11); settle a few frames.
    for (var i = 0; i < 4; i++) {
      s.stabilize(_frame('C', t: i * _hop, onset: 0));
    }
    expect(s.chordState, RecognitionDecision.confirmed);
    return s;
  }

  test('a wrong label confined to the attack window never flips the card', () {
    final s = confirmedC();
    // Next strum at t = 1.0 s; the decoder's boost window yields 'G' for the
    // three emitted frames inside 200 ms — 3 frames WOULD have confirmed
    // under the plain agreement counter (free profile, N = 3).
    for (final t in [1.02, 1.09, 1.15]) {
      expect(s.stabilize(_frame('G', t: t, onset: 1.0)), isNull);
      expect(s.chordState, RecognitionDecision.provisional);
    }
    // The sustain is C again: the established label, reaffirmed at once.
    final back = s.stabilize(_frame('C', t: 1.22, onset: 1.0));
    expect(back?.current?.label, 'C');
    expect(s.chordState, RecognitionDecision.confirmed);
    expect(s.flipRate, closeTo(1 / 8, 1e-9), reason: 'only the cold start');
  });

  test('a GENUINE change is confirmed by post-attack frames — never lost', () {
    final s = confirmedC();
    // Strum at 1.0 s, G from then on: 3 attack-window frames are held back,
    // the 3 frames after the guard confirm (free profile, N = 3).
    final results = <LiveFrame?>[];
    for (final t in [1.02, 1.09, 1.15, 1.22, 1.29, 1.35]) {
      results.add(s.stabilize(_frame('G', t: t, onset: 1.0)));
    }
    expect(results.sublist(0, 5), everyElement(isNull));
    expect(results.last?.current?.label, 'G');
    expect(s.chordState, RecognitionDecision.confirmed);
    // Confirmation latency counts from the FIRST G frame (ADR 0518 D8).
    expect(s.confirmationLatencyFrames, 6);
  });

  test('frames without onset timing are counted as before (guard inert)', () {
    final s = confirmedC();
    for (var i = 0; i < 2; i++) {
      expect(s.stabilize(_frame('G', t: -1, onset: -1)), isNull);
    }
    expect(s.stabilize(_frame('G', t: -1, onset: -1))?.current?.label, 'G');
  });

  test('guard 0 disables the window (plain ADR 0518 counting)', () {
    final s = RecognitionStabilizer(onsetTransientGuardSec: 0);
    s.stabilize(_frame('C', t: 0, onset: 0));
    for (final t in [1.02, 1.09]) {
      expect(s.stabilize(_frame('G', t: t, onset: 1.0)), isNull);
    }
    expect(s.stabilize(_frame('G', t: 1.15, onset: 1.0))?.current?.label, 'G');
  });

  test('property: a blip that ends inside the guard window never flips; a '
      'label that outlasts it by N frames always does', () {
    const labels = ['C', 'G', 'D', 'Am', 'Em', 'F'];
    for (var trial = 0; trial < 200; trial++) {
      final s = RecognitionStabilizer();
      final held = labels[rng.nextInt(labels.length)];
      s.stabilize(_frame(held, t: 0, onset: 0));
      var t = 0.5;
      var flips = 0;
      for (var strum = 0; strum < 6; strum++) {
        final onset = t;
        var other = labels[rng.nextInt(labels.length)];
        while (other == held) {
          other = labels[rng.nextInt(labels.length)];
        }
        // 0..3 blip frames strictly inside the 200 ms guard window.
        final blipFrames = rng.nextInt(4);
        for (var i = 0; i < blipFrames; i++) {
          final at = onset + 0.01 + rng.nextDouble() * 0.18;
          final out = s.stabilize(_frame(other, t: at, onset: onset));
          expect(
            out,
            isNull,
            reason: 'seed=$seed trial=$trial strum=$strum: attack blip passed',
          );
        }
        // Sustain: the held chord for the rest of the beat.
        for (var i = 0; i < 6; i++) {
          final at = onset + 0.25 + i * _hop;
          final out = s.stabilize(_frame(held, t: at, onset: onset));
          if (out?.current?.label != held) flips++;
        }
        t += 0.75;
      }
      expect(flips, 0, reason: 'seed=$seed trial=$trial: the card flipped');
      expect(
        s.flipRate * s.debugFramesProcessed,
        closeTo(1, 1e-9),
        reason: 'seed=$seed trial=$trial: only the cold-start confirmation',
      );

      // A real change: the new label outlasts the guard by N frames.
      final next = labels.firstWhere((l) => l != held);
      final onset = t;
      LiveFrame? confirmed;
      // Enough frames to clear the guard window and then agree N times.
      for (var i = 0; i < 8; i++) {
        confirmed = s.stabilize(
          _frame(next, t: onset + 0.02 + i * _hop, onset: onset),
        );
      }
      expect(
        confirmed?.current?.label,
        next,
        reason: 'seed=$seed trial=$trial: a sustained change must confirm',
      );
    }
  });
}
