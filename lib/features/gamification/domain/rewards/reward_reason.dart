/// Stable reason codes for a reward ledger entry.
///
/// Presentation maps these codes to localized copy; the persisted ledger never
/// stores a user-facing sentence.
enum RewardReason {
  activityCompleted,
  qualityBonus,
  streakMilestone,
  achievementUnlocked,
  questCompleted,
}
