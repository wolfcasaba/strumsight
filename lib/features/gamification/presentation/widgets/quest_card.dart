import 'package:flutter/material.dart';

import '../../domain/quests/quest_definition.dart';
import '../../domain/quests/quest_objective.dart';
import '../../domain/quests/quest_progress.dart';
import '../../domain/quests/quest_schedule.dart';
import '../../../../l10n/app_localizations.dart';

/// Typed route action emitted by a quest or challenge card. The widget layer
/// never navigates — the parent translates the action into a real route
/// registration (round 30). Free-text route strings are forbidden (brief §5.3).
sealed class QuestRouteAction {
  const QuestRouteAction();
}

/// Open the practice flow for the supplied [objective] — start a fresh session
/// when the quest has no progress yet.
final class QuestStartPracticeAction extends QuestRouteAction {
  const QuestStartPracticeAction(this.objective);
  final QuestObjective objective;
}

/// Resume the practice flow for an in-progress quest with the supplied
/// [objective].
final class QuestContinuePracticeAction extends QuestRouteAction {
  const QuestContinuePracticeAction(this.objective);
  final QuestObjective objective;
}

/// Open the live session for a daily challenge targeting the supplied
/// [definition].
final class QuestTryLiveAction extends QuestRouteAction {
  const QuestTryLiveAction(this.definition);
  final DailyChallengeDefinitionBridge definition;
}

/// Marker action surfaced when the challenge's underlying content is not
/// installed — the screen disables the CTA instead of invoking navigation.
final class QuestUnavailableAction extends QuestRouteAction {
  const QuestUnavailableAction();
}

/// Forward-declared bridge so the shared action type can name the challenge
/// definition without importing the full challenge_definition file. The
/// challenge card adapts its real definition to this record.
typedef DailyChallengeDefinitionBridge = Object;

/// Renders one quest supplied by the caller with no policy or repository
/// dependency. The card NEVER computes progress, never sums rewards, and never
/// runs a clock — every value is provided by the caller (ADR 0290 §2).
class QuestCard extends StatelessWidget {
  QuestCard({
    super.key,
    required this.title,
    required this.definition,
    required this.progress,
    required this.targetUnits,
    required this.completedUnits,
    required this.contentAvailable,
    required this.sourcePlanLabel,
    required this.onAction,
    required this.now,
  }) : assert(targetUnits >= 1, 'targetUnits must be positive'),
       assert(completedUnits >= 0, 'completedUnits must not be negative'),
       assert(
         title.trim().isNotEmpty,
         'a quest card must carry a caller-supplied title',
       );

  /// Human-readable quest title supplied by the caller (e.g. a plan-block
  /// title for a `PlanBlockQuestObjective`). The widget never invents one.
  final String title;

  /// The authored quest definition. The widget reads cadence, objective, and
  /// reward from it.
  final QuestDefinition definition;

  /// Caller-fed progress for this quest instance.
  final QuestProgress progress;

  /// Caller-fed target units (sourced from the weekly quest projection).
  final int targetUnits;

  /// Caller-fed completed units (sourced from the weekly quest projection).
  final int completedUnits;

  /// Whether the quest's underlying content is installed on the device. When
  /// `false` the CTA is disabled or replaced per the brief §5.3.
  final bool contentAvailable;

  /// Optional caller-supplied label for the originating plan block. When
  /// non-null and the objective is a `PlanBlockQuestObjective`, the card
  /// surfaces the source-plan connection (brief A5).
  final String? sourcePlanLabel;

  /// Typed route action callback — never a free-text route.
  final ValueChanged<QuestRouteAction> onAction;

  /// Caller-fed clock — keeps the time-bound rendering deterministic in
  /// widget tests.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final completed = progress.status == QuestStatus.completed;
    final archived =
        progress.status == QuestStatus.archived ||
        progress.status == QuestStatus.expired ||
        progress.status == QuestStatus.replaced;
    final showExpiry =
        !completed && !archived && progress.status == QuestStatus.active;
    final sourceLabel = _sourceLabel(l10n);
    final inProgress = completedUnits > 0 && !completed && !archived;
    final canStart = contentAvailable && !completed && !archived;

