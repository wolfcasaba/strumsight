/// Crediting what the learner actually strummed to the grid that asked for it.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md`
/// §2 (the honesty rules) and §3 (the rhythm pillar).
///
/// Three decisions in here are forks where the easy choice would have taught
/// something false, so each is stated rather than buried:
///
/// 1. **Pairing uses TIME only, never direction.** Which expected slot a stroke
///    belongs to is a timing question. If the matcher were allowed to prefer
///    pairings that agree on direction, a learner who strummed up-then-down
///    where the pattern asked down-then-up would be silently re-paired into two
///    correct strokes. That flatters instead of teaching. Pair by time, then
///    judge direction — the same order the engine's own measured `directionF1`
///    metric uses.
/// 2. **Confirmed evidence is matched FIRST.** Rules 1 and 2: an unconfirmed
///    detection earns nothing and supports no negative claim, so it must never
///    displace a confirmed one. Were a single stroke to surface as one confirmed
///    and one unconfirmed detection, nearest-first alone could pick the
///    unconfirmed twin and throw away the credit the learner earned.
/// 3. **A missed slot subtracts nothing.** Silence is absence of evidence, not
///    evidence of a wrong stroke (§3). It therefore leaves [directionAccuracy]
///    untouched and shows up only in [RhythmAttempt.coverage] — which is also
///    why coverage has to exist: without it, playing one stroke of eight
///    perfectly would read as a flawless attempt.
///
/// Matching is the shared maximum-cardinality helper, for the reason
/// `docs/LESSONS.md` L269 gives: the greedy nearest-free-pair strategy
/// measurably under-counts matches, and here an under-count would tell a learner
/// they missed a stroke they actually played.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6/§10).
library;

import 'package:meta/meta.dart';

import '../../../core/music/onset_matching.dart';
import '../../../core/music/strum.dart';
import 'rhythm_grid.dart';

/// The onset window a stroke may land in and still count as on time, in
/// microseconds.
///
/// This is [onsetToleranceMsPrimary] — the window the recogniser is MEASURED
/// against — and not a second window chosen for the curriculum. The app has one
/// notion of "in time", and it is the one with evidence behind it.
const int rhythmToleranceUs = onsetToleranceMsPrimary * 1000;

/// How much of the notated pattern must produce confirmed evidence before an
/// attempt is allowed to claim anything.
///
/// **A policy choice, not a measured constant** — said plainly because the
/// tolerance above IS measured and the two must not be mistaken for each other.
/// The policy is the majority rule: a verdict about someone's strumming should
/// rest on more than half of the strokes they were asked to play. Below that the
/// honest answer is not a low score but "I could not hear enough of that" —
/// which costs the learner nothing (§2 rule 6) and is shown by the level meter
/// rather than a banner (§2 rule 4).
const double minimumRhythmCoverage = 0.5;

/// One stroke as the recogniser saw it.
@immutable
final class DetectedStroke {
  const DetectedStroke({
    required this.atUs,
    required this.direction,
    required this.isConfirmed,
  });

  /// Onset time in microseconds, on the same clock as the grid.
  final int atUs;

  final StrumDirection direction;

  /// True only when the recognition decision was `confirmed`.
  ///
  /// Everything downstream hangs off this flag: an unconfirmed stroke can
  /// neither earn credit nor support the claim that the learner played the
  /// wrong way (§2 rules 1 and 2).
  final bool isConfirmed;

  @override
  bool operator ==(Object other) =>
      other is DetectedStroke &&
      other.atUs == atUs &&
      other.direction == direction &&
      other.isConfirmed == isConfirmed;

  @override
  int get hashCode => Object.hash(atUs, direction, isConfirmed);
}

/// What happened at one notated slot.
enum RhythmSlotOutcome {
  /// A confirmed stroke landed in time, travelling the way the grid asked.
  credited,

  /// A confirmed stroke landed in time travelling the OTHER way. Reportable —
  /// it is confirmed evidence — and this is the thing only this app can tell a
  /// learner. It still subtracts nothing: a mission cannot fail (§2 rule 6).
  wrongDirection,

