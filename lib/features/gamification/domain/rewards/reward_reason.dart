/// Stable, localizable codes that explain a reward decision.
///
/// Presentation maps these codes to localized user-facing text; the ledger
/// deliberately never persists a free-text explanation.
enum RewardReason {
  baseXp,
  qualityBonus,
  masteryUnlocked,
  verifiedEvidence,
  tooShort,
  cancelled,
  failed,
  fatalSignalQuality,
}
