import 'dart:collection';

import 'package:meta/meta.dart';

import '../model/compiled_practice_target.dart';
import '../model/practice_observation.dart';
import '../model/scoring_profile.dart';

/// How one compiled target event has been resolved by the matcher.
enum PracticeTargetResolution { open, matched, missed, optionalUnmatched }

/// The current pairing result for one compiled target event.
@immutable
final class PracticeEventMatchResult {
  const PracticeEventMatchResult._({
    required this.targetIndex,
    required this.target,
    required this.resolution,
    required this.matchedObservationSequence,
    required this.observedAt,
    required this.timingOffset,
  });

  factory PracticeEventMatchResult._open({
    required int targetIndex,
    required CompiledTargetEvent target,
  }) => PracticeEventMatchResult._(
    targetIndex: targetIndex,
    target: target,
    resolution: PracticeTargetResolution.open,
    matchedObservationSequence: null,
    observedAt: null,
    timingOffset: null,
  );

  final int targetIndex;
  final CompiledTargetEvent target;
  final PracticeTargetResolution resolution;
  final int? matchedObservationSequence;

  /// The observation time after subtracting calibrated input latency.
  final Duration? observedAt;

  /// [observedAt] minus the compiled target time; negative means early.
  final Duration? timingOffset;

  bool get isMatched => resolution == PracticeTargetResolution.matched;
  bool get isResolved => resolution != PracticeTargetResolution.open;
  bool get isMissed => resolution == PracticeTargetResolution.missed;

  PracticeEventMatchResult _matched({
    required int sequence,
    required Duration playedAt,
  }) => PracticeEventMatchResult._(
    targetIndex: targetIndex,
    target: target,
    resolution: PracticeTargetResolution.matched,
    matchedObservationSequence: sequence,
    observedAt: playedAt,
    timingOffset: playedAt - target.time,
  );

  PracticeEventMatchResult _unmatched(PracticeTargetResolution resolution) =>
      PracticeEventMatchResult._(
        targetIndex: targetIndex,
        target: target,
        resolution: resolution,
        matchedObservationSequence: null,
        observedAt: null,
        timingOffset: null,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeEventMatchResult &&
          other.targetIndex == targetIndex &&
          other.target == target &&
          other.resolution == resolution &&
          other.matchedObservationSequence == matchedObservationSequence &&
          other.observedAt == observedAt &&
          other.timingOffset == timingOffset;

  @override
  int get hashCode => Object.hash(
    targetIndex,
    target,
    resolution,
    matchedObservationSequence,
    observedAt,
    timingOffset,
  );
}

/// Deterministically pairs strum observations with compiled target events.
///
/// [target.events] must be ordered by nondecreasing time, as guaranteed by
/// `compilePracticeTarget`. Matching uses integer [Duration] values only.
final class PracticeEventMatcher {
  PracticeEventMatcher({
    required this.target,
    required this.scoringProfile,
    required this.inputLatency,
  }) : _results = [
         for (var index = 0; index < target.events.length; index++)
           PracticeEventMatchResult._open(
             targetIndex: index,
             target: target.events[index],
           ),
       ] {
    _resultsView = UnmodifiableListView(_results);
  }

  final CompiledPracticeTarget target;
  final ScoringProfile scoringProfile;
  final Duration inputLatency;

  final List<PracticeEventMatchResult> _results;
  late final UnmodifiableListView<PracticeEventMatchResult> _resultsView;

  var _openCursor = 0;
  Duration? _lastAdvancedPlayedAt;
  var _resolvedTargetCount = 0;
  var _extraStrumCount = 0;
  var _examinedTargetRecordCount = 0;

  /// Live per-target results in the same order as [target.events].
  List<PracticeEventMatchResult> get results => _resultsView;

  int get resolvedTargetCount => _resolvedTargetCount;
  int get extraStrumCount => _extraStrumCount;

  /// Cumulative target-record inspections by matching and closing operations.
  @visibleForTesting
  int get examinedTargetRecordCount => _examinedTargetRecordCount;

  /// Target-result records currently retained by this matcher.
  @visibleForTesting
  int get retainedTargetRecordCount => _results.length;

  /// Pairs [observation] with the nearest eligible open target, if any.
  ///
  /// Returns the newly matched target result. An observation outside every
  /// open match window is counted informationally and returns null. Sequence
  /// values are recorded, not globally deduplicated: the observation gateway
  /// restarts its sequence baseline on every capture start.
  PracticeEventMatchResult? registerStrum(StrumObservation observation) {
    final playedAt = observation.at - inputLatency;
    final matchWindow = scoringProfile.matchWindow;
    final minimumTime = playedAt - matchWindow;
    final maximumTime = playedAt + matchWindow;
    final firstCandidate = _lowerBound(minimumTime);
    PracticeEventMatchResult? bestCandidate;
    int? bestDeltaMicroseconds;

    for (var index = firstCandidate; index < _results.length; index++) {
      final candidate = _examine(index);
      if (candidate.target.time > maximumTime) break;
      if (candidate.isResolved) continue;

      final deltaMicroseconds = (candidate.target.time - playedAt)
          .inMicroseconds
          .abs();
      if (deltaMicroseconds <= matchWindow.inMicroseconds &&
          (bestDeltaMicroseconds == null ||
              deltaMicroseconds < bestDeltaMicroseconds)) {
        bestCandidate = candidate;
        bestDeltaMicroseconds = deltaMicroseconds;
      }
    }

    if (bestCandidate == null) {
      _extraStrumCount++;
      return null;
    }

    final matched = bestCandidate._matched(
      sequence: observation.sequence,
      playedAt: playedAt,
    );
    _results[bestCandidate.targetIndex] = matched;
    _resolvedTargetCount++;
    _advanceOpenCursor();
    return matched;
  }

  /// Closes target windows against [observedAt].
  ///
  /// Input latency is subtracted internally. Non-increasing corrected clock
  /// values are ignored so a closed target can never reopen.
  void advance(Duration observedAt) {
    final playedAt = observedAt - inputLatency;
    final previous = _lastAdvancedPlayedAt;
    if (previous != null && playedAt <= previous) return;
    _lastAdvancedPlayedAt = playedAt;

    while (_openCursor < _results.length) {
      final result = _examine(_openCursor);
      if (result.isResolved) {
        _openCursor++;
        continue;
      }
      if (!(result.target.time + scoringProfile.matchWindow < playedAt)) {
        break;
      }

      _results[_openCursor] = _closeUnmatched(result);
      _resolvedTargetCount++;
      _openCursor++;
    }
  }

  /// Resolves every target that is still open at session end.
  void finalize() {
    for (var index = _openCursor; index < _results.length; index++) {
      final result = _examine(index);
      if (result.isResolved) continue;
      _results[index] = _closeUnmatched(result);
      _resolvedTargetCount++;
    }
    _openCursor = _results.length;
  }

  PracticeEventMatchResult _closeUnmatched(PracticeEventMatchResult result) =>
      result._unmatched(
        result.target.optional
            ? PracticeTargetResolution.optionalUnmatched
            : PracticeTargetResolution.missed,
      );

  int _lowerBound(Duration minimumTime) {
    var low = _openCursor;
    var high = _results.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final result = _examine(middle);
      if (result.target.time < minimumTime) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void _advanceOpenCursor() {
    while (_openCursor < _results.length) {
      if (!_examine(_openCursor).isResolved) return;
      _openCursor++;
    }
  }

  PracticeEventMatchResult _examine(int index) {
    _examinedTargetRecordCount++;
    return _results[index];
  }
}
