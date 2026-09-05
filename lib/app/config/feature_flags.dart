import 'app_environment.dart';
import '../../features/audio_analysis/domain/rollout/analysis_rollout_stage.dart';

/// Compile-time feature availability (E01-R03, SDD Ch2 Kör 3 §3.2).
///
/// These are *availability* switches, not user preferences: whether the
/// account layer exists in this build, whether diagnostics/Lab paths are
/// available, and which stage of the parallel Practice V2 rollout is present.
/// The user's own opt-ins (e.g. `labModeProvider`) sit on top and can only turn
/// things on where the flag makes them available.
final class FeatureFlags {
  const FeatureFlags({
    required this.accountEnabled,
    required this.diagnosticsEnabled,
    required this.labModeAvailable,
    this.practiceEngineV2Enabled = false,
    this.migratedLearnEnabled = false,
    this.practiceDetailedHistoryEnabled = false,
    this.songTrainerV2Enabled = false,
    this.aiTutorEnabled = false,
    this.aiTutorCloudEnabled = false,
    this.practiceGeneratorEnabled = false,
    this.plannerAssistEnabled = false,
    this.visionEnabled = false,
    this.visionSetupEnabled = false,
    this.visionHandTrackingEnabled = false,
    this.visionPoseTrackingEnabled = false,
    this.visionGuitarGeometryEnabled = false,
    this.visionPracticeIntegrationEnabled = false,
    this.visionSongIntegrationEnabled = false,
    this.visionTutorIntegrationEnabled = false,
    this.visionAnalysisIntegrationEnabled = false,
    this.visionExperimentalFineFretEnabled = false,
    this.visionLabCaptureEnabled = false,
    this.audioAnalysisV2Enabled = false,
    this.analysisBeatGridEnabled = false,
    this.analysisPitchEnabled = false,
    this.analysisPreprocessingExperimentalEnabled = false,
    this.analysisExperimentalFusionEnabled = false,
    this.analysisTechniqueProxiesEnabled = false,
    this.analysisComparisonEnabled = false,
    this.analysisPracticeIntegrationEnabled = false,
    this.analysisTutorIntegrationEnabled = false,
    this.recognitionRecoveryEnabled = false,
    this.recognitionShadowModeEnabled = false,
    this.newLiveStageEnabled = false,
    this.communityEnabled = false,
    this.communityWritesEnabled = false,
    this.communityMediaEnabled = false,
    this.communityLeaderboardEnabled = false,
    this.communityClubsEnabled = false,
    this.adaptiveShellEnabled = false,
  });

  /// Derive the per-environment defaults, honoring explicit dart-defines.
  ///
  /// - [accountEnabled] follows the `STRUMSIGHT_ACCOUNT` define (default off —
  ///   there is no hosted backend; a Sign-in button that always fails is worse
  ///   than none).
  /// - Diagnostics + Lab availability default to ON outside production and
  ///   OFF in production. There is deliberately NO define to force them on in
  ///   production ("a diagnosztika nem kapcsolható be véletlenül") — a
  ///   diagnostics-capable device build is what [AppEnvironment.lab] is for.
  /// - Practice V2, detailed history, and migrated Learn are available outside
  ///   production. None of the practice flags has a dart-define override.
  /// - [practiceGeneratorEnabled] is available outside production through the
  ///   same `nonProd` rollout boundary (E15-R07, ADR 0491 D2); its default
  ///   constructor value remains OFF. [plannerAssistEnabled] (model-assisted
  ///   suggestions) is a separate rollout decision and stays OFF everywhere.
  /// - [songTrainerV2Enabled] is available outside production through the
  ///   same `nonProd` rollout boundary as Practice V2. The default constructor
  ///   remains OFF, so manually created flags still require an explicit opt-in.
  /// **Build-only ELŐNÉZET-kapcsoló — NEM termékdöntés, NEM merge-elendő.**
  ///
  /// `--dart-define=STRUMSIGHT_PREVIEW_ALL=true` mellett a rollout-kapu mögött
  /// álló képességek együtt kapcsolódnak be, hogy EGY oldalról telepíthető
  /// build megmutassa a teljes alkalmazást. A define hiányában `false`, tehát
  /// minden meglévő elvárás és a production alapértelmezés változatlan.
  static const bool previewAll = bool.fromEnvironment('STRUMSIGHT_PREVIEW_ALL');

