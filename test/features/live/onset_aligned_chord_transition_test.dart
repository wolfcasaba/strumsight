// E14-R28 (ADR 0545 D2/D3) — chord label transitions are ONSET-ALIGNED.
//
// The ADR 0518 stabilizer answered "what is the new label" (N agreeing
// frames). It had no answer for "when may a chord change at all", so a slow
// drift between two similar voicings could confirm a new chord in the middle
// of a held one, with no strum anywhere near it. This round adds exactly one
// condition on DISPLACEMENT: the confirming frame must sit inside a window
// that starts at a detected strum onset.
//
// Every cell drives the stabilizer directly with hand-built frames — no audio,
// no wall clock, only the frame's own engine sample clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/recognition_stabilizer.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

/// A frame on the engine's sample clock. [onsetTimeSec] is the newest DETECTED
/// onset — recorded before direction classification, so it exists even for a
/// strum whose direction was rejected (ADR 0545 D2).
LiveFrame _at(
  String? label, {
  required double engineTimeSec,
  required double onsetTimeSec,
}) => LiveFrame(
  current: label == null ? null : Chord(label),
  next: null,
  latestStrum: null,
  bar: const <BeatSlot>[],
  bpm: 0,
  inputLevel: 0,
  tuningHz: 440,
  listening: true,
  onsetTimeSec: onsetTimeSec,
  engineTimeSec: engineTimeSec,
);

/// A frame with no sample clock at all (mock producers, hand-built frames) —
/// the ADR 0518 fallback path.
LiveFrame _clockless(String? label) => LiveFrame(
  current: label == null ? null : Chord(label),
  next: null,
  latestStrum: null,
  bar: const <BeatSlot>[],
  bpm: 0,
  inputLevel: 0,
  tuningHz: 440,
  listening: true,
);

