import 'package:flutter/material.dart';

import 'quest_card.dart' show QuestRouteAction, QuestTryLiveAction;
import '../../domain/quests/challenge_definition.dart';
import '../../application/daily_challenge_service.dart'
    show DailyChallengeInstance;
import '../../../../l10n/app_localizations.dart';

/// Renders one caller-supplied daily challenge with no policy, navigation, or
/// clock dependency. The widget displays the typed description derived from
/// the sealed [DailyChallengeDefinition] and surfaces the completion badge
/// when the caller reports completion.
class ChallengeCard extends StatelessWidget {
  ChallengeCard({
    super.key,
    required this.title,
    required this.instance,
    required this.contentAvailable,
    required this.onAction,
  }) : assert(
         title.trim().isNotEmpty,
         'a challenge card must carry a caller-supplied title',
       );

  /// Human-readable title supplied by the caller (e.g. "Today's challenge").
  final String title;

  /// The caller-fed daily challenge instance. The widget reads `definition`
  /// and `completion` only.
  final DailyChallengeInstance instance;

  /// Whether the underlying content referenced by the definition is installed
  /// on the device. When `false` the CTA is disabled or replaced per the
  /// brief §5.3.
  final bool contentAvailable;

  /// Typed route action callback — never a free-text route.
  final ValueChanged<QuestRouteAction> onAction;

  bool get _completed => instance.completion != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description = _descriptionFor(l10n);
    final completed = _completed;

    return Semantics(
      container: true,
      label: completed
          ? l10n.challengeSemanticsCompleted(description)
          : l10n.challengeSemanticsActive(description),
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const Key('challenge-card-body'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChallengeHeader(title: title, completed: completed),
                const SizedBox(height: 8),
                Text(
                  l10n.challengeDailyBody,
                  key: const Key('challenge-body'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _ChallengeDescription(text: description),
                if (completed) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        key: const Key('challenge-completed-icon'),
                        semanticLabel: 'completed',
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.challengeCompletedToday,
                        key: const Key('challenge-completed-label'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
                if (!contentAvailable) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.challengeUnavailableBody,
                    key: const Key('challenge-unavailable-body'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                _ChallengeCta(
                  contentAvailable: contentAvailable,
                  onAction: () =>
                      onAction(QuestTryLiveAction(instance.definition)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _descriptionFor(AppLocalizations l10n) {
    final definition = instance.definition;
    return switch (definition) {
      StrumPatternChallenge(:final pattern, :final name) =>
        '${l10n.challengeStrumName(name)} (${pattern.length} steps)',
      ChordChangeChallenge(
        :final fromChordId,
        :final toChordId,
        :final beats,
      ) =>
        l10n.challengeChordChange(fromChordId, toChordId, beats),
      RhythmChallenge(:final contentId, :final targetBpm) =>
        l10n.challengeRhythm(contentId, targetBpm),
      SongSectionChallenge(
        :final songId,
        :final sectionId,
        :final repetitions,
      ) =>
        l10n.challengeSongSection(sectionId, songId, repetitions),
      TimingChallenge(:final contentId, :final targetWindowMs) =>
        l10n.challengeTiming(targetWindowMs, contentId),
    };
  }
}

class _ChallengeHeader extends StatelessWidget {
  const _ChallengeHeader({required this.title, required this.completed});

  final String title;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            key: const Key('challenge-title'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (completed)
          Icon(
            Icons.check_circle_outline,
            key: const Key('challenge-completed-badge'),
            semanticLabel: 'completed',
            size: 20,
            color: theme.colorScheme.primary,
          ),
      ],
    );
  }
}

class _ChallengeDescription extends StatelessWidget {
  const _ChallengeDescription({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      key: const Key('challenge-description'),
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class _ChallengeCta extends StatelessWidget {
  const _ChallengeCta({required this.contentAvailable, required this.onAction});

  final bool contentAvailable;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton(
        key: const Key('challenge-cta'),
        onPressed: contentAvailable ? onAction : null,
        child: Text(
          contentAvailable ? _activeLabel(context) : _disabledLabel(context),
          semanticsLabel: contentAvailable
              ? _activeSemantics(context)
              : _disabledSemantics(context),
        ),
      ),
    );
  }

  String _activeLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n.challengePlayAlong;
  }

  String _activeSemantics(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n.challengePlayAlong;
  }

  String _disabledLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n.questUnavailableBadge;
  }

  String _disabledSemantics(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n.questUnavailableBadge;
  }
}
