import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Caller-fed presentation of the offline reward ledger's pending and
/// quarantined state (brief §3 — "offline főkönyv, függő beváltás és
/// integritás-vizsgálat állapotok").
///
/// This widget NEVER credits a reward itself. [onRetry] is wired by the
/// caller to `ActivityEventIngestor.drain()` (§0.0.B/B4): the surface
/// operation for the pending-claim idempotency use case is retrying the
/// already-enqueued record, never an optimistic credit. Whether a retry
/// actually adds a ledger entry is decided by the ledger, not by this
/// widget — after a retry, the caller re-derives [pendingCount] from a
/// fresh read of the ledger/outbox and rebuilds this widget with the new
/// count.
class PendingRewardsCard extends StatelessWidget {
  const PendingRewardsCard({
    super.key,
    required this.pendingCount,
    required this.quarantinedCount,
    this.onRetry,
  }) : assert(pendingCount >= 0, 'pendingCount must not be negative'),
       assert(quarantinedCount >= 0, 'quarantinedCount must not be negative');

  /// Number of activity-outbox records not yet acknowledged by the ledger.
  final int pendingCount;

  /// Number of records the outbox has quarantined (attempt limit, capacity
  /// eviction, or a malformed record) — never framed as a lost reward, only
  /// as one that needs a closer look (brief §5.1 — no punitive language).
  final int quarantinedCount;

  /// Invoked when the user asks to retry the pending queue. `null` disables
  /// the retry action (e.g. while offline). The caller wires this to
  /// `ActivityEventIngestor.drain()` — this widget never calls it itself
  /// and never shows a credited balance ahead of the ledger confirming it.
  final VoidCallback? onRetry;

  bool get _isEmpty => pendingCount == 0 && quarantinedCount == 0;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GamificationThemeScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                container: true,
                label: l10n.rewardInboxPendingSemantics(pendingCount),
                child: ExcludeSemantics(
                  child: SsSurface(
                    key: const Key('pending-rewards-card'),
                    elevation: SsElevation.raised,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.cloud_sync_outlined,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      l10n.rewardInboxPendingTitle,
                                      key: const Key('pending-rewards-title'),
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.rewardInboxPendingBody(pendingCount),
                                      key: const Key('pending-rewards-body'),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: SsButton(
                              key: const Key('pending-rewards-retry-cta'),
                              label: l10n.rewardInboxPendingRetryCta,
                              variant: SsButtonVariant.secondary,
                              onPressed: onRetry,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (quarantinedCount > 0)
            Semantics(
              container: true,
              label:
                  '${l10n.rewardInboxIntegrityTitle}. '
                  '${l10n.rewardInboxIntegrityBody(quarantinedCount)}',
              child: ExcludeSemantics(
                child: SsSurface(
                  key: const Key('pending-rewards-integrity-card'),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.rewardInboxIntegrityTitle,
                                key: const Key(
                                  'pending-rewards-integrity-title',
                                ),
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.rewardInboxIntegrityBody(quarantinedCount),
                                key: const Key(
                                  'pending-rewards-integrity-body',
                                ),
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
        ],
      ),
    );
  }
}
