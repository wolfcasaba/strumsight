/// The rhythm exercise a mission drills: a grid, a mode, and a tempo.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
/// This is what turns the rhythm pillar from a model into something the shipped
/// ladder actually asks for.
///
/// It deliberately does NOT name a chord. Which chord a rung practises comes
/// from the mission's trained skills and the generator's own choice from the
/// learner's evidence; repeating it here would give the same decision two homes
/// that can disagree.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6/§10).
library;

import 'package:meta/meta.dart';

import 'chord_grading.dart';
import 'rhythm_grid.dart';
import 'rhythm_mode.dart';

/// One rhythm exercise, ready to be played and graded.
@immutable
final class RhythmAssignment {
  /// Throws when the assignment could not mean what it says:
  ///
  /// - a muted-stroke mode whose grid is not actually damped;
  /// - a chord-scoring mode on a damped grid — **a muted string has no chord to
  ///   name**, so scoring one would be scoring a label the engine cannot
  ///   produce (the same reason `G6` and `Cmaj7` are not scored targets);
  /// - a nonsense tempo or repetition count.
  RhythmAssignment({
    required this.mode,
    required this.grid,
    required this.bpm,
    required this.bars,
  }) {
    if (!bpm.isFinite || bpm <= 0) {
      throw ArgumentError.value(
        bpm,
        'bpm',
        'tempo must be finite and positive',
      );
    }
    if (bars <= 0) {
      throw ArgumentError.value(
        bars,
        'bars',
        'an exercise needs at least one bar',
      );
    }
    final anyMuted = grid.slots.any((slot) => slot.muted);
    if (mode == RhythmMode.mutedStrokes && !grid.slots.every((s) => s.muted)) {
      throw ArgumentError.value(
        grid,
        'grid',
        'the muted-strokes mode isolates the right hand, so every slot must be '
            'damped — a half-damped grid teaches neither thing',
      );
    }
    if (mode.scoresChord) {
      // The engine needs TIME to follow a chord change — measured at a 1344 ms
      // worst case. A bar shorter than that can be over before the change has been
      // followed into it, and the bar would then be graded as the previous chord:
      // a learner who changed on time told they played the wrong shape.
      final barUs = (60000000 / bpm * grid.beatsPerBar).round();
      if (barUs < minimumChordBarUs) {
        throw ArgumentError.value(
          bpm,
          'bpm',
          'a chord-scoring bar lasts ${barUs}us, under the measured '
              '${minimumChordBarUs}us the engine needs to follow a chord change '
              '(test/features/live/chord_change_latency_test.dart)',
        );
      }
    }
    if (mode.scoresChord && anyMuted) {
      throw ArgumentError.value(
        grid,
        'grid',
        'a damped string has no chord to name, so a chord-scoring mode cannot '
            'run on a muted grid',
      );
    }
  }

  final RhythmMode mode;
  final RhythmGrid grid;

  /// Tempo in quarter-note beats per minute.
  final double bpm;

  /// How many bars one attempt runs for.
  final int bars;

  /// Strokes the learner is asked to play in one attempt — the denominator
  /// behind `RhythmAttempt.coverage`.
  int get notatedStrokes => grid.struckSlots.length * bars;

  /// When each notated stroke is due, in microseconds from [startUs].
  List<int> onsetsUs({int startUs = 0}) => [
    for (var bar = 0; bar < bars; bar++)
      for (final slot in grid.struckSlots)
        startUs + grid.onsetUs(bar: bar, slotIndex: slot.index, bpm: bpm),
  ];

  @override
  bool operator ==(Object other) =>
      other is RhythmAssignment &&
      other.mode == mode &&
      other.bpm == bpm &&
      other.bars == bars &&
      _sameSlots(other.grid, grid);

  @override
  int get hashCode => Object.hash(mode, bpm, bars, Object.hashAll(grid.slots));

  static bool _sameSlots(RhythmGrid a, RhythmGrid b) =>
      a.subdivision == b.subdivision &&
      a.beatsPerBar == b.beatsPerBar &&
      a.slots.length == b.slots.length &&
      List.generate(
        a.slots.length,
        (i) => a.slots[i] == b.slots[i],
      ).every((same) => same);
}
