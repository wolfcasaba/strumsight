import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/domain/profile/gamification_profile.dart';
import 'package:strumsight/features/gamification/domain/rewards/experience_points.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/features/gamification/presentation/widgets/level_badge.dart';
import 'package:strumsight/features/gamification/presentation/widgets/xp_progress_bar.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// One XP-component entry rendered inside the "How experience points work"
/// explanation on the level-detail screen.
///
/// The widget layer never constructs the [ExperiencePoints] domain value
/// itself — the caller supplies an ordered, localized list of the five
/// R06 components so that the screen has no language policy and no policy
/// computation (ADR 0290 §2).
class LevelDetailScreen extends StatelessWidget {
  LevelDetailScreen({
    super.key,
    required this.profile,
    required this.latestSessionXp,
    required this.components,
  }) {
    if (profile.schemaVersion != gamificationProfileSchemaVersion) {
      throw ArgumentError.value(
        profile.schemaVersion,
        'profile.schemaVersion',
        'is not supported',
      );
    }
    if (components.length != 5) {
      throw ArgumentError.value(
        components.length,
        'components',
        'must contain exactly five R06 components',
      );
    }
  }

  /// Caller-supplied current [GamificationProfile] projection.
  final GamificationProfile profile;

  /// Caller-supplied latest session [ExperiencePoints] — used for the
  /// "Total experience points this session" footer and the sum.
  final ExperiencePoints latestSessionXp;

