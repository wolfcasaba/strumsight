import '../data/reward_ledger_repository.dart';
import '../domain/levels/level_curve.dart';
import '../domain/levels/level_definition.dart';
import '../domain/profile/gamification_profile.dart';
import '../domain/rewards/reward_ledger_entry.dart';

/// Rebuilds the gamification profile solely from append-only ledger entries.
final class ProfileProjector {
  ProfileProjector({
    required this.curve,
    required this.ledger,
    this.pageSize = 100,
  }) {
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be at least one');
    }
  }

  final LevelCurve curve;
  final RewardLedgerRepository ledger;
  final int pageSize;

  /// The deterministic zero-entry profile for this curve.
  GamificationProfile get initialProfile => GamificationProfile(
    schemaVersion: gamificationProfileSchemaVersion,
    totalXp: 0,
    progress: curve.progressForTotalXp(0),
  );

  /// Reads every stable ledger page and derives one profile from its entries.
  Future<ProfileProjection> rebuild() async {
    var projection = ProfileProjection(
      profile: initialProfile,
      crossedLevels: const <LevelDefinition>[],
    );
    final crossedLevels = <LevelDefinition>[];
    String? cursor;

    do {
      final page = ledger.readPage(limit: pageSize, cursor: cursor);
      for (final entry in page.entries) {
        projection = projectIncrementally(
          profile: projection.profile,
          entry: entry,
        );
        crossedLevels.addAll(projection.crossedLevels);
      }
      if (page.nextCursor == cursor) {
        throw StateError('ledger page cursor did not advance');
      }
      cursor = page.nextCursor;
    } while (cursor != null);

    return ProfileProjection(
      profile: projection.profile,
      crossedLevels: crossedLevels,
    );
  }

  /// Applies one immutable ledger entry using the same calculation as rebuild.
  ProfileProjection projectIncrementally({
    required GamificationProfile profile,
    required RewardLedgerEntry entry,
  }) {
    final totalXp = _saturatingAdd(profile.totalXp, entry.totalXp);
    final curveProgress = curve.progressForTotalXp(totalXp);
    final progress =
        curveProgress.currentLevel.number < profile.currentLevel.number
        ? profile.progress
        : curveProgress;
    final nextProfile = GamificationProfile(
      schemaVersion: gamificationProfileSchemaVersion,
      totalXp: totalXp,
      progress: progress,
    );

    return ProfileProjection(
      profile: nextProfile,
      crossedLevels: <LevelDefinition>[
        for (final level in curve.definitions)
          if (level.number > profile.currentLevel.number &&
              level.number <= nextProfile.currentLevel.number)
            level,
      ],
    );
  }

  int _saturatingAdd(int current, int additional) {
    final remaining = LevelCurve.maximumSupportedTotalXp - current;
    return additional >= remaining
        ? LevelCurve.maximumSupportedTotalXp
        : current + additional;
  }
}

/// A profile result together with every level crossed by the supplied entry.
final class ProfileProjection {
  ProfileProjection({
    required this.profile,
    required List<LevelDefinition> crossedLevels,
  }) : crossedLevels = List<LevelDefinition>.unmodifiable(crossedLevels);

  final GamificationProfile profile;
  final List<LevelDefinition> crossedLevels;
}