  factory FeatureFlags.forEnvironment(
    AppEnvironment environment, {
    required bool accountEnabled,
  }) {
    final nonProd = environment != AppEnvironment.production;
    // Az előnézeti kapcsoló SOSEM él productionben.
    final preview = nonProd && previewAll;
    return FeatureFlags(
      accountEnabled: accountEnabled,
      diagnosticsEnabled: nonProd,
      labModeAvailable: nonProd,
      practiceEngineV2Enabled: nonProd,
      migratedLearnEnabled: nonProd,
      practiceDetailedHistoryEnabled: nonProd,
      songTrainerV2Enabled: nonProd,
      aiTutorEnabled: preview,
      aiTutorCloudEnabled: false,
      // E15-R07 F1 (ADR 0491 D2) — same `nonProd` rollout boundary as
      // `practiceEngineV2Enabled`: ON outside production, OFF in
      // production. `plannerAssistEnabled` (model-assisted suggestions) is
      // a separate rollout decision and stays OFF everywhere.
      practiceGeneratorEnabled: nonProd,
      plannerAssistEnabled: preview,
      visionEnabled: preview,
      visionSetupEnabled: preview,
      visionHandTrackingEnabled: preview,
      visionPoseTrackingEnabled: preview,
      visionGuitarGeometryEnabled: preview,
      visionPracticeIntegrationEnabled: preview,
      visionSongIntegrationEnabled: preview,
      visionTutorIntegrationEnabled: preview,
      visionAnalysisIntegrationEnabled: preview,
      visionExperimentalFineFretEnabled: false,
      visionLabCaptureEnabled: false,
      audioAnalysisV2Enabled: preview,
      analysisBeatGridEnabled: preview,
      analysisPitchEnabled: preview,
      analysisPreprocessingExperimentalEnabled: false,
      analysisExperimentalFusionEnabled: false,
      analysisTechniqueProxiesEnabled: preview,
      analysisComparisonEnabled: preview,
      analysisPracticeIntegrationEnabled: preview,
      analysisTutorIntegrationEnabled: preview,
      recognitionRecoveryEnabled: false,
      recognitionShadowModeEnabled: false,
      newLiveStageEnabled: false,
      // Epic 9 Community (E09-R01, ADR 0395). The compile-time kill switch is
      // read directly here so app_config.dart stays untouched — without a
      // dart-define, every environment resolves to `false`, which keeps the
      // feature completely absent from production until a deliberate flip.
      communityEnabled:
          preview || const bool.fromEnvironment('STRUMSIGHT_COMMUNITY'),
      communityWritesEnabled:
          preview || const bool.fromEnvironment('STRUMSIGHT_COMMUNITY_WRITES'),
      communityMediaEnabled:
          preview || const bool.fromEnvironment('STRUMSIGHT_COMMUNITY_MEDIA'),
      communityLeaderboardEnabled:
          preview ||
          const bool.fromEnvironment('STRUMSIGHT_COMMUNITY_LEADERBOARD'),
      communityClubsEnabled:
          preview || const bool.fromEnvironment('STRUMSIGHT_COMMUNITY_CLUBS'),
      // E15-R02 (ADR 0467) — the five-area adaptive shell is now the
      // non-production default (`development`/`lab` on, `production` still
      // off; the GA-scope decision for production is Chapter 12 Kör 28).
      // There is deliberately no dart-define override (ADR 0275 unchanged).
      adaptiveShellEnabled: nonProd,
    );
  }

