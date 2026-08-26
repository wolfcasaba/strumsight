import 'package:flutter/material.dart';

/// Accessible textual alternative to a chart (ADR 0282, ADR 0286 §3). Every
/// chart that paints evidence must pair it with this: a screen reader never
/// sees the canvas, so the trend/extremes sentence IS the chart for it.
final class SsChartTextSummary extends StatelessWidget {
  const SsChartTextSummary({
    super.key,
    required this.summaryText,
    this.extremesText,
  });

  /// Already-localised trend/count sentence (e.g. "12 items, concentrated
  /// in the first half").
  final String summaryText;

  /// Already-localised extremes sentence (e.g. "first at 0:05, last at
  /// 1:42"). Null when the chart published fewer than two points — a
  /// single point has no meaningful extremes, so this is omitted rather
  /// than fabricated.
  final String? extremesText;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final extremesText = this.extremesText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(summaryText, style: style),
        if (extremesText != null) Text(extremesText, style: style),
      ],
    );
  }
}
