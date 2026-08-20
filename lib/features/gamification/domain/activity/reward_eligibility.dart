/// Immutable input for the reward-policy decision introduced in E08-R05.
final class RewardEligibility {
  factory RewardEligibility({
    required bool eligible,
    required String reasonCode,
    required Duration validDuration,
    required double? quality,
    required int difficultyBand,
  }) {
    if (reasonCode.trim().isEmpty) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'must not be empty or blank',
      );
    }
    if (validDuration.isNegative) {
      throw ArgumentError.value(
        validDuration,
        'validDuration',
        'must not be negative',
      );
    }
    if (quality != null && (!quality.isFinite || quality < 0 || quality > 1)) {
      throw ArgumentError.value(
        quality,
        'quality',
        'must be finite and in the range [0, 1]',
      );
    }
    if (difficultyBand < 0) {
      throw ArgumentError.value(
        difficultyBand,
        'difficultyBand',
        'must not be negative',
      );
    }
    return RewardEligibility._(
      eligible: eligible,
      reasonCode: reasonCode,
      validDuration: validDuration,
      quality: quality,
      difficultyBand: difficultyBand,
    );
  }

  const RewardEligibility._({
    required this.eligible,
    required this.reasonCode,
    required this.validDuration,
    required this.quality,
    required this.difficultyBand,
  });

  final bool eligible;
  final String reasonCode;
  final Duration validDuration;
  final double? quality;
  final int difficultyBand;

  @override
  bool operator ==(Object other) =>
      other is RewardEligibility &&
      eligible == other.eligible &&
      reasonCode == other.reasonCode &&
      validDuration == other.validDuration &&
      quality == other.quality &&
      difficultyBand == other.difficultyBand;

  @override
  int get hashCode =>
      Object.hash(eligible, reasonCode, validDuration, quality, difficultyBand);
}
