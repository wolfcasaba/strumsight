import 'package:flutter/material.dart';

import 'package:strumsight/features/gamification/domain/profile/gamification_profile.dart';
import 'package:strumsight/features/gamification/presentation/widgets/level_badge.dart';
import 'package:strumsight/features/gamification/presentation/widgets/xp_progress_bar.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Caller-fed description of the latest measured session surfaced on the Hub.
///
/// The widget layer never reads the ledger or any reward event — the parent
/// owns the projection and decides whether to show an entry or an empty
/// state. The Hub is therefore a pure layout container with no policy.
class LatestHubResult {
  const LatestHubResult({
    required this.title,
    required this.body,
    required this.earnedXp,
  });

  final String title;
  final String body;
  final int earnedXp;
}

/// The non-dominant overview screen — surfaces the gamification state
/// without replacing the dedicated screens for quests, streaks, achievements
/// or the reward inbox. Visual separation between XP (a progress bar) and
/// the XP-derived level (a circular medallion badge) is enforced by the two
/// dedicated widgets ([XpProgressBar], [LevelBadge]) — the Hub never
/// collapses them into a single surface, and never mislabels the
/// XP-derived level as skill mastery (ADR 0289, brief §5.1).
class GamificationHubScreen extends StatelessWidget {
  const GamificationHubScreen({
    super.key,
    required this.profile,
    required this.activeQuestCount,
    required this.streakCurrentDays,
    required this.masteryUnlockedCount,
    required this.inboxUnseenCount,
    required this.onOpenLevelDetail,
    required this.onOpenInbox,
    required this.onOpenAchievements,
    required this.onOpenStreak,
    required this.onOpenQuests,
    required this.onOpenMastery,
    this.latestResult,
    this.isLegacyEmpty = false,
  }) : assert(activeQuestCount >= 0, 'activeQuestCount must not be negative'),
       assert(streakCurrentDays >= 0, 'streakCurrentDays must not be negative'),
       assert(
         masteryUnlockedCount >= 0,
         'masteryUnlockedCount must not be negative',
       ),
       assert(inboxUnseenCount >= 0, 'inboxUnseenCount must not be negative');

  /// Caller-supplied current [GamificationProfile].
  final GamificationProfile profile;

  final int activeQuestCount;
  final int streakCurrentDays;
  final int masteryUnlockedCount;
  final int inboxUnseenCount;

  /// Caller-supplied latest measured session, or `null` when the user has
  /// not completed one yet.
  final LatestHubResult? latestResult;

  /// `true` when the user is on the legacy path (history exists but no
  /// current projection is available yet). Surfaces a different empty state
  /// — the brief §3 distinguishes legacy from new.
  final bool isLegacyEmpty;

