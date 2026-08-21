import '../domain/mastery/mastery_badge.dart';
import '../domain/mastery/mastery_milestone.dart';
import '../domain/mastery/mastery_progress.dart';

/// Version stamp for the mastery evaluator. Bump when the gating logic or
/// confidence threshold changes; downstream persistence keys can store the
/// version to detect stale receipts.
const int masteryEvaluatorPolicyVersion = 1;

/// Minimum confidence required for vision/analysis-origin evidence. Matches
/// the VisionClaimGuard positive-claim threshold (`vision_claim_guard.dart`
/// `_minimumConfidence = 0.70`, ADR 0388 §3). Sub-threshold vision/analysis
/// evidence is dropped from the qualifying set entirely (no partial credit).
const double masteryEvidenceConfidenceThreshold = 0.70;

/// Pure, deterministic mastery evaluator. Inputs are explicit and ordered:
/// a milestone definition, an optional previous monotonic progress and an
/// evidence batch. The evaluator does NOT read or write XP, the level ledger
/// or the gamification profile (brief §1, A1).
///
/// Three guarantees:
///
/// 1. **Multi-session.** A single qualifying session is never enough; the
///    milestone's `minEvidenceSessions` is the inclusive completion boundary
///    (brief §6.1 "alatt / rajta / fölött" matrix).
/// 2. **Confidence-gated.** Vision/analysis evidence without a
///    `confidence >= 0.70` is excluded; device evidence is accepted on raw
///    measured values.
/// 3. **Monotonic.** An already-achieved progress is preserved exactly —
///    subsequent weaker evidence never revokes the achievement (brief §6 A5).
final class MasteryEvaluator {
  const MasteryEvaluator();

  /// Evaluates [evidence] against [milestone] and returns the next monotonic
  /// progress. When [previous] is null this is a cold evaluation; when the
  /// caller already holds an achieved progress it MUST be passed here so a
  /// later weak batch does not regress it.
  MasteryProgress evaluate({
    required MasteryMilestone milestone,
    required MasteryProgress? previous,
    required Iterable<MasteryEvidence> evidence,
    required DateTime now,
  }) {
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'now', 'must be UTC');
    }

    final qualifying = _qualifyingSessions(milestone, evidence);
    final distinctCount = qualifying.length;

    if (previous != null && previous.isAchieved && previous.badge != null) {
      // Monotonic achievement: keep the prior achievedAt/badge regardless of
      // a weaker fresh batch. `evidenceSessionCount` is clamped up only.
      return previous.advanceTo(evidenceSessionCount: distinctCount);
    }

    if (distinctCount >= milestone.minEvidenceSessions &&
        _bestMetric(qualifying) >= milestone.minimumThreshold) {
      final achievedAt = _completionTimestamp(qualifying, milestone, now);
      final badge = MasteryBadge(
        milestoneId: milestone.id,
        skill: milestone.skill,
        metric: milestone.metric,
        difficulty: milestone.difficulty,
        tempoRange: milestone.tempoRange,
        contributingSessionCount: distinctCount,
        achievedAt: achievedAt,
      );
      final base =
          previous?.advanceTo(evidenceSessionCount: distinctCount) ??
          MasteryProgress.fresh(
            milestoneId: milestone.id,
            catalogVersion: milestone.catalogVersion,
          ).advanceTo(evidenceSessionCount: distinctCount);
      return base.achieve(achievedAt: achievedAt, badge: badge);
    }

    final base =
        previous?.advanceTo(evidenceSessionCount: distinctCount) ??
        MasteryProgress.fresh(
          milestoneId: milestone.id,
          catalogVersion: milestone.catalogVersion,
        );
    return base.advanceTo(evidenceSessionCount: distinctCount);
  }

  /// Returns the deduped, qualifying evidence set: same `sessionId` collapses
  /// to a single entry (segments are not multiple evidence — brief §6 A3),
  /// difficulty must match, tempo must be in the milestone's range, and
  /// vision/analysis must clear the confidence gate.
  List<MasteryEvidence> _qualifyingSessions(
    MasteryMilestone milestone,
    Iterable<MasteryEvidence> evidence,
  ) {
    final bySession = <String, MasteryEvidence>{};
    for (final sample in evidence) {
      if (!_passesConfidenceGate(sample)) continue;
      if (sample.difficulty != milestone.difficulty) continue;
      if (!milestone.tempoRange.contains(sample.tempoBpm)) continue;
      // Dedup: keep the first occurrence per session id. Multiple segments of
      // the same session reduce to a single evidence item (brief §6 A3).
      bySession.putIfAbsent(sample.sessionId, () => sample);
    }
    return bySession.values.toList();
  }

  bool _passesConfidenceGate(MasteryEvidence sample) {
    switch (sample.origin) {
      case MasteryEvidenceOrigin.vision:
      case MasteryEvidenceOrigin.analysis:
        final confidence = sample.confidence;
        if (confidence == null) return false;
        return confidence >= masteryEvidenceConfidenceThreshold;
      case MasteryEvidenceOrigin.device:
        return true;
    }
  }

  num _bestMetric(List<MasteryEvidence> samples) {
    var best = num.nan;
    for (final sample in samples) {
      final value = sample.metricValue;
      if (!value.isFinite) continue;
      if (best.isNaN || value > best) best = value;
    }
    return best;
  }

  /// Timestamp of completion: the observed-at of the `minEvidenceSessions`-th
  /// qualifying session (ordered by observed-at ascending). Falls back to
  /// `now` if fewer than the bound exist (defensive — should not trigger
  /// because the boundary check gates the caller).
  DateTime _completionTimestamp(
    List<MasteryEvidence> qualifying,
    MasteryMilestone milestone,
    DateTime now,
  ) {
    if (qualifying.length < milestone.minEvidenceSessions) return now;
    final ordered = [...qualifying]
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return ordered[milestone.minEvidenceSessions - 1].observedAt;
  }
}