    return Semantics(
      container: true,
      label: _semanticsLabel(l10n),
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const Key('quest-card-body'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _QuestHeader(
                  title: title,
                  completed: completed,
                  archived: archived,
                ),
                const SizedBox(height: 8),
                _QuestProgress(
                  completed: completed,
                  archived: archived,
                  completedUnits: completedUnits,
                  targetUnits: targetUnits,
                  semantics: l10n.questProgressSemantics(
                    completedUnits,
                    targetUnits,
                  ),
                  label: l10n.questProgressLabel(completedUnits, targetUnits),
                ),
                const SizedBox(height: 12),
                _QuestReward(
                  xp: definition.reward.totalXp,
                  completed: completed || archived,
                  creditedLabel: l10n.questRewardAlreadyCredited,
                  xpLabel: l10n.questRewardLabel(definition.reward.totalXp),
                  semanticsLabel: l10n.questRewardSemantics(
                    definition.reward.totalXp,
                  ),
                ),
                if (sourceLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sourceLabel,
                    key: const Key('quest-source-label'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (showExpiry) ...[
                  const SizedBox(height: 8),
                  Text(
                    _expiryLabel(l10n, definition.schedule),
                    key: const Key('quest-expiry-label'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!contentAvailable) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.questUnavailableBody,
                    key: const Key('quest-unavailable-body'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (completed) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.questCompletedBody,
                    key: const Key('quest-completed-body'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                _QuestCta(
                  canStart: canStart,
                  contentAvailable: contentAvailable,
                  inProgress: inProgress,
                  startLabel: l10n.questStartCta,
                  continueLabel: l10n.questContinueCta,
                  unavailableLabel: l10n.questUnavailableBadge,
                  startSemantics: l10n.questStartSemantics(title),
                  continueSemantics: l10n.questContinueSemantics(title),
                  onAction: () {
                    if (inProgress) {
                      onAction(
                        QuestContinuePracticeAction(definition.objective),
                      );
                    } else {
                      onAction(QuestStartPracticeAction(definition.objective));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _sourceLabel(AppLocalizations l10n) {
    if (sourcePlanLabel != null && sourcePlanLabel!.trim().isNotEmpty) {
      return sourcePlanLabel;
    }
    return switch (definition.objective) {
      SkillTagQuestObjective(:final skillTag) => l10n.questSourceSkillLabel(
        skillTag,
      ),
      PracticeModeQuestObjective() => l10n.questSourceModeLabel,
      MetricQuestObjective(:final metric) => l10n.questSourceMetricLabel(
        metric.code,
      ),
      PlanBlockQuestObjective() => null,
      UnknownQuestObjective() => null,
    };
  }

  String _expiryLabel(AppLocalizations l10n, QuestSchedule schedule) {
    if (!schedule.isActiveAt(now)) {
      return l10n.questExpiredBadge;
    }
    final remaining = schedule.expiresAt.difference(now.toUtc());
    if (definition.cadence == QuestCadence.daily && remaining.inHours < 24) {
      return l10n.questExpiryToday;
    }
    if (definition.cadence == QuestCadence.weekly && remaining.inDays <= 7) {
      return l10n.questExpiryWeekly;
    }
    return l10n.questExpiryDate(
      MaterialLocalizations.of(context).formatMediumDate(schedule.expiresAt),
    );
  }

  String _semanticsLabel(AppLocalizations l10n) {
    final progressSemantics = l10n.questProgressSemantics(
      completedUnits,
      targetUnits,
    );
    final rewardSemantics = l10n.questRewardSemantics(
      definition.reward.totalXp,
    );
    if (progress.status == QuestStatus.completed) {
      return l10n.questCompletedSemantics(title) +
          ' ' +
          progressSemantics +
          ' ' +
          rewardSemantics;
    }
    if (!contentAvailable) {
      return '$title. $progressSemantics $rewardSemantics ${l10n.questUnavailableBody}';
    }
    return '$title. $progressSemantics $rewardSemantics';
  }
}

class _QuestHeader extends StatelessWidget {
  const _QuestHeader({
    required this.title,
    required this.completed,
    required this.archived,
  });

  final String title;
  final bool completed;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            key: const Key('quest-title'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (completed)
          Icon(
            Icons.check_circle_outline,
            key: const Key('quest-completed-badge'),
            semanticLabel: 'completed',
            size: 20,
            color: theme.colorScheme.primary,
          )
        else if (archived)
          Icon(
            Icons.archive_outlined,
            key: const Key('quest-archived-badge'),
            semanticLabel: 'archived',
            size: 20,
            color: theme.colorScheme.outline,
          ),
      ],
    );
  }
}

class _QuestProgress extends StatelessWidget {
  const _QuestProgress({
    required this.completed,
    required this.archived,
    required this.completedUnits,
    required this.targetUnits,
    required this.label,
    required this.semantics,
  });

  final bool completed;
  final bool archived;
  final int completedUnits;
  final int targetUnits;
  final String label;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = targetUnits == 0
        ? 0.0
        : (completedUnits / targetUnits).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: semantics,
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const Key('quest-progress-bar'),
                value: completed || archived ? 1.0 : ratio,
                minHeight: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          key: const Key('quest-progress-label'),
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _QuestReward extends StatelessWidget {
  const _QuestReward({
    required this.xp,
    required this.completed,
    required this.creditedLabel,
    required this.xpLabel,
    required this.semanticsLabel,
  });

  final int xp;
  final bool completed;
  final String creditedLabel;
  final String xpLabel;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.star_outline,
          size: 18,
          color: theme.colorScheme.primary,
          semanticLabel: semanticsLabel,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            completed ? creditedLabel : xpLabel,
            key: const Key('quest-reward-label'),
            style: theme.textTheme.bodyMedium,
            semanticsLabel: semanticsLabel,
          ),
        ),
      ],
    );
  }
}

class _QuestCta extends StatelessWidget {
  const _QuestCta({
    required this.canStart,
    required this.contentAvailable,
    required this.inProgress,
    required this.startLabel,
    required this.continueLabel,
    required this.unavailableLabel,
    required this.startSemantics,
    required this.continueSemantics,
    required this.onAction,
  });

  final bool canStart;
  final bool contentAvailable;
  final bool inProgress;
  final String startLabel;
  final String continueLabel;
  final String unavailableLabel;
  final String startSemantics;
  final String continueSemantics;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    if (!contentAvailable) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          unavailableLabel,
          key: const Key('quest-cta-disabled'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final label = inProgress ? continueLabel : startLabel;
    final semantics = inProgress ? continueSemantics : startSemantics;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton(
        key: const Key('quest-cta'),
        onPressed: canStart ? onAction : null,
        child: Text(label, semanticsLabel: semantics),
      ),
    );
  }
}
