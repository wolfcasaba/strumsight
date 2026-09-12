import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';

/// The metric channel's verdict for one onset — three DISTINCT states, because
/// collapsing them is what turns this class into a lie (see
/// [StrumMetricChannel]).
@immutable
class MetricCall {
  const MetricCall._({
    required this.direction,
    required this.slot,
    required this.offsetSlots,
  });

  /// No tempo grid exists, so the channel has nothing to say about any onset.
  /// This is the state of free play without a metronome — a normal mode, not a
  /// failure.
  static const unavailable = MetricCall._(
    direction: null,
    slot: -1,
    offsetSlots: double.nan,
  );

  /// The prescribed direction at the nearest slot, or `null` when that slot is a
  /// REST — the pattern says nothing should have been played there, so the
  /// channel has NO OPINION about a stroke that happened anyway. (A stroke on a
  /// rest is itself a pattern violation, which is a finding for the post-bar
  /// review, not a direction claim.)
  final StrumDirection? direction;

  /// Index of the nearest slot in the pattern, or `-1` when [available] is false.
  final int slot;

  /// How far the onset sat from that slot's centre, in SLOTS, within
  /// `[-0.5, 0.5]` — negative = early, positive = late. `NaN` when unavailable.
  /// Not a confidence: it is the raw geometric offset, and any mapping from it
  /// to a probability would be a fitted parameter this class deliberately has
  /// none of.
  final double offsetSlots;

  /// Whether a grid existed at all. `available && direction == null` means "on
  /// the grid, but the pattern prescribes a rest here".
  bool get available => slot >= 0;

  /// True only when the channel actually names a direction.
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
/// The rule is the nearest slot of the supplied pattern, wrapping. It is
/// deliberately NOT "an upstroke sits on a sixteenth offbeat": that is one
/// corpus's pattern. A lesson's pattern is whatever its own notation says, and
/// the app knows it — so the map is notation, not a parameter fitted to a
/// corpus (ADR 0557 D3). Measured, a 2-bin eighth-note map scores 0.5426 on
/// GuitarSet's sixteenth-note material, i.e. near chance: using the wrong
/// pattern's map is not a small error, it is no signal at all.
///
/// ## What this class must NEVER be used for
///
/// **The direction returned here is the ANSWER KEY.** Reporting it as what the
/// learner played — or letting it flip a confident acoustic call — makes the app
/// confirm the pattern the learner was told to play, whether or not they played
/// it. That is worse than a missing signal, because it is confident, and it is
/// exactly the false teaching the project forbids (ADR 0557 D4).
///
/// So the binding rule, which the wiring must preserve:
///
/// 1. **Scoring** takes direction from the ACOUSTIC channel only, with
///    abstention. This channel may move the abstention bar; it may never flip
///    the call. Measured at the settled tier, that tie-break rule never loses at
///    ANY learner compliance (`c* = 0.000`) while gaining +0.0723 macro-F1
///    (ADR 0558 D1).
/// 2. **Disagreement** between the two channels, under a confident acoustic
///    call, is itself the pedagogical output — "your strumming hand left the
///    pendulum here" — and belongs in the post-bar review (ADR 0556 D4).
/// 3. This class never decides whether a stroke HAPPENED. It says which
///    direction a stroke had, never whether there was one.
@immutable
class StrumMetricChannel {
  const StrumMetricChannel({required this.pattern, required this.beatsPerBar})
    : assert(beatsPerBar > 0, 'a bar needs at least one beat');

  /// One bar of prescribed slots at ANY subdivision — 8 for the eighth-note
  /// presets the app ships today, 16 for sixteenth-note material. `null` is a
  /// rest. This is the lesson's notation, passed in rather than fitted.
  final List<StrumDirection?> pattern;

  /// Beats per bar (4 in 4/4, 3 in 3/4). Only used to turn [bpm] into a bar
  /// length, so the caller's metre and the pattern's length stay independent.
  final int beatsPerBar;

  /// Slots per beat — 2 for an eighth-note pattern in 4/4, 4 for sixteenths.
  double get slotsPerBeat => pattern.length / beatsPerBar;

  /// The prescribed call for an onset at [onsetTimeSec], given the bar that
  /// started at [barStartSec] and a tempo of [bpm].
  ///
  /// A non-positive [bpm] (the [TempoTracker] before it has seen three onsets,
  /// or after a long gap) yields [MetricCall.unavailable] — the channel reports
  /// that it has no grid rather than inventing one, because a guessed grid would
  /// produce a confident direction from nothing.
  MetricCall callAt({
    required double onsetTimeSec,
    required double barStartSec,
    required double bpm,
  }) {
    // An empty pattern prescribes nothing, which is genuinely the same state as
    // having no grid: the channel has nothing to say. Checked here rather than
    // asserted in the constructor so the constructor can stay `const` — a
    // const-evaluated `pattern.length` is not available to an initializer assert.
    if (pattern.isEmpty) return MetricCall.unavailable;
    if (!bpm.isFinite || bpm <= 0) return MetricCall.unavailable;
    if (!onsetTimeSec.isFinite || !barStartSec.isFinite) {
      return MetricCall.unavailable;
    }
    final barSec = beatsPerBar * 60.0 / bpm;
    if (barSec <= 0) return MetricCall.unavailable;

    // Wrap FIRST, into [0, 1). Two reasons, both load-bearing: an onset can sit
    // before the bar start (the pipeline re-anchors bars, so a stroke can arrive
    // early), and the nearest-slot arithmetic below only matches the Python
    // reference for non-negative inputs — Dart's `round()` breaks ties away from
    // zero while the reference uses `floor(x + 0.5)`, and those differ in sign
    // only for negatives. Wrapping removes the disagreement instead of relying
    // on it never arising.
    var phaseInBar = ((onsetTimeSec - barStartSec) / barSec) % 1.0;
    if (phaseInBar < 0) phaseInBar += 1.0;

    final slots = pattern.length;
    final scaled = phaseInBar * slots;
    final index = scaled.round() % slots;
    return MetricCall._(
      direction: pattern[index],
      slot: index,
      offsetSlots: scaled - scaled.roundToDouble(),
    );
  }
}