  /// Ordered, pre-localized explanation for the five R06 XP components.
  /// The widget renders them in the supplied order without reordering.
  final List<LevelDetailXpComponent> components;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = profile.currentLevel;
    final next = profile.nextLevel;
    return GamificationThemeScope(
      child: Builder(
        builder: (context) {
          // A fresh `context` from inside the wrapper's subtree — the
          // outer `build(context)` parameter sits ABOVE the merged theme,
          // so resolving the SS extensions on it would null-check against
          // the ambient (non-DS) theme.
          final colors = Theme.of(context).extension<SsColorScheme>()!;
          final typography = Theme.of(context).extension<SsTypography>()!;
          return Scaffold(
            appBar: AppBar(
              title: Semantics(
                header: true,
                child: Text(l10n.gamificationLevelDetailTitle(current.number)),
              ),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  SsSpacing.space5,
                  SsSpacing.space3,
                  SsSpacing.space5,
                  SsSpacing.space6,
                ),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.gamificationLevelDetailCurrentTitle,
                      key: const Key('level-detail-current-header'),
                      style: typography.titleMedium.copyWith(
                        color: colors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(height: SsSpacing.space2),
                  LevelBadge(level: current),
                  const SizedBox(height: SsSpacing.space4),
                  Text(
                    l10n.gamificationLevelDetailCurrentBody,
                    key: const Key('level-detail-current-body'),
                    style: typography.bodyMedium,
                  ),
                  if (next != null) ...[
                    const SizedBox(height: SsSpacing.space5),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.gamificationLevelDetailNextTitle,
                        key: const Key('level-detail-next-header'),
                        style: typography.titleMedium.copyWith(
                          color: colors.brand,
                        ),
                      ),
                    ),
                    const SizedBox(height: SsSpacing.space2),
                    LevelBadge(level: next),
                    const SizedBox(height: SsSpacing.space2),
                    Text(
                      l10n.gamificationLevelDetailNextBody,
                      key: const Key('level-detail-next-body'),
                      style: typography.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: SsSpacing.space6),
                  XpProgressBar(
                    xpIntoCurrentLevel: profile.xpIntoCurrentLevel,
                    xpToNextLevel: profile.xpToNextLevel,
                    totalXp: profile.totalXp,
                  ),
                  const SizedBox(height: SsSpacing.space6),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.gamificationLevelDetailHowXpWorksTitle,
                      key: const Key('level-detail-how-title'),
                      style: typography.titleMedium,
                    ),
                  ),
                  const SizedBox(height: SsSpacing.space1),
                  Text(
                    l10n.gamificationLevelDetailHowXpWorksBody,
                    key: const Key('level-detail-how-body'),
                    style: typography.bodyMedium,
                  ),
                  const SizedBox(height: SsSpacing.space3),
                  for (final entry in components) ...[
                    _XpComponentRow(component: entry),
                    const SizedBox(height: SsSpacing.space2),
                  ],
                  const SizedBox(height: SsSpacing.space2),
                  Text(
                    l10n.gamificationLevelDetailXpTotalLabel(
                      latestSessionXp.totalXp,
                    ),
                    key: const Key('level-detail-session-total'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typography.titleMedium.copyWith(color: colors.brand),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pre-localized XP-component entry consumed by [LevelDetailScreen].
final class LevelDetailXpComponent {
  const LevelDetailXpComponent({
    required this.title,
    required this.body,
    required this.xp,
    required this.semantics,
  });

  final String title;
  final String body;
  final int xp;
  final String semantics;
}

class _XpComponentRow extends StatelessWidget {
  const _XpComponentRow({required this.component});

  final LevelDetailXpComponent component;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Semantics(
      container: true,
      label: component.semantics,
      child: ExcludeSemantics(
        child: SsCard(
          key: const Key('level-detail-component-row'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.star_outline, color: colors.brand, size: 18),
              const SizedBox(width: SsSpacing.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      component.title,
                      key: const Key('level-detail-component-title'),
                      style: typography.titleMedium,
                    ),
                    const SizedBox(height: SsSpacing.space1),
                    Text(
                      component.body,
                      key: const Key('level-detail-component-body'),
                      style: typography.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SsSpacing.space2),
              Flexible(
                child: Text(
                  '${component.xp} XP',
                  key: const Key('level-detail-component-value'),
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: typography.labelLarge.copyWith(color: colors.brand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience helper for the parent — resolves the five R06 components in
/// the canonical order using the supplied [ExperiencePoints] and the
/// caller's [AppLocalizations]. The function is pure (no rebuilds) so the
/// level-detail caller can pre-build it once.
List<LevelDetailXpComponent> buildR06XpComponents({
  required AppLocalizations l10n,
  required ExperiencePoints xp,
}) => <LevelDetailXpComponent>[
  LevelDetailXpComponent(
    title: l10n.gamificationLevelDetailXpComponentBaseTitle,
    body: l10n.gamificationLevelDetailXpComponentBaseBody,
    xp: xp.baseXp,
    semantics: l10n.gamificationLevelDetailXpComponentSemantics(
      l10n.gamificationLevelDetailXpComponentBaseTitle,
      l10n.gamificationLevelDetailXpComponentBaseBody,
      xp.baseXp,
    ),
  ),
  LevelDetailXpComponent(
    title: l10n.gamificationLevelDetailXpComponentDurationTitle,
    body: l10n.gamificationLevelDetailXpComponentDurationBody,
    xp: xp.durationXp,
    semantics: l10n.gamificationLevelDetailXpComponentSemantics(
      l10n.gamificationLevelDetailXpComponentDurationTitle,
      l10n.gamificationLevelDetailXpComponentDurationBody,
      xp.durationXp,
    ),
  ),
  LevelDetailXpComponent(
    title: l10n.gamificationLevelDetailXpComponentQualityTitle,
    body: l10n.gamificationLevelDetailXpComponentQualityBody,
    xp: xp.qualityXp,
    semantics: l10n.gamificationLevelDetailXpComponentSemantics(
      l10n.gamificationLevelDetailXpComponentQualityTitle,
      l10n.gamificationLevelDetailXpComponentQualityBody,
      xp.qualityXp,
    ),
  ),
  LevelDetailXpComponent(
    title: l10n.gamificationLevelDetailXpComponentImprovementTitle,
    body: l10n.gamificationLevelDetailXpComponentImprovementBody,
    xp: xp.improvementXp,
    semantics: l10n.gamificationLevelDetailXpComponentSemantics(
      l10n.gamificationLevelDetailXpComponentImprovementTitle,
      l10n.gamificationLevelDetailXpComponentImprovementBody,
      xp.improvementXp,
    ),
  ),
  LevelDetailXpComponent(
    title: l10n.gamificationLevelDetailXpComponentDiversityTitle,
    body: l10n.gamificationLevelDetailXpComponentDiversityBody,
    xp: xp.diversityXp,
    semantics: l10n.gamificationLevelDetailXpComponentSemantics(
      l10n.gamificationLevelDetailXpComponentDiversityTitle,
      l10n.gamificationLevelDetailXpComponentDiversityBody,
      xp.diversityXp,
    ),
  ),
];
