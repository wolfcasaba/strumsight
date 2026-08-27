import '../../gamification/public.dart';

/// One auditable reference behind a mastery claim (A2, §0.0.B/B8):
/// [sessionId] is the dedup key AND the identifier the caller opens on tap.
final class SkillEvidenceReference {
  const SkillEvidenceReference({
    required this.sessionId,
    required this.origin,
    required this.observedAt,
    this.confidence,
  });

  final String sessionId;
  final MasteryEvidenceOrigin origin;
  final DateTime observedAt;
  final double? confidence;
}

/// Deduplicates [evidence] by `sessionId` (the dedup key, §0.0.B/B8),
/// keeping the first-seen sample per session and preserving input order.
List<SkillEvidenceReference> dedupeEvidenceBySession(
  List<MasteryEvidence> evidence,
) {
  final seen = <String>{};
  final result = <SkillEvidenceReference>[];
  for (final sample in evidence) {
    if (!seen.add(sample.sessionId)) continue;
    result.add(
      SkillEvidenceReference(
        sessionId: sample.sessionId,
        origin: sample.origin,
        observedAt: sample.observedAt,
        confidence: sample.confidence,
      ),
    );
  }
  return List.unmodifiable(result);
}

/// A next-step practice suggestion gated by an optional prerequisite
/// milestone (A7, §5.6 — the recommendation must never ignore a missing
/// prerequisite).
final class SkillRecommendation {
  const SkillRecommendation({
    required this.milestoneId,
    required this.title,
    required this.message,
    this.prerequisiteMilestoneId,
    this.prerequisiteTitle,
  });

  final String milestoneId;
  final String title;
  final String message;

  /// Null when this recommendation has no prerequisite.
  final String? prerequisiteMilestoneId;

  /// Already-localised prerequisite title, required whenever
  /// [prerequisiteMilestoneId] is set.
  final String? prerequisiteTitle;
}

/// Whether [recommendation] may be offered given [achievedMilestoneIds] — a
/// recommendation with an unmet prerequisite is NEVER eligible (A7).
bool isRecommendationEligible(
  SkillRecommendation recommendation,
  Set<String> achievedMilestoneIds,
) {
  final prerequisiteId = recommendation.prerequisiteMilestoneId;
  return prerequisiteId == null ||
      achievedMilestoneIds.contains(prerequisiteId);
}

/// Immutable, caller-fed projection for the skill detail screen (UI-50,
/// §0.0.B/B7). [title]/[description] are already localised by the caller —
/// this feature never resolves `MasteryMilestone.titleKey`/`descriptionKey`
/// dynamically.
final class SkillDetailProjection {
  const SkillDetailProjection({
    required this.milestone,
    required this.progress,
    required this.title,
    required this.description,
    required this.evidence,
    required this.achievedMilestoneIds,
    this.recommendation,
  });

  final MasteryMilestone milestone;
  final MasteryProgress progress;
  final String title;
  final String description;
  final List<SkillEvidenceReference> evidence;
  final Set<String> achievedMilestoneIds;
  final SkillRecommendation? recommendation;

  bool get hasEvidence => progress.evidenceSessionCount > 0;

  /// Only meaningful when [hasEvidence] is true (A1, A3).
  double get ratio => progress.progressValue(milestone);
}
