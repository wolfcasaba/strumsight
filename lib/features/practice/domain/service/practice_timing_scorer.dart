import 'package:meta/meta.dart';

import '../model/practice_metrics.dart';
import '../model/practice_verdict.dart';
import '../model/scoring_profile.dart';
import 'practice_event_matcher.dart';

const int _maximumScorePerMille = 1000;
const int _goodScorePerMille = 800;
const int _matchBoundaryScorePerMille = 350;

/// The timing evaluation of one compiled target event.
@immutable
final class PracticeTimingEventScore {
  const PracticeTimingEventScore._({
    required this.targetIndex,
    required this.grade,
    required this.scorePerMille,
  });

  final int targetIndex;
  final TimingGrade grade;
  final int scorePerMille;

  double get score => scorePerMille / _maximumScorePerMille;
}

/// Event timing evaluations and their attempt-level rhythm statistics.
@immutable
final class PracticeTimingScore {
  PracticeTimingScore._({
    required List<PracticeTimingEventScore> events,
    required this.rhythmPerMille,
    required this.rhythm,
    required this.meanAbsoluteOffset,
    required this.timingBias,
  }) : events = List<PracticeTimingEventScore>.unmodifiable(events);

  final List<PracticeTimingEventScore> events;

  /// Null when [rhythm] is not available.
  final int? rhythmPerMille;

  final MetricValue rhythm;
  final Duration meanAbsoluteOffset;
  final Duration timingBias;
}

/// Scores matcher results with deterministic integer-per-mille arithmetic.
final class PracticeTimingScorer {
  const PracticeTimingScorer();

  PracticeTimingScore score({
    required List<PracticeEventMatchResult> matches,
    required ScoringProfile scoringProfile,
  }) {
    final events = <PracticeTimingEventScore>[
      for (final match in matches) _scoreEvent(match, scoringProfile),
    ];
    final applicableIndexes = <int>[
      for (var index = 0; index < matches.length; index++)
        if (!(matches[index].target.optional && !matches[index].isMatched))
          index,
    ];
    final matchedOffsets = <int>[
      for (final index in applicableIndexes)
        if (matches[index].isMatched)
          _requiredOffset(matches[index]).inMicroseconds,
    ];

    final int? rhythmPerMille;
    final MetricValue rhythm;
    if (applicableIndexes.isEmpty) {
      rhythmPerMille = null;
      rhythm = const MetricNotApplicable();
    } else if (matchedOffsets.isEmpty) {
      rhythmPerMille = null;
      rhythm = const MetricInsufficientData(PracticeMetricReasonCode.noSignal);
    } else {
      final totalPerMille = applicableIndexes.fold<int>(
        0,
        (sum, index) => sum + events[index].scorePerMille,
      );
      rhythmPerMille = totalPerMille ~/ applicableIndexes.length;
      rhythm = MetricAvailable(rhythmPerMille / _maximumScorePerMille);
    }

    final absoluteOffsetTotal = matchedOffsets.fold<int>(
      0,
      (sum, offset) => sum + offset.abs(),
    );
    final signedOffsetTotal = matchedOffsets.fold<int>(
      0,
      (sum, offset) => sum + offset,
    );
    final meanAbsoluteOffset = matchedOffsets.isEmpty
        ? Duration.zero
        : Duration(microseconds: absoluteOffsetTotal ~/ matchedOffsets.length);
    final timingBias = matchedOffsets.isEmpty
        ? Duration.zero
        : Duration(microseconds: signedOffsetTotal ~/ matchedOffsets.length);

    return PracticeTimingScore._(
      events: events,
      rhythmPerMille: rhythmPerMille,
      rhythm: rhythm,
      meanAbsoluteOffset: meanAbsoluteOffset,
      timingBias: timingBias,
    );
  }

  PracticeTimingEventScore _scoreEvent(
    PracticeEventMatchResult match,
    ScoringProfile scoringProfile,
  ) {
    if (match.target.optional && !match.isMatched) {
      return PracticeTimingEventScore._(
        targetIndex: match.targetIndex,
        grade: TimingGrade.notApplicable,
        scorePerMille: 0,
      );
    }
    if (!match.isMatched) {
      return PracticeTimingEventScore._(
        targetIndex: match.targetIndex,
        grade: TimingGrade.missed,
        scorePerMille: 0,
      );
    }

    final offset = _requiredOffset(match);
    final magnitudeMicroseconds = offset.inMicroseconds.abs();
    final perfectMicroseconds = scoringProfile.perfectWindow.inMicroseconds;
    final goodMicroseconds = scoringProfile.goodWindow.inMicroseconds;
    final matchMicroseconds = scoringProfile.matchWindow.inMicroseconds;

    if (magnitudeMicroseconds <= perfectMicroseconds) {
      return PracticeTimingEventScore._(
        targetIndex: match.targetIndex,
        grade: TimingGrade.perfect,
        scorePerMille: _maximumScorePerMille,
      );
    }
    if (magnitudeMicroseconds <= goodMicroseconds) {
      return PracticeTimingEventScore._(
        targetIndex: match.targetIndex,
        grade: TimingGrade.good,
        scorePerMille: _goodScorePerMille,
      );
    }
    if (magnitudeMicroseconds > matchMicroseconds) {
      throw StateError(
        'Matched timing offset exceeds the scoring profile match window.',
      );
    }

    final interpolationSpan = matchMicroseconds - goodMicroseconds;
    final scoreDrop =
        (_goodScorePerMille - _matchBoundaryScorePerMille) *
        (magnitudeMicroseconds - goodMicroseconds) ~/
        interpolationSpan;
    return PracticeTimingEventScore._(
      targetIndex: match.targetIndex,
      grade: offset.isNegative ? TimingGrade.early : TimingGrade.late,
      scorePerMille: _goodScorePerMille - scoreDrop,
    );
  }
}

Duration _requiredOffset(PracticeEventMatchResult match) {
  final offset = match.timingOffset;
  if (offset == null) {
    throw StateError('A matched target must carry a timing offset.');
  }
  return offset;
}
