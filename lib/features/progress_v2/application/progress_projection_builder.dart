import '../../gamification/public.dart';
import '../../practice/public.dart';
import '../domain/metric_version_segment.dart';
import '../domain/progress_overview_projection.dart';
import '../domain/progress_trend.dart';
import '../domain/skill_detail_projection.dart';

/// Deterministic, pure builder for the Progress V2 screens' projections
/// (ADR 0500 §5.1). Every field is derived from the given arguments alone —
/// no wall-clock read and no randomness anywhere in this file. The caller
/// (`progress_providers.dart`) supplies [now] and reads the practice
/// history/catalog through their own providers.
///
/// [localize] resolves a `MasteryMilestone.titleKey`/`descriptionKey` to
/// display text. This stays a caller-supplied function — not an
/// `AppLocalizations` import — so this file has no Flutter dependency and
/// the localization switch itself lives in the composition layer, matching
/// §5.6's "EXPLICIT switch in the composition layer" rule.
ProgressOverviewProjection buildProgressOverviewProjection({
  required List<MasteryMilestone> milestoneCatalog,
  required List<PracticeHistoryEntry> practiceHistory,
  required List<PracticeDefinition> practiceCatalog,
  required DateTime now,
  required bool isOffline,
  required String Function(String key) localize,
  MasteryEvaluator evaluator = const MasteryEvaluator(),
}) {
  final milestones = <MilestoneOverviewEntry>[
    for (final milestone in milestoneCatalog)
      MilestoneOverviewEntry(
        milestone: milestone,
        progress: _evaluateMilestone(
          milestone: milestone,
          practiceHistory: practiceHistory,
          practiceCatalog: practiceCatalog,
          now: now,
          evaluator: evaluator,
        ),
        title: localize(milestone.titleKey),
      ),
  ];

  final trendPoints = _overallTrendPoints(practiceHistory);
  // Every v1 milestone shares `catalogVersion: 1` (pinned,
  // `mastery_milestone_catalog_test.dart`); tagging every point with the
  // catalog's own version — rather than a hardcoded `1` — keeps this
  // correct automatically once a v2 catalog exists.
  final catalogVersion = milestoneCatalog.isEmpty
      ? 1
      : milestoneCatalog.first.catalogVersion;
  final metricSegments = segmentByCatalogVersion([
    for (final point in trendPoints)
      (catalogVersion: catalogVersion, point: point),
  ]);

  return ProgressOverviewProjection(
    isOffline: isOffline,
    milestones: milestones,
    trend: ProgressTrend(points: trendPoints),
    metricSegments: metricSegments,
  );
}

/// Resolves the skill-detail projection for [skillCode] (a
/// `MasterySkill.code`, §5.8), or `null` when [skillCode] does not match any
/// milestone in [milestoneCatalog] — the caller (the router) redirects to
/// the overview on `null` rather than guessing a fallback skill.
SkillDetailProjection? buildSkillDetailProjection({
  required String skillCode,
  required List<MasteryMilestone> milestoneCatalog,
  required List<PracticeHistoryEntry> practiceHistory,
  required List<PracticeDefinition> practiceCatalog,
  required DateTime now,
  required String Function(String key) localize,
  MasteryEvaluator evaluator = const MasteryEvaluator(),
}) {
  MasteryMilestone? target;
  for (final milestone in milestoneCatalog) {
    if (milestone.skill.code == skillCode) {
      target = milestone;
      break;
    }
  }
  if (target == null) return null;

  final achievedMilestoneIds = <String>{};
  MasteryProgress? targetProgress;
  List<MasteryEvidence> targetEvidence = const <MasteryEvidence>[];
  for (final milestone in milestoneCatalog) {
    final evidence = masteryEvidenceFromPracticeHistory(
      history: practiceHistory,
      milestone: milestone,
      practiceCatalog: practiceCatalog,
    );
    final progress = evaluator.evaluate(
      milestone: milestone,
      previous: null,
      evidence: evidence,
      now: now,
    );
    if (progress.isAchieved) achievedMilestoneIds.add(milestone.id);
    if (identical(milestone, target)) {
      targetProgress = progress;
      targetEvidence = evidence;
    }
  }

  return SkillDetailProjection(
    milestone: target,
    progress: targetProgress!,
    title: localize(target.titleKey),
    description: localize(target.descriptionKey),
    evidence: dedupeEvidenceBySession(targetEvidence),
    achievedMilestoneIds: achievedMilestoneIds,
    // No recommendation catalog exists on the tree (§5.7) — an EXPLICIT
    // `null`, not an invented next-step suggestion.
    recommendation: null,
  );
}

MasteryProgress _evaluateMilestone({
  required MasteryMilestone milestone,
  required List<PracticeHistoryEntry> practiceHistory,
  required List<PracticeDefinition> practiceCatalog,
  required DateTime now,
  required MasteryEvaluator evaluator,
}) {
  final evidence = masteryEvidenceFromPracticeHistory(
    history: practiceHistory,
    milestone: milestone,
    practiceCatalog: practiceCatalog,
  );
  // No persisted `MasteryProgress` exists anywhere on the tree this round
  // (no `data/` mastery-progress store) — `previous` is always `null`, and
  // the full practice history is re-evaluated on every build. This is still
  // deterministic (A3): the same history always yields the same progress.
  return evaluator.evaluate(
    milestone: milestone,
    previous: null,
    evidence: evidence,
    now: now,
  );
}

/// The overview trend line: each history entry's `overall` metric, when
/// measured, ordered by when it was recorded. An entry whose `overall` is
/// `notApplicable`/`insufficientData` contributes NO point (§5.2) — never a
/// `0.0` placeholder that would read as a measured regression.
List<ProgressTrendPoint> _overallTrendPoints(
  List<PracticeHistoryEntry> practiceHistory,
) {
  final sorted = [...practiceHistory]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final points = <ProgressTrendPoint>[];
  for (final entry in sorted) {
    final overall = entry.finalMetricSnapshot.overall;
    if (overall is PracticeMetricDimensionAvailable) {
      points.add(
        ProgressTrendPoint(
          observedAt: entry.createdAt.toUtc(),
          value: overall.value,
        ),
      );
    }
  }
  return List.unmodifiable(points);
}