  /// Something landed in time but was not confirmed. Says nothing either way.
  unclear,

  /// Nothing landed. Absence of evidence; the remedy is another repetition.
  noEvidence,
}

/// One notated slot's verdict, addressed so a UI can point at it.
@immutable
final class RhythmSlotResult {
  const RhythmSlotResult({
    required this.bar,
    required this.slotIndex,
    required this.expected,
    required this.outcome,
    this.detected,
    this.errorUs,
  });

  final int bar;
  final int slotIndex;

  /// The direction the grid asked for here.
  final StrumDirection expected;

  final RhythmSlotOutcome outcome;

  /// The direction actually played, when a stroke was matched AND confirmed.
  /// Null for [RhythmSlotOutcome.unclear] and [RhythmSlotOutcome.noEvidence],
  /// because naming a direction there would be a claim without evidence.
  final StrumDirection? detected;

  /// Signed timing error in microseconds: positive = played LATE. Null unless a
  /// confirmed stroke was matched here AND the device is calibrated.
  ///
  /// Without a calibration this stays null rather than holding a raw engine
  /// figure: an uncalibrated number would be the device's display↔microphone
  /// skew as much as the learner's playing, and presenting it as theirs would be
  /// a claim with no evidence behind it.
  final int? errorUs;

  @override
  bool operator ==(Object other) =>
      other is RhythmSlotResult &&
      other.bar == bar &&
      other.slotIndex == slotIndex &&
      other.expected == expected &&
      other.outcome == outcome &&
      other.detected == detected &&
      other.errorUs == errorUs;

  @override
  int get hashCode =>
      Object.hash(bar, slotIndex, expected, outcome, detected, errorUs);
}

/// The graded result of one run through a grid.
@immutable
final class RhythmAttempt {
  const RhythmAttempt({
    required this.slots,
    required this.extraConfirmedStrokes,
  });

  /// Every notated (struck) slot of every bar, in time order. Ghost slots are
  /// absent: the grid asked for no sound there, so there is nothing to grade.
  final List<RhythmSlotResult> slots;

  /// Confirmed strokes that belonged to no notated slot — played where the
  /// pattern asked for silence, or too far from anything to credit. Reported,
  /// never subtracted.
  final int extraConfirmedStrokes;

  int get notatedStrokes => slots.length;

  int _count(RhythmSlotOutcome outcome) =>
      slots.where((slot) => slot.outcome == outcome).length;

  int get credited => _count(RhythmSlotOutcome.credited);
  int get wrongDirection => _count(RhythmSlotOutcome.wrongDirection);
  int get unclear => _count(RhythmSlotOutcome.unclear);
  int get noEvidence => _count(RhythmSlotOutcome.noEvidence);

  /// Slots where confirmed evidence exists — the only ones an accuracy may be
  /// computed over.
  int get heard => credited + wrongDirection;

  /// Of the strokes that could be heard, the share travelling the right way.
  ///
  /// Null when nothing was heard: a ratio over zero evidence would be a claim
  /// about a learner who has not been measured (§2 rule 1). Never coerced to 0,
  /// which would read as "you got everything wrong".
  double? get directionAccuracy => heard == 0 ? null : credited / heard;

  /// The share of notated strokes that produced confirmed evidence.
  ///
  /// This is what stops a thin attempt from looking perfect: two clean strokes
  /// out of sixteen give a [directionAccuracy] of 1.0 and a coverage of 0.125.
  double get coverage => notatedStrokes == 0 ? 0 : heard / notatedStrokes;

  /// Whether this attempt may claim anything at all.
  ///
  /// False is not a failure — it is the app declining to judge on too little
  /// evidence. See [minimumRhythmCoverage].
  bool get isReportable => coverage >= minimumRhythmCoverage;

