import 'package:meta/meta.dart';

import '../../../core/music/strum.dart';
import '../domain/model/practice_verdict.dart';

/// One detected strum, as the presentation layer hears about it the moment
/// the scoring pass has run — the per-stroke feedback the Learn highway and
/// Live already show (chunk 016b P0 "juice"), now on the Practice engine.
///
/// Carries the OBSERVED stroke (what the hand did: direction + confidence)
/// and, when the matcher paired it with a target event, that event's live
/// [verdict]. A stray strum with no target in range has a null verdict —
/// the UI still shows the stroke's direction, just without a timing grade.
/// Never stored on the session state; emitted once per observation.
@immutable
final class PracticeStrumFeedback {
  const PracticeStrumFeedback({
    required this.sequence,
    required this.direction,
    required this.confidence,
    required this.verdict,
  });

  /// The observation's monotonic sequence number.
  final int sequence;

  /// The direction the detector heard.
  final StrumDirection direction;

  /// The detector's 0..1 confidence in that stroke.
  final double confidence;

  /// The live verdict of the target this stroke matched, if any.
  final PracticeVerdict? verdict;

  bool get isDown => direction == StrumDirection.down;

  /// Burst strength for this stroke (0..1): a PERFECT hit bursts biggest,
  /// an early/late one small, an unmatched or missed stroke dimmest — the
  /// same ladder the Learn highway uses, so both surfaces feel alike.
  double get strength => switch (verdict?.timingGrade) {
    TimingGrade.perfect => 1.0,
    TimingGrade.good => 0.72,
    TimingGrade.early || TimingGrade.late => 0.45,
    TimingGrade.missed || TimingGrade.notApplicable || null => 0.35,
  };
}