void main() {
  group('ADR 0545 D2 — the window is DERIVED from constants that existed', () {
    test('free = onset boost + 3 emitted frames, guided = + 5', () {
      const boost = DspConfig.chordOnsetBoostSeconds;
      const emit = DspConfig.frameEmitSeconds;
      expect(boost, closeTo(2 * 4096 / 44100, 1e-12));
      expect(
        StabilizerProfile.free.onsetAlignmentWindowSec,
        closeTo(boost + 3 * emit, 1e-12),
      );
      expect(
        StabilizerProfile.guided.onsetAlignmentWindowSec,
        closeTo(boost + 5 * emit, 1e-12),
      );
      expect(
        StabilizerProfile.guided.onsetAlignmentWindowSec,
        greaterThan(StabilizerProfile.free.onsetAlignmentWindowSec),
        reason: 'guided is longer only because its agreement threshold is',
      );
    });
  });

  group('ADR 0545 D2 — a displacement waits for an onset', () {
    // Baseline A is established at t=0 with a fresh onset; the challenger B
    // then agrees for 3 frames, but the newest onset is 1.0 s old — inside
    // neither the alignment window (0.384 s) nor the staleness horizon (2 s).
    RecognitionStabilizer bootstrapped() {
      final s = RecognitionStabilizer();
      s.stabilize(_at('A', engineTimeSec: 0.0, onsetTimeSec: 0.0));
      return s;
    }

    test('agreement alone no longer confirms: an un-aligned challenger is '
        'held, not confirmed', () {
      final s = bootstrapped();
      for (var i = 1; i <= 4; i++) {
        final frame = _at(
          'B',
          engineTimeSec: 1.0 + i * DspConfig.frameEmitSeconds,
          onsetTimeSec: 0.0,
        );
        expect(
          s.stabilize(frame),
          isNull,
          reason: 'frame $i is 1 s past the last onset',
        );
      }
      expect(s.chordState, RecognitionDecision.provisional);
      expect(
        s.onsetHeldFrames,
        greaterThan(0),
        reason: 'the gate must report the latency it cost',
      );
    });

    test('the moment an onset arrives the already-proven challenger confirms '
        'on that very frame (no re-accumulation)', () {
      final s = bootstrapped();
      for (var i = 1; i <= 4; i++) {
        s.stabilize(
          _at(
            'B',
            engineTimeSec: 1.0 + i * DspConfig.frameEmitSeconds,
            onsetTimeSec: 0.0,
          ),
        );
      }
      // A strum lands at t = 1.30; the next frame is 20 ms later.
      final confirmed = s.stabilize(
        _at('B', engineTimeSec: 1.32, onsetTimeSec: 1.30),
      );
      expect(confirmed, isNotNull);
      expect(confirmed!.current?.label, 'B');
      expect(s.chordState, RecognitionDecision.confirmed);
    });

    test('a challenger whose agreement runs entirely INSIDE the window '
        'confirms exactly on the 3rd frame, as before', () {
      final s = bootstrapped();
      // Onset at t = 1.00, frames at 1.02 / 1.08 / 1.14 — all inside 0.384 s.
      expect(
        s.stabilize(_at('B', engineTimeSec: 1.02, onsetTimeSec: 1.00)),
        isNull,
      );
      expect(
        s.stabilize(_at('B', engineTimeSec: 1.08, onsetTimeSec: 1.00)),
        isNull,
      );
      final third = s.stabilize(
        _at('B', engineTimeSec: 1.14, onsetTimeSec: 1.00),
      );
      expect(third?.current?.label, 'B');
      expect(
        s.onsetHeldFrames,
        0,
        reason: 'an on-the-strum change costs no extra latency',
      );
    });
  });

  group('ADR 0545 D2 — the window boundary is inclusive', () {
    RecognitionStabilizer proven() {
      final s = RecognitionStabilizer();
      s.stabilize(_at('A', engineTimeSec: 0.0, onsetTimeSec: 0.0));
      // Two agreeing B frames, both aligned, so the 3rd decides.
      s.stabilize(_at('B', engineTimeSec: 1.01, onsetTimeSec: 1.00));
      s.stabilize(_at('B', engineTimeSec: 1.02, onsetTimeSec: 1.00));
      return s;
    }

    test('exactly at the window edge the displacement is admitted', () {
      final s = proven();
      final edge = 1.00 + StabilizerProfile.free.onsetAlignmentWindowSec;
      expect(
        s.stabilize(_at('B', engineTimeSec: edge, onsetTimeSec: 1.00))
            ?.current
            ?.label,
        'B',
      );
    });

    test('one millisecond past the edge it is held', () {
      final s = proven();
      final past =
          1.00 + StabilizerProfile.free.onsetAlignmentWindowSec + 0.001;
      expect(
        s.stabilize(_at('B', engineTimeSec: past, onsetTimeSec: 1.00)),
        isNull,
      );
      expect(s.chordState, RecognitionDecision.provisional);
    });
  });

  group('ADR 0545 D2 — the gate can never freeze a label', () {
    test('an onset older than LiveFrame.strumHoldSec has expired, so the '
        'gate re-opens', () {
      final s = RecognitionStabilizer();
      s.stabilize(_at('A', engineTimeSec: 0.0, onsetTimeSec: 0.0));
      // The detector never fired again; by t = 5 s the producer has long
      // dropped the strum, so onset evidence no longer exists to align to.
      LiveFrame? out;
      for (var i = 1; i <= 3; i++) {
        out = s.stabilize(
          _at('B', engineTimeSec: 5.0 + i * 0.066, onsetTimeSec: 0.0),
        );
      }
      expect(out?.current?.label, 'B');
      expect(s.chordState, RecognitionDecision.confirmed);
    });

    test('clockless frames are unaffected: pure ADR 0518 agreement', () {
      final s = RecognitionStabilizer();
      s.stabilize(_clockless('A'));
      expect(s.stabilize(_clockless('B')), isNull);
      expect(s.stabilize(_clockless('B')), isNull);
      expect(s.stabilize(_clockless('B'))?.current?.label, 'B');
      expect(s.onsetHeldFrames, 0);
    });

    test('reaffirming the ALREADY confirmed label is never onset-gated', () {
      // A held chord must keep reaching the timeline between strums —
      // the gate is about CHANGE, not about presence.
      final s = RecognitionStabilizer();
      s.stabilize(_at('A', engineTimeSec: 0.0, onsetTimeSec: 0.0));
      final held = s.stabilize(
        _at('A', engineTimeSec: 3.5, onsetTimeSec: 0.0),
      );
      expect(held?.current?.label, 'A');
      expect(s.chordState, RecognitionDecision.confirmed);
    });

    test('the cold-start label still confirms on sight, un-aligned or not', () {
      final s = RecognitionStabilizer();
      final first = s.stabilize(
        _at('A', engineTimeSec: 1.5, onsetTimeSec: 0.0),
      );
      expect(first?.current?.label, 'A');
      expect(s.chordState, RecognitionDecision.confirmed);
    });
  });
}