  /// Signed timing errors of the heard slots, in microseconds, in time order.
  /// Positive = late. Empty when uncalibrated or when nothing was heard.
  List<int> get timingErrorsUs => [
    for (final slot in slots)
      if (slot.errorUs != null) slot.errorUs!,
  ];

  /// How far off the heard strokes were on average, ignoring direction of error.
  /// Null when there is nothing to average — uncalibrated, or nothing heard.
  double? get meanAbsTimingErrorUs {
    final errors = timingErrorsUs;
    if (errors.isEmpty) return null;
    return errors.fold<int>(0, (a, e) => a + e.abs()) / errors.length;
  }

  /// The learner's systematic BIAS: positive = consistently late.
  ///
  /// Reported separately from [meanAbsTimingErrorUs] because the two say
  /// different things to a learner and call for different practice. Being
  /// steadily 40 ms late is a lag — one thing to fix, and the pattern is
  /// otherwise even. Being scattered ±40 ms with no bias is unsteadiness, which
  /// is a different problem entirely. A single "accuracy" number would hide
  /// which one they have.
  double? get timingBiasUs {
    final errors = timingErrorsUs;
    if (errors.isEmpty) return null;
    return errors.fold<int>(0, (a, e) => a + e) / errors.length;
  }

  /// Whether a timing claim is allowed at all: the device must be calibrated
  /// AND the attempt must clear the coverage floor.
  bool get hasTimingReport => timingErrorsUs.isNotEmpty && isReportable;

  /// Whether the error is mostly a steady LAG/RUSH or mostly scatter.
  ///
  /// The threshold is half the mean absolute error: when the bias accounts for
  /// at least half of it, the strokes are mostly on one side of the beat and the
  /// learner has a lag to correct. Below that they are on both sides and the
  /// problem is steadiness. Null when no timing may be claimed.
  ///
  /// This exists because the advice differs: "you are playing behind the beat"
  /// is actionable in a way that "your timing is 30 ms out" is not.
  RhythmTimingShape? get timingShape {
    if (!hasTimingReport) return null;
    final bias = timingBiasUs!;
    final spread = meanAbsTimingErrorUs!;
    if (spread == 0) return RhythmTimingShape.scattered;
    if (bias.abs() * 2 < spread) return RhythmTimingShape.scattered;
    return bias > 0
        ? RhythmTimingShape.systematicLate
        : RhythmTimingShape.systematicEarly;
  }
}

/// Whether a timing error is a steady lag, a steady rush, or scatter.
enum RhythmTimingShape { systematicLate, systematicEarly, scattered }

