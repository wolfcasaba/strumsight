/// Central catalogue for every route path exposed by the application.
abstract final class AppRoutes {
  static const String welcome = '/welcome';
  // SDD Ch13 Kör 16 (ADR 0281 §3/§6) — the in-app safe-mode/recovery
  // surface, distinct from the pre-first-frame `BootstrapFailureApp`.
  static const String recovery = '/recovery';
  static const String live = '/live';
  static const String analyze = '/analyze';
  static const String learn = '/learn';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String tuner = '/tuner';
  static const String metronome = '/metronome';
  static const String calibrate = '/calibrate';
  static const String streak = '/streak';
  static const String progress = '/progress';
  static const String songs = '/songs';
  static const String setlists = '/setlists';
  static const String chords = '/chords';
  static const String login = '/login';
  static const String librarySession = '/library/session';
  static const String practiceHub = '/practice';
  static const String practiceSetup = '/practice/setup';
  static const String practiceSession = '/practice/session';
  static const String practiceResult = '/practice/result';

  // Practice Generator entry points (E15-R07 F1, ADR 0491 D1). Only the two
  // MEASURED-constructible screens get a route — `PlanPreviewScreen`,
  // `PlanPrivacyScreen`, `WeeklyPlanScreen`, and `PlanChangeReviewScreen`
  // stay unreachable until a later round wires the two seams their
  // providers transitively depend on (ADR 0491 D5).
  static const String practiceGeneratorSetup = '/practice/generator/setup';
  static const String practiceGeneratorToday = '/practice/generator/today';
  // A tervező további négy képernyője (2026-09-05). Eddig azért nem volt
  // útvonaluk, mert két provider élesben dobott — nem azért, mert a route
  // hiányzott.
  static const String practiceGeneratorWeekly = '/practice/generator/weekly';
  static const String practiceGeneratorPrivacy = '/practice/generator/privacy';
  static const String practiceGeneratorPreview = '/practice/generator/preview';
  static const String practiceGeneratorChangeReview =
      '/practice/generator/change-review';
  static const String songTrainerLibrary = '/song-trainer';
  static const String songTrainerImport = '/song-trainer/import';
  static const String songTrainerNewEditor = '/song-trainer/editor/new';
  static const String songTrainerEditor = '/song-trainer/editor/:songId';
  static const String songTrainerOverview = '/song-trainer/overview/:songId';
  static const String songTrainerSetup = '/song-trainer/setup/:songId';
  static const String songTrainerSession = '/song-trainer/session/:songId';
  static const String songTrainerResult = '/song-trainer/result/:songId';
  static const String tutorHome = '/tutor/home';
  static const String tutorChat = '/tutor/chat';
  static const String tutorProfile = '/tutor/profile';
  static const String tutorPrivacy = '/tutor/privacy';
  static const String tutorData = '/tutor/data';
  static const String visionSetup = '/vision/setup';
  static const String visionGuitarGeometry = '/vision/guitar-geometry';
  static const String visionSession = '/vision/session';

  // Audio Analysis V2 (E06-R23) — overview and metric detail screens.
  // Both routes are flag-gated in app_router.dart and are intentionally
  // unreachable while `audioAnalysisV2Enabled == false`.
  // A felvételi folyamat (2026-09-05). Három lépés, három cím: a
  // kezdőlap → felvétel → feldolgozás sorrend így mély-linkelhető és
  // visszalépéskor is értelmes.
  static const String analysisCapture = '/analysis/capture';
  static const String analysisRecord = '/analysis/record';
  static const String analysisProcessing = '/analysis/processing';
  static const String analysisOverview = '/analysis/overview';
  static const String analysisMetricDetail = '/analysis/metric-detail';
  static const String analysisTimeline = '/analysis/timeline';

  // Session comparison and trend (E06-R25, ADR 0246) — flag-gated behind
  // its own `analysisComparisonEnabled` flag, independent of
  // `audioAnalysisV2Enabled`.
  static const String analysisCompare = '/analysis/compare';

