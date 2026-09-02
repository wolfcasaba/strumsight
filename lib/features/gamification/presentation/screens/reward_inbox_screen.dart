import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/domain/profile/reward_inbox_item.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/features/gamification/presentation/widgets/pending_rewards_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Read-only postaláda screen.
///
/// The screen is explicitly NOT a claim mechanism (brief §5.2 / ADR 0389
/// §4): it never offers a "claim" button, never expires items, and never
/// mutates the ledger. Its only side effects are:
///
///  * marking items as seen (display state only),
///  * forwarding a typed item-selection to the caller's router, and
///  * forwarding a retry request for the offline outbox via [onRetryPending]
///    — wired by the caller to `ActivityEventIngestor.drain()`
///    (§0.0.B/B4). The screen never calls it itself and never derives a
///    credited balance; [pendingCount]/[quarantinedCount] are caller-fed
///    reads of the outbox, refreshed by the caller after each retry.
class RewardInboxScreen extends StatefulWidget {
  const RewardInboxScreen({
    super.key,
    required this.items,
    required this.onItemSelected,
    required this.onMarkSeen,
    this.pendingCount = 0,
    this.quarantinedCount = 0,
    this.onRetryPending,
  });

  /// The inbox items to render. Caller-supplied — the screen never reads
  /// from storage directly.
  final List<RewardInboxItem> items;

  /// Forwarded when the user opens an item. The parent owns the
  /// navigation (free-text route strings are forbidden elsewhere; this
  /// callback keeps the screen route-agnostic).
  final ValueChanged<RewardInboxItem> onItemSelected;

  /// Called when the screen wants an item's `seen` flag to flip. The parent
  /// is responsible for persisting the change — the screen is purely a
  /// view of the caller-supplied list.
  final ValueChanged<RewardInboxItem> onMarkSeen;

  /// Caller-fed count of activity-outbox records not yet acknowledged by
  /// the ledger. Zero (the default) renders no pending-rewards surface.
  final int pendingCount;

  /// Caller-fed count of quarantined outbox records.
  final int quarantinedCount;

  /// Invoked when the user taps the retry CTA. `null` disables the CTA.
  final VoidCallback? onRetryPending;

  @override
  State<RewardInboxScreen> createState() => _RewardInboxScreenState();
}

class _RewardInboxScreenState extends State<RewardInboxScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unseenCount = widget.items.where((i) => !i.seen).length;
    return GamificationThemeScope(
      child: Scaffold(
        appBar: AppBar(
          title: Semantics(header: true, child: Text(l10n.rewardInboxTitle)),
        ),
        // A single CustomScrollView (not a Column+Expanded(ListView)) so the
        // pending-rewards card, count header, and item rows all scroll
        // together — at large text scale the fixed-size header rows could
        // otherwise outgrow the viewport and force the Expanded list into
        // negative space, overflowing (§0.0.A/R5/R6, same pattern fixed for
        // both branches below since only one caused the probe to fail).
        body: SafeArea(
          child: CustomScrollView(
            key: const Key('reward-inbox-list'),
            slivers: [
              if (widget.pendingCount > 0 || widget.quarantinedCount > 0)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SsSpacing.space5,
                    SsSpacing.space3,
                    SsSpacing.space5,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: PendingRewardsCard(
                      pendingCount: widget.pendingCount,
                      quarantinedCount: widget.quarantinedCount,
                      onRetry: widget.onRetryPending,
                    ),
                  ),
                ),
              if (widget.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    key: const Key('reward-inbox-empty'),
                    title: l10n.rewardInboxEmptyTitle,
                    body: l10n.rewardInboxEmptyBody,
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SsSpacing.space5,
                    SsSpacing.space3,
                    SsSpacing.space5,
                    SsSpacing.space2,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      // Builder gives a fresh context INSIDE the
                      // GamificationThemeScope subtree — the outer
                      // `context` sits above the merged theme, so
                      // resolving the SS extension on it would
                      // null-check against the ambient (non-DS) theme.
                      child: Builder(
                        builder: (context) => Text(
                          l10n.rewardInboxCountSemantics(unseenCount),
                          key: const Key('reward-inbox-count'),
                          style: Theme.of(
                            context,
                          ).extension<SsTypography>()!.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SsSpacing.space5,
                    SsSpacing.space1,
                    SsSpacing.space5,
                    SsSpacing.space6,
                  ),
                  sliver: SliverList.separated(
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: SsSpacing.space3),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return _InboxEntryTile(
                        key: Key('reward-inbox-entry-${item.id}'),
                        item: item,
                        onTap: () => _onTap(item),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(RewardInboxItem item) {
    if (!item.seen) {
      widget.onMarkSeen(item);
    }
    widget.onItemSelected(item);
  }
}

// Screen-local, token-styled — NOT SsEmptyState: the inbox is a read-only
// ledger view (brief §5.2 / ADR 0389 §4 — no claim action exists anywhere
// on this screen), so there is no real next step to attach as the required
// SsEmptyState action (brief §0.0.A/R7, same exception class as
// E15-R06/R07's empty states).
class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: colors.textSecondary,
              semanticLabel: title,
            ),
            const SizedBox(height: SsSpacing.space3),
            Text(
              title,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxEntryTile extends StatelessWidget {
  const _InboxEntryTile({super.key, required this.item, required this.onTap});

  final RewardInboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final l10n = AppLocalizations.of(context);
    final semantics = l10n.rewardInboxEntrySemantics(
      item.event.titleKey,
      item.event.earnedXp,
      item.event.bodyKey,
    );

    return Semantics(
      button: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Material(
          color: item.seen ? colors.surface : colors.surfaceRaised,
          borderRadius: BorderRadius.circular(SsRadius.lg),
          child: InkWell(
            key: Key('reward-inbox-entry-tap-${item.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(SsRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(SsSpacing.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_iconFor(item.event.kind), color: colors.brand),
                  const SizedBox(width: SsSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.event.titleKey,
                                style: typography.titleMedium,
                              ),
                            ),
                            if (!item.seen)
                              Container(
                                key: Key('reward-inbox-entry-badge-${item.id}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: SsSpacing.space2,
                                  vertical: SsSpacing.space1 / 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.brand,
                                  borderRadius: BorderRadius.circular(
                                    SsRadius.sm,
                                  ),
                                ),
                                child: Text(
                                  l10n.rewardInboxUnseenLabel,
                                  style: typography.labelLarge.copyWith(
                                    color: colors.onBrand,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: SsSpacing.space1),
                        Text(item.event.bodyKey, style: typography.bodyMedium),
                      ],
                    ),
                  ),
                  const SizedBox(width: SsSpacing.space3),
                  Flexible(
                    child: Text(
                      l10n.rewardInboxEarnedXpLabel(item.event.earnedXp),
                      maxLines: 2,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: typography.labelLarge.copyWith(
                        color: colors.brand,
                      ),
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

  IconData _iconFor(RewardKind kind) => switch (kind) {
    RewardKind.dailyReward => Icons.star_outline,
    RewardKind.questCompleted => Icons.task_alt,
    RewardKind.challengeCompleted => Icons.flash_on_outlined,
    RewardKind.levelUp => Icons.trending_up,
    RewardKind.masteryMilestone => Icons.workspace_premium_outlined,
  };
}
