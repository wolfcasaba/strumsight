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

/// A detected chord, or an explicit no-chord observation when [label] is null.
@immutable
final class ChordObservation extends PracticeObservation {
  const ChordObservation({
    required super.at,
    required this.label,
    required this.confidence,
  });

  final String? label;
  final double confidence;

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
          other.confidence == confidence;

  @override
  int get hashCode => Object.hash(at, label, confidence);
}

List<PracticeValidationFailure> _commonObservationFailures(
  Duration at,
  double confidence,
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
