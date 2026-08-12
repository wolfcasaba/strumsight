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

  // --- practice ------------------------------------------------------------
  /// Versioned Practice History V2 — separate from the V1 `practiceLog`
  /// (ADR 0084 §Döntés 1). The V1 store is deliberately untouched in this
  /// round; the two sources will be unified in E02-R19.
  static const String practiceHistoryV2 = 'ss.practice.history_v2';

  // --- vision --------------------------------------------------------------
  static const String visionSetupProfile = 'ss.vision.setup_profile';
  static const String visionCamera = 'ss.vision.camera';

  /// Versioned, normalized-space camera + guitar calibration bundle
  /// (SDD Ch6 §13.3, E05-R10). Separate from the setup profile / camera
  /// preference keys above — a calibration is the per-session geometry,
  /// the setup preferences are the camera framing defaults.
  static const String visionCalibration = 'ss.vision.calibration';

  /// Privacy-safe, versioned summaries of completed Vision sessions.
  ///
  /// This deliberately holds only aggregate session results; raw frames and
  /// landmark time series have no storage key (ADR 0183).
  static const String visionSessionHistory = 'ss.vision.session_history';

  /// Every persisted Vision datum that the privacy control can erase.
  ///
  /// `visionLabCaptureEnabled` has no persistent capture store in this build,
  /// so Lab data contributes no key here. If that changes, the new key must be
  /// added to this list before it can be written.
  static const List<String> visionData = <String>[
    visionSessionHistory,
    visionCalibration,
  ];

  // --- audio analysis -----------------------------------------------------
  /// Migration checkpoint for the V1 → V2 analysis migration
  /// (ADR 0239 §Döntés 9, E06-R21 brief §5.5). The marker lives at
  /// `<analysisRoot>/migration/state.json`; this constant is the
  /// preference-key shadow used by support tooling and the
  /// migration-supplier guard.
  static const String analysisMigrationState = 'ss.analysis.migration_state';

  // --- AI tutor ------------------------------------------------------------
  /// Versioned documents, recovery index, and inspectable memory facts.
  static const String tutorConversationDocuments =
      'ss.tutor.conversation_documents';
  static const String tutorConversationIndex = 'ss.tutor.conversation_index';
  static const String tutorMemoryFacts = 'ss.tutor.memory_facts';

  /// Every local AI tutor document. Delete-all must visit this exact list and
  /// the quarantine of each key because [KeyValueStore] cannot enumerate keys.
  static const List<String> tutorAiData = <String>[
    tutorConversationDocuments,
    tutorConversationIndex,
    tutorMemoryFacts,
  ];

  /// Secure-store key for the JWT. Deliberately NOT renamed: the secure store
  /// is not covered by the preference migrator, so a rename would silently log
  /// out every signed-in user.
  static const String secureAuthToken = 'strumsight_auth_token';

  /// Where a document that could not be decoded is kept (Kör 7 §7.4).
  ///
  /// Corrupt user content is isolated, never dropped: the unreadable bytes move
  /// here so the app can carry on with a clean document while the original
  /// stays recoverable (by a support build, a later repair migration, or a
  /// device dump). One slot per document — a second corruption replaces the
  /// first, which is still strictly more than the zero copies a blind
  /// overwrite would leave.
  static String quarantineOf(String key) => '$key.corrupt';

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
    practiceHistoryV2,
    visionSetupProfile,
    visionCamera,
    visionCalibration,
    visionSessionHistory,
    tutorConversationDocuments,
    tutorConversationIndex,
    tutorMemoryFacts,
    analysisMigrationState,
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
