// E14-R12 — RecognitionStabilizer state-machine matrix (ADR 0518). Every cell
// drives the stabilizer directly with hand-built LiveFrames: no audio, no
// wall-clock, only the frame-agreement counter (ADR 0518 D3).
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/engine/recognition_stabilizer.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

LiveFrame _frame(String? label, {Strum? strum, int strumSeq = 0}) {
  return LiveFrame(
    current: label == null ? null : Chord(label),
    next: null,
    latestStrum: strum,
    bar: const <BeatSlot>[],
    bpm: 0,
    inputLevel: 0,
    tuningHz: 440,
    listening: true,
    strumSeq: strumSeq,
  );
}

void main() {
  group('brief §6 pt.1 — threshold triple cell (free, N=3, inclusive)', () {
    // The very first label ever seen has no established baseline to
    // disagree with, so it confirms on sight (ADR 0518 D1) — every cell
    // below therefore measures a DISPLACEMENT away from a bootstrapped
    // baseline, which is exactly the case the threshold exists to gate.
    RecognitionStabilizer bootstrapped() {
      final s = RecognitionStabilizer();
      s.stabilize(_frame('A'));
      return s;
    }

    test('below the threshold (2 agreeing frames) -> provisional, dropped', () {
      final s = bootstrapped();
      expect(s.stabilize(_frame('B')), isNull);
      expect(s.chordState, RecognitionDecision.provisional);
      expect(s.stabilize(_frame('B')), isNull);
      expect(s.chordState, RecognitionDecision.provisional);
    });

    test('exactly on the threshold (3rd agreeing frame) -> confirmed', () {
      final s = bootstrapped();
      s.stabilize(_frame('B'));
      s.stabilize(_frame('B'));
      final third = s.stabilize(_frame('B'));
      expect(third, isNotNull);
      expect(third!.current?.label, 'B');
      expect(s.chordState, RecognitionDecision.confirmed);
    });

    test('above the threshold (4th agreeing frame) -> still confirmed', () {
      final s = bootstrapped();
      s.stabilize(_frame('B'));
      s.stabilize(_frame('B'));
      s.stabilize(_frame('B'));
      final fourth = s.stabilize(_frame('B'));
      expect(fourth, isNotNull);
      expect(s.chordState, RecognitionDecision.confirmed);
    });
  });

  group('brief §6 pt.2 — confirmed resists weak counter-evidence, yields to '
      'strong (both directions)', () {
    test('A confirmed: 1 foreign B frame does not flip; 3 consecutive do', () {
      final s = RecognitionStabilizer();
      s.stabilize(_frame('A')); // cold-start bootstrap, confirms on sight
      expect(s.chordState, RecognitionDecision.confirmed);

      // Weak: a single foreign frame is dropped, no transition.
      expect(s.stabilize(_frame('B')), isNull);

      // Recovering to the label that is ALREADY established needs no
      // re-accumulation — it reaffirms on the very next frame (ADR 0518 D6).
      final recoveredA = s.stabilize(_frame('A'));
      expect(recoveredA?.current?.label, 'A');
      expect(s.chordState, RecognitionDecision.confirmed);

      // Strong: 3 consecutive foreign frames DOES flip.
      s.stabilize(_frame('B'));
      s.stabilize(_frame('B'));
      final flipped = s.stabilize(_frame('B'));
      expect(flipped?.current?.label, 'B');
      expect(s.chordState, RecognitionDecision.confirmed);
    });

    test('B confirmed: 1 foreign A frame does not flip; 3 consecutive do', () {
      final s = RecognitionStabilizer();
      s.stabilize(_frame('B')); // cold-start bootstrap, confirms on sight
      expect(s.chordState, RecognitionDecision.confirmed);

      expect(s.stabilize(_frame('A')), isNull);

      // Recovering to the established B needs no re-accumulation.
      final stillB = s.stabilize(_frame('B'));
      expect(stillB?.current?.label, 'B');

      // Strong: 3 consecutive foreign frames DOES flip.
      s.stabilize(_frame('A'));
      s.stabilize(_frame('A'));
      final flipped = s.stabilize(_frame('A'));
      expect(flipped?.current?.label, 'A');
    });
  });

  group(
    'brief §6 pt.4 — an accepted strum event is immutable (strumSeq id)',
    () {
      test(
        'same strumSeq with an opposite direction is refused; new seq admitted',
        () {
          final s = RecognitionStabilizer();
          s.stabilize(_frame('A')); // cold-start bootstrap, confirms on sight

          final accepted = s.stabilize(
            _frame(
              'A',
              strum: const Strum(
                direction: StrumDirection.down,
                confidence: 0.9,
              ),
              strumSeq: 1,
            ),
          );
          expect(accepted?.latestStrum?.direction, StrumDirection.down);

          // Same event (strumSeq unchanged) proposing the opposite direction —
          // must be refused, not rewritten: the frame is dropped.
          final revised = s.stabilize(
            _frame(
              'A',
              strum: const Strum(direction: StrumDirection.up, confidence: 0.5),
              strumSeq: 1,
            ),
          );
          expect(revised, isNull);

          // A genuinely NEW event (a new strumSeq) is admitted.
          final nextEvent = s.stabilize(
            _frame(
              'A',
              strum: const Strum(direction: StrumDirection.up, confidence: 0.7),
              strumSeq: 2,
            ),
          );
          expect(nextEvent?.latestStrum?.direction, StrumDirection.up);
        },
      );
    },
  );

  group('brief §6 pt.5 — free vs guided give a measurably different '
      '(confirmationLatencyFrames, flipRate) pair on the same input', () {
    // Cold-start A confirms on sight for BOTH profiles (nothing to disagree
    // with yet); each later 3-frame segment then meets free's threshold
    // (3) but never guided's (5), so guided keeps the cold-start baseline
    // while free tracks every displacement — a clean divergence on both
    // metrics from identical input.
    List<LiveFrame> sequence() => [
      _frame('A'),
      for (final label in ['B', 'C', 'D', 'E'])
        for (var i = 0; i < 3; i++) _frame(label),
    ];

    test('the two profiles diverge on both metrics', () {
      final free = RecognitionStabilizer(profile: StabilizerProfile.free);
      for (final f in sequence()) {
        free.stabilize(f);
      }

      final guided = RecognitionStabilizer(profile: StabilizerProfile.guided);
      for (final f in sequence()) {
        guided.stabilize(f);
      }

      expect(
        free.confirmationLatencyFrames,
        isNot(equals(guided.confirmationLatencyFrames)),
      );
      expect(free.flipRate, isNot(equals(guided.flipRate)));
    });
  });

  group(
    'brief §6 pt.6 — recovery path (L165): the state machine never freezes',
    () {
      test('after arbitrarily long noisy alternating history, 3 consecutive '
          'frames still confirm', () {
        final s = RecognitionStabilizer();
        const noisyLabels = [
          'A', 'B', 'C', 'A', 'C', 'B', 'A', 'B', //
          'C', 'A', 'B', 'A', 'C', 'B', 'A', 'C', //
        ];
        for (final label in noisyLabels) {
          s.stabilize(_frame(label));
        }
        // None of the noise ever confirmed anything (no 3-in-a-row run) — the
        // machine must still respond to a clean run, not be stuck.
        s.stabilize(_frame('B'));
        s.stabilize(_frame('B'));
        final confirmed = s.stabilize(_frame('B'));
        expect(confirmed?.current?.label, 'B');
        expect(s.chordState, RecognitionDecision.confirmed);
      });
    },
  );
}
