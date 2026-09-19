import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';
import 'practice_event.dart';
import 'practice_validation.dart';

/// One timestamped input observed while a practice session is running.
@immutable
sealed class PracticeObservation {
  const PracticeObservation({required this.at});

  final Duration at;

  /// Returns every independent validation problem for this observation.
  List<PracticeValidationFailure> validate();
}

/// A detected strum with its stable sequence number.
@immutable
final class StrumObservation extends PracticeObservation {
  const StrumObservation({
    required super.at,
    required this.sequence,
    required this.direction,
    required this.confidence,
  });

  final int sequence;
  final StrumDirection direction;
  final double confidence;

  @override
  List<PracticeValidationFailure> validate() {
    final failures = _commonObservationFailures(at, confidence);
    if (sequence < 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.observationSequenceNegative,
          message: 'Strum observation sequence cannot be negative.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrumObservation &&
          other.at == at &&
          other.sequence == sequence &&
          other.direction == direction &&
          other.confidence == confidence;

  @override
  int get hashCode => Object.hash(at, sequence, direction, confidence);
}

/// How much EVIDENCE a [ChordObservation] carries (E14-R38, ADR 0551 D1).
///
/// Before this round every chord observation coming off the Live frame
/// stream was recorded with `confidence: 1.0` — the adapter's own comment
/// admitted the number was invented because `LiveFrame` had no chord
/// confidence field. It has carried a typed `chordDecision` since ADR 0516,
/// so the honest thing to record is not a number but the DECISION STATE:
/// scoring can then treat an unconfident reading as *absence of evidence*
/// instead of as a wrong chord.
enum ChordEvidence {
  /// The recognizer confirmed this reading. Only these observations may
  /// decide whether a chord target was played correctly.
  measured,

  /// The recognizer produced (or was still forming) a reading it does not
  /// stand behind — `candidate`, `provisional`, `uncertain`, `expired`.
  /// NOT evidence: it can neither confirm nor refute the target.
  uncertain,

  /// The recognizer actively refused a reading; the observation's
  /// `rejectReasonCode` names why. Also NOT evidence.
  rejected;

  /// Whether an observation in this state may be scored at all. Exhaustive,
  /// no `default`, so a fourth state cannot silently become evidence.
  bool get isEvidence => switch (this) {
    ChordEvidence.measured => true,
    ChordEvidence.uncertain || ChordEvidence.rejected => false,
  };
}

/// A detected chord, or an explicit no-chord observation when [label] is null.
@immutable
final class ChordObservation extends PracticeObservation {
  const ChordObservation({
    required super.at,
    required this.label,
    required this.confidence,
    this.evidence = ChordEvidence.measured,
    this.rejectReasonCode,
  });

  final String? label;

  /// The recognizer's confidence in [label], or `null` when the producer
  /// does not measure one (E14-R38, ADR 0551 D2).
  ///
  /// `null` means NOT MEASURED — it is never read as "zero confidence" and
  /// never as "certain". The Live adapter passes `null` because the live
  /// chord path has no calibrated chord confidence to report (ADR 0544/0516:
  /// `ChordPrediction.calibratedConfidence` is `null` by design); consumers
  /// that need to know whether the reading counts read [evidence] instead.
  final double? confidence;

  /// Whether this reading counts as evidence at all.
  final ChordEvidence evidence;

  /// The stable name of the recognizer's reject reason (the
  /// `RecognitionRejectReason` enum name), or `null` when there is none.
  ///
  /// Kept as a plain code rather than the Live enum so this domain stays
  /// framework- and feature-independent (the architecture guard's
  /// `sharedDomainMustRemainFrameworkIndependent` rule covers
  /// `lib/features/practice/domain/`). The presentation layer decodes it
  /// back into the typed reason and reuses the SAME localized sentences the
  /// Live uncertainty banner shows.
  final String? rejectReasonCode;

  @override
  List<PracticeValidationFailure> validate() {
    final failures = _commonObservationFailures(at, confidence);
    if (!isCanonicalPracticeChordLabel(label)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.observationChordInvalid,
          message: 'Observed chord must be canonical or null.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordObservation &&
          other.at == at &&
          other.label == label &&
          other.confidence == confidence &&
          other.evidence == evidence &&
          other.rejectReasonCode == rejectReasonCode;

  @override
  int get hashCode =>
      Object.hash(at, label, confidence, evidence, rejectReasonCode);
}

/// Shared per-observation checks. [confidence] is nullable because a chord
/// observation may honestly report "not measured" (ADR 0551 D2); a `null`
/// confidence is neither out of range nor non-finite, so it produces no
/// failure. Strum observations always pass a real number, so their behaviour
/// is unchanged.
List<PracticeValidationFailure> _commonObservationFailures(
  Duration at,
  double? confidence,
) {
  final failures = <PracticeValidationFailure>[];
  if (at < Duration.zero) {
    failures.add(
      const PracticeValidationFailure(
        code: PracticeValidationCode.observationAtNegative,
        message: 'Observation timestamp cannot be negative.',
      ),
    );
  }
  if (confidence == null) {
    return failures;
  }
  if (!confidence.isFinite) {
    failures.add(
      const PracticeValidationFailure(
        code: PracticeValidationCode.observationConfidenceNotFinite,
        message: 'Observation confidence must be finite.',
      ),
    );
  } else if (confidence < 0 || confidence > 1) {
    failures.add(
      const PracticeValidationFailure(
        code: PracticeValidationCode.observationConfidenceOutOfRange,
        message: 'Observation confidence must be between zero and one.',
      ),
    );
  }
  return failures;
}
