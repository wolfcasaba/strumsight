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

  // Adaptive shell (E13-R08, ADR 0275) — five target destinations, reachable
  // only when `adaptiveShellEnabled` is on. `practiceHub` and `songs` above
  // are reused as the Practice and Songs destinations; `today`, `coachHome`,
  // and `profileHome` are new paths with no legacy equivalent.
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
