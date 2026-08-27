import 'package:flutter/material.dart';

/// Direction of a before/after or time-series movement. [unknown] is a
/// distinct state — it never collapses into [flat] (SDD §25.8: status is
/// never conveyed by a default-looking icon for "we don't know").
enum SsTrendDirection { up, down, flat, unknown }

/// Icon-first trend marker. [label] is optional: callers that already
/// render the direction as text alongside this widget (e.g. a `Chip`) pass
/// `label: null` so the icon never duplicates text already on screen, while
/// [semanticLabel] still carries the full meaning for assistive tech.
final class SsTrendIndicator extends StatelessWidget {
  const SsTrendIndicator({
    super.key,
    required this.direction,
    required this.semanticLabel,
    this.label,
    this.iconSize = 18,
  });

  final SsTrendDirection direction;
  final String semanticLabel;
  final String? label;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (direction) {
      SsTrendDirection.up => Icons.trending_up,
      SsTrendDirection.down => Icons.trending_down,
      SsTrendDirection.flat => Icons.trending_flat,
      SsTrendDirection.unknown => Icons.help_outline,
    };
    final label = this.label;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: iconSize, color: colorScheme.onSurface),
          if (label != null) ...<Widget>[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
