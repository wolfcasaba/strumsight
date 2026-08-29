# Screen retirement and migration plan (measured, E15-R03)

**Status:** proposal only. This document does not remove anything — no route,
no screen, no file (ADR 0471 D5). Every `retire` row below is a recommendation
for a separate, reviewed round; every `migrate` row assigns a named E15 round
(ADR 0471 D6); every `unreachable` row is a candidate for human/product review,
never an automatic deletion authorisation (ADR 0471 D7).

**Measured from:** `main` at the E15-R03 pre-flight baseline
(`docs/rounds/e15-r03-legacy-reachability-audit-and-retirement.md` §0.0.A,
code `main @ fc880063`), using:

```bash
dart run tool/check_screen_reachability.dart --format table
dart run tool/check_screen_reachability.dart --format json
```

## 1. Method (ADR 0471)

A screen is **reachable** if EITHER channel finds it (D2):

- **Declarative** — its class name is textually present in
  `lib/app/routing/app_router.dart`, `adaptive_shell_routes.dart`, or
  `route_guards.dart`.
- **Imperative** — its class is CONSTRUCTED (`ClassName(` or
  `ClassName.namedCtor(`) anywhere else under `lib/`.

Matching is by **class name**, never by import path or file name (D3): the
router reaches three features only through a `public.dart` barrel (measured:
`vision/public.dart` re-exports `VisionSetupScreen`, `GuitarCalibrationScreen`,
`VisionSessionScreen`), and a path-based checker would falsely report those
three as dead.

A **flag-gated** verdict (D4) means every declarative registration of that
screen sits behind an `if (...Enabled...)` condition and there is no
unconditional imperative construction either — reachable code with a closed
door today, not dead code.

**Stated limits (D7), all real in this tree, not hypothetical:**

- **Static text matching only.** No reflective or data-driven navigation
  (a class looked up by a runtime string key) is visible to this tool.
- **One hop only.** The imperative channel finds "constructed somewhere in
  `lib/`", not "constructed somewhere reachable from an entry point". Two
  Community screens below (`EditProfileScreen`, `ClubMemberManagementScreen`)
  are measured `reachable` this way while their only construction site is
  itself unreachable — see §3.3.
- A `retire` or `unreachable` verdict is a proposal for the next round to
  weigh, never grounds to delete anything in this round or silently in a
  future one.

## 2. Summary (measured)

| | Count |
| --- | ---: |
| Screens measured | 96 |
| Reachable | 68 |
| Unreachable | 28 |
| Flag-gated (closed door today) | 25 |
| Verdict: `keep` (reachable, already migrated) | 27 |
| Verdict: `migrate` (reachable, legacy) | 35 |
| Verdict: `retire` (reachable, legacy, superseded) | 6 |
| Verdict: `unreachable` | 28 |

The 35 `migrate` + 6 `retire` = 41 reachable-and-legacy screens are grouped
into eight named rounds, `E15-R04`…`E15-R11` (§4) — every one of them, per
ADR 0471 D6. The 28 `unreachable` rows carry NO round assignment: assigning a
Ch15 design-migration round to a screen nobody can reach would be exactly the
waste this round exists to prevent (brief §0.0). They are not silently
dropped, though — §3 groups them with their own measured findings and owners.

## 3. Findings beyond the per-screen table

### 3.1 `progress_v2` is not wired — corrects the prior "both reachable" claim

`docs/ui/migration-status.md`'s "Superseded pairs measured this round" section
(written E13-R36) states that the `progress` ↔ `progress_v2` pair is "both
still reachable". Measured now: **false**. `lib/app/routing/app_router.dart`
builds the legacy `ProgressScreen` for BOTH `AppRoutes.progress` (line 284)
and `AppRoutes.profileProgress` (line 528) — `ProgressDashboardScreen` and
`SkillDetailScreen` (`lib/features/progress_v2/screens/`) have no declarative
reference and no construction site anywhere in `lib/`. They are `unreachable`
in the table below, and `progress/progress_screen.dart` is `migrate` (not
`retire`) as a direct consequence: there is nothing live to retire it in
favor of yet. Wiring `progress_v2` into a route is a prerequisite for a future
round to revisit this as a `retire` candidate — this round does not do that
wiring (`lib/**` is out of scope, brief §3).

