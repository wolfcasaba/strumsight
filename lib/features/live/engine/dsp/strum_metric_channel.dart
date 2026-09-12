import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';

/// One crossing of the strings in the prescribed pattern: which way the hand is
/// travelling, and whether the pattern asks for a sound there.
///
/// Both halves are needed, and conflating them was a real defect in the first
/// version of this file. A slot the pattern leaves silent is NOT a slot without
/// a direction: the strumming hand is a pendulum and does not stop, so it still
/// travels through that crossing — it simply misses the strings. That is
/// `RhythmGrid`'s `StrokeSound.ghost`, documented from the same pedagogy
/// research this channel rests on (`docs/research/
/// strumming-direction-pedagogy-2026-09.md`). So if a learner DOES strike there,
/// the pendulum still predicts which way they were moving.
@immutable
class MetricSlot {
  const MetricSlot({required this.direction, required this.expected});

  /// Which way the hand travels at this crossing. Always known on a grid.
  final StrumDirection direction;

  /// Whether the pattern asks for a STRUCK stroke here. `false` is a ghost
  /// crossing: real hand travel, nothing to hear, nothing the pattern asked for.
  final bool expected;
}

/// The metric channel's verdict for one onset — and the states are kept apart
/// because collapsing them is what makes this class dangerous (see
/// [StrumMetricChannel]).
@immutable
class MetricCall {
  const MetricCall._({
    required this.direction,
    required this.slot,
    required this.offsetSlots,
    required this.expectedHere,
  });

  /// No tempo grid exists, so the channel has nothing to say about any onset.
  /// This is free play without a metronome — a normal mode, not a failure, and
  /// MEASURED to be the only honest answer there: on a grid manufactured from
  /// `TempoTracker` plus a self-anchored bar the channel scores below a constant
  /// "always down" (ADR 0560).
  static const unavailable = MetricCall._(
    direction: null,
    slot: -1,
    offsetSlots: double.nan,
    expectedHere: false,
  );

  /// The direction the hand was travelling at the nearest crossing, or `null`
  /// only when [available] is false. Non-null whenever a grid exists, INCLUDING
  /// on a ghost crossing — see [MetricSlot].
  final StrumDirection? direction;

  /// Index of the nearest crossing, or `-1` when [available] is false.
  final int slot;

  /// How far the onset sat from that crossing's centre, in SLOTS, within
  /// `[-0.5, 0.5]` — negative = early, positive = late. `NaN` when unavailable.
  /// Not a confidence: it is the raw geometric offset, and any mapping from it
  /// to a probability would be a fitted parameter this class deliberately has
  /// none of.
  final double offsetSlots;

  /// Whether the pattern asked for a struck stroke at that crossing. `false`
  /// with [available] true means the learner played where the pattern ghosts —
  /// itself a pattern violation, and a finding for the post-bar review rather
  /// than a reason to doubt [direction].
  final bool expectedHere;

  /// Whether a grid existed at all.
  bool get available => slot >= 0;

  /// Whether the channel names a direction. Equal to [available] on a grid, and
  /// kept as its own name so call sites read as intent rather than arithmetic.
  bool get hasOpinion => available && direction != null;
}

