import 'package:flutter/material.dart';

/// Three-step confidence scale shared by every analytics surface (SDD
/// §19.5). Deliberately its own enum rather than importing a feature's
/// badge-level type: the design system never depends on a feature.
enum SsConfidenceLevel { high, medium, low }

/// One legend row: the caller resolves [label] through its own
/// localisation — this widget never owns a string literal.
final class SsConfidenceLegendEntry {
  const SsConfidenceLegendEntry({required this.level, required this.label});

  final SsConfidenceLevel level;
  final String label;
}

/// Compact, once-per-screen explainer for the confidence badges sprinkled
/// across metric cards (ADR 0286 §3). Pairs an icon with a label for every
/// level, so the legend itself never conveys meaning by colour alone.
final class SsConfidenceLegend extends StatelessWidget {
  const SsConfidenceLegend({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<SsConfidenceLegendEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              for (final entry in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _iconFor(entry.level),
                      size: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 4),
                    Text(entry.label, style: theme.textTheme.labelSmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(SsConfidenceLevel level) => switch (level) {
    SsConfidenceLevel.high => Icons.check_circle_outline,
    SsConfidenceLevel.medium => Icons.info_outline,
    SsConfidenceLevel.low => Icons.help_outline,
  };
}
