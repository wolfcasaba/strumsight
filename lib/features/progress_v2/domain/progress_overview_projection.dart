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
  factory ProgressOverviewProjection({
    required bool isOffline,
    required List<MilestoneOverviewEntry> milestones,
    required ProgressTrend trend,
    required List<MetricVersionSegment> metricSegments,
    bool isUnavailable = false,
  }) => ProgressOverviewProjection._(
    isOffline: isOffline,
    milestones: List.unmodifiable(milestones),
    trend: trend,
    metricSegments: List.unmodifiable(metricSegments),
    isUnavailable: isUnavailable,
  );

  const ProgressOverviewProjection._({
    required this.isOffline,
    required this.milestones,
    required this.trend,
    required this.metricSegments,
    required this.isUnavailable,
  });

  /// True when local progress exists that has not synced to the account
  /// layer yet (A6) — resolved by the caller from cloud-sync state, never
  /// read here.
  final bool isOffline;
  final List<MilestoneOverviewEntry> milestones;
  final ProgressTrend trend;
  final List<MetricVersionSegment> metricSegments;

  /// True when the practice history could NOT be read (M9, re-audit
  /// 2026-09-08) — resolved by the caller from
  /// `progressPracticeHistoryProvider`, never read here.
  ///
  /// Distinct from [isNewUser] on purpose: an unreadable store leaves every
  /// milestone without evidence, so without this bit the dashboard would
  /// greet a user with years of practice as a beginner. Defaults to `false`,
  /// so every fixture that hands this projection a plain history keeps its
  /// exact previous meaning.
  final bool isUnavailable;

  /// True when not one milestone has any evidence yet — the dashboard's new
  /// user state (§3 scope). Only meaningful when [isUnavailable] is false:
  /// "no evidence" is a fact about the user solely when the history was
  /// actually read.
  bool get isNewUser => milestones.every((entry) => !entry.hasEvidence);
}
