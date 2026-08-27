import '../../gamification/public.dart';
import 'metric_version_segment.dart';
import 'progress_trend.dart';

/// One milestone's overview row (§3). [title] is already localised by the
/// caller (§0.0.B/B7 — this feature performs no dynamic
/// `MasteryMilestone.titleKey` lookup).
///
/// [hasEvidence] is what separates "measured 0%" from "not measured at all"
/// (A3, §0.0.B "`?? 0` a hiányzó mérőszámra" falsification cell): a fresh
/// [MasteryProgress] (`evidenceSessionCount == 0`) is treated as unavailable
/// and is never rendered as a literal 0%.
final class MilestoneOverviewEntry {
  const MilestoneOverviewEntry({
    required this.milestone,
    required this.progress,
    required this.title,
  });

  final MasteryMilestone milestone;
  final MasteryProgress progress;
  final String title;

  bool get hasEvidence => progress.evidenceSessionCount > 0;

  /// Only meaningful when [hasEvidence] is true — mastery derives SOLELY
  /// from measured evidence sessions, never from XP (A1, ADR 0289 §1).
  double get ratio => progress.progressValue(milestone);
}

/// Immutable, caller-fed projection for the progress overview screen (UI-49,
/// §0.0.B/B7): no repository, `SharedPreferences`, or `DateTime.now()` read
/// happens on this tree — every field here is already resolved by the
/// caller.
final class ProgressOverviewProjection {
  const ProgressOverviewProjection({
    required this.isOffline,
    required this.milestones,
    required this.trend,
    required this.metricSegments,
  });

  /// True when local progress exists that has not synced to the account
  /// layer yet (A6) — resolved by the caller from cloud-sync state, never
  /// read here.
  final bool isOffline;
  final List<MilestoneOverviewEntry> milestones;
  final ProgressTrend trend;
  final List<MetricVersionSegment> metricSegments;

  /// True when not one milestone has any evidence yet — the dashboard's new
  /// user state (§3 scope).
  bool get isNewUser => milestones.every((entry) => !entry.hasEvidence);
}
