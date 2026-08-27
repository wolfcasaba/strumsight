// Golden snapshots of the E13-R32 gamification screens (Hub, Quests,
// Achievements, Streak detail, Reward inbox) at a compact portrait phone
// (412×915) and the same frame at textScaler 2.0, per the round brief
// §7/A9. Pattern follows the merged
// `test/ui/goldens/e13_r31_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme) plus a local `GamificationThemeScope`
// (mirrors `progress_theme_scope.dart`'s measured fix) because `AppTheme`
// alone does not carry the design-system's `SsColorScheme`/`SsTypography`
// extensions the migrated widgets (SsSurface/SsButton) need.
//
// Recorded on x86_64 (ADR 0426, §0.0.B §7/B10) via `tools/golden-x86.sh
// record` — NOT `flutter test --update-goldens` on this (aarch64) box.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

GamificationProfile _profile() {
  final curve = LevelCurve(<LevelDefinition>[
    LevelDefinition(
      number: 1,
      levelThreshold: 0,
      titleKey: 'gamification.level.beginner',
    ),
    LevelDefinition(
      number: 2,
      levelThreshold: 100,
      titleKey: 'gamification.level.explorer',
    ),
    LevelDefinition(
      number: 3,
      levelThreshold: 250,
      titleKey: 'gamification.level.consistent',
    ),
  ]);
  return GamificationProfile(
    schemaVersion: gamificationProfileSchemaVersion,
    totalXp: 60,
    progress: curve.progressForTotalXp(60),
  );
}

Widget _hubScreen() => GamificationHubScreen(
  profile: _profile(),
  activeQuestCount: 2,
  streakCurrentDays: 4,
  masteryUnlockedCount: 1,
  inboxUnseenCount: 2,
  latestResult: const LatestHubResult(
    title: 'A measured session',
    body: 'Five XP components credited.',
    earnedXp: 30,
  ),
  onOpenLevelDetail: () {},
  onOpenInbox: () {},
  onOpenAchievements: () {},
  onOpenStreak: () {},
  onOpenQuests: () {},
  onOpenMastery: () {},
);

QuestDefinition _questDefinition() => QuestDefinition(
  id: 'daily_open_chord_progression',
  schemaVersion: questDefinitionSchemaVersion,
  cadence: QuestCadence.daily,
  objective: SkillTagQuestObjective('barre_chords'),
  schedule: QuestSchedule(
    schemaVersion: questScheduleSchemaVersion,
    generationEpochDay: 20000,
    timezoneOffsetMinutes: 0,
    catalogVersion: 1,
    expiresAt: DateTime.utc(2026, 12, 31, 23, 59, 59),
  ),
  reward: QuestReward(baseXp: 50, bonusXp: 0, policyVersion: 1),
);

Widget _questsScreen() {
  final definition = _questDefinition();
  final progress = QuestProgress.active(
    definition: definition,
    completedUnits: 2,
    practiceResultIds: const <String>[],
  );
  return QuestsScreen(
    dailyChallengeTitle: "Today's challenge",
    dailyChallenge: DailyChallengeInstance(
      schemaVersion: dailyChallengeInstanceSchemaVersion,
      epochDay: 20000,
      catalogVersion: 1,
      generatedAt: DateTime.utc(2026, 8, 21),
      definition: const StrumPatternChallenge(
        pattern: <StrumDirection>[StrumDirection.down, StrumDirection.down],
        name: 'Steady downstrokes',
      ),
      contentCatalog: DailyChallengeContentCatalogSnapshot(
        schemaVersion: dailyChallengeContentCatalogSchemaVersion,
        catalogVersion: 1,
        chordIds: const <String>[],
        rhythmIds: const <String>[],
        songIds: const <String>[],
        timingContentIds: const <String>[],
      ),
      completion: null,
    ),
    dailyChallengeAvailable: true,
    dailyQuests: [
      QuestViewProjection(
        definition: definition,
        progress: progress,
        targetUnits: 4,
        completedUnits: 2,
        contentAvailable: true,
        sourcePlanLabel: 'Plan block: open chord progression',
      ),
    ],
    weeklyQuests: const [],
    onAction: (_) {},
    now: DateTime.utc(2026, 8, 21, 14),
  );
}

Widget _achievementsScreen() {
  final definitions = <AchievementDefinition>[
    AchievementDefinition(
      id: 'first_valid_session',
      category: AchievementCategory.practice,
      titleKey: 'achievementFirstValidSessionTitle',
      descriptionKey: 'achievementFirstValidSessionDescription',
      accessibilityDescriptionKey: 'achievementFirstValidSessionSemantics',
      objectives: <AchievementObjective>[
        CountAchievementObjective(
          eventKind: AchievementEventKind.practice,
          target: 1,
        ),
      ],
      tierPrerequisiteIds: const [],
      hidden: false,
      version: 1,
      deprecated: false,
    ),
    AchievementDefinition(
      id: 'practice_starter',
      category: AchievementCategory.practice,
      titleKey: 'achievementPracticeStarterTitle',
      descriptionKey: 'achievementPracticeStarterDescription',
      accessibilityDescriptionKey: 'achievementPracticeStarterSemantics',
      objectives: <AchievementObjective>[
        CountAchievementObjective(
          eventKind: AchievementEventKind.practice,
          target: 5,
        ),
      ],
      tierPrerequisiteIds: const [],
      hidden: false,
      version: 1,
      deprecated: false,
    ),
  ];
  return AchievementsScreen(
    definitions: definitions,
    progressByAchievement: <String, AchievementProgress>{
      'first_valid_session': AchievementProgress(
        achievementId: 'first_valid_session',
        catalogVersion: 1,
        value: 0.6,
      ),
      'practice_starter': AchievementProgress(
        achievementId: 'practice_starter',
        catalogVersion: 1,
        value: 1,
        completedAt: DateTime.utc(2026, 8, 21),
        rewardLedgerEntryId: 'achievement:practice_starter:1',
      ),
    },
    onAchievementSelected: (_) {},
  );
}

Widget _streakDetailScreen() => StreakDetailScreen(
  state: StreakState(
    current: 3,
    longest: 8,
    lastQualifiedDay: 20400,
    totalQualifiedDays: 12,
    freezes: 2,
  ),
  reason: StreakEvaluationReason.grace,
  weeklyConsistencyDays: 4,
  onRecoveryPressed: () {},
);

Widget _rewardInboxScreen() {
  final event = RewardEvent(
    id: 'evt-1',
    kind: RewardKind.dailyReward,
    titleKey: 'Daily reward',
    bodyKey: 'You practiced today.',
    earnedXp: 15,
    earnedAt: DateTime.utc(2026, 8, 22, 9),
    sourceLedgerId: 'ledger-evt-1',
  );
  return RewardInboxScreen(
    items: [
      RewardInboxItem(
        id: 'evt-1',
        event: event,
        addedAt: DateTime.utc(2026, 8, 22, 9),
      ),
    ],
    onItemSelected: (_) {},
    onMarkSeen: (_) {},
    pendingCount: 1,
    onRetryPending: () {},
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screens = <String, Widget Function()>{
    'hub': _hubScreen,
    'quests': _questsScreen,
    'achievements': _achievementsScreen,
    'streak_detail': _streakDetailScreen,
    'reward_inbox': _rewardInboxScreen,
  };

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    for (final entry in screens.entries) {
      testWidgets('${entry.key} — $suffix', (tester) async {
        await _pump(tester, entry.value(), textScale: textScale);
        await _expectGolden(tester, 'e13_r32_${entry.key}_$suffix');
      });
    }
  }
}
