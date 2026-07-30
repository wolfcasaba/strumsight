import 'package:meta/meta.dart';

import 'practice_validation.dart';
import 'practice_value_equality.dart';

/// A dimension that can contribute to practice scoring.
enum PracticeScoreDimension {
  completion('completion'),
  rhythm('rhythm'),
  direction('direction'),
  chord('chord'),
  consistency('consistency'),
  overall('overall');

  const PracticeScoreDimension(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable code without guessing a fallback.
PracticeScoreDimension? practiceScoreDimensionFromCode(String code) {
  for (final value in PracticeScoreDimension.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// How observations with no matching target affect rhythm scoring.
enum ExtraStrumPolicy {
  ignore('ignore'),
  countInformationally('countInformationally'),
  penalizeRhythm('penalizeRhythm');

  const ExtraStrumPolicy(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable code without guessing a fallback.
ExtraStrumPolicy? extraStrumPolicyFromCode(String code) {
  for (final value in ExtraStrumPolicy.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Immutable scoring thresholds and weights for one practice definition.
///
/// [weights] must be immutable; pass a const map or an unmodifiable map. Mode
/// compatibility is validated by `PracticeDefinition`, while this type owns
/// numeric integrity.
@immutable
final class ScoringProfile {
  const ScoringProfile({
    required this.id,
    required this.matchWindow,
    required this.perfectWindow,
    required this.goodWindow,
    required this.extraStrumPolicy,
    required this.weights,
    required this.completionThresholdPercent,
    required this.overallThresholdPercent,
  });

  /// Legacy Learn timing and pass-policy parity for strum-pattern practice.
  static const legacyLearnParity = ScoringProfile(
    id: 'legacyLearnParity',
    matchWindow: Duration(milliseconds: 280),
    perfectWindow: Duration(milliseconds: 50),
    goodWindow: Duration(milliseconds: 120),
    extraStrumPolicy: ExtraStrumPolicy.ignore,
    weights: {
      PracticeScoreDimension.rhythm: 55,
      PracticeScoreDimension.direction: 45,
    },
    completionThresholdPercent: 85,
    overallThresholdPercent: 70,
  );

  /// Default scoring for chord-change practice (chord-led, rhythm secondary).
  static const chordChangeDefault = ScoringProfile(
    id: 'chordChangeDefault',
    matchWindow: Duration(milliseconds: 280),
    perfectWindow: Duration(milliseconds: 50),
    goodWindow: Duration(milliseconds: 120),
    extraStrumPolicy: ExtraStrumPolicy.ignore,
    weights: {
      PracticeScoreDimension.chord: 60,
      PracticeScoreDimension.rhythm: 40,
    },
    completionThresholdPercent: 85,
    overallThresholdPercent: 70,
  );

  /// Default scoring for chord-progression practice (rhythm + direction + chord).
  static const chordProgressionDefault = ScoringProfile(
    id: 'chordProgressionDefault',
    matchWindow: Duration(milliseconds: 280),
    perfectWindow: Duration(milliseconds: 50),
    goodWindow: Duration(milliseconds: 120),
    extraStrumPolicy: ExtraStrumPolicy.ignore,
    weights: {
      PracticeScoreDimension.rhythm: 40,
      PracticeScoreDimension.direction: 25,
      PracticeScoreDimension.chord: 35,
    },
    completionThresholdPercent: 85,
    overallThresholdPercent: 70,
  );

  /// Default scoring for rhythm-only practice (no chord or direction scoring).
  static const rhythmOnlyDefault = ScoringProfile(
    id: 'rhythmOnlyDefault',
    matchWindow: Duration(milliseconds: 280),
    perfectWindow: Duration(milliseconds: 50),
    goodWindow: Duration(milliseconds: 120),
    extraStrumPolicy: ExtraStrumPolicy.ignore,
    weights: {PracticeScoreDimension.rhythm: 100},
    completionThresholdPercent: 85,
    overallThresholdPercent: 70,
  );

  /// Open scoring for free-practice mode: no dimensions, no thresholds.
  static const freePracticeOpen = ScoringProfile(
    id: 'freePracticeOpen',
    matchWindow: Duration(milliseconds: 280),
    perfectWindow: Duration(milliseconds: 50),
    goodWindow: Duration(milliseconds: 120),
    extraStrumPolicy: ExtraStrumPolicy.ignore,
    weights: {},
    completionThresholdPercent: 0,
    overallThresholdPercent: 0,
  );

  final String id;
  final Duration matchWindow;
  final Duration perfectWindow;
  final Duration goodWindow;
  final ExtraStrumPolicy extraStrumPolicy;

  /// Integer-percent weights; empty means no overall score.
  final Map<PracticeScoreDimension, int> weights;

  final int completionThresholdPercent;
  final int overallThresholdPercent;

  /// Returns every independent validation problem for this profile.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (id.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.scoringProfileIdEmpty,
          message: 'Scoring profile ID cannot be empty.',
        ),
      );
    }
    if (matchWindow <= Duration.zero ||
        perfectWindow <= Duration.zero ||
        goodWindow <= Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.scoringProfileWindowNonPositive,
          message: 'Scoring windows must be strictly positive.',
        ),
      );
    }
    if (perfectWindow > goodWindow || goodWindow > matchWindow) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.scoringProfileWindowOrdering,
          message: 'Windows must satisfy perfect <= good <= match.',
        ),
      );
    }
    if (weights.values.any((weight) => weight < 0)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.scoringProfileWeightsNegative,
          message: 'Scoring weights cannot be negative.',
        ),
      );
    }
    if (weights.isNotEmpty &&
        weights.values.fold<int>(0, (sum, weight) => sum + weight) != 100) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.scoringProfileWeightsSumNotHundred,
          message: 'Non-empty scoring weights must sum to exactly 100.',
        ),
      );
    }
    if (!_isPercent(completionThresholdPercent) ||
        !_isPercent(overallThresholdPercent)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.scoringProfileThresholdOutOfRange,
          message: 'Scoring thresholds must be between 0 and 100.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  static bool _isPercent(int value) => value >= 0 && value <= 100;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoringProfile &&
          other.id == id &&
          other.matchWindow == matchWindow &&
          other.perfectWindow == perfectWindow &&
          other.goodWindow == goodWindow &&
          other.extraStrumPolicy == extraStrumPolicy &&
          mapEquals(other.weights, weights) &&
          other.completionThresholdPercent == completionThresholdPercent &&
          other.overallThresholdPercent == overallThresholdPercent;

  @override
  int get hashCode => Object.hash(
    id,
    matchWindow,
    perfectWindow,
    goodWindow,
    extraStrumPolicy,
    mapHash(weights),
    completionThresholdPercent,
    overallThresholdPercent,
  );
}
