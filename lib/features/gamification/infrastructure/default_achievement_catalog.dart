import '../domain/achievements/achievement_catalog.dart';
import '../domain/achievements/achievement_definition.dart';

/// Curated first-release achievement content; identifiers remain stable when copy changes.
final AchievementCatalog defaultAchievementCatalog = AchievementCatalog(
  contentVersion: 1,
  definitions: <AchievementDefinition>[
    _achievement(
      id: 'first_valid_session',
      category: AchievementCategory.practice,
      keyStem: 'achievementFirstValidSession',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 1,
      ),
    ),
    _achievement(
      id: 'practice_starter',
      category: AchievementCategory.practice,
      keyStem: 'achievementPracticeStarter',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 5,
      ),
    ),
    _achievement(
      id: 'practice_builder',
      category: AchievementCategory.practice,
      keyStem: 'achievementPracticeBuilder',
      prerequisiteIds: const <String>['practice_starter'],
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 10,
      ),
    ),
    _achievement(
      id: 'practice_regular',
      category: AchievementCategory.consistency,
      keyStem: 'achievementPracticeRegular',
      prerequisiteIds: const <String>['practice_builder'],
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 25,
      ),
    ),
    _achievement(
      id: 'practice_devotee',
      category: AchievementCategory.consistency,
      keyStem: 'achievementPracticeDevotee',
      prerequisiteIds: const <String>['practice_regular'],
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 50,
      ),
    ),
    _achievement(
      id: 'rhythm_first_steps',
      category: AchievementCategory.rhythm,
      keyStem: 'achievementRhythmFirstSteps',
      objective: ThresholdAchievementObjective(
        eventKind: AchievementEventKind.practice,
        metric: AchievementMetric.score,
        minimum: 0.6,
      ),
    ),
    _achievement(
      id: 'rhythm_builder_one',
      category: AchievementCategory.rhythm,
      keyStem: 'achievementRhythmBuilderOne',
      prerequisiteIds: const <String>['rhythm_first_steps'],
      objective: ThresholdAchievementObjective(
        eventKind: AchievementEventKind.practice,
        metric: AchievementMetric.score,
        minimum: 0.7,
      ),
    ),
    _achievement(
      id: 'rhythm_builder_two',
      category: AchievementCategory.rhythm,
      keyStem: 'achievementRhythmBuilderTwo',
      prerequisiteIds: const <String>['rhythm_builder_one'],
      objective: ThresholdAchievementObjective(
        eventKind: AchievementEventKind.practice,
        metric: AchievementMetric.score,
        minimum: 0.8,
      ),
    ),
    _achievement(
      id: 'rhythm_builder_three',
      category: AchievementCategory.rhythm,
      keyStem: 'achievementRhythmBuilderThree',
      prerequisiteIds: const <String>['rhythm_builder_two'],
      objective: ThresholdAchievementObjective(
        eventKind: AchievementEventKind.practice,
        metric: AchievementMetric.score,
        minimum: 0.9,
      ),
    ),
    _achievement(
      id: 'song_first_finish',
      category: AchievementCategory.songs,
      keyStem: 'achievementSongFirstFinish',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.song,
        target: 1,
      ),
    ),
    _achievement(
      id: 'song_explorer_one',
      category: AchievementCategory.songs,
      keyStem: 'achievementSongExplorerOne',
      prerequisiteIds: const <String>['song_first_finish'],
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.song,
        target: 5,
      ),
    ),
    _achievement(
      id: 'song_explorer_two',
      category: AchievementCategory.songs,
      keyStem: 'achievementSongExplorerTwo',
      prerequisiteIds: const <String>['song_explorer_one'],
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.song,
        target: 10,
      ),
    ),
    _achievement(
      id: 'analysis_first_review',
      category: AchievementCategory.analysis,
      keyStem: 'achievementAnalysisFirstReview',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.analysis,
        target: 1,
      ),
    ),
    _achievement(
      id: 'analysis_insight',
      category: AchievementCategory.analysis,
      keyStem: 'achievementAnalysisInsight',
      prerequisiteIds: const <String>['analysis_first_review'],
      objective: ThresholdAchievementObjective(
        eventKind: AchievementEventKind.analysis,
        metric: AchievementMetric.score,
        minimum: 0.75,
      ),
    ),
    _achievement(
      id: 'plan_first_block',
      category: AchievementCategory.exploration,
      keyStem: 'achievementPlanFirstBlock',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.plan,
        target: 1,
      ),
    ),
    _achievement(
      id: 'plan_pathfinder',
      category: AchievementCategory.exploration,
      keyStem: 'achievementPlanPathfinder',
      prerequisiteIds: const <String>['plan_first_block'],
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.plan,
        target: 10,
      ),
    ),
    _achievement(
      id: 'tutor_first_checkin',
      category: AchievementCategory.exploration,
      keyStem: 'achievementTutorFirstCheckin',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.tutor,
        target: 1,
      ),
    ),
    _achievement(
      id: 'vision_first_observation',
      category: AchievementCategory.accessibilityNeutral,
      keyStem: 'achievementVisionFirstObservation',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.vision,
        target: 1,
      ),
    ),
    _achievement(
      id: 'source_explorer',
      category: AchievementCategory.exploration,
      keyStem: 'achievementSourceExplorer',
      objective: DistinctAchievementObjective(
        eventKind: AchievementEventKind.practice,
        dimension: AchievementDistinctDimension.activitySource,
        target: 3,
      ),
    ),
    _achievement(
      id: 'balanced_practice_week',
      category: AchievementCategory.consistency,
      keyStem: 'achievementBalancedPracticeWeek',
      hidden: true,
      objective: CompoundAchievementObjective(
        objectives: <AchievementObjective>[
          CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: 3,
          ),
          CountAchievementObjective(
            eventKind: AchievementEventKind.song,
            target: 1,
          ),
          CountAchievementObjective(
            eventKind: AchievementEventKind.analysis,
            target: 1,
          ),
        ],
      ),
    ),
    _achievement(
      id: 'xp_first_hundred',
      category: AchievementCategory.personalBest,
      keyStem: 'achievementXpFirstHundred',
      objective: ThresholdAchievementObjective(
        eventKind: AchievementEventKind.practice,
        metric: AchievementMetric.totalXp,
        minimum: 100,
      ),
    ),
    _achievement(
      id: 'legacy_first_step',
      category: AchievementCategory.practice,
      keyStem: 'achievementLegacyFirstStep',
      objective: CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 1,
      ),
      deprecated: true,
      deprecatedSinceVersion: 1,
    ),
  ],
);

AchievementDefinition _achievement({
  required String id,
  required AchievementCategory category,
  required String keyStem,
  required AchievementObjective objective,
  List<String> prerequisiteIds = const <String>[],
  bool hidden = false,
  bool deprecated = false,
  int? deprecatedSinceVersion,
}) => AchievementDefinition(
  id: id,
  category: category,
  titleKey: '${keyStem}Title',
  descriptionKey: '${keyStem}Description',
  accessibilityDescriptionKey: '${keyStem}Semantics',
  objectives: <AchievementObjective>[objective],
  tierPrerequisiteIds: prerequisiteIds,
  hidden: hidden,
  version: 1,
  deprecated: deprecated,
  deprecatedSinceVersion: deprecatedSinceVersion,
);
