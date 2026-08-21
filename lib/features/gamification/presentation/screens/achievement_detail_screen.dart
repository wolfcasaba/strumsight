import 'package:flutter/material.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_definition.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_progress.dart';
import 'package:strumsight/features/gamification/presentation/widgets/achievement_tile.dart';
import 'package:strumsight/l10n/app_localizations.dart';

enum AchievementEvidenceReasonCode {
  measuredProgress,
  completionRecorded,
  unknown,
}

final class AchievementEvidence {
  AchievementEvidence({
    required this.reason,
    required this.current,
    required this.target,
  }) {
    if (!current.isFinite || current < 0) {
      throw ArgumentError.value(
        current,
        'current',
        'must be finite and nonnegative',
      );
    }
    if (!target.isFinite || target <= 0) {
      throw ArgumentError.value(
        target,
        'target',
        'must be finite and positive',
      );
    }
  }

  final AchievementEvidenceReasonCode reason;
  final num current;
  final num target;
}

class AchievementDetailScreen extends StatelessWidget {
  const AchievementDetailScreen({
    super.key,
    required this.achievementId,
    required this.definitions,
    required this.progressByAchievement,
    this.evidence,
  });

  final String achievementId;
  final List<AchievementDefinition> definitions;
  final Map<String, AchievementProgress> progressByAchievement;
  final AchievementEvidence? evidence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final definition = _definitionForId();
    if (definition == null) return _notFound(context, l10n);

    final progress = progressByAchievement[definition.id];
    if (definition.hidden && !achievementIsUnlocked(progress)) {
      return _hidden(context, l10n);
    }

    final content = localizedAchievementContent(l10n, definition);
    if (content == null) return _notFound(context, l10n);
    final percent = achievementPercent(progress);
    final completedAt = progress?.completedAt;
    final formattedCompletedAt = completedAt == null
        ? null
        : MaterialLocalizations.of(context).formatMediumDate(completedAt);
    final completion = formattedCompletedAt == null
        ? null
        : l10n.achievementUnlockedOn(formattedCompletedAt);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.achievementsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Semantics(
              container: true,
              label: formattedCompletedAt == null
                  ? l10n.achievementTileSemanticsInProgress(
                      achievementSemanticsDescription(
                        content.accessibilityDescription,
                      ),
                      percent,
                    )
                  : l10n.achievementTileSemanticsUnlocked(
                      achievementSemanticsDescription(
                        content.accessibilityDescription,
                      ),
                      percent,
                      formattedCompletedAt,
                    ),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(content.description),
                    const SizedBox(height: 16),
                    Text(l10n.achievementProgress(percent)),
                    if (completion != null) ...[
                      const SizedBox(height: 4),
                      Text(completion),
                    ],
                  ],
                ),
              ),
            ),
            if (evidence != null) ...[
              const SizedBox(height: 24),
              Text(
                l10n.achievementEvidenceTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_evidenceText(l10n, evidence!)),
            ],
          ],
        ),
      ),
    );
  }

  AchievementDefinition? _definitionForId() {
    for (final definition in definitions) {
      if (definition.id == achievementId) return definition;
    }
    return null;
  }

  Widget _notFound(BuildContext context, AppLocalizations l10n) => Scaffold(
    appBar: AppBar(title: Text(l10n.achievementsTitle)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_outlined),
            const SizedBox(height: 12),
            Text(l10n.achievementNotFoundTitle),
            const SizedBox(height: 4),
            Text(l10n.achievementNotFoundBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );

  Widget _hidden(BuildContext context, AppLocalizations l10n) => Scaffold(
    appBar: AppBar(title: Text(l10n.achievementsTitle)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline),
            const SizedBox(height: 12),
            Text(l10n.achievementHiddenTitle),
            const SizedBox(height: 4),
            Text(l10n.achievementHiddenBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

String _evidenceText(
  AppLocalizations l10n,
  AchievementEvidence evidence,
) => switch (evidence.reason) {
  AchievementEvidenceReasonCode.measuredProgress =>
    l10n.achievementEvidenceMeasuredProgress(evidence.current, evidence.target),
  AchievementEvidenceReasonCode.completionRecorded =>
    l10n.achievementEvidenceCompletionRecorded,
  AchievementEvidenceReasonCode.unknown => l10n.achievementEvidenceUnavailable,
};
