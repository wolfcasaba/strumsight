import 'package:flutter/material.dart';

import 'package:strumsight/l10n/app_localizations.dart';

import 'controllers/overview_view_model.dart';
import 'widgets/metric_card.dart';

/// Single-metric detail screen — lists every metric card the document
/// publishes. The route is the catch-all for "see all details" navigation
/// from the overview; it never accepts a navigation-only payload.
class AnalysisMetricDetailScreen extends StatelessWidget {
  const AnalysisMetricDetailScreen({super.key, this.metrics});

  /// The metric cards to render. When the route was reached from the
  /// overview's primary grid, this contains one entry; when reached via the
  /// "See all details" button it contains every published card.
  final List<OverviewMetricCard>? metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = metrics ?? const <OverviewMetricCard>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisOverviewMetricDetailTitle)),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int index) {
            final card = cards[index];
            return MetricCard(
              card: card,
              confidenceHighLabel: l10n.analysisOverviewConfidenceHigh,
              confidenceMediumLabel: l10n.analysisOverviewConfidenceMedium,
              confidenceLowLabel: l10n.analysisOverviewConfidenceLow,
              notApplicableLabel: l10n.analysisOverviewNotApplicable,
              unavailableLabel: l10n.analysisOverviewUnavailable,
              metricSemanticLabel: (label, value, status) =>
                  l10n.analysisOverviewMetricSemantic(label, value, status),
              detailLabel: l10n.analysisOverviewSeeDetails,
            );
          },
        ),
      ),
    );
  }
}
