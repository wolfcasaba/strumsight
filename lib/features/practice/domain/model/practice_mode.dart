import 'scoring_profile.dart';

/// The shape of targets and feedback used by one practice definition.
enum PracticeMode {
  strumPattern('strumPattern'),
  chordChanges('chordChanges'),
  chordProgression('chordProgression'),
  rhythmOnly('rhythmOnly'),
  freePractice('freePractice');

  const PracticeMode(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;

  /// Score dimensions that must be weighted by this mode's profile.
  Set<PracticeScoreDimension> get scoredDimensions => switch (this) {
    PracticeMode.strumPattern => const {
      PracticeScoreDimension.rhythm,
      PracticeScoreDimension.direction,
    },
    PracticeMode.chordChanges => const {
      PracticeScoreDimension.chord,
      PracticeScoreDimension.rhythm,
    },
    PracticeMode.chordProgression => const {
      PracticeScoreDimension.rhythm,
      PracticeScoreDimension.direction,
      PracticeScoreDimension.chord,
    },
    PracticeMode.rhythmOnly => const {PracticeScoreDimension.rhythm},
    PracticeMode.freePractice => const {},
  };
}

/// Resolves a stable code without guessing a fallback.
PracticeMode? practiceModeFromCode(String code) {
  for (final value in PracticeMode.values) {
    if (value.code == code) return value;
  }
  return null;
}
