import 'mastery_badge.dart';
import 'mastery_milestone.dart';

/// Origin of a mastery evidence sample. Vision and Analysis origin samples
/// must clear the confidence gate (mastery_evaluator.dart) before they may
/// contribute to a milestone; Device-origin samples are accepted on raw
/// measured values (ADR 0388 §3).
enum MasteryEvidenceOrigin { vision, analysis, device }

/// A single measured result for one session, scoped to a milestone's metric.
///
/// `sessionId` is the dedup key — multiple samples sharing a `sessionId` are
/// treated as ONE evidence item at evaluation time (brief §6 A3).
///
/// `confidence` is required for vision/analysis origins (the evaluator will
/// reject a missing or sub-threshold value), optional for device origin.
final class MasteryEvidence {
  factory MasteryEvidence({
    required String sessionId,
    required MasteryEvidenceOrigin origin,
    required MasteryDifficulty difficulty,
    required num tempoBpm,
    required num metricValue,
    required DateTime observedAt,
    double? confidence,
  }) {
    if (sessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (!tempoBpm.isFinite || tempoBpm <= 0) {
      throw ArgumentError.value(
        tempoBpm,
        'tempoBpm',
        'must be finite and positive',
      );
    }
    if (!metricValue.isFinite || metricValue < 0) {
      throw ArgumentError.value(
        metricValue,
        'metricValue',
        'must be finite and non-negative',
      );
    }
    if (confidence != null) {
      if (!confidence.isFinite || confidence < 0 || confidence > 1) {
        throw ArgumentError.value(
          confidence,
          'confidence',
          'when supplied must be a finite value in [0,1]',
        );
      }
    }
    return MasteryEvidence._(
      sessionId: sessionId,
      origin: origin,
      difficulty: difficulty,
      tempoBpm: tempoBpm,
      metricValue: metricValue,
      observedAt: observedAt,
      confidence: confidence,
    );
  }

  const MasteryEvidence._({
    required this.sessionId,
    required this.origin,
    required this.difficulty,
    required this.tempoBpm,
    required this.metricValue,
    required this.observedAt,
    required this.confidence,
  });

  final String sessionId;
  final MasteryEvidenceOrigin origin;
  final MasteryDifficulty difficulty;
  final num tempoBpm;
  final num metricValue;
  final DateTime observedAt;
  final double? confidence;
}

/// Monotonic progress for one milestone. `achievedAt` and `badge` are coupled —
/// once set neither is regressed by a later, weaker evaluation (brief §6 A5).
final class MasteryProgress {
  factory MasteryProgress({
    required String milestoneId,
    required int catalogVersion,
    required int evidenceSessionCount,
    DateTime? achievedAt,
    MasteryBadge? badge,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(milestoneId)) {
      throw ArgumentError.value(
        milestoneId,
        'milestoneId',
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
    if (evidenceSessionCount < 0) {
      throw ArgumentError.value(
        evidenceSessionCount,
        'evidenceSessionCount',
        'must not be negative',
      );
    }
    if (badge != null && achievedAt == null) {
      throw ArgumentError.value(
        badge,
        'badge',
        'requires achievedAt to be set in the same step',
      );
    }
    if (achievedAt != null && badge == null) {
      throw ArgumentError.value(
        achievedAt,
        'achievedAt',
        'requires badge to be set in the same step',
      );
    }
    return MasteryProgress._(
      milestoneId: milestoneId,
      catalogVersion: catalogVersion,
      evidenceSessionCount: evidenceSessionCount,
      achievedAt: achievedAt,
      badge: badge,
    );
  }

  const MasteryProgress._({
    required this.milestoneId,
    required this.catalogVersion,
    required this.evidenceSessionCount,
    required this.achievedAt,
    required this.badge,
  });

  /// Empty progress for a freshly issued milestone — zero distinct sessions,
  /// not yet achieved.
  factory MasteryProgress.fresh({
    required String milestoneId,
    required int catalogVersion,
  }) => MasteryProgress(
    milestoneId: milestoneId,
    catalogVersion: catalogVersion,
    evidenceSessionCount: 0,
    achievedAt: null,
    badge: null,
  );

  final String milestoneId;
  final int catalogVersion;
  final int evidenceSessionCount;
  final DateTime? achievedAt;
  final MasteryBadge? badge;

  bool get isAchieved => achievedAt != null;

  /// Scaled progress in `[0, 1]` relative to the milestone's inclusive
  /// `minEvidenceSessions` boundary. Returns 0 when the milestone is null
  /// or already achieved above 1 (capped).
  double progressValue(MasteryMilestone milestone) {
    if (milestone.minEvidenceSessions <= 0) return 0;
    final raw = evidenceSessionCount / milestone.minEvidenceSessions;
    if (raw < 0) return 0;
    if (raw > 1) return 1;
    return raw;
  }

  /// Returns a new state and ensures `evidenceSessionCount` only ever
  /// increases. `achievedAt`/`badge` are preserved if this progress was
  /// already achieved — passing a later observedAt would overwrite a
  /// previously-locked achievement timestamp (not desired); keep them in
  /// the absence of a transition.
  MasteryProgress advanceTo({required int evidenceSessionCount}) {
    if (evidenceSessionCount < 0) {
      throw ArgumentError.value(
        evidenceSessionCount,
        'evidenceSessionCount',
        'must not be negative',
      );
    }
    if (evidenceSessionCount < this.evidenceSessionCount) {
      throw ArgumentError.value(
        evidenceSessionCount,
        'evidenceSessionCount',
        'must not regress',
      );
    }
    return MasteryProgress(
      milestoneId: milestoneId,
      catalogVersion: catalogVersion,
      evidenceSessionCount: evidenceSessionCount,
      achievedAt: achievedAt,
      badge: badge,
    );
  }

  /// Transitions a not-yet-achieved progress to achieved. Rejects a second
  /// call when already achieved — the monotonic achievement rule (brief
  /// §6 A5) is enforced by `advanceTo` upstream.
  MasteryProgress achieve({
    required DateTime achievedAt,
    required MasteryBadge badge,
  }) {
    if (isAchieved) {
      throw StateError(
        'mastery milestone $milestoneId is already achieved; '
        'use advanceTo for further progress updates',
      );
    }
    return MasteryProgress(
      milestoneId: milestoneId,
      catalogVersion: catalogVersion,
      evidenceSessionCount: evidenceSessionCount,
      achievedAt: achievedAt,
      badge: badge,
    );
  }
}
