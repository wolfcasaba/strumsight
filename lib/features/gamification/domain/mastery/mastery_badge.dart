import 'mastery_milestone.dart';

/// Privacy-safe, explainable milestone badge. The badge exposes ONLY the
/// measured primitives that founded the achievement (ADR 0388 §6):
/// skill, metric, difficulty, tempo range and contributing session count.
///
/// Deliberately absent (and forbidden in any derived summary): raw audio,
/// session identifiers, free text, and any health/medical framing (brief §6 A7).
final class MasteryBadge {
  factory MasteryBadge({
    required String milestoneId,
    required MasterySkill skill,
    required MasteryMetric metric,
    required MasteryDifficulty difficulty,
    required MasteryTempoRange tempoRange,
    required int contributingSessionCount,
    required DateTime achievedAt,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(milestoneId)) {
      throw ArgumentError.value(
        milestoneId,
        'milestoneId',
        'must be lower snake case',
      );
    }
    if (contributingSessionCount < 2) {
      throw ArgumentError.value(
        contributingSessionCount,
        'contributingSessionCount',
        'must be at least 2 (single-session evidence is not mastery)',
      );
    }
    return MasteryBadge._(
      milestoneId: milestoneId,
      skill: skill,
      metric: metric,
      difficulty: difficulty,
      tempoRange: tempoRange,
      contributingSessionCount: contributingSessionCount,
      achievedAt: achievedAt,
    );
  }

  const MasteryBadge._({
    required this.milestoneId,
    required this.skill,
    required this.metric,
    required this.difficulty,
    required this.tempoRange,
    required this.contributingSessionCount,
    required this.achievedAt,
  });

  final String milestoneId;
  final MasterySkill skill;
  final MasteryMetric metric;
  final MasteryDifficulty difficulty;
  final MasteryTempoRange tempoRange;
  final int contributingSessionCount;
  final DateTime achievedAt;

  /// Returns ONLY the measured primitives that backed the badge (brief §6
  /// A8). The map deliberately omits any raw session-id, audio, or health
  /// field; this is the single supportable summary shape.
  Map<String, Object?> toSummary() => <String, Object?>{
    'milestoneId': milestoneId,
    'skill': skill.code,
    'metric': metric.code,
    'difficulty': difficulty.code,
    'tempoBpmMin': tempoRange.minBpm,
    'tempoBpmMax': tempoRange.maxBpm,
    'contributingSessionCount': contributingSessionCount,
    'achievedAt': achievedAt.toUtc().toIso8601String(),
  };
}
