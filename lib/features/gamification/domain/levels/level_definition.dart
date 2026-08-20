/// Immutable definition for one XP level in a [LevelCurve].
final class LevelDefinition {
  factory LevelDefinition({
    required int number,
    required int levelThreshold,
    required String titleKey,
  }) {
    if (number < 1) {
      throw ArgumentError.value(number, 'number', 'must be positive');
    }
    if (levelThreshold < 0) {
      throw ArgumentError.value(
        levelThreshold,
        'levelThreshold',
        'must not be negative',
      );
    }
    if (titleKey.trim().isEmpty) {
      throw ArgumentError.value(titleKey, 'titleKey', 'must not be blank');
    }
    return LevelDefinition._(
      number: number,
      levelThreshold: levelThreshold,
      titleKey: titleKey,
    );
  }

  const LevelDefinition._({
    required this.number,
    required this.levelThreshold,
    required this.titleKey,
  });

  /// Stable, positive ordinal used by profile and celebration consumers.
  final int number;

  /// Inclusive total-XP boundary at which this level is reached.
  final int levelThreshold;

  /// Localization key; display text stays outside the Flutter-free domain.
  final String titleKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LevelDefinition &&
          number == other.number &&
          levelThreshold == other.levelThreshold &&
          titleKey == other.titleKey;

  @override
  int get hashCode => Object.hash(number, levelThreshold, titleKey);
}