  final VoidCallback onOpenLevelDetail;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenAchievements;
  final VoidCallback onOpenStreak;
  final VoidCallback onOpenQuests;
  final VoidCallback onOpenMastery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final showEmpty = _isEmpty();
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.gamificationHubTitle)),
      ),
      body: SafeArea(
        child: showEmpty
            ? _EmptyHubState(
                key: const Key('gamification-hub-empty'),
                isLegacy: isLegacyEmpty,
                title: isLegacyEmpty
                    ? l10n.gamificationHubEmptyLegacyTitle
                    : l10n.gamificationHubEmptyNewTitle,
                body: isLegacyEmpty
                    ? l10n.gamificationHubEmptyLegacyBody
                    : l10n.gamificationHubEmptyNewBody,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _SectionHeader(
                    icon: Icons.workspace_premium_outlined,
                    title: l10n.gamificationHubSkillSectionTitle,
                    body: l10n.gamificationHubSkillSectionBody,
                    accent: theme.colorScheme.secondary,
                    semantics: l10n.gamificationHubSkillSectionTitle,
                  ),
                  const SizedBox(height: 8),
                  LevelBadge(level: profile.currentLevel),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    icon: Icons.star_outline,
                    title: l10n.gamificationHubXpSectionTitle,
                    body: l10n.gamificationHubXpSectionBody,
                    accent: theme.colorScheme.primary,
                    semantics: l10n.gamificationHubXpSectionTitle,
                  ),
                  const SizedBox(height: 8),
                  XpProgressBar(
                    xpIntoCurrentLevel: profile.xpIntoCurrentLevel,
                    xpToNextLevel: profile.xpToNextLevel,
                    totalXp: profile.totalXp,
                  ),
                  const SizedBox(height: 16),
                  _InboxIndicator(
                    unseenCount: inboxUnseenCount,
                    title: l10n.gamificationHubInboxIndicatorTitle,
                    cta: l10n.gamificationHubInboxIndicatorCta,
                    semantics: l10n.gamificationHubInboxIndicatorSemantics(
                      inboxUnseenCount,
                    ),
                    onTap: onOpenInbox,
                  ),
                  const SizedBox(height: 16),
                  _CountSummaryTile(
                    key: const Key('gamification-hub-quests-tile'),
                    icon: Icons.flag_outlined,
                    title: l10n.gamificationHubQuestsTitle,
                    summary: l10n.gamificationHubQuestsSummary(
                      activeQuestCount,
                    ),
                    semantics: l10n.gamificationHubQuestsSemantics(
                      activeQuestCount,
                    ),
                    onTap: onOpenQuests,
                  ),
                  const SizedBox(height: 12),
                  _CountSummaryTile(
                    key: const Key('gamification-hub-streak-tile'),
                    icon: Icons.local_fire_department_outlined,
                    title: l10n.gamificationHubStreakTitle,
                    summary: l10n.gamificationHubStreakSummary(
                      streakCurrentDays,
                    ),
                    semantics:
                        '${l10n.gamificationHubStreakTitle}. ${l10n.gamificationHubStreakSummary(streakCurrentDays)}',
                    onTap: onOpenStreak,
                  ),
                  const SizedBox(height: 12),
                  _CountSummaryTile(
                    key: const Key('gamification-hub-mastery-tile'),
                    icon: Icons.workspace_premium_outlined,
                    title: l10n.gamificationHubMasteryTitle,
                    summary: l10n.gamificationHubMasterySummary(
                      masteryUnlockedCount,
                    ),
                    semantics: l10n.gamificationHubMasterySummary(
                      masteryUnlockedCount,
                    ),
                    onTap: onOpenMastery,
                  ),
                  const SizedBox(height: 12),
                  _CountSummaryTile(
                    key: const Key('gamification-hub-achievements-tile'),
                    icon: Icons.emoji_events_outlined,
                    title: l10n.gamificationHubAchievementsTitle,
                    summary: l10n.gamificationHubMasterySummary(
                      masteryUnlockedCount,
                    ),
                    semantics: l10n.gamificationHubAchievementsTitle,
                    onTap: onOpenAchievements,
                  ),
                  const SizedBox(height: 20),
                  _LatestResultCard(
                    result: latestResult,
                    emptyTitle: l10n.gamificationHubLatestResultEmptyTitle,
                    emptyBody: l10n.gamificationHubLatestResultEmptyBody,
                    sectionTitle: l10n.gamificationHubLatestResultTitle,
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      key: const Key('gamification-hub-level-detail-cta'),
                      onPressed: onOpenLevelDetail,
                      icon: const Icon(Icons.info_outline),
                      label: Text(l10n.gamificationHubOpenLevelDetailCta),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.gamificationHubOfflineReadyLabel,
                          key: const Key('gamification-hub-offline-label'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// The brief §3 distinguishes a legacy empty state (history exists) from
  /// a brand-new empty state (no measured sessions yet). The Hub collapses
  /// to its empty surface whenever the profile has zero XP AND the caller
  /// reports no other measured signal.
  bool _isEmpty() {
    if (isLegacyEmpty) return true;
    final hasAnySignal =
        activeQuestCount > 0 ||
        streakCurrentDays > 0 ||
        masteryUnlockedCount > 0 ||
        latestResult != null;
    return profile.totalXp == 0 && !hasAnySignal;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    required this.semantics,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: '$semantics. $body',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(body, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InboxIndicator extends StatelessWidget {
  const _InboxIndicator({
    required this.unseenCount,
    required this.title,
    required this.cta,
    required this.semantics,
    required this.onTap,
  });

  final int unseenCount;
  final String title;
  final String cta;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = unseenCount == 0 ? 'No new rewards' : semantics;
    return Semantics(
      button: true,
      label: '$title. $status. Tap to open.',
      child: ExcludeSemantics(
        child: InkWell(
          key: const Key('gamification-hub-inbox-indicator'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: const Key('gamification-hub-inbox-title'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        semantics,
                        key: const Key('gamification-hub-inbox-status'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    cta,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountSummaryTile extends StatelessWidget {
  const _CountSummaryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $summary.',
      child: ExcludeSemantics(
        child: InkWell(
          key: const Key('gamification-hub-summary-tile'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(summary, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestResultCard extends StatelessWidget {
  const _LatestResultCard({
    required this.result,
    required this.emptyTitle,
    required this.emptyBody,
    required this.sectionTitle,
  });

  final LatestHubResult? result;
  final String emptyTitle;
  final String emptyBody;
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('gamification-hub-latest-result'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sectionTitle,
            key: const Key('gamification-hub-latest-result-title'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          if (result == null)
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emptyTitle, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(emptyBody, style: theme.textTheme.bodyMedium),
                ],
              ),
            )
          else
            Semantics(
              container: true,
              label: l10n.gamificationHubLatestResultSemantics(
                result!.title,
                result!.earnedXp,
              ),
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.history_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            result!.title,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(result!.body, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '+${result!.earnedXp} XP',
                        maxLines: 2,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyHubState extends StatelessWidget {
  const _EmptyHubState({
    super.key,
    required this.isLegacy,
    required this.title,
    required this.body,
  });

  final bool isLegacy;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLegacy ? Icons.history_toggle_off_outlined : Icons.timeline,
              size: 48,
              color: theme.colorScheme.outline,
              semanticLabel: title,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