/// The METRIC channel (ADR 0557): the direction the PRESCRIBED pattern puts at
/// this onset's place in the bar.
///
/// Measured (`ml/probe_direction_metric.py`, held-out GuitarSet, unseen player
/// AND unseen tune): this channel reads direction at AUC 0.9797 with ZERO fitted
/// parameters, against the acoustic CRNN's 0.7484 at the 70 ms live deadline. It
/// also has NO deadline — the phase is known at the onset instant, not 70 or
/// 238 ms later, which is why ADR 0551's binding latency constraint dissolves
/// rather than needing to be managed.
///
/// The rule is the nearest crossing of the supplied pattern, wrapping. It is
/// deliberately NOT "an upstroke sits on a sixteenth offbeat": that is one
/// corpus's pattern. A lesson's pattern is whatever its own notation says, and
/// the app knows it — so the map is notation, not a parameter fitted to a corpus
/// (ADR 0557 D3). Measured, a 2-bin eighth-note map scores 0.5426 on GuitarSet's
/// sixteenth-note material, i.e. near chance: using the wrong pattern's map is
/// not a small error, it is no signal at all.
///
/// ## The pendulum is NOT derived here
///
/// `RhythmGrid.pendulumDirection` is the single authority for which way the hand
/// travels at a slot, and it carries the pedagogy sources with it. This class
/// takes [MetricSlot]s already carrying their direction precisely so there is no
/// second implementation of that rule to drift from the first. Callers build the
/// slots with [StrumMetricChannel.crossings], which is also where a quarter-note
/// grid is expanded — see that constructor for why it must be.
///
/// ## What this class must NEVER be used for
///
/// **The direction returned here is the ANSWER KEY.** Reporting it as what the
/// learner played — or letting it flip a confident acoustic call — makes the app
/// confirm the pattern the learner was told to play, whether or not they played
/// it. That is worse than a missing signal, because it is confident, and it is
/// exactly the false teaching the project forbids (ADR 0557 D4).
///
/// **ADR 0562: this class must NOT reach the scoring path at all — not even as a
/// tie-break.** `gradeRhythm` compares a stroke's direction against the GRID's
/// expected direction to produce `RhythmSlotOutcome.wrongDirection`, which its own
/// code calls "the thing only this app can tell a learner". Fold this channel's
/// prescription into `DetectedStroke.direction` and the grader compares the grid
/// to itself: `wrongDirection` collapses and the app tells every learner their
/// strumming hand is perfect. Measured, not feared — on pendulum-violating
/// strokes the fused rule takes accuracy 0.5000 to 0.2500, and those strokes ARE
/// the `wrongDirection` cases, so fusion HALVES detection of the one finding the
/// rhythm pillar exists for.
///
/// The same argument kills the arrow use (ADR 0558 D2 is superseded too): a fused
/// arrow beside an acoustic-only grader would contradict itself on exactly the
/// violating strokes — the learner sees the arrow the pattern asked for, then
/// reads after the bar that they strummed the other way.
///
/// So the rules are:
///
/// 1. **Scoring** takes direction from the ACOUSTIC channel only, with
///    abstention (`RhythmSlotOutcome.unclear`). This channel contributes nothing,
///    in either direction — an earlier version of this comment said it could move
///    the abstention bar, and ADR 0558 D1 then let it flip low-margin calls while
///    claiming the two rules coincided. They did not (ADR 0562 D2).
/// 2. **Disagreement** as the pedagogical output needs nothing from here: the
///    grid plus `wrongDirection` already is it.
/// 3. This class never decides whether a stroke HAPPENED. It says which
///    direction a stroke had, never whether there was one.
///
/// What it is FOR, then: a measurement instrument (the Dart twin of
/// `ml/probe_direction_metric.py`, pinned by a parity fixture), and the candidate
/// basis for choosing which recorded sessions are worth collecting — the ones
/// where the two channels disagree are where the scarce pendulum-violating
/// strokes live (ADR 0562 D5).
///
/// And one hazard that is NOT this class's to fix but must be respected by its
/// callers: a metronome click lands exactly ON the beat, which is exactly where
/// the grid expects a downstroke, and the onset detector hears clicks (MEASURED:
/// 15 reported strums from 16 clicks, `metronome_click_pollution_test.dart`). So
/// this channel would rubber-stamp a click as a confident downstroke. While
/// scoring, the pulse must be HAPTIC — that is a precondition of using this
/// channel, not a convenience (ADR 0560 D4).
@immutable
class StrumMetricChannel {
  const StrumMetricChannel({required this.pattern, required this.beatsPerBar})
    : assert(beatsPerBar > 0, 'a bar needs at least one beat');

  /// One bar of crossings at ANY resolution — 8 for the eighth-note patterns the
  /// app ships today, 16 for sixteenth-note material. This is the lesson's
  /// notation, passed in rather than fitted.
  final List<MetricSlot> pattern;

  /// Beats per bar (4 in 4/4, 3 in 3/4). Only used to turn `bpm` into a bar
  /// length, so the caller's metre and the pattern's length stay independent.
  final int beatsPerBar;

  /// Crossings per beat — 2 for an eighth-note pattern, 4 for sixteenths.
  double get slotsPerBeat => pattern.length / beatsPerBar;

