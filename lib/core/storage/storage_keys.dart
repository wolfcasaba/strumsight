/// Every persisted key in the app, in one place (SDD Ch2 Kör 5 §5.2).
///
/// New keys carry the `ss.` namespace so a StrumSight key is always
/// recognisable in a device dump and can never collide with a key written by a
/// plugin. The pre-namespace keys shipped builds already wrote live in
/// [LegacyStorageKeys]; a feature moves from one to the other together with its
/// [StorageMigration] entry (Kör 6–7), never by editing a constant in place —
/// that would orphan the user's data.
abstract final class StorageKeys {
  /// Schema version the migrator maintains. Absent means "0" (pre-migrator).
  static const String schemaVersion = 'ss.storage.schema_version';

  // --- settings ------------------------------------------------------------
  static const String themeMode = 'ss.settings.theme_mode';
  static const String locale = 'ss.settings.locale';
  static const String confidenceThreshold = 'ss.settings.confidence_threshold';
  static const String capoFret = 'ss.settings.capo_fret';
  static const String tuningA4 = 'ss.settings.tuning_a4';
  static const String leftHanded = 'ss.settings.left_handed';
  static const String inputLatencyMs = 'ss.settings.input_latency_ms';
  static const String visualLatencyMs = 'ss.settings.visual_latency_ms';
  static const String labMode = 'ss.settings.lab_mode';
  static const String nudgeEnabled = 'ss.settings.nudge_enabled';

  // --- onboarding ----------------------------------------------------------
  static const String onboardingSeen = 'ss.onboarding.seen';

  // --- tuner / chords ------------------------------------------------------
  static const String tunerTuning = 'ss.tuner.tuning';
  static const String favoriteChords = 'ss.chords.favorites';

  // --- learn ---------------------------------------------------------------
  static const String lessonProgress = 'ss.learn.lesson_progress';
  static const String metronomeMuted = 'ss.learn.metronome_muted';
  static const String practiceSpeed = 'ss.learn.practice_speed';

  // --- user content --------------------------------------------------------
  static const String librarySessions = 'ss.library.sessions';
  static const String songs = 'ss.songs.songs';
  static const String setlists = 'ss.songs.setlists';

  // --- progress ------------------------------------------------------------
  static const String practiceLog = 'ss.progress.practice_log';
  static const String dailyGoalMinutes = 'ss.progress.daily_goal_minutes';
  static const String streak = 'ss.streak.state';

  /// Secure-store key for the JWT. Deliberately NOT renamed: the secure store
  /// is not covered by the preference migrator, so a rename would silently log
  /// out every signed-in user.
  static const String secureAuthToken = 'strumsight_auth_token';

  /// All preference keys, for guard tests (uniqueness, namespace).
  static const List<String> all = [
    schemaVersion,
    themeMode,
    locale,
    confidenceThreshold,
    capoFret,
    tuningA4,
    leftHanded,
    inputLatencyMs,
    visualLatencyMs,
    labMode,
    nudgeEnabled,
    onboardingSeen,
    tunerTuning,
    favoriteChords,
    lessonProgress,
    metronomeMuted,
    practiceSpeed,
    librarySessions,
    songs,
    setlists,
    practiceLog,
    dailyGoalMinutes,
    streak,
  ];
}

/// Keys written by builds released before the `ss.` catalogue existed.
///
/// These are still the live keys for every feature that has not been migrated
/// yet — the constants are a record, not a target. Deleting one without the
/// matching migration deletes user data.
abstract final class LegacyStorageKeys {
  static const String themeMode = 'theme_mode';
  static const String locale = 'app_locale';
  static const String confidenceThreshold = 'confidence_threshold';
  static const String capoFret = 'capo_fret';
  static const String tuningA4 = 'tuning_a4';
  static const String leftHanded = 'left_handed_v1';
  static const String inputLatencyMs = 'input_latency_ms';
  static const String visualLatencyMs = 'visual_latency_ms';
  static const String labMode = 'lab_mode';
  static const String nudgeEnabled = 'nudge_enabled';
  static const String onboardingSeen = 'onboarding_seen_v1';
  static const String tunerTuning = 'tuner_tuning';
  static const String favoriteChords = 'favorite_chords';
  static const String lessonProgress = 'lesson_progress_v1';
  static const String metronomeMuted = 'metronome_muted_v1';
  static const String practiceSpeed = 'practice_speed_v1';
  static const String librarySessions = 'library_sessions';
  static const String songs = 'user_songs_v1';
  static const String setlists = 'user_setlists_v1';
  static const String practiceLog = 'practice_log_v1';
  static const String dailyGoalMinutes = 'daily_goal_min_v1';
  static const String streak = 'practice_streak_v1';
}
