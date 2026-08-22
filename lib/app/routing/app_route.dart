/// Central catalogue for every route path exposed by the application.
abstract final class AppRoutes {
  static const String welcome = '/welcome';
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

  /// Top-level destinations in the same order as the shell navigation bar.
  static const List<String> shellTabs = <String>[
    live,
    analyze,
    learn,
    library,
    settings,
  ];
}