  /// Build a channel from a notated bar, expanding a QUARTER-note grid to the
  /// crossings the hand actually makes.
  ///
  /// [directions] and [struck] are one entry per NOTATED slot, in bar order —
  /// exactly `RhythmGrid.slots`' `direction` and `isStruck`. [slotsPerBeatNotated]
  /// is that grid's own resolution.
  ///
  /// **Why a quarter grid must be expanded, and why getting this wrong would
  /// invert half the answers.** A quarter-note bar notates four downstrokes. The
  /// hand still comes back UP between them — `RhythmGrid.handCrossings` exists
  /// for exactly that, and the class documents the distinction as "what is ASKED
  /// (the slots) versus what the hand DOES". This channel is about what the hand
  /// DOES. Read at slot resolution, a stroke halfway between two beats would land
  /// on the nearest quarter slot and be called DOWN, while the hand was travelling
  /// UP — a confident inversion on precisely the off-beat strokes a learner adds
  /// when they start filling in the pattern.
  ///
  /// A grid already at eighth resolution or finer is taken as given: its notation
  /// already names every crossing.
  factory StrumMetricChannel.crossings({
    required List<StrumDirection> directions,
    required List<bool> struck,
    required int slotsPerBeatNotated,
    int beatsPerBar = 4,
  }) {
    assert(
      directions.length == struck.length,
      'one struck flag per notated slot',
    );
    if (slotsPerBeatNotated >= 2) {
      return StrumMetricChannel(
        beatsPerBar: beatsPerBar,
        pattern: [
          for (var i = 0; i < directions.length; i++)
            MetricSlot(direction: directions[i], expected: struck[i]),
        ],
      );
    }
    // One notated slot per beat: insert the return travel as a ghost crossing,
    // travelling opposite to the notated stroke.
    return StrumMetricChannel(
      beatsPerBar: beatsPerBar,
      pattern: [
        for (var i = 0; i < directions.length; i++) ...[
          MetricSlot(direction: directions[i], expected: struck[i]),
          MetricSlot(direction: _opposite(directions[i]), expected: false),
        ],
      ],
    );
  }

  static StrumDirection _opposite(StrumDirection direction) =>
      direction == StrumDirection.down
      ? StrumDirection.up
      : StrumDirection.down;

  /// The prescribed call for an onset at [onsetTimeSec], given the bar that
  /// started at [barStartSec] and a tempo of [bpm].
  ///
  /// [barStartSec] must come from a grid the APP OWNS — the metronome or lesson
  /// timeline, whose phase is known by construction (`RhythmGrid.onsetUs`). It
  /// must NOT be estimated from the learner's own strokes: measured, a grid
  /// anchored to an arbitrary stroke scores below a constant "always down",
  /// because an origin off by one crossing INVERTS every call on an alternating
  /// pattern (ADR 0560).
  ///
  /// A non-positive [bpm] yields [MetricCall.unavailable] — the channel reports
  /// that it has no grid rather than inventing one.
  MetricCall callAt({
    required double onsetTimeSec,
    required double barStartSec,
    required double bpm,
  }) {
    // An empty pattern prescribes nothing, which is genuinely the same state as
    // having no grid. Checked here rather than asserted in the constructor so the
    // constructor can stay `const` — a const-evaluated `pattern.length` is not
    // available to an initializer assert.
    if (pattern.isEmpty) return MetricCall.unavailable;
    if (!bpm.isFinite || bpm <= 0) return MetricCall.unavailable;
    if (!onsetTimeSec.isFinite || !barStartSec.isFinite) {
      return MetricCall.unavailable;
    }
    final barSec = beatsPerBar * 60.0 / bpm;
    if (barSec <= 0) return MetricCall.unavailable;

    // Wrap FIRST, into [0, 1). Two reasons, both load-bearing: an onset can sit
    // before the bar start (a stroke can arrive early), and the nearest-crossing
    // arithmetic below only matches the Python reference for non-negative inputs
    // — Dart's `round()` breaks ties away from zero while the reference uses
    // `floor(x + 0.5)`, and those differ in sign only for negatives. Wrapping
    // removes the disagreement instead of relying on it never arising.
    var phaseInBar = ((onsetTimeSec - barStartSec) / barSec) % 1.0;
    if (phaseInBar < 0) phaseInBar += 1.0;

    final slots = pattern.length;
    final scaled = phaseInBar * slots;
    final index = scaled.round() % slots;
    return MetricCall._(
      direction: pattern[index].direction,
      slot: index,
      offsetSlots: scaled - scaled.roundToDouble(),
      expectedHere: pattern[index].expected,
    );
  }
}
