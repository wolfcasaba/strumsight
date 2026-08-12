import 'package:flutter/material.dart';

/// Three-step textual confidence scale (SDD §19.5). The numeric confidence
/// is never rendered — the badge always pairs the [label] with an icon, so
/// status is conveyed by both icon AND text (the SDD §25.8 colour-only ban).
enum ConfidenceBadgeLevel { high, medium, low }

/// Compact, accessible confidence badge. Wraps the label and icon in a
/// [Semantics] container with the exact label as the spoken hint so screen
/// readers never rely on colour alone.
final class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    required this.level,
    required this.label,
    super.key,
  });

  final ConfidenceBadgeLevel level;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colorsFor(context, level);
    final icon = switch (level) {
      ConfidenceBadgeLevel.high => Icons.check_circle_outline,
      ConfidenceBadgeLevel.medium => Icons.info_outline,
      ConfidenceBadgeLevel.low => Icons.help_outline,
    };
    return Semantics(
      container: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: colors.foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeColors _colorsFor(BuildContext context, ConfidenceBadgeLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      ConfidenceBadgeLevel.high => _BadgeColors(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurface,
        border: scheme.outline,
      ),
      ConfidenceBadgeLevel.medium => _BadgeColors(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurface,
        border: scheme.outline,
      ),
      ConfidenceBadgeLevel.low => _BadgeColors(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurface,
        border: scheme.outline,
      ),
    };
  }
}

class _BadgeColors {
  const _BadgeColors({
    required this.background,
    required this.foreground,
    required this.border,
  });
  final Color background;
  final Color foreground;
  final Color border;
}
