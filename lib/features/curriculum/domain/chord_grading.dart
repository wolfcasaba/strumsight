/// Crediting the shape the learner actually held to the bar that asked for it.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2.
/// The sibling of `rhythm_grading.dart`, and deliberately a SEPARATE measurement:
/// direction accuracy and chord accuracy come out of the same run but say
/// different things, and a single blended "accuracy" would hide which one a
/// learner actually needs to work on.
///
/// ## Why the unit is a BAR, not a stroke
///
/// A chord is held, not struck. The decoder needs several frames of a ringing
/// shape to confirm it (30-36 of 43 frames on modelled audio), so asking "which
/// chord was confirmed at the instant of this stroke" would be measuring the
/// decoder's own latency rather than the learner's fingers. The bar is the unit
/// the chord is actually asked for — the cycle changes per bar — so the bar is
/// what gets graded.
///
/// ## Why that still measures a CHANGE
///
/// A change rung alternates bar by bar (`chord.emToAm` asks Em, Am, Em, Am). Both
/// bars cannot be credited without the learner having changed between them, so
/// bar-level chord accuracy is a measurement of the change happening.
///
/// ## Why there is no "your change was N ms late", and it is not a gap
///
/// That score was the obvious next step, and it was MEASURED to be impossible
/// rather than merely deferred. `test/features/live/chord_change_latency_test.dart`
/// feeds the engine changes at instants known by construction and reports how long
/// it takes to follow one:
///
/// ```
/// Em->Am 508 ms   Am->D 1344 ms   D->G 159 ms   G->C 438 ms
/// median 508 ms, mean 612 ms, worst deviation 731 ms
/// ```
///
/// At the course's 70 bpm a beat is 857 ms. So the engine's own lag averages
/// ~0.7 of a beat and SCATTERS by ~0.85 of a beat — on clean modelled audio with
/// instantaneous, perfectly fingered changes. A systematic lag could be subtracted
/// the way the strum path's calibration subtracts device latency; a lag that varies
/// by 731 ms cannot, so any "N ms late" shown to a learner would be mostly decoder
/// noise wearing their name. The app therefore does not score change timing, and
/// says so rather than showing a plausible-looking number.
///
/// The same measurement VINDICATES the bar as the unit: the worst case is 39% of a
/// 3.43 s bar, and the previous shape stops being confirmed 90-368 ms after a
/// change, so bar-level crediting is comfortable where stroke-level crediting would
/// have been measuring the decoder. [minimumChordBarUs] is the floor that keeps it
/// that way.
///
/// ## The honesty rules, same as the rhythm pillar's
///
/// - **Only confirmed decisions count** (§2 rule 1). An unconfirmed decision
///   earns nothing AND supports no negative claim, so it can neither credit a bar
///   nor mark it wrong.
/// - **A bar with no confirmed decision subtracts nothing.** It is absence of
///   evidence, and it shows up only in [ChordAttempt.coverage].
/// - **A confirmed DIFFERENT chord is reported.** It is confirmed evidence, and it
///   is the useful half — "I heard A minor there" is actionable where "wrong" is
///   not. It still subtracts nothing: a mission cannot fail (§2 rule 6).
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6/§10).
library;

import 'package:meta/meta.dart';

import 'rhythm_grading.dart' show minimumRhythmCoverage;

/// How much of the asked chord sequence must produce confirmed evidence before an
/// attempt may claim anything.
///
/// Deliberately THE SAME policy as the rhythm pillar's, written as a reference to
/// it rather than as a second literal so the two can never drift apart: a verdict
/// about someone's playing should rest on more than half of what they were asked
/// to play, and below that the honest answer is "I could not hear enough of that"
/// rather than a low score. Like its sibling it is a POLICY choice, not a measured
/// constant.
const double minimumChordCoverage = minimumRhythmCoverage;

/// The shortest bar a chord may be asked for in, in microseconds.
///
/// MEASURED, not chosen. `test/features/live/chord_change_latency_test.dart` feeds
/// the engine chord changes at instants known by construction and reports how long
/// it takes to FOLLOW one: median 508 ms over the four changes the course teaches,
/// worst case **1344 ms** (Am to D), on clean modelled audio with instantaneous,
/// perfectly fingered changes. A bar shorter than that latency could pass entirely
/// before the engine had followed the change into it, so the bar would read as
/// `noEvidence` or — worse — as the PREVIOUS chord, and a learner who changed on
/// time would be told they played the wrong shape.
///
/// 2.0 s is roughly 1.5x the measured worst case. The shipped rungs sit well above
/// it (3.43 s at 70 bpm, 3.0 s at 80), so this constrains nothing today; it exists
/// so a future rung at a faster tempo or a shorter metre fails loudly at
/// construction instead of quietly scoring the wrong bar.
const int minimumChordBarUs = 2000000;

/// What the recogniser said while one bar was being asked for.
///
/// [isConfirmed] is the only thing that makes this usable as evidence: the live
/// pipeline publishes a decision well before it confirms one, and an unconfirmed
/// label is a guess the app is not allowed to score either way.
@immutable
final class DetectedChord {
  const DetectedChord({
    required this.atUs,
    required this.label,
    required this.isConfirmed,
  });

  /// When the decision was published, in microseconds on the grid's clock.
  final int atUs;

  /// The chord the decoder named, or null when it named none.
  final String? label;

  /// True only when the recognition decision was `confirmed`.
  final bool isConfirmed;

