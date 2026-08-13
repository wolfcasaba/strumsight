import 'package:flutter/material.dart';

/// Pre-formatted content for one [MetricDeltaRow]. Formatting-only, no
/// domain type dependency, so the widget stays trivially testable — every
/// string is resolved by the screen from [MetricComparison] + [AppLocalizations].
final class MetricDeltaRowData {
  const MetricDeltaRowData({
    required this.metricId,
    required this.metricLabel,
    required this.directionLabel,
    required this.directionIcon,
    required this.beforeValueText,
    required this.afterValueText,
    required this.deltaText,
    required this.confidenceText,
    required this.sampleCountText,
    required this.isInconclusive,
    this.reasonText = '',
  });

  final String metricId;
  final String metricLabel;

  /// "Improved" / "Regressed" / "Unchanged" / "Inconclusive" — always
  /// non-empty; the row never conveys direction by colour or icon alone,
  /// only ever icon *plus* this label.
  final String directionLabel;
  final IconData directionIcon;
  final String beforeValueText;
  final String afterValueText;
  final String deltaText;
  final String confidenceText;
  final String sampleCountText;

  /// Non-empty only when [isInconclusive] — the explicit reason the
  /// comparison could not be resolved (SDD §26.1: never a silent omission).
  final String reasonText;
  final bool isInconclusive;
}

/// One metric's before/after row on the comparison screen. Renders the
/// before value, after value, delta, direction, confidence and sample count;
/// for an inconclusive comparison it renders [MetricDeltaRowData.reasonText]
/// instead of a fabricated delta.
final class MetricDeltaRow extends StatelessWidget {
  const MetricDeltaRow({required this.data, super.key});

  final MetricDeltaRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('metric-delta-row-${data.metricId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(data.directionIcon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.metricLabel,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (data.isInconclusive)
              Text(data.reasonText, style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: <Widget>[
                  Text(data.beforeValueText, style: theme.textTheme.bodyMedium),
                  Text(data.afterValueText, style: theme.textTheme.bodyMedium),
                  Text(
                    data.deltaText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                Chip(
                  label: Text(
                    data.directionLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Text(data.confidenceText, style: theme.textTheme.bodySmall),
                Text(data.sampleCountText, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
