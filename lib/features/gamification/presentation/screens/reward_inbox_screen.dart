import 'package:flutter/material.dart';

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
        body: SafeArea(
          child: widget.items.isEmpty
              ? Column(
                  children: [
                    if (widget.pendingCount > 0 || widget.quarantinedCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: PendingRewardsCard(
                          pendingCount: widget.pendingCount,
                          quarantinedCount: widget.quarantinedCount,
                          onRetry: widget.onRetryPending,
                        ),
                      ),
                    Expanded(
                      child: _EmptyState(
                        key: const Key('reward-inbox-empty'),
                        title: l10n.rewardInboxEmptyTitle,
                        body: l10n.rewardInboxEmptyBody,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    if (widget.pendingCount > 0 || widget.quarantinedCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: PendingRewardsCard(
                          pendingCount: widget.pendingCount,
                          quarantinedCount: widget.quarantinedCount,
                          onRetry: widget.onRetryPending,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l10n.rewardInboxCountSemantics(unseenCount),
                          key: const Key('reward-inbox-count'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        key: const Key('reward-inbox-list'),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: widget.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.title, required this.body});

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
              Icons.inbox_outlined,
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

class _InboxEntryTile extends StatelessWidget {
  const _InboxEntryTile({super.key, required this.item, required this.onTap});

  final RewardInboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          color: item.seen
              ? theme.colorScheme.surface
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: Key('reward-inbox-entry-tap-${item.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _iconFor(item.event.kind),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.event.titleKey,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            if (!item.seen)
                              Container(
                                key: Key('reward-inbox-entry-badge-${item.id}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  l10n.rewardInboxUnseenLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.event.bodyKey,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      l10n.rewardInboxEarnedXpLabel(item.event.earnedXp),
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
