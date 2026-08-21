import 'package:flutter/material.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_definition.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_progress.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class AchievementTile extends StatelessWidget {
  const AchievementTile({
    super.key,
    required this.definition,
    required this.progress,
  });

  final AchievementDefinition definition;
  final AchievementProgress? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (definition.hidden && !achievementIsUnlocked(progress)) {
      return Semantics(
        container: true,
        label: l10n.achievementHiddenTitle,
        child: ExcludeSemantics(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.achievementHiddenTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      );
    }

    final content = localizedAchievementContent(l10n, definition);
    if (content == null) return const SizedBox.shrink();
    final percent = achievementPercent(progress);
    final completedAt = progress?.completedAt;
    final completion = completedAt == null
        ? null
        : l10n.achievementUnlockedOn(
            MaterialLocalizations.of(context).formatMediumDate(completedAt!),
          );
    final semantics = completion == null
        ? l10n.achievementTileSemanticsInProgress(
            achievementSemanticsDescription(content.accessibilityDescription),
            percent,
          )
        : l10n.achievementTileSemanticsUnlocked(
            achievementSemanticsDescription(content.accessibilityDescription),
            percent,
            MaterialLocalizations.of(context).formatMediumDate(completedAt!),
          );

    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(content.description),
                const SizedBox(height: 12),
                Text(l10n.achievementProgress(percent)),
                if (completion != null) ...[
                  const SizedBox(height: 4),
                  Text(completion),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool achievementIsUnlocked(AchievementProgress? progress) =>
    progress?.completedAt != null && progress?.rewardLedgerEntryId != null;

int achievementPercent(AchievementProgress? progress) {
  final value = progress?.value ?? 0;
  return (value.clamp(0, 1) * 100).round();
}

String achievementSemanticsDescription(String description) =>
    description.endsWith('.')
    ? description.substring(0, description.length - 1)
    : description;

String localizedAchievementCategory(
  AppLocalizations l10n,
  AchievementCategory category,
) => switch (category) {
  AchievementCategory.consistency => l10n.achievementCategoryConsistency,
  AchievementCategory.practice => l10n.achievementCategoryPractice,
  AchievementCategory.songs => l10n.achievementCategorySongs,
  AchievementCategory.rhythm => l10n.achievementCategoryRhythm,
  AchievementCategory.chords => l10n.achievementCategoryChords,
  AchievementCategory.technique => l10n.achievementCategoryTechnique,
  AchievementCategory.analysis => l10n.achievementCategoryAnalysis,
  AchievementCategory.exploration => l10n.achievementCategoryExploration,
  AchievementCategory.personalBest => l10n.achievementCategoryPersonalBest,
  AchievementCategory.accessibilityNeutral =>
    l10n.achievementCategoryAccessibilityNeutral,
};

_AchievementContent? localizedAchievementContent(
  AppLocalizations l10n,
  AchievementDefinition definition,
) {
  final title = switch (definition.titleKey) {
    'achievementFirstValidSessionTitle' =>
      l10n.achievementFirstValidSessionTitle,
    'achievementPracticeStarterTitle' => l10n.achievementPracticeStarterTitle,
    'achievementPracticeBuilderTitle' => l10n.achievementPracticeBuilderTitle,
    'achievementPracticeRegularTitle' => l10n.achievementPracticeRegularTitle,
    'achievementPracticeDevoteeTitle' => l10n.achievementPracticeDevoteeTitle,
    'achievementRhythmFirstStepsTitle' => l10n.achievementRhythmFirstStepsTitle,
    'achievementRhythmBuilderOneTitle' => l10n.achievementRhythmBuilderOneTitle,
    'achievementRhythmBuilderTwoTitle' => l10n.achievementRhythmBuilderTwoTitle,
    'achievementRhythmBuilderThreeTitle' =>
      l10n.achievementRhythmBuilderThreeTitle,
    'achievementSongFirstFinishTitle' => l10n.achievementSongFirstFinishTitle,
    'achievementSongExplorerOneTitle' => l10n.achievementSongExplorerOneTitle,
    'achievementSongExplorerTwoTitle' => l10n.achievementSongExplorerTwoTitle,
    'achievementAnalysisFirstReviewTitle' =>
      l10n.achievementAnalysisFirstReviewTitle,
    'achievementAnalysisInsightTitle' => l10n.achievementAnalysisInsightTitle,
    'achievementPlanFirstBlockTitle' => l10n.achievementPlanFirstBlockTitle,
    'achievementPlanPathfinderTitle' => l10n.achievementPlanPathfinderTitle,
    'achievementTutorFirstCheckinTitle' =>
      l10n.achievementTutorFirstCheckinTitle,
    'achievementVisionFirstObservationTitle' =>
      l10n.achievementVisionFirstObservationTitle,
    'achievementSourceExplorerTitle' => l10n.achievementSourceExplorerTitle,
    'achievementBalancedPracticeWeekTitle' =>
      l10n.achievementBalancedPracticeWeekTitle,
    'achievementXpFirstHundredTitle' => l10n.achievementXpFirstHundredTitle,
    'achievementLegacyFirstStepTitle' => l10n.achievementLegacyFirstStepTitle,
    _ => null,
  };
  final description = switch (definition.descriptionKey) {
    'achievementFirstValidSessionDescription' =>
      l10n.achievementFirstValidSessionDescription,
    'achievementPracticeStarterDescription' =>
      l10n.achievementPracticeStarterDescription,
    'achievementPracticeBuilderDescription' =>
      l10n.achievementPracticeBuilderDescription,
    'achievementPracticeRegularDescription' =>
      l10n.achievementPracticeRegularDescription,
    'achievementPracticeDevoteeDescription' =>
      l10n.achievementPracticeDevoteeDescription,
    'achievementRhythmFirstStepsDescription' =>
      l10n.achievementRhythmFirstStepsDescription,
    'achievementRhythmBuilderOneDescription' =>
      l10n.achievementRhythmBuilderOneDescription,
    'achievementRhythmBuilderTwoDescription' =>
      l10n.achievementRhythmBuilderTwoDescription,
    'achievementRhythmBuilderThreeDescription' =>
      l10n.achievementRhythmBuilderThreeDescription,
    'achievementSongFirstFinishDescription' =>
      l10n.achievementSongFirstFinishDescription,
    'achievementSongExplorerOneDescription' =>
      l10n.achievementSongExplorerOneDescription,
    'achievementSongExplorerTwoDescription' =>
      l10n.achievementSongExplorerTwoDescription,
    'achievementAnalysisFirstReviewDescription' =>
      l10n.achievementAnalysisFirstReviewDescription,
    'achievementAnalysisInsightDescription' =>
      l10n.achievementAnalysisInsightDescription,
    'achievementPlanFirstBlockDescription' =>
      l10n.achievementPlanFirstBlockDescription,
    'achievementPlanPathfinderDescription' =>
      l10n.achievementPlanPathfinderDescription,
    'achievementTutorFirstCheckinDescription' =>
      l10n.achievementTutorFirstCheckinDescription,
    'achievementVisionFirstObservationDescription' =>
      l10n.achievementVisionFirstObservationDescription,
    'achievementSourceExplorerDescription' =>
      l10n.achievementSourceExplorerDescription,
    'achievementBalancedPracticeWeekDescription' =>
      l10n.achievementBalancedPracticeWeekDescription,
    'achievementXpFirstHundredDescription' =>
      l10n.achievementXpFirstHundredDescription,
    'achievementLegacyFirstStepDescription' =>
      l10n.achievementLegacyFirstStepDescription,
    _ => null,
  };
  final accessibilityDescription =
      switch (definition.accessibilityDescriptionKey) {
        'achievementFirstValidSessionSemantics' =>
          l10n.achievementFirstValidSessionSemantics,
        'achievementPracticeStarterSemantics' =>
          l10n.achievementPracticeStarterSemantics,
        'achievementPracticeBuilderSemantics' =>
          l10n.achievementPracticeBuilderSemantics,
        'achievementPracticeRegularSemantics' =>
          l10n.achievementPracticeRegularSemantics,
        'achievementPracticeDevoteeSemantics' =>
          l10n.achievementPracticeDevoteeSemantics,
        'achievementRhythmFirstStepsSemantics' =>
          l10n.achievementRhythmFirstStepsSemantics,
        'achievementRhythmBuilderOneSemantics' =>
          l10n.achievementRhythmBuilderOneSemantics,
        'achievementRhythmBuilderTwoSemantics' =>
          l10n.achievementRhythmBuilderTwoSemantics,
        'achievementRhythmBuilderThreeSemantics' =>
          l10n.achievementRhythmBuilderThreeSemantics,
        'achievementSongFirstFinishSemantics' =>
          l10n.achievementSongFirstFinishSemantics,
        'achievementSongExplorerOneSemantics' =>
          l10n.achievementSongExplorerOneSemantics,
        'achievementSongExplorerTwoSemantics' =>
          l10n.achievementSongExplorerTwoSemantics,
        'achievementAnalysisFirstReviewSemantics' =>
          l10n.achievementAnalysisFirstReviewSemantics,
        'achievementAnalysisInsightSemantics' =>
          l10n.achievementAnalysisInsightSemantics,
        'achievementPlanFirstBlockSemantics' =>
          l10n.achievementPlanFirstBlockSemantics,
        'achievementPlanPathfinderSemantics' =>
          l10n.achievementPlanPathfinderSemantics,
        'achievementTutorFirstCheckinSemantics' =>
          l10n.achievementTutorFirstCheckinSemantics,
        'achievementVisionFirstObservationSemantics' =>
          l10n.achievementVisionFirstObservationSemantics,
        'achievementSourceExplorerSemantics' =>
          l10n.achievementSourceExplorerSemantics,
        'achievementBalancedPracticeWeekSemantics' =>
          l10n.achievementBalancedPracticeWeekSemantics,
        'achievementXpFirstHundredSemantics' =>
          l10n.achievementXpFirstHundredSemantics,
        'achievementLegacyFirstStepSemantics' =>
          l10n.achievementLegacyFirstStepSemantics,
        _ => null,
      };
  if (title == null ||
      description == null ||
      accessibilityDescription == null) {
    return null;
  }
  return _AchievementContent(title, description, accessibilityDescription);
}

final class _AchievementContent {
  const _AchievementContent(
    this.title,
    this.description,
    this.accessibilityDescription,
  );

  final String title;
  final String description;
  final String accessibilityDescription;
}
