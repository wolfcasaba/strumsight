import 'package:flutter/material.dart';

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
    final cards = metrics ?? const <OverviewMetricCard>[];
    final insights = remainingInsights ?? const <OverviewInsightCard>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisOverviewMetricDetailTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            for (final card in cards) ...<Widget>[
              MetricCard(
                card: card,
                metricSemanticLabel: (label, value, status) =>
                    l10n.analysisOverviewMetricSemantic(label, value, status),
                detailLabel: l10n.analysisOverviewSeeDetails,
              ),
              const SizedBox(height: 8),
            ],
            if (insights.isNotEmpty) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.analysisOverviewRemainingInsights,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final insight in insights) ...<Widget>[
                InsightCard(card: insight),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
