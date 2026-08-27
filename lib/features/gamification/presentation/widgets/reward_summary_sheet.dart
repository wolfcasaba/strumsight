import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/application/celebration_coordinator.dart';
import 'package:strumsight/features/gamification/domain/profile/reward_inbox_item.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Caller-fed behavioural switches for the summary sheet.
///
/// The haptic / sound toggles are caller-fed because the live settings
/// provider does not exist yet (ADR 0389 §6 — the wiring lands in round
/// 27, this round only consumes the values).
class RewardSummaryFeedback {
  const RewardSummaryFeedback({
    this.hapticsEnabled = true,
    this.soundEnabled = true,
  });

  /// Whether the celebration may emit a haptic pulse. Honoured by the
  /// surrounding presentation, NOT by the pure coordinator.
  final bool hapticsEnabled;

  /// Whether the celebration may play a confirmation sound. Same caveat.
  final bool soundEnabled;
}

/// Modal sheet that renders one already-drained [CelebrationSummary].
///
/// Renders the SAME content under reduced motion — the animation duration
/// collapses to zero but no information is dropped (brief §5.4 / §6 A7).
/// The sheet never offers a "claim" button — the reward is already
/// credited in the ledger (ADR 0389 §1 / brief §5.2).
class RewardSummarySheet extends StatelessWidget {
  RewardSummarySheet({
    super.key,
    required this.summary,
    this.feedback = const RewardSummaryFeedback(),
    this.reduceMotion = false,
  }) : assert(summary.events.isNotEmpty, 'summary must have events');

  final CelebrationSummary summary;
  final RewardSummaryFeedback feedback;

  /// Caller-fed reduced-motion preference (e.g. `GamificationPreferences.reduceMotion`).
  /// ORed with `MediaQuery.disableAnimationsOf` — either source collapses
  /// the transition duration to zero without dropping any content (brief
  /// §5.6 / §6 A8).
  final bool reduceMotion;

  /// Convenience for `showModalBottomSheet`.
  static Future<T?> show<T>(
    BuildContext context, {
    required CelebrationSummary summary,
    RewardSummaryFeedback feedback = const RewardSummaryFeedback(),
    bool reduceMotion = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => RewardSummarySheet(
        summary: summary,
        feedback: feedback,
        reduceMotion: reduceMotion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context) || reduceMotion;
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final theme = Theme.of(context);

    return GamificationThemeScope(
      child: Semantics(
        container: true,
        label: l10n.rewardSummaryConsolidatedSemantics(summary.count),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.celebration_outlined,
                      color: theme.colorScheme.primary,
                      semanticLabel: l10n.rewardSummaryTitle,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.rewardSummaryTitle,
                        key: const Key('reward-summary-title'),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                if (summary.count > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.rewardSummaryConsolidatedLabel(summary.count),
                    key: const Key('reward-summary-consolidated-label'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    key: const Key('reward-summary-events'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in summary.events)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SummaryEventTile(event: event),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: const Key('reward-summary-dismiss'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Dismiss'),
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

class _SummaryEventTile extends StatelessWidget {
  const _SummaryEventTile({required this.event});

  final RewardEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '${event.titleKey}. ${event.bodyKey}',
      child: ExcludeSemantics(
        child: SsSurface(
          elevation: SsElevation.raised,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconFor(event.kind),
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.titleKey,
                        key: const Key('reward-summary-event-title'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.bodyKey,
                        key: const Key('reward-summary-event-body'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (event.kind == RewardKind.levelUp &&
                          event.crossedLevelNumbers.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.crossedLevelNumbers.join(', '),
                          key: const Key('reward-summary-event-levels'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${event.earnedXp} XP',
                  key: const Key('reward-summary-event-xp'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
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