### 3.2 Practice Generator and the Audio Analysis capture wizard: built, unwired

Two whole flows have zero measured entry point:

- **Practice Generator** (`lib/features/practice_generator/`, 6 screens:
  `PlanSetupScreen`, `PlanPreviewScreen`, `PlanChangeReviewScreen`,
  `PlanPrivacyScreen`, `TodayPlanScreen`, `WeeklyPlanScreen`) — no route, no
  construction site anywhere in `lib/`.
- **Audio Analysis V2 capture wizard**
  (`lib/features/audio_analysis/presentation/capture/`, 3 screens:
  `AnalysisHomeScreen`, `AnalysisProcessingScreen`, `AnalysisRecordingScreen`)
  — same measurement. The rest of `audio_analysis` (overview, timeline,
  compare, metric detail, export) IS wired behind `audioAnalysisV2Enabled` —
  only the capture entry point is missing.

Neither is a Chapter 15 design-migration concern (design tokens are moot on
a screen nobody can open). Both need a product/navigation decision — wire an
entry point, or retire the flow — which this round proposes but does not
make (D5/D7). Owner: a future scoped round, unscheduled.

### 3.3 Community: 15 screens, one flag, zero routes

`lib/app/config/feature_flags.dart` defines `communityEnabled` and four
narrower community flags, but **no `community/**` class name appears
anywhere in `lib/app/routing/**`, gated or not.** 13 of the feature's 15
screens have no measured reference outside their own file at all. The
remaining two are a one-hop artifact, not a real path in (D7 §1, §3.1 above):

- `EditProfileScreen` is constructed only from `CommunityGateScreen`
  (`community_gate_screen.dart:127,237`) — itself unreachable.
- `ClubMemberManagementScreen` is constructed only from `ClubDetailScreen`
  (`club_detail_screen.dart:434`) — itself unreachable.

14 of the 15 are already design-system migrated (`migration-status.md`'s
"community 14/15" row) — this is not a migration backlog, it is an entirely
unwired feature. `FollowersScreen` (the one legacy community screen) is
`unreachable`; the other 14 are `unreachable` or `keep`-with-a-caveat in the
table, all carrying the same reason. Owner: a product/navigation decision
(wire `communityEnabled` to a route, or retire the feature) — not a Ch15
round, unscheduled.

### 3.4 Smaller one-off unreachable findings

- `lib/features/gamification/presentation/screens/level_detail_screen.dart`
  (`LevelDetailScreen`, legacy) — no measured reference anywhere in `lib/`.
- `lib/features/song_trainer/presentation/screens/setlist_session_screen.dart`
  (`SetlistSessionScreen`, legacy) — same.
- `lib/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart`
  (`PracticePlanPreviewScreen`, already migrated) — same.
- `lib/features/onboarding/screens/first_win_stage_screen.dart`
  (`FirstWinStageScreen`, already migrated) — same.

None of these get a Ch15 round for the same reason as §3.2/§3.3: there is no
reachable screen here to migrate.

## 4. Round assignment (ADR 0471 D6)

