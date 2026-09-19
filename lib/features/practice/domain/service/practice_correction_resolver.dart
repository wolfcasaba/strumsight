import '../model/practice_correction.dart';
import '../model/practice_metrics.dart';
import '../model/practice_observation.dart';
import '../model/practice_verdict.dart';
import 'practice_chord_scorer.dart';
import 'practice_event_matcher.dart';

/// Derives the ONE concrete correction to show next (E14-R38, ADR 0551 D6).
///
/// Pure and total: same inputs → same output, no clock, no state, no I/O.
/// That is what lets the session's feedback slot state a correction WITHOUT
/// the reducer gaining a state — the correction is a projection of the
/// scoring pass that already ran, and it disappears again by itself as soon
/// as the next target resolves cleanly.
///
/// The rule, in order:
///  1. Look at the LATEST resolved, non-optional target — the thing that just
///     happened. Earlier problems are history; a correction loop that keeps
///     nagging about a target three bars back is not a loop, it is a log.
///  2. If the recognizer abstained there (`insufficientData` +
///     [PracticeMetricReasonCode.chordUncertain]), the correction is the
///     recognizer's own reject reason. This case is checked FIRST: telling a
///     player "play C" when the app simply could not hear is a false
///     accusation (ADR 0271 §1).
///  3. If the target was missed, or the chord was heard confidently as the
///     wrong one, the correction names the expected chord — or, when the
///     target carries no chord, the target itself.
///  4. Otherwise there is nothing to correct: `null`.
///
/// [matches] and `chord.events` must be index-aligned, which is exactly the
/// invariant `PracticeScoreAggregator` already enforces.
PracticeCorrection? resolvePracticeCorrection({
  required List<PracticeEventMatchResult> matches,
  required PracticeChordScore chord,
  required List<ChordObservation> observations,
}) {
  if (matches.length != chord.events.length) {
    throw ArgumentError(
      'matches and chord.events must be index-aligned '
      '(${matches.length} vs ${chord.events.length}).',
    );
  }
  for (var index = matches.length - 1; index >= 0; index--) {
    final match = matches[index];
    if (!match.isResolved) continue;
    if (match.target.optional && !match.isMatched) continue;
    final chordEvent = chord.events[index];

    if (chordEvent.outcome == ChordOutcome.insufficientData &&
        chordEvent.insufficientReasonCode ==
            PracticeMetricReasonCode.chordUncertain) {
      return PracticeCorrection.recognitionUnclear(
        targetIndex: match.targetIndex,
        rejectReasonCode: _latestRejectReasonCode(observations),
      );
    }

    final expectedChord = match.target.chord;
    final wrongChord =
        chordEvent.outcome == ChordOutcome.wrong ||
        chordEvent.outcome == ChordOutcome.noDetection;
    if (match.isMissed || wrongChord) {
      return expectedChord == null
          ? PracticeCorrection.hitTheTarget(targetIndex: match.targetIndex)
          : PracticeCorrection.playExpectedChord(
              targetIndex: match.targetIndex,
              expectedChord: expectedChord,
            );
    }
    // The latest resolved target is clean — nothing to correct.
    return null;
  }
  return null;
}

/// The newest reason the recognizer gave for standing down, or `null` when it
/// gave none. Deliberately the NEWEST across the whole attempt rather than
/// only inside the target window: a reject reason describes the listening
/// conditions, which persist across targets, and the target window is often
/// too short to contain a rejected frame at all.
String? _latestRejectReasonCode(List<ChordObservation> observations) {
  for (var index = observations.length - 1; index >= 0; index--) {
    final observation = observations[index];
    if (observation.evidence.isEvidence) continue;
    final code = observation.rejectReasonCode;
    if (code != null && code.isNotEmpty) return code;
  }
  return null;
}