/// Grades [strokes] against [bars] repetitions of [grid] at [bpm].
///
/// [startUs] is when bar 0 slot 0 is due, on the same clock as
/// [DetectedStroke.atUs]. [toleranceUs] defaults to the measured window and is
/// a parameter only so a test can show the boundary; shipping code should leave
/// it alone.
///
/// [timingCalibrationUs] is this device's measured pendulum↔strum offset, and it
/// does TWO things — both of them necessary:
///
/// 1. It is subtracted from every stroke BEFORE matching. This is not a
///    cosmetic correction to a displayed number: an uncorrected skew larger than
///    [toleranceUs] pairs with nothing at all, so coverage collapses and the
///    screen reports "I could not hear enough" to a learner who in fact played
///    the pattern. Direction accuracy and coverage therefore depend on it too.
/// 2. Its presence is what PERMITS a timing claim. When it is null every
///    [RhythmSlotResult.errorUs] stays null and the attempt reports no timing,
///    because an uncalibrated error figure is the device's skew mixed with the
///    learner's playing and cannot honestly be attributed to them (§2 rule 1).
RhythmAttempt gradeRhythm(
  RhythmGrid grid, {
  required double bpm,
  required int bars,
  required List<DetectedStroke> strokes,
  int startUs = 0,
  int toleranceUs = rhythmToleranceUs,
  int? timingCalibrationUs,
}) {
  if (bars <= 0) {
    throw ArgumentError.value(
      bars,
      'bars',
      'an attempt needs at least one bar',
    );
  }

  // The notated slots, in time order — the ghosts are not graded.
  final expected = <({int bar, RhythmSlot slot, int atUs})>[];
  for (var bar = 0; bar < bars; bar++) {
    for (final slot in grid.slots) {
      if (!slot.isStruck) continue;
      expected.add((
        bar: bar,
        slot: slot,
        atUs: startUs + grid.onsetUs(bar: bar, slotIndex: slot.index, bpm: bpm),
      ));
    }
  }

  // The calibration shifts the learner's strokes onto the grid's own timeline.
  // Zero when uncalibrated, so the arithmetic is identical to before and only
  // the REPORTING differs.
  final shiftUs = timingCalibrationUs ?? 0;
  final corrected = [
    for (final stroke in strokes)
      DetectedStroke(
        atUs: stroke.atUs - shiftUs,
        direction: stroke.direction,
        isConfirmed: stroke.isConfirmed,
      ),
  ];
  final confirmed = [...corrected.where((stroke) => stroke.isConfirmed)]
    ..sort((a, b) => a.atUs.compareTo(b.atUs));
  final unconfirmed = [...corrected.where((stroke) => !stroke.isConfirmed)]
    ..sort((a, b) => a.atUs.compareTo(b.atUs));
  final expectedTimes = [for (final slot in expected) slot.atUs];

  // Pass 1 — confirmed evidence, so it can never be displaced by a detection
  // that says nothing (decision 2 in the library comment).
  final confirmedMatch = matchWithinTolerance(
    expected: expectedTimes,
    detected: [for (final stroke in confirmed) stroke.atUs],
    tolerance: toleranceUs,
  );
  final strokeOfSlot = List<DetectedStroke?>.filled(expected.length, null);
  var matchedConfirmed = 0;
  for (var j = 0; j < confirmedMatch.length; j++) {
    final i = confirmedMatch[j];
    if (i != -1) {
      strokeOfSlot[i] = confirmed[j];
      matchedConfirmed++;
    }
  }

  // Pass 2 — the slots still without evidence may only become `unclear`, so
  // the unconfirmed detections are matched against those alone.
  final openSlots = <int>[
    for (var i = 0; i < expected.length; i++)
      if (strokeOfSlot[i] == null) i,
  ];
  final unclearMatch = matchWithinTolerance(
    expected: [for (final i in openSlots) expectedTimes[i]],
    detected: [for (final stroke in unconfirmed) stroke.atUs],
    tolerance: toleranceUs,
  );
  final isUnclear = List<bool>.filled(expected.length, false);
  for (final i in unclearMatch) {
    if (i != -1) isUnclear[openSlots[i]] = true;
  }

  return RhythmAttempt(
    slots: List<RhythmSlotResult>.unmodifiable([
      for (var i = 0; i < expected.length; i++)
        _resultFor(
          expected[i],
          strokeOfSlot[i],
          isUnclear[i],
          reportTiming: timingCalibrationUs != null,
        ),
    ]),
    extraConfirmedStrokes: confirmed.length - matchedConfirmed,
  );
}

RhythmSlotResult _resultFor(
  ({int bar, RhythmSlot slot, int atUs}) expected,
  DetectedStroke? matched,
  bool isUnclear, {
  required bool reportTiming,
}) {
  final RhythmSlotOutcome outcome;
  if (matched == null) {
    outcome = isUnclear
        ? RhythmSlotOutcome.unclear
        : RhythmSlotOutcome.noEvidence;
  } else if (matched.direction == expected.slot.direction) {
    outcome = RhythmSlotOutcome.credited;
  } else {
    outcome = RhythmSlotOutcome.wrongDirection;
  }
  return RhythmSlotResult(
    bar: expected.bar,
    slotIndex: expected.slot.index,
    expected: expected.slot.direction,
    outcome: outcome,
    detected: matched?.direction,
    errorUs: (reportTiming && matched != null)
        ? matched.atUs - expected.atUs
        : null,
  );
}
