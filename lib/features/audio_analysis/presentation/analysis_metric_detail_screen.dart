import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import 'controllers/overview_view_model.dart';
import 'widgets/insight_card.dart';
import 'widgets/metric_card.dart';

/// Single-metric detail screen — lists every metric card the document
/// publishes, plus (when reached via the overview's "Részletek" entry
/// point) every insight the four-slot maximum-policy did not show on the
/// overview. The route is the catch-all for "see all details" navigation
/// from the overview; it never accepts a navigation-only payload.
class AnalysisMetricDetailScreen extends StatelessWidget {
  const AnalysisMetricDetailScreen({
    super.key,
    this.metrics,
    this.remainingInsights,
  });

  /// The metric cards to render. When the route was reached from the
  /// overview's primary grid, this contains one entry; when reached via the
  /// "See all details" button it contains every published card.
  final List<OverviewMetricCard>? metrics;

  /// Insights beyond the four maximum-policy slots the overview showed.
  /// `null`/empty when the route was reached from a single metric card.
  final List<OverviewInsightCard>? remainingInsights;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final cards = metrics ?? const <OverviewMetricCard>[];
    final insights = remainingInsights ?? const <OverviewInsightCard>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisOverviewMetricDetailTitle)),
      body: SafeArea(
        child: cards.isEmpty && insights.isEmpty
            // This branch is reached with an EXISTING document whose metric
            // and insight lists are both empty — not a missing document, so
            // `analysisOverviewNoDocument` misreports the situation (review
            // m2). The title also must not repeat the AppBar's own
            // `analysisOverviewMetricDetailTitle` above. Both replaced with
            // existing, meaning-accurate keys — no new ARB key needed.
            ? SsEmptyState(
                key: const Key('analysis-metric-detail-empty'),
                icon: Icons.insights_outlined,
                title: l10n.analysisOverviewUnavailable,
                message: l10n.analysisOverviewNotApplicable,
                actionLabel: l10n.commonClose,
                onAction: () => Navigator.of(context).maybePop(),
              )
            : ListView(
                padding: const EdgeInsets.all(SsSpacing.space4),
                children: <Widget>[
                  for (final card in cards) ...<Widget>[
                    MetricCard(
                      card: card,
                      metricSemanticLabel: (label, value, status) => l10n
                          .analysisOverviewMetricSemantic(label, value, status),
                      detailLabel: l10n.analysisOverviewSeeDetails,
                    ),
                    const SizedBox(height: SsSpacing.space2),
                  ],
                  if (insights.isNotEmpty) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: SsSpacing.space2,
                      ),
                      child: Text(
                        l10n.analysisOverviewRemainingInsights,
                        style: typography.titleMedium.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    for (final insight in insights) ...<Widget>[
                      InsightCard(card: insight),
                      const SizedBox(height: SsSpacing.space2),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
