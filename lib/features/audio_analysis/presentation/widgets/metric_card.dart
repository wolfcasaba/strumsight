import 'package:flutter/material.dart';

import '../controllers/overview_view_model.dart';
import 'confidence_badge.dart';

/// Template that resolves the screen-reader label for a single metric card.
/// Three placeholders are substituted in order: `{label}`, `{value}`,
/// `{status}`. The widget never depends on the concrete localisation call,
/// so a test fixture can drive it with a plain closure.
typedef MetricSemanticLabelBuilder =
    String Function(String label, String value, String status);

/// Reusable, five-state metric card. Each state has a distinct icon and
/// text label so the status is never conveyed by colour alone (SDD §25.8).
/// The unavailable and lowConfidence states ALWAYS render the reason and a
/// tip — never an empty body.
final class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.card,
    required this.metricSemanticLabel,
    this.detailLabel,
    this.onOpenDetail,
    super.key,
  });

  final OverviewMetricCard card;

  /// Resolves the screen-reader label. Called once per build with the
  /// metric label, value and status.
  final MetricSemanticLabelBuilder metricSemanticLabel;

  /// Optional "see details" label. When null, the button is hidden.
  final String? detailLabel;

  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = card.statusLabel;
    final icon = _iconForState();
    final confidenceLevel = _confidenceLevel();
    final semanticLabel = metricSemanticLabel(
      card.metricLabel,
      card.valueText,
      statusLabel,
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Card(
        key: ValueKey('metric-card-${card.metricId}'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.onSurface),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      card.metricLabel,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      card.valueText,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (card.unit.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(card.unit, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Flexible(
                    child: ConfidenceBadge(
                      level: confidenceLevel,
                      label: statusLabel,
                    ),
                  ),
                  if (onOpenDetail != null && detailLabel != null) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onOpenDetail,
                      child: Text(
                        detailLabel!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (card.state == OverviewMetricCardState.unavailable ||
                  card.state ==
                      OverviewMetricCardState.lowConfidence) ...<Widget>[
                const SizedBox(height: 8),
                Text(card.reasonText, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  card.tipText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ConfidenceBadgeLevel _confidenceLevel() => switch (card.state) {
    OverviewMetricCardState.available => ConfidenceBadgeLevel.high,
    OverviewMetricCardState.degraded => ConfidenceBadgeLevel.medium,
    OverviewMetricCardState.lowConfidence => ConfidenceBadgeLevel.low,
    OverviewMetricCardState.unavailable => ConfidenceBadgeLevel.low,
    OverviewMetricCardState.notApplicable => ConfidenceBadgeLevel.medium,
  };

  IconData _iconForState() => switch (card.state) {
    OverviewMetricCardState.available => Icons.check_circle_outline,
    OverviewMetricCardState.degraded => Icons.info_outline,
    OverviewMetricCardState.lowConfidence => Icons.help_outline,
    OverviewMetricCardState.unavailable => Icons.block,
    OverviewMetricCardState.notApplicable => Icons.remove_circle_outline,
  };
}
