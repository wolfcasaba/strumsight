import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../app/routing/app_route.dart';
import '../domain/analysis_document.dart';
import 'controllers/overview_view_model.dart';
import 'widgets/insight_card.dart';
import 'widgets/labels_adapter.dart';
import 'widgets/metric_card.dart';
import 'widgets/signal_quality_card.dart';

/// Capability-aware overview screen for the V2 analysis document (E06-R23).
///
/// The screen consumes one [AnalysisDocument] from `GoRouterState.extra`. If
/// the caller forgot to supply one, the screen renders an explanatory empty
/// state rather than crashing — the route itself `redirect`s to a safe
/// location when the extra is wrong, so this is a defense-in-depth fallback.
class AnalysisOverviewScreen extends StatelessWidget {
  const AnalysisOverviewScreen({super.key, this.document});

  final AnalysisDocument? document;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final document = this.document;
    if (document == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.analysisOverviewTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.analysisOverviewNoDocument,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final labels = AppLocalizationsOverviewLabels(l10n);
    final viewModel = OverviewViewModel.from(
      document,
      labels: labels,
    );
    return _AnalysisOverviewBody(viewModel: viewModel);
  }
}

class _AnalysisOverviewBody extends StatelessWidget {
  const _AnalysisOverviewBody({required this.viewModel});

  final OverviewViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semanticLabel = l10n
        .analysisOverviewSemantic(viewModel.header.title);
    return Scaffold(
      appBar: AppBar(
        title: Text(viewModel.header.title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: l10n.analysisOverviewSeeAllInsights,
            onPressed: () => context.go(
              AppRoutes.analysisMetricDetail,
              extra: viewModel.details,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Semantics(
          container: true,
          label: semanticLabel,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _HeaderCard(viewModel: viewModel),
              const SizedBox(height: 12),
              SignalQualityCardFromL10n(card: viewModel.signalQuality),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.analysisOverviewPrimaryMetrics,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final metric in viewModel.primaryMetrics) ...<Widget>[
                MetricCard(
                  card: metric,
                  confidenceHighLabel: l10n.analysisOverviewConfidenceHigh,
                  confidenceMediumLabel:
                      l10n.analysisOverviewConfidenceMedium,
                  confidenceLowLabel: l10n.analysisOverviewConfidenceLow,
                  notApplicableLabel: l10n.analysisOverviewNotApplicable,
                  unavailableLabel: l10n.analysisOverviewUnavailable,
                  metricSemanticLabel: (label, value, status) =>
                      l10n.analysisOverviewMetricSemantic(
                    label,
                    value,
                    status,
                  ),
                  detailLabel: l10n.analysisOverviewSeeDetails,
                  onOpenDetail: () => context.go(
                    AppRoutes.analysisMetricDetail,
                    extra: <OverviewMetricCard>[metric],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (viewModel.insights.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final insight in viewModel.insights) ...<Widget>[
                  InsightCard(card: insight),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('overview-see-details'),
                icon: const Icon(Icons.tune),
                onPressed: () => context.go(
                  AppRoutes.analysisMetricDetail,
                  extra: viewModel.details,
                ),
                label: Text(l10n.analysisOverviewSeeDetails),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.viewModel});

  final OverviewViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(viewModel.header.subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              l10n.analysisOverviewDuration(viewModel.header.durationText),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              viewModel.header.completionLabel,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
