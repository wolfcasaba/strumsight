import 'practice_validation.dart';

/// Practice tempo in beats per minute.
///
/// Tempo is continuous, unlike musical position, so BPM intentionally remains
/// a [double]. Call [validate] at data boundaries; the domain never clamps it.
final class Tempo {
  const Tempo(this.bpm);

  static const double minimumBpm = 30.0;
  static const double maximumBpm = 300.0;

  final double bpm;

  /// Returns every validation problem, or an empty list when this tempo is
  /// valid.
  List<PracticeValidationFailure> validate() {
    if (!bpm.isFinite) {
      return const [
        PracticeValidationFailure(
          code: PracticeValidationCode.tempoBpmNotFinite,
          message: 'Tempo BPM must be finite.',
        ),
      ];
    }
    if (bpm < minimumBpm || bpm > maximumBpm) {
      return const [
        PracticeValidationFailure(
          code: PracticeValidationCode.tempoBpmOutOfRange,
          message: 'Tempo must be between 30.0 and 300.0 BPM.',
        ),
      ];
    }
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tempo && other.bpm == bpm;

  @override
  int get hashCode => bpm.hashCode;

  @override
  String toString() => 'Tempo($bpm BPM)';
}
