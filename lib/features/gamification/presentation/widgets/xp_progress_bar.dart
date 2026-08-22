import 'package:flutter/material.dart';

import 'package:strumsight/l10n/app_localizations.dart';

/// Visual surface for the EXPERIENCE-POINTS indicator on the Hub and
/// level-detail screens.
///
/// The bar is intentionally shaped DIFFERENTLY from the [LevelBadge]
/// (ADR 0289, brief §5.1): a horizontal progress bar with a star icon, never
/// a circular medallion. The label and semantics spell out "Experience
/// points" so the two indicators can never be read as the same thing.
class XpProgressBar extends StatelessWidget {
  const XpProgressBar({
    super.key,
    required this.xpIntoCurrentLevel,
    required this.xpToNextLevel,
    required this.totalXp,
  });

  /// XP accumulated in the current level. Caller-fed — the widget never
  /// reads the ledger.
  final int xpIntoCurrentLevel;

  /// XP remaining until the next skill level crosses. `null` means the
  /// user has reached the saturated highest configured level.
  final int? xpToNextLevel;

  /// Total accumulated XP across every level — used only for the
  /// supplementary "Total experience points" label.
  final int totalXp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasNext = xpToNextLevel != null;
    final span = hasNext
        ? xpIntoCurrentLevel + xpToNextLevel!
        : xpIntoCurrentLevel;
    final ratio = span <= 0 ? 0.0 : (xpIntoCurrentLevel / span).clamp(0.0, 1.0);
    final progressLabel = hasNext
        ? l10n.gamificationHubXpProgressLabel(xpIntoCurrentLevel, span)
        : l10n.gamificationHubXpSaturatedLabel;
    final progressSemantics = hasNext
        ? l10n.gamificationHubXpProgressSemantics(xpIntoCurrentLevel, span)
        : l10n.gamificationHubXpSaturatedLabel;
    final toNextLabel = hasNext
        ? l10n.gamificationHubXpToNextLabel(xpToNextLevel!)
        : null;

    return Semantics(
      container: true,
      label: progressSemantics,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('xp-progress-bar'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.star_outline,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.gamificationHubXpSectionTitle,
                      key: const Key('xp-progress-title'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    l10n.gamificationHubXpTotalLabel(totalXp),
                    key: const Key('xp-progress-total'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  key: const Key('xp-progress-indicator'),
                  value: ratio,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.10,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                progressLabel,
                key: const Key('xp-progress-label'),
                style: theme.textTheme.bodyMedium,
              ),
              if (toNextLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  toNextLabel,
                  key: const Key('xp-progress-to-next'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