  @override
  bool operator ==(Object other) =>
      other is DetectedChord &&
      other.atUs == atUs &&
      other.label == label &&
      other.isConfirmed == isConfirmed;

  @override
  int get hashCode => Object.hash(atUs, label, isConfirmed);
}

/// What happened in one bar.
enum ChordBarOutcome {
  /// The asked chord was confirmed during the bar.
  credited,

  /// A DIFFERENT chord was confirmed, and no confirmation of the asked one.
  /// Reportable, and the useful half: it names what was heard instead.
  wrongChord,

  /// Nothing was confirmed. Absence of evidence; the remedy is another bar.
  noEvidence,
}

/// One bar's verdict, addressed so a UI can point at it.
@immutable
final class ChordBarResult {
  const ChordBarResult({
    required this.bar,
    required this.expected,
    required this.outcome,
    this.heardInstead,
  });

  final int bar;

  /// The chord the cycle asked for in this bar.
  final String expected;

  final ChordBarOutcome outcome;

  /// The chord confirmed instead, for [ChordBarOutcome.wrongChord] only. Null
  /// otherwise, because naming one without a confirmation would be a claim with
  /// no evidence.
  final String? heardInstead;

  @override
  bool operator ==(Object other) =>
      other is ChordBarResult &&
      other.bar == bar &&
      other.expected == expected &&
      other.outcome == outcome &&
      other.heardInstead == heardInstead;

  @override
  int get hashCode => Object.hash(bar, expected, outcome, heardInstead);
}

/// The graded chord result of one run.
@immutable
final class ChordAttempt {
  const ChordAttempt({required this.bars});

  /// Every bar of the attempt, in order.
  final List<ChordBarResult> bars;

  int get askedBars => bars.length;

  int _count(ChordBarOutcome outcome) =>
      bars.where((bar) => bar.outcome == outcome).length;

  int get credited => _count(ChordBarOutcome.credited);
  int get wrongChord => _count(ChordBarOutcome.wrongChord);
  int get noEvidence => _count(ChordBarOutcome.noEvidence);

  /// Bars where a chord was confirmed — the only ones an accuracy may be
  /// computed over.
  int get heard => credited + wrongChord;

  /// Of the bars a chord could be heard in, the share holding the asked one.
  ///
  /// Null when nothing was heard: a ratio over zero evidence would be a claim
  /// about an unmeasured learner. Never coerced to 0, which would read as "you
  /// got everything wrong".
  double? get accuracy => heard == 0 ? null : credited / heard;

  /// The share of asked bars that produced confirmed evidence.
  double get coverage => askedBars == 0 ? 0 : heard / askedBars;

  /// Whether this attempt may claim anything at all.
  ///
  /// False is not a failure — it is the app declining to judge on too little
  /// evidence. See [minimumChordCoverage].
  bool get isReportable => coverage >= minimumChordCoverage;

  /// The chords confirmed in place of the asked ones, in bar order.
  ///
  /// This is what a surface can say back to the learner: naming the shape the
  /// recogniser actually heard is actionable, where "wrong chord" is not.
  List<String> get heardInstead => [
    for (final bar in bars)
      if (bar.heardInstead != null) bar.heardInstead!,
  ];
}

/// Grades [detections] against [bars] bars of [cycle] at [bpm].
///
/// [cycle] repeats: bar `n` asks `cycle[n % cycle.length]`. [startUs] is when bar
/// 0 begins, on the same clock as [DetectedChord.atUs].
///
/// A detection counts towards a bar when it falls inside that bar's own span. The
/// span is NOT widened by a tolerance, unlike a stroke's onset window: a stroke is
/// an instant that can be early or late, while a chord is held for the whole bar
/// and a detection from the previous bar is evidence about the PREVIOUS chord.
/// Widening the window is exactly how a learner who never changed would get both
/// bars of a change rung credited.
ChordAttempt gradeChords({
  required List<String> cycle,
  required int bars,
  required double bpm,
  required int beatsPerBar,
  required List<DetectedChord> detections,
  int startUs = 0,
}) {
  if (cycle.isEmpty || bars <= 0) return const ChordAttempt(bars: []);
  final barUs = (60000000 / bpm * beatsPerBar).round();
  final results = <ChordBarResult>[];
  for (var bar = 0; bar < bars; bar++) {
    final expected = cycle[bar % cycle.length];
    final from = startUs + bar * barUs;
    final to = from + barUs;
    // Confirmed only. An unconfirmed decision is not allowed to credit a bar and
    // not allowed to condemn one either.
    final inBar = detections.where(
      (detection) =>
          detection.isConfirmed &&
          detection.label != null &&
          detection.atUs >= from &&
          detection.atUs < to,
    );
    String? other;
    var matched = false;
    for (final detection in inBar) {
      if (detection.label == expected) {
        matched = true;
        break;
      }
      // The FIRST other chord confirmed, not the last: what the learner was
      // holding when the bar began is the more useful thing to name back, and a
      // later one may simply be them correcting themselves.
      other ??= detection.label;
    }
    results.add(
      ChordBarResult(
        bar: bar,
        expected: expected,
        outcome: matched
            ? ChordBarOutcome.credited
            : other != null
            ? ChordBarOutcome.wrongChord
            : ChordBarOutcome.noEvidence,
        heardInstead: matched ? null : other,
      ),
    );
  }
  return ChordAttempt(bars: results);
}
