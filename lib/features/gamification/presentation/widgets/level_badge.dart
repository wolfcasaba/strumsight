import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/domain/levels/level_definition.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Visual surface for the XP-derived LEVEL indicator on the Hub and
/// level-detail screens.
///
/// The badge is intentionally shaped and coloured DIFFERENTLY from the XP
/// progress bar (ADR 0289, brief §5.1): a card with a circular medallion in
/// the secondary container, never a progress bar. The label spells out
/// "Level {level}" so the two indicators can never be read as the single
/// surface — and so the level is never confused with evidence-gated mastery
/// (mastery milestones are surfaced separately on the Hub via the
/// `masteryUnlockedCount` tile).
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level});

  /// Caller-fed current [LevelDefinition]. The widget reads only the level
  /// number and the localization key — it never derives evidence, only
  /// renders the XP-derived level supplied by the caller.
  final LevelDefinition level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final label = l10n.gamificationHubLevelBadgeLabel(level.number);
    final semantics = l10n.gamificationHubLevelBadgeSemantics(
      level.number,
      level.titleKey,
    );

    return GamificationThemeScope(
      child: Semantics(
        container: true,
        label: semantics,
        child: ExcludeSemantics(
          child: SsSurface(
            key: const Key('level-badge'),
            elevation: SsElevation.raised,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _SkillMedallion(
                    level: level.number,
                    color: theme.colorScheme.secondary,
                    onColor: theme.colorScheme.onSecondary,
                    outline: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          key: const Key('level-badge-label'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          level.titleKey,
                          key: const Key('level-badge-title'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillMedallion extends StatelessWidget {
  const _SkillMedallion({
    required this.level,
    required this.color,
    required this.onColor,
    required this.outline,
  });

  final int level;
  final Color color;
  final Color onColor;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 72, minHeight: 72),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: outline.withValues(alpha: 0.50), width: 2),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, color: color, size: 22),
            Text(
              '$level',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: onColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
