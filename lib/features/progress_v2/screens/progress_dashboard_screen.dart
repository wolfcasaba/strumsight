import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/metric_version_segment.dart';
import '../domain/progress_overview_projection.dart';
import '../domain/progress_trend.dart';
import '../widgets/progress_theme_scope.dart';

/// UI-49 Progress Dashboard — new-user, trend, offline and metric-migration
/// states over a caller-fed [ProgressOverviewProjection] (§0.0.B/B7). This
/// feature has no registered route (§0.0.B/B4: `lib/app/routing/` is out of
/// this round's scope) — it is instantiated directly, exactly like
/// `VisionResultScreen` (E13-R30).
final class ProgressDashboardScreen extends StatelessWidget {
  const ProgressDashboardScreen({
    required this.projection,
    required this.onOpenSkillDetail,
    required this.onGetStarted,
    super.key,
  });

  final ProgressOverviewProjection projection;

  /// Called with the tapped milestone's stable id — this screen never
  /// navigates itself (§0.0.B/B4).
  final ValueChanged<String> onOpenSkillDetail;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ProgressThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.progressV2DashboardTitle)),
        body: SafeArea(
          child: projection.isNewUser
              ? _NewUserState(l10n: l10n, onGetStarted: onGetStarted)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (projection.isOffline) ...[
                        SsStatusBadge(
                          l10n: l10n,
                          kind: SsStatusBadgeKind.offline,
                        ),
                        const SizedBox(height: 12),
                      ],
                      SsSection(
                        title: l10n.progressV2TrendSectionTitle,
                        child: _TrendSection(
                          l10n: l10n,
                          trend: projection.trend,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SsSection(
                        title: l10n.progressV2SkillsSectionTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final entry in projection.milestones)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _MilestoneRow(
                                  l10n: l10n,
                                  entry: entry,
                                  onTap: () =>
                                      onOpenSkillDetail(entry.milestone.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (projection.metricSegments.length > 1) ...[
                        const SizedBox(height: 16),
                        SsSection(
                          title: l10n.progressV2MetricHistorySectionTitle,
                          child: _MetricHistorySection(
                            l10n: l10n,
                            segments: projection.metricSegments,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _NewUserState extends StatelessWidget {
  const _NewUserState({required this.l10n, required this.onGetStarted});

  final AppLocalizations l10n;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return SsEmptyState(
      key: const Key('progress-dashboard-new-user'),
      icon: Icons.insights_outlined,
      title: l10n.progressV2NewUserTitle,
      message: l10n.progressV2NewUserMessage,
      actionLabel: l10n.progressV2NewUserAction,
      onAction: onGetStarted,
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.l10n,
    required this.entry,
    required this.onTap,
  });

  final AppLocalizations l10n;
  final MilestoneOverviewEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasEvidence = entry.hasEvidence;
    final statusText = hasEvidence
        ? '${(entry.ratio * 100).round()}%'
        : l10n.progressV2SkillStatusUnmeasured;
    return SsSurface(
      child: InkWell(
        key: ValueKey('progress-skill-row-${entry.milestone.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SsScoreRing(
                state: hasEvidence
                    ? SsScoreRingState.measured
                    : SsScoreRingState.unavailable,
                ratio: hasEvidence ? entry.ratio : null,
                label: hasEvidence
                    ? statusText
                    : l10n.progressV2ScoreRingUnavailableGlyph,
                semanticLabel: l10n.progressV2SkillRowSemanticLabel(
                  entry.title,
                  statusText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      key: ValueKey(
                        'progress-skill-title-${entry.milestone.id}',
                      ),
                    ),
                    // Only shown when unmeasured: the measured case already
                    // paints its percentage inside the ring itself (above),
                    // so repeating it here would duplicate the same text
                    // rather than add information.
                    if (!hasEvidence)
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.l10n, required this.trend});

  final AppLocalizations l10n;
  final ProgressTrend trend;

  @override
  Widget build(BuildContext context) {
    if (!trend.hasTrend) {
      return Text(
        l10n.progressV2TrendInsufficientData,
        key: const Key('progress-trend-insufficient'),
      );
    }

    final dateFormat = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    );
    final points = trend.points;
    final first = points.first.value;
    final last = points.last.value;
    final direction = last > first
        ? SsTrendDirection.up
        : last < first
        ? SsTrendDirection.down
        : SsTrendDirection.flat;
    final directionLabel = switch (direction) {
      SsTrendDirection.up => l10n.progressV2TrendDirectionUp,
      SsTrendDirection.down => l10n.progressV2TrendDirectionDown,
      SsTrendDirection.flat => l10n.progressV2TrendDirectionFlat,
      SsTrendDirection.unknown => l10n.progressV2TrendDirectionFlat,
    };
    final sessionsTrackedLabel = l10n.progressV2TrendSessionsTracked(
      points.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SsChartTextSummary(
          key: const Key('progress-trend-chart-summary'),
          summaryText: '$directionLabel · $sessionsTrackedLabel',
          extremesText: l10n.progressV2TrendExtremes(
            '${(first * 100).round()}%',
            '${(last * 100).round()}%',
          ),
        ),
        const SizedBox(height: 8),
        SsTrendIndicator(direction: direction, semanticLabel: directionLabel),
        const SizedBox(height: 12),
        SsEventList(
          key: const Key('progress-trend-event-list'),
          semanticLabel: l10n.progressV2TrendEventListSemanticLabel,
          rows: [
            for (final point in points)
              SsEventListRow(
                id: point.observedAt.toIso8601String(),
                label:
                    '${(point.value * 100).round()}% · '
                    '${dateFormat.format(point.observedAt)}',
                semanticLabel: l10n.progressV2TrendPointSemanticLabel(
                  '${(point.value * 100).round()}%',
                  dateFormat.format(point.observedAt),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MetricHistorySection extends StatelessWidget {
  const _MetricHistorySection({required this.l10n, required this.segments});

  final AppLocalizations l10n;
  final List<MetricVersionSegment> segments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.progressV2MetricVersionChangedNote,
          key: const Key('progress-metric-version-changed-note'),
        ),
        const SizedBox(height: 8),
        for (final (index, segment) in segments.indexed)
          Padding(
            // Keyed by POSITION, not `catalogVersion` alone: a version can
            // reappear later without re-merging into its earlier segment
            // (`segmentByCatalogVersion`, `metric_migration_test.dart`
            // "a version reappearing later starts a NEW segment") — two
            // same-version segments would otherwise collide on one key.
            key: ValueKey(
              'progress-metric-segment-$index-v${segment.catalogVersion}',
            ),
            padding: const EdgeInsets.only(bottom: 4),
            // Wrap, not Row: at a large text scale "Measure v2" and "1
            // sample" no longer fit one line side by side (measured while
            // recording this round's A9 golden — a RenderFlex overflow at
            // textScaler 2.0).
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(l10n.progressV2MetricVersionLabel(segment.catalogVersion)),
                Text(
                  l10n.progressV2MetricVersionPointCount(segment.points.length),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