| Round | Scope |
| --- | --- |
| `E15-R04` | Legacy retirement review — the 6 `retire` proposals below (§5): `LibraryScreen`, `SessionDetailScreen`, `StreakScreen`, `SongListScreen`, `SongBuilderScreen`, `AnalyzeScreen`. Reviews and, if approved, executes each retirement (route removal is its own change, D5) — this round only proposes. |
| `E15-R05` | AI Tutor design migration — `TutorChatScreen`, `TutorDataScreen`, `TutorHomeScreen`, `TutorPrivacyScreen`, `TutorProfileScreen` (5). |
| `E15-R06` | Gamification design migration — `AchievementDetailScreen`, `AchievementsScreen`, `QuestsScreen`, `RewardInboxScreen`, `StreakDetailScreen` (5). |
| `E15-R07` | Learn + Onboarding design migration — `LatencyCalibrationScreen`, `LearnScreen`, `LessonListScreen`, `LessonScorePreviewScreen`, `OnboardingScreen` (5). |
| `E15-R08` | Practice + Progress design migration — `PracticeHistoryScreen`, `PracticeHubScreen`, `PracticeResultScreen`, `SpeedBuilderScreen`, `ProgressScreen` (5; `ProgressScreen` carries the §3.1 caveat). |
| `E15-R09` | Song Trainer design migration — `SongEditorScreen`, `SongImportPreviewScreen`, `SongImportScreen`, `SongLibraryScreen`, `SongOverviewScreen`, `SongResultScreen`, `SongTrainerScreen`, `TrainerSetupScreen` (8 — one feature, matches `migration-status.md`'s note that Song Trainer needs its own Ch15 round). |
| `E15-R10` | Songs remainder + Audio Analysis remainder — `SetlistDetailScreen`, `SetlistListScreen` (no successor in Song Trainer), `AnalysisExportScreen`, `AnalysisMetricDetailScreen` (4). |
| `E15-R11` | Vision design migration — `GuitarCalibrationScreen`, `VisionSessionScreen`, `VisionSetupScreen` (3). |

Every reachable-and-legacy screen (41 total: 35 `migrate` + 6 `retire`) has
exactly one row above. §3's unreachable findings deliberately have none.

## 5. Retire proposals in detail (ADR 0471 D5, A4)

| Legacy screen | Successor | Reason |
| --- | --- | --- |
| `lib/features/library/screens/library_screen.dart` (`LibraryScreen`) | `lib/features/library_v2/screens/unified_library_screen.dart` (`UnifiedLibraryScreen`) | Superseded by the unified library; successor is reachable and migrated. |
| `lib/features/library/screens/session_detail_screen.dart` (`SessionDetailScreen`) | `lib/features/library_v2/screens/library_item_detail_screen.dart` (`LibraryItemDetailScreen`) | Superseded by the unified library's item detail screen; successor is reachable and migrated. |
| `lib/features/streak/screens/streak_screen.dart` (`StreakScreen`) | `lib/features/gamification/presentation/screens/gamification_hub_screen.dart` (`GamificationHubScreen`) | Superseded by the Gamification hub (`migration-status.md` "Superseded pairs"); successor is reachable and migrated. |
| `lib/features/songs/screens/song_list_screen.dart` (`SongListScreen`) | `lib/features/song_trainer/presentation/screens/song_library_screen.dart` (`SongLibraryScreen`) | Superseded by Song Trainer V2 (`songTrainerEnabled`); successor is reachable, but itself still legacy — its own migration is `E15-R09`. |
| `lib/features/songs/screens/song_builder_screen.dart` (`SongBuilderScreen`) | `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` (`SongEditorScreen`) | Superseded by Song Trainer V2 (`songTrainerEnabled`); successor is reachable, but itself still legacy — its own migration is `E15-R09`. |
| `lib/features/analyze/screens/analyze_screen.dart` (`AnalyzeScreen`) | `lib/features/audio_analysis/presentation/analysis_overview_screen.dart` (`AnalysisOverviewScreen`) | Superseded by the Audio Analysis V2 pipeline (`audioAnalysisV2Enabled`); successor is reachable and migrated. |

`lib/features/songs/screens/setlist_list_screen.dart` and
`setlist_detail_screen.dart` are deliberately **not** in this table: Song
Trainer has no setlist-equivalent screen today, so there is no successor to
name. They are `migrate` (`E15-R10`) instead — proposing `retire` without a
real successor would be exactly the fabricated-reason failure A4 exists to
catch.

## 6. Full per-screen table (all 96, machine-measured)

| Screen | Class | Reachable | Flag-gated | Verdict | Owner round | Successor | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `lib/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart` | `PracticePlanPreviewScreen` | no | no | unreachable | — | — | Already design-system migrated but no measured construction site anywhere in lib/. |
| `lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart` | `TutorChatScreen` | yes | yes | migrate | E15-R05 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart` | `TutorDataScreen` | yes | yes | migrate | E15-R05 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart` | `TutorHomeScreen` | yes | yes | migrate | E15-R05 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart` | `TutorPrivacyScreen` | yes | yes | migrate | E15-R05 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart` | `TutorProfileScreen` | yes | yes | migrate | E15-R05 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/analyze/screens/analyze_screen.dart` | `AnalyzeScreen` | yes | no | retire | E15-R04 | `lib/features/audio_analysis/presentation/analysis_overview_screen.dart` | Superseded by the Audio Analysis V2 pipeline (audioAnalysisV2Enabled); successor is reachable and migrated. |
| `lib/features/audio_analysis/presentation/analysis_compare_screen.dart` | `AnalysisCompareScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/audio_analysis/presentation/analysis_export_screen.dart` | `AnalysisExportScreen` | yes | no | migrate | E15-R10 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart` | `AnalysisMetricDetailScreen` | yes | yes | migrate | E15-R10 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/audio_analysis/presentation/analysis_overview_screen.dart` | `AnalysisOverviewScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/audio_analysis/presentation/analysis_timeline_screen.dart` | `AnalysisTimelineScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart` | `AnalysisHomeScreen` | no | no | unreachable | — | — | Audio Analysis V2 capture wizard entry point is unwired; no route, no construction site. |
| `lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart` | `AnalysisProcessingScreen` | no | no | unreachable | — | — | Audio Analysis V2 capture wizard entry point is unwired; no route, no construction site. |
| `lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart` | `AnalysisRecordingScreen` | no | no | unreachable | — | — | Audio Analysis V2 capture wizard entry point is unwired; no route, no construction site. |
| `lib/features/auth/screens/login_screen.dart` | `LoginScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/chords/screens/chord_library_screen.dart` | `ChordLibraryScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/community/presentation/screens/bookmarks_screen.dart` | `BookmarksScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/clubs/club_detail_screen.dart` | `ClubDetailScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/clubs/club_list_screen.dart` | `ClubListScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/clubs/club_member_management_screen.dart` | `ClubMemberManagementScreen` | yes | no | keep | — | — | Already design-system migrated. Only constructed from `ClubDetailScreen` (itself unreachable) — a one-hop-only measurement (ADR 0471 D7) marks this reachable, but the entry point into it is dead. |
| `lib/features/community/presentation/screens/comments_screen.dart` | `CommentsScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/community_challenges_screen.dart` | `CommunityChallengesScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/community_gate_screen.dart` | `CommunityGateScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/community_notifications_screen.dart` | `CommunityNotificationsScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/community_search_screen.dart` | `CommunitySearchScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/edit_profile_screen.dart` | `EditProfileScreen` | yes | no | keep | — | — | Already design-system migrated. Only constructed from `CommunityGateScreen` (itself unreachable) — a one-hop-only measurement (ADR 0471 D7) marks this reachable, but the entry point into it is dead. |
| `lib/features/community/presentation/screens/followers_screen.dart` | `FollowersScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/following_feed_screen.dart` | `FollowingFeedScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/leaderboard_screen.dart` | `LeaderboardScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/post_composer_screen.dart` | `PostComposerScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/community/presentation/screens/safety_relationships_screen.dart` | `SafetyRelationshipsScreen` | no | no | unreachable | — | — | Community feature (`communityEnabled`) has no route registered in lib/app/routing/** at all, gated or not; unreachable by any measured path. |
| `lib/features/gamification/presentation/screens/achievement_detail_screen.dart` | `AchievementDetailScreen` | yes | no | migrate | E15-R06 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/gamification/presentation/screens/achievements_screen.dart` | `AchievementsScreen` | yes | no | migrate | E15-R06 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/gamification/presentation/screens/gamification_hub_screen.dart` | `GamificationHubScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/gamification/presentation/screens/level_detail_screen.dart` | `LevelDetailScreen` | no | no | unreachable | — | — | Achievement/level detail drill-down has no measured construction site anywhere in lib/. |
| `lib/features/gamification/presentation/screens/quests_screen.dart` | `QuestsScreen` | yes | no | migrate | E15-R06 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/gamification/presentation/screens/reward_inbox_screen.dart` | `RewardInboxScreen` | yes | no | migrate | E15-R06 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/gamification/presentation/screens/streak_detail_screen.dart` | `StreakDetailScreen` | yes | no | migrate | E15-R06 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/learn/screens/latency_calibration_screen.dart` | `LatencyCalibrationScreen` | yes | no | migrate | E15-R07 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/learn/screens/learn_screen.dart` | `LearnScreen` | yes | no | migrate | E15-R07 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/learn/screens/lesson_list_screen.dart` | `LessonListScreen` | yes | no | migrate | E15-R07 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/learn/screens/lesson_score_preview_screen.dart` | `LessonScorePreviewScreen` | yes | no | migrate | E15-R07 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/library/screens/library_screen.dart` | `LibraryScreen` | yes | no | retire | E15-R04 | `lib/features/library_v2/screens/unified_library_screen.dart` | Superseded by the unified library (ADR 0471 context); successor is reachable and migrated. |
| `lib/features/library/screens/session_detail_screen.dart` | `SessionDetailScreen` | yes | no | retire | E15-R04 | `lib/features/library_v2/screens/library_item_detail_screen.dart` | Superseded by the unified library item detail screen; successor is reachable and migrated. |
| `lib/features/library_v2/screens/library_item_detail_screen.dart` | `LibraryItemDetailScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/library_v2/screens/unified_library_screen.dart` | `UnifiedLibraryScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/live/screens/live_screen.dart` | `LiveScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/metronome/screens/metronome_screen.dart` | `MetronomeScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/offline_ai/screens/model_manager_screen.dart` | `ModelManagerScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/onboarding/screens/first_win_stage_screen.dart` | `FirstWinStageScreen` | no | no | unreachable | — | — | Already design-system migrated but no measured construction site anywhere in lib/. |
| `lib/features/onboarding/screens/onboarding_screen.dart` | `OnboardingScreen` | yes | no | migrate | E15-R07 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/onboarding/screens/permission_primer_screen.dart` | `PermissionPrimerScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/practice/presentation/screens/practice_history_screen.dart` | `PracticeHistoryScreen` | yes | no | migrate | E15-R08 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | `PracticeHubScreen` | yes | yes | migrate | E15-R08 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/practice/presentation/screens/practice_result_screen.dart` | `PracticeResultScreen` | yes | no | migrate | E15-R08 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | `PracticeSessionScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/practice/presentation/screens/practice_setup_screen.dart` | `PracticeSetupScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/practice/presentation/screens/speed_builder_screen.dart` | `SpeedBuilderScreen` | yes | no | migrate | E15-R08 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart` | `PlanChangeReviewScreen` | no | no | unreachable | — | — | Practice Generator has no route and no measured construction site anywhere in lib/. |
| `lib/features/practice_generator/presentation/screens/plan_preview_screen.dart` | `PlanPreviewScreen` | no | no | unreachable | — | — | Practice Generator has no route and no measured construction site anywhere in lib/. |
| `lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart` | `PlanPrivacyScreen` | no | no | unreachable | — | — | Practice Generator has no route and no measured construction site anywhere in lib/. |
| `lib/features/practice_generator/presentation/screens/plan_setup_screen.dart` | `PlanSetupScreen` | no | no | unreachable | — | — | Practice Generator has no route and no measured construction site anywhere in lib/. |
| `lib/features/practice_generator/presentation/screens/today_plan_screen.dart` | `TodayPlanScreen` | no | no | unreachable | — | — | Practice Generator has no route and no measured construction site anywhere in lib/. |
| `lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart` | `WeeklyPlanScreen` | no | no | unreachable | — | — | Practice Generator has no route and no measured construction site anywhere in lib/. |
| `lib/features/practice_hub/screens/practice_area_hub_screen.dart` | `PracticeAreaHubScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/profile_hub/screens/profile_hub_screen.dart` | `ProfileHubScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/progress/screens/progress_screen.dart` | `ProgressScreen` | yes | no | migrate | E15-R08 | — | Legacy, reachable, the ONLY working Progress path today — progress_v2 is unwired (see its own unreachable rows), so this is `migrate`, not `retire`, until progress_v2 is wired. |
| `lib/features/progress_v2/screens/progress_dashboard_screen.dart` | `ProgressDashboardScreen` | no | no | unreachable | — | — | progress_v2 is NOT wired into the router — `/profile/progress` still builds the legacy `ProgressScreen` (app_router.dart:528). Corrects migration-status.md's prior "both still reachable" claim for this pair. |
| `lib/features/progress_v2/screens/skill_detail_screen.dart` | `SkillDetailScreen` | no | no | unreachable | — | — | progress_v2 is NOT wired into the router (see progress_dashboard_screen.dart row). |
| `lib/features/settings/screens/privacy_center_screen.dart` | `PrivacyCenterScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/settings/screens/settings_screen.dart` | `SettingsScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/settings/screens/vision_privacy_screen.dart` | `VisionPrivacyScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/share/screens/share_preview_screen.dart` | `SharePreviewScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/share/screens/strum_reel_screen.dart` | `StrumReelScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/share/screens/wrapped_preview_screen.dart` | `WrappedPreviewScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/song_trainer/presentation/screens/setlist_session_screen.dart` | `SetlistSessionScreen` | no | no | unreachable | — | — | No route and no measured construction site anywhere in lib/. |
| `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` | `SongEditorScreen` | yes | yes | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart` | `SongImportPreviewScreen` | yes | no | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | `SongImportScreen` | yes | no | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | `SongLibraryScreen` | yes | yes | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/song_overview_screen.dart` | `SongOverviewScreen` | yes | yes | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/song_result_screen.dart` | `SongResultScreen` | yes | yes | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart` | `SongTrainerScreen` | yes | yes | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart` | `TrainerSetupScreen` | yes | yes | migrate | E15-R09 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/songs/screens/setlist_detail_screen.dart` | `SetlistDetailScreen` | yes | no | migrate | E15-R10 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/songs/screens/setlist_list_screen.dart` | `SetlistListScreen` | yes | no | migrate | E15-R10 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/songs/screens/song_builder_screen.dart` | `SongBuilderScreen` | yes | no | retire | E15-R04 | `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` | Superseded by Song Trainer V2 (songTrainerEnabled); successor is reachable, itself still legacy (own E15-R09 migration). |
| `lib/features/songs/screens/song_list_screen.dart` | `SongListScreen` | yes | yes | retire | E15-R04 | `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | Superseded by Song Trainer V2 (songTrainerEnabled); successor is reachable, itself still legacy (own E15-R09 migration). |
| `lib/features/streak/screens/streak_screen.dart` | `StreakScreen` | yes | no | retire | E15-R04 | `lib/features/gamification/presentation/screens/gamification_hub_screen.dart` | Superseded by the Gamification hub (migration-status.md "Superseded pairs"); successor is reachable and migrated. |
| `lib/features/today/screens/today_hub_screen.dart` | `TodayHubScreen` | yes | yes | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/tuner/screens/tuner_screen.dart` | `TunerScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/vision/presentation/screens/guitar_calibration_screen.dart` | `GuitarCalibrationScreen` | yes | yes | migrate | E15-R11 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/vision/presentation/screens/vision_result_screen.dart` | `VisionResultScreen` | yes | no | keep | — | — | Already design-system migrated; reachable — no Ch15 action. |
| `lib/features/vision/presentation/screens/vision_session_screen.dart` | `VisionSessionScreen` | yes | yes | migrate | E15-R11 | — | Legacy, reachable — Ch15 design-system migration. |
| `lib/features/vision/presentation/screens/vision_setup_screen.dart` | `VisionSetupScreen` | yes | yes | migrate | E15-R11 | — | Legacy, reachable — Ch15 design-system migration. |
