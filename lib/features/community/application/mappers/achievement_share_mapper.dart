/// Gamification → Community share-artifact mapper (E09-R10, ADR 0404 §D1).
///
/// One mapper file, two factory methods — the brief's allowed
/// `achievement_share_mapper.dart` is the SEAM that translates
/// gamification types into the two distinct artifact subtypes the
/// Community surface exposes:
///
/// * [achievementFromDefinitionAndProgress] → [AchievementArtifact]
/// * [challengeFromDefinitionAndReceipt] → [ChallengeArtifact]
///
/// Both mappers import only the gamification `public.dart` barrel.
/// The challenge mapper translates the existing
/// `LedgerEntrySyncStatus { unverified, verified }` (E08-R28,
/// ADR 0394) into a wire literal — the Community domain does NOT
/// import the gamification enum directly (ADR 0404 §D4, brief §5.3,
/// §A1 measure-matrix).
library;

import 'package:strumsight/features/gamification/public.dart';

import '../../domain/entities/share_artifact.dart';

// ---------------------------------------------------------------------------
// Wire codes mirroring gamification enums — the Community domain
// never imports the gamification enums directly (ADR 0404 §D4, brief §5.3).
// ---------------------------------------------------------------------------

const String _ledgerStatusUnverified = 'unverified';
const String _ledgerStatusVerified = 'verified';

const Map<LedgerEntrySyncStatus, String> _ledgerStatusCodes = {
  LedgerEntrySyncStatus.unverified: _ledgerStatusUnverified,
  LedgerEntrySyncStatus.verified: _ledgerStatusVerified,
};

String _encodeLedgerStatus(LedgerEntrySyncStatus status) {
  final code = _ledgerStatusCodes[status];
  if (code == null) {
    throw ArgumentError.value(
      status,
      'status',
      'is not a known LedgerEntrySyncStatus',
    );
  }
  return code;
}

const Map<AchievementCategory, String> _categoryCodes = {
  AchievementCategory.consistency: 'consistency',
  AchievementCategory.practice: 'practice',
  AchievementCategory.songs: 'songs',
  AchievementCategory.rhythm: 'rhythm',
  AchievementCategory.chords: 'chords',
  AchievementCategory.technique: 'technique',
  AchievementCategory.analysis: 'analysis',
  AchievementCategory.exploration: 'exploration',
  AchievementCategory.personalBest: 'personalBest',
  AchievementCategory.accessibilityNeutral: 'accessibilityNeutral',
};

String _encodeCategory(AchievementCategory category) {
  final code = _categoryCodes[category];
  if (code == null) {
    throw ArgumentError.value(
      category,
      'category',
      'is not a known AchievementCategory',
    );
  }
  return code;
}

const Map<DailyChallengeType, String> _challengeTypeCodes = {
  DailyChallengeType.strumPattern: 'strumPattern',
  DailyChallengeType.chordChange: 'chordChange',
  DailyChallengeType.rhythm: 'rhythm',
  DailyChallengeType.songSection: 'songSection',
  DailyChallengeType.timing: 'timing',
};

String _encodeChallengeType(DailyChallengeType type) {
  final code = _challengeTypeCodes[type];
  if (code == null) {
    throw ArgumentError.value(
      type,
      'type',
      'is not a known DailyChallengeType',
    );
  }
  return code;
}

// ---------------------------------------------------------------------------
// Achievement
// ---------------------------------------------------------------------------

/// Builds an [AchievementArtifact] from an [AchievementDefinition]
/// and the matching [AchievementProgress].
///
/// The `sourceId` is the achievement id (`definition.id`); the
/// `progressValue` is the user's progress against the achievement's
/// objectives, not a fabricated total.
AchievementArtifact achievementFromDefinitionAndProgress(
  AchievementDefinition definition,
  AchievementProgress progress, {
  required DateTime createdAt,
  String sourceId = '',
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  final resolvedSourceId = sourceId.isEmpty ? definition.id : sourceId;
  return AchievementArtifact(
    schemaVersion: schemaVersion,
    sourceId: resolvedSourceId,
    createdAt: createdAt,
    achievementId: definition.id,
    categoryCode: _encodeCategory(definition.category),
    catalogVersion: progress.catalogVersion,
    progressValue: progress.value,
    completedAt: progress.completedAt,
  );
}

// ---------------------------------------------------------------------------
// Challenge
// ---------------------------------------------------------------------------

/// Builds a [ChallengeArtifact] from a [DailyChallengeDefinition] and
/// the matching reward-ledger entry.
///
/// When [receipt] is null (the challenge is in-flight or unattributed)
/// the artifact carries `rewardStatusCode: "unverified"` — the
/// Community surface never shows a challenge as `verified` without a
/// matching `RewardLedgerEntry` (ADR 0404 §D4, brief §5.3).
ChallengeArtifact challengeFromDefinitionAndReceipt(
  DailyChallengeDefinition definition,
  RewardLedgerEntry? receipt,
  LedgerEntrySyncStatus receiptStatus, {
  required DateTime createdAt,
  required String sourceId,
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  final challengeTypeCode = _encodeChallengeType(definition.type);
  // The `name` slot carries the human-readable label — for
  // strum-pattern challenges this is the rotating legacy name, for
  // content-based challenges it's the contentId (per
  // `DailyChallengeDefinition.contentId`).
  final challengeName = definition is StrumPatternChallenge
      ? definition.name
      : (definition.contentId ?? '');
  return ChallengeArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId,
    createdAt: createdAt,
    challengeTypeCode: challengeTypeCode,
    challengeName: challengeName,
    rewardStatusCode: _encodeLedgerStatus(receiptStatus),
    completedAt: receipt?.createdAt,
    rewardXp: receipt?.totalXp,
    ledgerId: receipt?.ledgerId,
  );
}