  /// Whether the optional account layer (login + settings cloud sync) is
  /// offered. The app is fully usable with this off.
  final bool accountEnabled;

  /// Whether the Lab diagnostics upload path is available.
  final bool diagnosticsEnabled;

  /// Whether Settings offers the Lab-mode toggle.
  final bool labModeAvailable;

  /// Whether the parallel Practice Engine V2 is available in this build.
  final bool practiceEngineV2Enabled;

  /// Whether Learn is served by Practice Engine V2 instead of the legacy path.
  /// [forEnvironment] enables it outside production; the default constructor
  /// remains OFF for explicitly constructed flag sets.
  final bool migratedLearnEnabled;

  /// Whether the versioned, detailed Practice history store may be written.
  final bool practiceDetailedHistoryEnabled;

  /// Whether the parallel Song Trainer V2 (SongDocument V2 + file/asset
  /// storage + importer + Practice Engine integration) is reachable in this
  /// build. It is enabled by [forEnvironment] outside production, while the
  /// default constructor stays OFF. The flag has no dart-define override.
  final bool songTrainerV2Enabled;

  /// Whether the AI Tutor feature is available. Defaults to OFF.
  final bool aiTutorEnabled;

  /// Whether cloud AI Tutor capabilities are available. Defaults to OFF.
  final bool aiTutorCloudEnabled;

  /// Whether deterministic practice-plan generation is available. Available
  /// outside production through the same `nonProd` rollout boundary as
  /// [practiceEngineV2Enabled] (E15-R07, ADR 0491 D2); the default
  /// constructor remains OFF, so manually created flag sets still require
  /// an explicit opt-in.
  final bool practiceGeneratorEnabled;

  /// Whether model-assisted practice-plan suggestions are available. It
  /// remains OFF in every environment until its rollout decision is recorded.
  final bool plannerAssistEnabled;

  /// Whether the offline-first Computer Vision capability is available.
  final bool visionEnabled;

  /// Whether the vision setup flow is available.
  final bool visionSetupEnabled;

  /// Whether hand tracking may run locally.
  final bool visionHandTrackingEnabled;

  /// Whether pose tracking may run locally.
  final bool visionPoseTrackingEnabled;

  /// Whether guitar geometry may be derived locally.
  final bool visionGuitarGeometryEnabled;

  /// Whether vision evidence may augment Practice.
  final bool visionPracticeIntegrationEnabled;

  /// Whether vision evidence may augment Song Trainer.
  final bool visionSongIntegrationEnabled;

  /// Whether vision evidence may be shown to AI Tutor locally.
  final bool visionTutorIntegrationEnabled;

  /// Whether vision evidence may augment Analyze.
  final bool visionAnalysisIntegrationEnabled;

  /// Whether the experimental fine-fret capability is available.
  final bool visionExperimentalFineFretEnabled;

  /// Whether Lab-only camera capture diagnostics are available.
  final bool visionLabCaptureEnabled;

  /// Whether the parallel Audio Analysis V2 route is available. It remains
  /// OFF in every environment throughout the Epic 6 build phase (ADR 0220).
  final bool audioAnalysisV2Enabled;

  /// Whether V2 may publish beat-grid evidence. Defaults to OFF (ADR 0220).
  final bool analysisBeatGridEnabled;

  /// Whether V2 may publish pitch evidence. Defaults to OFF (ADR 0220).
  final bool analysisPitchEnabled;

  /// Whether experimental V2 DC removal and peak normalization may run.
  /// It remains OFF in every environment until a later production-wiring round.
  final bool analysisPreprocessingExperimentalEnabled;

  /// Whether experimental DSP/ML chord fusion may run in a future V2 caller.
  /// It remains OFF in every environment until E06-R29 evaluation evidence.
  final bool analysisExperimentalFusionEnabled;

