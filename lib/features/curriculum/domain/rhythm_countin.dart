import 'rhythm_grid.dart';

/// The beats counted before bar 1 of a rhythm exercise.
///
/// ## Why this exists at all
///
/// Asking a learner to strum on beat 1 from silence asks them to invent the
/// pulse. Every metronome-practice method starts the same way: "give yourself a
/// 4 beat count in (or whatever is appropriate for the metre you are playing
/// in)". Without it, the first bar of every attempt is a guess, and a timing
/// score over that bar would be measuring our own missing count-in.
///
/// ## Three decisions, and the research behind each
///
/// **1. ONE bar of the exercise's OWN metre — not always four.** [beats] comes
/// from [RhythmGrid.beatsPerBar], so the 3/4 waltz rung (the taught D-U-U
/// counterexample) counts **three**, not four. A fixed four would teach the
/// learner to feel the waltz as 4/4 and then contradict itself at bar 1 — the
/// app would be the thing playing the wrong metre.
///
/// **2. The count-in is on the BEAT, even for an eighth-note exercise.** The
/// pedagogy is explicit and ordered: first count "one, two, three, four" to the
/// metronome, and only *then* "add the 'and' between each count". The pulse is
/// established first and the subdivision is layered onto it. Counting in at the
/// subdivision would present the eighths AS the pulse, which is precisely the
/// confusion beginners already have when their eighths come out uneven. So the
/// spoken count is [beats] numbers regardless of [RhythmSubdivision].
///
/// **3. The hand is ALREADY swinging during the count-in.** This one comes from
/// this project's own model rather than an outside source: the strumming hand
/// never stops, and a missed stroke is a *ghost* stroke the hand still travels
/// through. A count-in that leaves the pendulum parked would have the learner
/// start their arm from rest on beat 1 — the exact cold start the count-in is
/// there to prevent. Hence [ghostCrossings]: real motion, nothing struck.
///
/// Pure Dart, no Flutter, no I/O (SDD Ch2 §10.1).
final class RhythmCountIn {
  const RhythmCountIn({required this.beats})
    : assert(beats > 0, 'a count-in of no beats is not a count-in');

  /// One bar of [grid]'s own metre.
  factory RhythmCountIn.forGrid(RhythmGrid grid) =>
      RhythmCountIn(beats: grid.beatsPerBar);

  /// How many numbers are spoken. Three in 3/4, four in 4/4.
  final int beats;

  /// Crossings the hand makes during the count-in: two per beat, because the
  /// hand comes back up as well as going down.
  int get crossingCount => beats * crossingsPerBeat;

  /// The hand travels through every one of them and strikes NONE. Handed
  /// straight to the pendulum, so the count-in swings exactly like the exercise
  /// without sounding a note.
  List<bool> get ghostCrossings => List<bool>.filled(crossingCount, false);

  /// Two crossings per beat — down on the number, up on the "and". The same
  /// constant the pendulum uses; stated here so this file stays free of widget
  /// imports.
  static const int crossingsPerBeat = 2;

  Duration durationAt(Duration beatDuration) => beatDuration * beats;

  /// The number to show at [position], or null once the count-in is over.
  ///
  /// [position] is measured from the moment playback started, so the exercise's
  /// own bar 1 begins at `durationAt(beatDuration)`. Counting is one-based
  /// because that is how it is spoken: the first beat is "1", never "0".
  int? numberAt({required Duration position, required Duration beatDuration}) {
    final beatMicros = beatDuration.inMicroseconds;
    if (beatMicros <= 0) return null;
    final micros = position.inMicroseconds;
    if (micros < 0 || micros >= beatMicros * beats) return null;
    return micros ~/ beatMicros + 1;
  }

  /// Where the exercise's own timeline stands, given [position] since playback
  /// started. Negative for the whole count-in, zero exactly at bar 1 beat 1.
  Duration exercisePosition({
    required Duration position,
    required Duration beatDuration,
  }) => position - durationAt(beatDuration);

  /// Whether a stroke heard at [atUs] on the exercise timeline belongs to the
  /// attempt at all.
  ///
  /// Strokes during the count-in are NOT mistakes — the count-in is for
  /// listening, and a learner who strums along while counting has done nothing
  /// wrong. They are dropped rather than graded.
  ///
  /// But the boundary is the tolerance window, not zero: a stroke 30 ms BEFORE
  /// bar 1 beat 1 is beat 1 played slightly early, which is a real attempt with
  /// a real timing error. Cutting at zero would silently delete exactly the
  /// rushed first stroke that a beginner most often plays, and then report
  /// perfect coverage of a bar they actually fluffed.
  static bool countsTowardAttempt({
    required int atUs,
    required int toleranceUs,
  }) => atUs >= -toleranceUs;
}
