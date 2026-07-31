import 'package:meta/meta.dart';

import '../../../core/foundation/app_result.dart';
import '../domain/model/practice_observation.dart';
import '../domain/model/practice_validation.dart';

/// Converts live detector frames into practice-domain observations.
abstract interface class PracticeObservationGateway {
  Stream<PracticeObservation> get observations;

  Future<AppResult<void>> start({required PracticeObservationConfig config});

  void setExpectedChord(String? chord);

  Future<AppResult<void>> stop();

  Future<void> dispose();
}

/// Thresholds and sampling durations used by a practice observation gateway.
@immutable
final class PracticeObservationConfig {
  const PracticeObservationConfig({
    this.strumMinConfidence = 0.55,
    this.chordMinConfidence = 0.60,
    this.chordStableDuration = const Duration(milliseconds: 180),
    this.maxFrameDeliveryLag = const Duration(milliseconds: 500),
  });

  final double strumMinConfidence;
  final double chordMinConfidence;
  final Duration chordStableDuration;
  final Duration maxFrameDeliveryLag;

  /// Returns every independent configuration problem for this gateway.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (!_confidenceIsValid(strumMinConfidence) ||
        !_confidenceIsValid(chordMinConfidence)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.observationConfigConfidenceOutOfRange,
          message:
              'Observation confidence thresholds must be finite and between zero and one.',
        ),
      );
    }
    if (chordStableDuration <= Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code:
              PracticeValidationCode.observationConfigStableDurationNonPositive,
          message: 'Chord stable duration must be strictly positive.',
        ),
      );
    }
    if (maxFrameDeliveryLag <= Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.observationConfigMaxLagNonPositive,
          message: 'Maximum frame delivery lag must be strictly positive.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  static bool _confidenceIsValid(double value) =>
      value.isFinite && value >= 0 && value <= 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeObservationConfig &&
          other.strumMinConfidence == strumMinConfidence &&
          other.chordMinConfidence == chordMinConfidence &&
          other.chordStableDuration == chordStableDuration &&
          other.maxFrameDeliveryLag == maxFrameDeliveryLag;

  @override
  int get hashCode => Object.hash(
    strumMinConfidence,
    chordMinConfidence,
    chordStableDuration,
    maxFrameDeliveryLag,
  );
}
