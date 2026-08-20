import '../levels/level_curve.dart';
import '../levels/level_definition.dart';

/// Current schema for an in-memory [GamificationProfile] snapshot.
const int gamificationProfileSchemaVersion = 1;

/// Immutable, rebuildable summary derived from the reward ledger.
final class GamificationProfile {
  GamificationProfile({
    required this.schemaVersion,
    required this.totalXp,
    required this.progress,
  }) {
    if (schemaVersion != gamificationProfileSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported',
      );
    }
    if (totalXp < 0) {
      throw ArgumentError.value(totalXp, 'totalXp', 'must not be negative');
    }
  }

  final int schemaVersion;
  final int totalXp;
  final LevelProgress progress;

  /// The highest level derived by the curve; it is never decreased in updates.
  LevelDefinition get currentLevel => progress.currentLevel;

  /// Null at the saturated highest configured level.
  LevelDefinition? get nextLevel => progress.nextLevel;

  int get xpIntoCurrentLevel => progress.xpIntoCurrentLevel;
  int? get xpToNextLevel => progress.xpToNextLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GamificationProfile &&
          schemaVersion == other.schemaVersion &&
          totalXp == other.totalXp &&
          progress == other.progress;

  @override
  int get hashCode => Object.hash(schemaVersion, totalXp, progress);
}
