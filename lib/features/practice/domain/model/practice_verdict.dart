import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';
import 'practice_validation.dart';

/// Timing quality assigned to one target event.
enum TimingGrade {
  perfect('perfect'),
  good('good'),
  early('early'),
  late('late'),
  missed('missed'),
  notApplicable('notApplicable');

  const TimingGrade(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable timing-grade code without guessing a fallback.
TimingGrade? timingGradeFromCode(String code) {
  for (final value in TimingGrade.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Comparison result for a strum-direction target.
enum DirectionOutcome { correct, wrong, notApplicable }

/// Comparison result for a chord target.
enum ChordOutcome { correct, wrong, insufficientData, notApplicable }

/// Stable coaching codes that may be attached to a practice verdict.
abstract final class PracticeCoachingCode {
  static const String early = 'practice.coach.early';
  static const String late = 'practice.coach.late';
  static const String wrongDirection = 'practice.coach.wrong_direction';
  static const String chordNotStable = 'practice.coach.chord_not_stable';
  static const String noSignal = 'practice.coach.no_signal';

  static const Set<String> values = {
    early,
    late,
    wrongDirection,
    chordNotStable,
    noSignal,
  };
}

/// The complete, immutable evaluation of one target event.
@immutable
final class PracticeVerdict {
  const PracticeVerdict({
    required this.targetEventId,
    required this.matchedObservationSequence,
    required this.targetAt,
    required this.observedAt,
    required this.timingOffset,
    required this.timingGrade,
    required this.expectedDirection,
    required this.observedDirection,
    required this.directionOutcome,
    required this.expectedChord,
    required this.observedChord,
    required this.chordOutcome,
    required this.eventScore,
    required this.missReasonCode,
    required this.coachingCode,
  });

  final String targetEventId;
  final int? matchedObservationSequence;
  final Duration targetAt;
  final Duration? observedAt;
  final Duration? timingOffset;
  final TimingGrade timingGrade;
  final StrumDirection? expectedDirection;
  final StrumDirection? observedDirection;
  final DirectionOutcome directionOutcome;
  final String? expectedChord;
  final String? observedChord;
  final ChordOutcome chordOutcome;
  final double eventScore;
  final String? missReasonCode;
  final String? coachingCode;

  /// Returns every independent validation problem for this verdict.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (targetEventId.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.verdictTargetEventIdEmpty,
          message: 'Verdict target event ID cannot be empty.',
        ),
      );
    }
    if (!eventScore.isFinite) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.verdictEventScoreNotFinite,
          message: 'Event score must be finite.',
        ),
      );
    } else if (eventScore < 0 || eventScore > 1) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.verdictEventScoreOutOfRange,
          message: 'Event score must be between zero and one.',
        ),
      );
    }
    if (matchedObservationSequence == null &&
        (observedAt != null ||
            (timingGrade != TimingGrade.missed &&
                timingGrade != TimingGrade.notApplicable))) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.verdictMatchInconsistent,
          message: 'An unmatched verdict cannot carry a matched timing grade.',
        ),
      );
    }
    if (coachingCode != null &&
        !PracticeCoachingCode.values.contains(coachingCode)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.verdictCoachingCodeUnknown,
          message: 'Verdict coaching code is not canonical.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeVerdict &&
          other.targetEventId == targetEventId &&
          other.matchedObservationSequence == matchedObservationSequence &&
          other.targetAt == targetAt &&
          other.observedAt == observedAt &&
          other.timingOffset == timingOffset &&
          other.timingGrade == timingGrade &&
          other.expectedDirection == expectedDirection &&
          other.observedDirection == observedDirection &&
          other.directionOutcome == directionOutcome &&
          other.expectedChord == expectedChord &&
          other.observedChord == observedChord &&
          other.chordOutcome == chordOutcome &&
          other.eventScore == eventScore &&
          other.missReasonCode == missReasonCode &&
          other.coachingCode == coachingCode;

  @override
  int get hashCode => Object.hash(
    targetEventId,
    matchedObservationSequence,
    targetAt,
    observedAt,
    timingOffset,
    timingGrade,
    expectedDirection,
    observedDirection,
    directionOutcome,
    expectedChord,
    observedChord,
    chordOutcome,
    eventScore,
    missReasonCode,
    coachingCode,
  );
}