  /// Whether the Lab-only technique-proxy calculators (E06-R18, ADR 0236) may
  /// run. Even when true, the calculator itself only executes for a caller
  /// that separately signals explicit Lab mode — the two gates are distinct
  /// and both required. It remains OFF in every environment until the
  /// proxies' eval-matrix rows are closed.
  final bool analysisTechniqueProxiesEnabled;

  /// Whether the session comparison and trend route (E06-R25, ADR 0246) is
  /// reachable. Remains OFF in every environment until the eval-matrix rows
  /// are closed with real device data (brief §9).
  final bool analysisComparisonEnabled;

  /// Whether Analysis evidence adapters for Practice and Song may instantiate.
  /// This remains OFF in every environment until consumer wiring ships.
  final bool analysisPracticeIntegrationEnabled;

  /// Whether the redacted Analysis-to-Tutor adapter may instantiate.
  /// This remains OFF in every environment until Tutor wiring ships.
  final bool analysisTutorIntegrationEnabled;

  /// Whether the recognition recovery program may activate its guarded paths.
  /// It remains OFF in every environment until evaluation evidence is accepted.
  final bool recognitionRecoveryEnabled;

  /// Whether recognition recovery may run in shadow mode without UI changes.
  /// It remains OFF in every environment until evaluation evidence is accepted.
  final bool recognitionShadowModeEnabled;

  /// Whether the new Live recognition stage may be reachable.
  /// It remains OFF in every environment until evaluation evidence is accepted.
  final bool newLiveStageEnabled;

  /// Epic 9 master kill switch. The four sub-flags below are only honoured
  /// when this is on; this gate is the one audit reviewers and on-call
  /// operators reach for to pull the entire Community surface area offline
  /// in a single build.
  ///
  /// Production default is OFF (ADR 0395) — a `STRUMSIGHT_COMMUNITY` define
  /// is the only way to flip this on.
  final bool communityEnabled;

  /// Whether Community *writes* (posts, comments, follows, club actions,
  /// challenge submissions) are accepted. Reads may already be served by
  /// static fixtures while writes stay off. Production default OFF.
  final bool communityWritesEnabled;

  /// Whether user-uploaded *media* (images attached to posts/challenges) is
  /// accepted. Until this is on, the surface area is text-only. Production
  /// default OFF.
  final bool communityMediaEnabled;

  /// Whether the public *leaderboard* surfaces user ranking. The on-device
  /// gamification ledger is unaffected — this only controls the social
  /// visibility layer. Production default OFF.
  final bool communityLeaderboardEnabled;

  /// Whether *clubs* (membership, club-targets, club-only posts) are
  /// reachable. Club membership is opt-in and reversible. Production default
  /// OFF.
  final bool communityClubsEnabled;

  /// Whether the five-area (Today/Practice/Songs/Coach/Profile) adaptive
  /// shell is reachable (ADR 0275, ADR 0467). [forEnvironment] enables it
  /// outside production; the default constructor stays OFF for explicitly
  /// constructed flag sets. Production remains off pending the GA-scope
  /// decision (Chapter 12 Kör 28). The legacy shell navigation is unaffected
  /// while this stays off.
  final bool adaptiveShellEnabled;

  /// The build-time rollout level. Shadow execution has an additional
  /// runtime Lab-mode gate, so it is intentionally not inferred here.
  AnalysisRolloutStage get analysisRolloutStage => audioAnalysisV2Enabled
      ? AnalysisRolloutStage.v2OptIn
      : AnalysisRolloutStage.v1Default;

