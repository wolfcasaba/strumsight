// Randomized property gate (anti-reward-hacking — HORIZON pattern) for the
// Live chord-timeline reducer (r185).
//
// The deterministic unit tests below are the visible dev-loop harness; this
// suite re-checks the reducer's INVARIANTS on randomized frame sequences so
// the logic cannot be (even accidentally) tuned to the fixed fixtures.
//
// Seed: PROPERTY_SEED env var — CI passes the run id (a fresh gate every run);
// locally absent → fixed 42, so the dev-loop suite stays deterministic.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/chord.dart';
import 'package:music_theory/features/live/model/chord_event.dart';
import 'package:music_theory/features/live/model/live_frame.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/providers/chord_timeline_provider.dart';

/// A minimal engine frame carrying only what the reducer reads.
LiveFrame _frame(
  String? label, {
  Strum? strum,
  double latestStrumTime = -1,
  double engineTimeSec = -1,
}) {
  return LiveFrame(
    current: label == null ? null : Chord(label),
    next: null,
    latestStrum: strum,
    bar: const <BeatSlot>[],
    bpm: 0,
    inputLevel: 0,
    tuningHz: 440,
    listening: true,
    latestStrumTime: latestStrumTime,
    engineTimeSec: engineTimeSec,
  );
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // Always visible in logs so any failure is reproducible.
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  const labels = ['C', 'G', 'Am', 'F', 'D', 'Em'];

  test('property: reducer invariants hold over random frame sequences', () {
    for (var trial = 0; trial < 40; trial++) {
      final cap = 3 + rng.nextInt(5); // 3..7
      var buffer = <ChordEvent>[];
      final steps = 20 + rng.nextInt(40); // 20..59 frames

      for (var s = 0; s < steps; s++) {
        // ~15% idle frames (null current) interleaved.
        final idle = rng.nextDouble() < 0.15;
        final label = idle ? null : labels[rng.nextInt(labels.length)];
        final hasStrum = rng.nextBool();
        final strum = hasStrum
            ? Strum(
                direction:
                    rng.nextBool() ? StrumDirection.down : StrumDirection.up,
                confidence: rng.nextDouble(),
              )
            : null;
        final frame = _frame(
          label,
          strum: strum,
          latestStrumTime: rng.nextBool() ? rng.nextDouble() * 100 : -1,
          engineTimeSec: rng.nextDouble() * 100,
        );

        // Snapshot to prove the reducer never mutates its input.
        final before = List<ChordEvent>.of(buffer);
        final lenBefore = buffer.length;
        final lastLabelBefore =
            buffer.isEmpty ? null : buffer.last.chord.label;

        final next = reduceChordTimeline(buffer, frame, cap: cap);

        // Input must be untouched (same instance, same contents).
        expect(buffer, orderedEquals(before),
            reason: 'seed=$seed trial=$trial step=$s: input mutated');

        // Invariant: never exceed cap.
        expect(next.length, lessThanOrEqualTo(cap),
            reason: 'seed=$seed trial=$trial step=$s: buffer over cap');

        // Invariant: seq strictly increasing (newest last).
        for (var i = 1; i < next.length; i++) {
          expect(next[i].seq, greaterThan(next[i - 1].seq),
              reason: 'seed=$seed trial=$trial step=$s: seq not increasing');
        }

        // Invariant: no two CONSECUTIVE events share a chord label.
        for (var i = 1; i < next.length; i++) {
          expect(next[i].chord.label == next[i - 1].chord.label, isFalse,
              reason:
                  'seed=$seed trial=$trial step=$s: consecutive dup label');
        }

        // Same-label + strum → in-place update (length unchanged, not append).
        if (label != null && label == lastLabelBefore && strum != null) {
          expect(next.length, lenBefore,
              reason: 'seed=$seed trial=$trial step=$s: dedupe should update '
                  'in place, not append');
          expect(next.last.direction, strum.direction);
          expect(next.last.confidence, strum.confidence);
          // The identity fields must be preserved through the update.
          expect(next.last.seq, before.last.seq);
          expect(next.last.timeSec, before.last.timeSec);
        }

        // Idle frames never change the buffer.
        if (label == null) {
          expect(next, same(buffer),
              reason: 'seed=$seed trial=$trial step=$s: idle changed buffer');
        }

        buffer = next;
      }
    }
  });

  // ---- Deterministic unit tests (the visible harness) ----------------------

  test('A→A dedupe: same chord does not spawn a second card', () {
    var b = <ChordEvent>[];
    b = reduceChordTimeline(b, _frame('C'));
    b = reduceChordTimeline(b, _frame('C'));
    expect(b.length, 1);
    expect(b.single.chord.label, 'C');
  });

  test('A→A with a strum updates the last card in place', () {
    var b = <ChordEvent>[];
    b = reduceChordTimeline(b, _frame('C'));
    final firstSeq = b.single.seq;
    b = reduceChordTimeline(
      b,
      _frame('C',
          strum: const Strum(direction: StrumDirection.up, confidence: 0.9)),
    );
    expect(b.length, 1, reason: 'still one card');
    expect(b.single.seq, firstSeq, reason: 'identity preserved');
    expect(b.single.direction, StrumDirection.up);
    expect(b.single.confidence, 0.9);
  });

  test('held chord with an UNCHANGED strum returns the same list reference '
      '(no per-frame reallocation)', () {
    var b = <ChordEvent>[];
    b = reduceChordTimeline(
      b,
      _frame('C',
          strum: const Strum(direction: StrumDirection.down, confidence: 0.8)),
    );
    // `latestStrum` is sticky: the very same frame arrives again next tick.
    final same = reduceChordTimeline(
      b,
      _frame('C',
          strum: const Strum(direction: StrumDirection.down, confidence: 0.8)),
    );
    expect(identical(same, b), isTrue,
        reason: 'unchanged held chord must not allocate a new buffer');
    // A genuinely new strum on the same chord still updates in place.
    final updated = reduceChordTimeline(
      b,
      _frame('C',
          strum: const Strum(direction: StrumDirection.up, confidence: 0.4)),
    );
    expect(identical(updated, b), isFalse);
    expect(updated.single.direction, StrumDirection.up);
    expect(updated.single.confidence, 0.4);
  });

  test('A→B→A gives 3 distinct cards (A recurrence is a NEW card)', () {
    var b = <ChordEvent>[];
    b = reduceChordTimeline(b, _frame('A'));
    b = reduceChordTimeline(b, _frame('B'));
    b = reduceChordTimeline(b, _frame('A'));
    expect(b.map((e) => e.chord.label).toList(), ['A', 'B', 'A']);
    expect(b.map((e) => e.seq).toList(), [0, 1, 2]);
  });

  test('cap trimming drops the oldest, keeps newest last', () {
    var b = <ChordEvent>[];
    // Distinct consecutive labels so each appends a card.
    const seq = ['C', 'G', 'Am', 'F', 'D', 'Em', 'C', 'G'];
    for (final l in seq) {
      b = reduceChordTimeline(b, _frame(l), cap: 6);
    }
    expect(b.length, 6);
    // The two oldest ('C','G' at seq 0,1) fell off the front.
    expect(b.first.seq, 2);
    expect(b.last.seq, 7);
    expect(b.map((e) => e.chord.label).toList(),
        ['Am', 'F', 'D', 'Em', 'C', 'G']);
  });

  test('timeSec falls back to engineTimeSec when no strum time', () {
    var b = <ChordEvent>[];
    b = reduceChordTimeline(
      b,
      _frame('C', latestStrumTime: -1, engineTimeSec: 12.5),
    );
    expect(b.single.timeSec, 12.5);
    b = reduceChordTimeline(
      b,
      _frame('G', latestStrumTime: 3.2, engineTimeSec: 99),
    );
    expect(b.last.timeSec, 3.2, reason: 'strum time preferred when present');
  });

  test('confidence falls back to frame.confidence when no strum', () {
    var b = <ChordEvent>[];
    // No strum → frame.confidence is 0 (getter derives from latestStrum).
    b = reduceChordTimeline(b, _frame('C'));
    expect(b.single.confidence, 0);
    expect(b.single.direction, isNull);
  });

  test('idle (null current) leaves the buffer identical instance', () {
    final b = <ChordEvent>[];
    final out = reduceChordTimeline(b, _frame(null));
    expect(identical(out, b), isTrue);
  });
}
