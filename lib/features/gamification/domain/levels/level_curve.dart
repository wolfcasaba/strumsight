import 'level_definition.dart';

/// The single source of truth for monotonically increasing XP levels.
final class LevelCurve {
  LevelCurve(List<LevelDefinition> definitions)
    : definitions = List<LevelDefinition>.unmodifiable(definitions) {
    if (this.definitions.isEmpty) {
      throw ArgumentError.value(
        definitions,
        'definitions',
        'must not be empty',
      );
    }

    var previous = this.definitions.first;
    if (previous.number != 1 || previous.levelThreshold != 0) {
      throw ArgumentError.value(
        definitions,
        'definitions',
        'must start with level one at zero XP',
      );
    }

    for (final definition in this.definitions.skip(1)) {
      if (definition.number != previous.number + 1) {
        throw ArgumentError.value(
          definitions,
          'definitions',
          'level numbers must be consecutive',
        );
      }
      if (definition.levelThreshold <= previous.levelThreshold) {
        throw ArgumentError.value(
          definitions,
          'definitions',
          'level thresholds must be strictly increasing',
        );
      }
      previous = definition;
    }
  }

  /// Saturating ceiling for profile accumulation on all supported platforms.
  static const int maximumSupportedTotalXp = 9223372036854775807;

  final List<LevelDefinition> definitions;

  /// Resolves [totalXp] with inclusive thresholds and upper saturation.
  LevelProgress progressForTotalXp(int totalXp) {
    if (totalXp < 0) {
      throw ArgumentError.value(totalXp, 'totalXp', 'must not be negative');
    }
    final saturatedTotalXp = totalXp > maximumSupportedTotalXp
        ? maximumSupportedTotalXp
        : totalXp;

    var currentIndex = 0;
    for (var index = 1; index < definitions.length; index++) {
      if (saturatedTotalXp < definitions[index].levelThreshold) break;
      currentIndex = index;
    }

    final currentLevel = definitions[currentIndex];
    final nextLevel = currentIndex + 1 < definitions.length
        ? definitions[currentIndex + 1]
        : null;
    return LevelProgress(
      currentLevel: currentLevel,
      nextLevel: nextLevel,
      xpIntoCurrentLevel: saturatedTotalXp - currentLevel.levelThreshold,
      xpToNextLevel: nextLevel == null
          ? null
          : nextLevel.levelThreshold - saturatedTotalXp,
    );
  }
}

/// Current and next-level progress derived exclusively from a [LevelCurve].
final class LevelProgress {
  const LevelProgress({
    required this.currentLevel,
    required this.nextLevel,
    required this.xpIntoCurrentLevel,
    required this.xpToNextLevel,
  });

  final LevelDefinition currentLevel;
  final LevelDefinition? nextLevel;
  final int xpIntoCurrentLevel;
  final int? xpToNextLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LevelProgress &&
          currentLevel == other.currentLevel &&
          nextLevel == other.nextLevel &&
          xpIntoCurrentLevel == other.xpIntoCurrentLevel &&
          xpToNextLevel == other.xpToNextLevel;

  @override
  int get hashCode =>
      Object.hash(currentLevel, nextLevel, xpIntoCurrentLevel, xpToNextLevel);
}