  /// True when any flag implies network use (drives URL validation).
  bool get usesNetwork => accountEnabled || diagnosticsEnabled;

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags &&
      other.accountEnabled == accountEnabled &&
      other.diagnosticsEnabled == diagnosticsEnabled &&
      other.labModeAvailable == labModeAvailable &&
      other.practiceEngineV2Enabled == practiceEngineV2Enabled &&
      other.migratedLearnEnabled == migratedLearnEnabled &&
      other.practiceDetailedHistoryEnabled == practiceDetailedHistoryEnabled &&
      other.songTrainerV2Enabled == songTrainerV2Enabled &&
      other.aiTutorEnabled == aiTutorEnabled &&
      other.aiTutorCloudEnabled == aiTutorCloudEnabled &&
      other.practiceGeneratorEnabled == practiceGeneratorEnabled &&
      other.plannerAssistEnabled == plannerAssistEnabled &&
      other.visionEnabled == visionEnabled &&
      other.visionSetupEnabled == visionSetupEnabled &&
      other.visionHandTrackingEnabled == visionHandTrackingEnabled &&
      other.visionPoseTrackingEnabled == visionPoseTrackingEnabled &&
      other.visionGuitarGeometryEnabled == visionGuitarGeometryEnabled &&
      other.visionPracticeIntegrationEnabled ==
          visionPracticeIntegrationEnabled &&
      other.visionSongIntegrationEnabled == visionSongIntegrationEnabled &&
      other.visionTutorIntegrationEnabled == visionTutorIntegrationEnabled &&
      other.visionAnalysisIntegrationEnabled ==
          visionAnalysisIntegrationEnabled &&
      other.visionExperimentalFineFretEnabled ==
          visionExperimentalFineFretEnabled &&
      other.visionLabCaptureEnabled == visionLabCaptureEnabled &&
      other.audioAnalysisV2Enabled == audioAnalysisV2Enabled &&
      other.analysisBeatGridEnabled == analysisBeatGridEnabled &&
      other.analysisPitchEnabled == analysisPitchEnabled &&
      other.analysisPreprocessingExperimentalEnabled ==
          analysisPreprocessingExperimentalEnabled &&
      other.analysisExperimentalFusionEnabled ==
          analysisExperimentalFusionEnabled &&
      other.analysisTechniqueProxiesEnabled ==
          analysisTechniqueProxiesEnabled &&
      other.analysisComparisonEnabled == analysisComparisonEnabled &&
      other.analysisPracticeIntegrationEnabled ==
          analysisPracticeIntegrationEnabled &&
      other.analysisTutorIntegrationEnabled ==
          analysisTutorIntegrationEnabled &&
      other.recognitionRecoveryEnabled == recognitionRecoveryEnabled &&
      other.recognitionShadowModeEnabled == recognitionShadowModeEnabled &&
      other.newLiveStageEnabled == newLiveStageEnabled &&
      other.communityEnabled == communityEnabled &&
      other.communityWritesEnabled == communityWritesEnabled &&
      other.communityMediaEnabled == communityMediaEnabled &&
      other.communityLeaderboardEnabled == communityLeaderboardEnabled &&
      other.communityClubsEnabled == communityClubsEnabled &&
      other.adaptiveShellEnabled == adaptiveShellEnabled;

  @override
  int get hashCode {
    final legacyHash = Object.hash(
      accountEnabled,
      diagnosticsEnabled,
      labModeAvailable,
      practiceEngineV2Enabled,
      migratedLearnEnabled,
      practiceDetailedHistoryEnabled,
    );
    final additionalBits = <bool>[
      songTrainerV2Enabled,
      aiTutorEnabled,
      aiTutorCloudEnabled,
      practiceGeneratorEnabled,
      plannerAssistEnabled,
      visionEnabled,
      visionSetupEnabled,
      visionHandTrackingEnabled,
      visionPoseTrackingEnabled,
      visionGuitarGeometryEnabled,
      visionPracticeIntegrationEnabled,
      visionSongIntegrationEnabled,
      visionTutorIntegrationEnabled,
      visionAnalysisIntegrationEnabled,
      visionExperimentalFineFretEnabled,
      visionLabCaptureEnabled,
      audioAnalysisV2Enabled,
      analysisBeatGridEnabled,
      analysisPitchEnabled,
      analysisPreprocessingExperimentalEnabled,
      analysisExperimentalFusionEnabled,
      analysisTechniqueProxiesEnabled,
      analysisComparisonEnabled,
      analysisPracticeIntegrationEnabled,
      analysisTutorIntegrationEnabled,
      recognitionRecoveryEnabled,
      recognitionShadowModeEnabled,
      newLiveStageEnabled,
      communityEnabled,
      communityWritesEnabled,
      communityMediaEnabled,
      communityLeaderboardEnabled,
      communityClubsEnabled,
      adaptiveShellEnabled,
    ];
    if (!additionalBits.contains(true)) {
      return legacyHash;
    }
    return Object.hashAll(<Object?>[legacyHash, ...additionalBits]);
  }

