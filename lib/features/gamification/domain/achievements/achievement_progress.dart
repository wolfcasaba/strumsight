/// Versioned, monotonic state for one achievement without evaluation or storage.
final class AchievementProgress {
  factory AchievementProgress({
    required String achievementId,
    required int catalogVersion,
    required num value,
    DateTime? completedAt,
    String? rewardLedgerEntryId,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(achievementId)) {
      throw ArgumentError.value(
        achievementId,
        'achievementId',
        'must be lower snake case',
      );
    }
    if (catalogVersion < 1) {
      throw ArgumentError.value(
        catalogVersion,
        'catalogVersion',
        'must be positive',
      );
    }
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must not be negative');
    }
    if (rewardLedgerEntryId != null && completedAt == null) {
      throw ArgumentError.value(
        rewardLedgerEntryId,
        'rewardLedgerEntryId',
        'requires completedAt',
      );
    }
    return AchievementProgress._(
      achievementId: achievementId,
      catalogVersion: catalogVersion,
      value: value,
      completedAt: completedAt,
      rewardLedgerEntryId: rewardLedgerEntryId,
    );
  }

  const AchievementProgress._({
    required this.achievementId,
    required this.catalogVersion,
    required this.value,
    required this.completedAt,
    required this.rewardLedgerEntryId,
  });

  final String achievementId;
  final int catalogVersion;
  final num value;
  final DateTime? completedAt;
  final String? rewardLedgerEntryId;

  /// Returns a new state and prevents a future evaluator from decreasing progress.
  AchievementProgress advanceTo({
    required num value,
    DateTime? completedAt,
    String? rewardLedgerEntryId,
  }) {
    if (value < this.value) {
      throw ArgumentError.value(value, 'value', 'must not decrease progress');
    }
    return AchievementProgress(
      achievementId: achievementId,
      catalogVersion: catalogVersion,
      value: value,
      completedAt: completedAt ?? this.completedAt,
      rewardLedgerEntryId: rewardLedgerEntryId ?? this.rewardLedgerEntryId,
    );
  }
}
