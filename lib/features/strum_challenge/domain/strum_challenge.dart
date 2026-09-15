/// The 60-second strum challenge: what is asked, and how a run is scored.
///
/// Why this exists (market research, 2026-09-15): no competitor scores strum
/// DIRECTION, and the most-loved measurable micro-goal in the category is a
/// one-minute drill with a per-day best. StrumSight's unique asset is the
/// down/up detector, so a fixed-pattern, one-minute challenge is the cheapest
/// honest headline differentiator: offline, no account, and never a false
/// "wrong".
///
/// Everything here is derived from the curriculum's shipped rhythm machinery
/// (`RhythmGrid`, `gradeRhythm`) rather than re-implemented: the grid IS the
/// pattern rung's grid, and the score IS `RhythmAttempt.credited`, so the
/// challenge cannot drift from what the course teaches.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6/§10).
library;

import '../../curriculum/public.dart';

/// `D DU UDU` at eighth-note subdivision — the pattern the course ships as
/// its pattern rung (`beginner_course.dart`). The two silent slots are
/// ghosts: the hand keeps travelling through them.
final RhythmGrid strumChallengeGrid = RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.eighth,
  struck: const [true, false, true, true, false, true, true, true],
);

/// The challenge tempo. The same as the course's eighth-note rungs, so a
/// learner who can play the rung can play the challenge.
const double strumChallengeBpm = 80;

/// How long the SCORED part of the run lasts, in seconds. The count-in bar
/// before it is extra.
const int strumChallengeSeconds = 60;

/// Whole bars that fit [strumChallengeSeconds] at [bpm] — rounded UP, so the
/// run is never shorter than the promised minute. 20 bars at 80 BPM in 4/4.
int strumChallengeBars({
  double bpm = strumChallengeBpm,
  int beatsPerBar = 4,
}) {
  final barSeconds = beatsPerBar * 60 / bpm;
  return (strumChallengeSeconds / barSeconds).ceil();
}

/// Bars whose EVERY struck slot was credited — a "full pattern".
///
/// A bar with one stroke the wrong way round is not a pattern the learner
/// played; it is five-sixths of one, and counting it would make the number
/// mean nothing. Silence subtracts nothing here either: a bar with no evidence
/// is simply not full, which is what [RhythmAttempt.credited] already says.
int strumChallengeFullPatterns(RhythmAttempt attempt) {
  final fullByBar = <int, bool>{};
  for (final slot in attempt.slots) {
    final credited = slot.outcome == RhythmSlotOutcome.credited;
    fullByBar[slot.bar] = (fullByBar[slot.bar] ?? true) && credited;
  }
  return fullByBar.values.where((full) => full).length;
}