  @override
  String toString() =>
      'FeatureFlags(accountEnabled: $accountEnabled, '
      'diagnosticsEnabled: $diagnosticsEnabled, '
      'labModeAvailable: $labModeAvailable, '
      'practiceEngineV2Enabled: $practiceEngineV2Enabled, '
      'migratedLearnEnabled: $migratedLearnEnabled, '
      'practiceDetailedHistoryEnabled: $practiceDetailedHistoryEnabled, '
      'songTrainerV2Enabled: $songTrainerV2Enabled, '
      'aiTutorEnabled: $aiTutorEnabled, '
      'aiTutorCloudEnabled: $aiTutorCloudEnabled, '
      'practiceGeneratorEnabled: $practiceGeneratorEnabled, '
      'plannerAssistEnabled: $plannerAssistEnabled, '
      'visionEnabled: $visionEnabled, '
      'visionSetupEnabled: $visionSetupEnabled, '
      'visionHandTrackingEnabled: $visionHandTrackingEnabled, '
      'visionPoseTrackingEnabled: $visionPoseTrackingEnabled, '
      'visionGuitarGeometryEnabled: $visionGuitarGeometryEnabled, '
      'visionPracticeIntegrationEnabled: $visionPracticeIntegrationEnabled, '
      'visionSongIntegrationEnabled: $visionSongIntegrationEnabled, '
      'visionTutorIntegrationEnabled: $visionTutorIntegrationEnabled, '
      'visionAnalysisIntegrationEnabled: $visionAnalysisIntegrationEnabled, '
      'visionExperimentalFineFretEnabled: '
      '$visionExperimentalFineFretEnabled, '
      'visionLabCaptureEnabled: $visionLabCaptureEnabled, '
      'audioAnalysisV2Enabled: $audioAnalysisV2Enabled, '
      'analysisBeatGridEnabled: $analysisBeatGridEnabled, '
      'analysisPitchEnabled: $analysisPitchEnabled, '
      'analysisPreprocessingExperimentalEnabled: '
      '$analysisPreprocessingExperimentalEnabled, '
      'analysisExperimentalFusionEnabled: '
      '$analysisExperimentalFusionEnabled, '
      'analysisTechniqueProxiesEnabled: $analysisTechniqueProxiesEnabled, '
      'analysisComparisonEnabled: $analysisComparisonEnabled, '
      'analysisPracticeIntegrationEnabled: '
      '$analysisPracticeIntegrationEnabled, '
      'analysisTutorIntegrationEnabled: $analysisTutorIntegrationEnabled, '
      'recognitionRecoveryEnabled: $recognitionRecoveryEnabled, '
      'recognitionShadowModeEnabled: $recognitionShadowModeEnabled, '
      'newLiveStageEnabled: $newLiveStageEnabled, '
      'communityEnabled: $communityEnabled, '
      'communityWritesEnabled: $communityWritesEnabled, '
      'communityMediaEnabled: $communityMediaEnabled, '
      'communityLeaderboardEnabled: $communityLeaderboardEnabled, '
      'communityClubsEnabled: $communityClubsEnabled, '
      'adaptiveShellEnabled: $adaptiveShellEnabled)';
}