  // Gamification V2 routes (E08-R30) — the canonical Epic 8 destination
  // surface. The legacy `/streak` and `/progress` deep links remain wired
  // to their V1 screens above (ADR §5.1 — old routes stay live).
  static const String gamificationHub = '/gamification';
  static const String achievements = '/gamification/achievements';
  static const String achievementDetail =
      '/gamification/achievement/:achievementId';
  static const String quests = '/gamification/quests';
  static const String streakDetail = '/gamification/streak';
  static const String rewardInbox = '/gamification/inbox';

  // Level detail (E16-R01, ADR 0496 §4 / §0.0.A/R3 #2) — the composition
  // root's route constant for the already-built, already-tested
  // `LevelDetailScreen`, which had no route before this round.
  static const String levelDetail = '/gamification/level';

  // Adaptive shell (E13-R08, ADR 0275) — five target destinations, reachable
  // only when `adaptiveShellEnabled` is on. `practiceHub` and `songs` above
  // are reused as the Practice and Songs destinations; `today`, `coachHome`,
  // and `profileHome` are new paths with no legacy equivalent.
  // ---------------------------------------------------------------------
  // Community (2026-09-05). A belépési pont a `/community` gate-képernyő:
  // az minden al-útvonal ELŐTT álló szűrő, ami a fiók- és kapu-állapotot
  // ellenőrzi. A mély-linkek ettől függetlenül közvetlenül is nyílnak — a
  // gate nem navigációs kényszer, hanem belépési felület.
  // ---------------------------------------------------------------------
  static const String community = '/community';
  static const String communityFeed = '/community/feed';
  static const String communityCompose = '/community/compose';
  static const String communityComments = '/community/posts/:postId/comments';
  static const String communityBookmarks = '/community/bookmarks';
  static const String communityNotifications = '/community/notifications';
  static const String communitySearch = '/community/search';
  static const String communityFollowers =
      '/community/profiles/:profileId/followers';
  static const String communityFollowing =
      '/community/profiles/:profileId/following';
  static const String communityChallenges = '/community/challenges';
  static const String communityLeaderboard =
      '/community/challenges/:challengeId/leaderboard';
  static const String communitySafety = '/community/safety';
  static const String communityClubs = '/community/clubs';
  static const String communityClubDetail = '/community/clubs/:clubId';

  static const String today = '/today';
  static const String coachHome = '/coach';
  static const String profileHome = '/profile';

  /// Adaptive shell destinations in navigation order.
  static const List<String> adaptiveShellDestinations = <String>[
    today,
    practiceHub,
    songs,
    coachHome,
    profileHome,
  ];

  // Adaptive shell target sub-routes (E13-R08) — each renders the same
  // existing screen the corresponding legacy route rendered; see D6.
  static const String practiceLive = '/practice/live';
  static const String practiceAnalyze = '/practice/analyze';
  static const String practiceLearn = '/practice/learn';
  static const String practiceTuner = '/practice/tuner';
  static const String practiceMetronome = '/practice/metronome';
  static const String practiceChords = '/practice/chords';
  static const String songsSetlists = '/songs/setlists';
  static const String profileLibrary = '/profile/library';

  // Unified Library session detail (E13-R28, SDD Ch13 UI-41). The `extra`
  // payload carries the strongly-typed `LibraryItem` for a type-safe push;
  // `:sessionId` mirrors it in the path for deep-link shape only — a
  // redirect to [profileLibrary] covers the missing-extra case, matching
  // the existing `librarySession` pattern above.
  static const String profileLibrarySession =
      '/profile/library/session/:sessionId';
  static const String profileSettings = '/profile/settings';
  static const String profileProgress = '/profile/progress';

  // Progress V2 skill detail (E16-R02, SDD UI-50, ADR 0500 §5.8). `:skillId`
  // is a `MasterySkill.code` (`chordTransition`/`rhythmAccuracy`/
  // `strumConsistency`/`tempoStability`); an unknown or unmapped code
  // redirects to [profileProgress] rather than 404ing. Not a shell
  // destination — pushed on top, like [profileLibrarySession].
  static const String profileProgressSkill =
      '/profile/progress/skills/:skillId';
  static const String profileRewards = '/profile/rewards';

  /// Top-level destinations in the same order as the shell navigation bar.
  static const List<String> shellTabs = <String>[
    live,
    analyze,
    learn,
    library,
    settings,
  ];
}
