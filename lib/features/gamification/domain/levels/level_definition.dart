/// Immutable definition for one XP level in a [LevelCurve].
final class LevelDefinition {
  const LevelDefinition({
    required this.number,
    required this.levelThreshold,
    required this.titleKey,
  }) : assert(number > 0),
       assert(levelThreshold >= 0),
       assert(titleKey != '');

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
