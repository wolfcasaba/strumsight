import 'app_environment.dart';
import 'recognition_rollout_stage.dart';
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
    this.recognitionChordShadowModeEnabled = false,
    this.recognitionPreprocessingEnabled = false,
    this.recognitionFieldSessionTaggingEnabled = false,
    this.betaTelemetryEnabled = false,
    this.strumModelRolloutStage = RecognitionRolloutStage.off,
    this.chordModelRolloutStage = RecognitionRolloutStage.off,
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
  factory FeatureFlags.forEnvironment(
    AppEnvironment environment, {
    required bool accountEnabled,
  }) {
    final nonProd = environment != AppEnvironment.production;
    return FeatureFlags(
      accountEnabled: accountEnabled,
      diagnosticsEnabled: nonProd,
      labModeAvailable: nonProd,
      practiceEngineV2Enabled: nonProd,
      migratedLearnEnabled: nonProd,
      practiceDetailedHistoryEnabled: nonProd,
      songTrainerV2Enabled: nonProd,
      aiTutorEnabled: false,
      aiTutorCloudEnabled: false,
      // E15-R07 F1 (ADR 0491 D2) — same `nonProd` rollout boundary as
      // `practiceEngineV2Enabled`: ON outside production, OFF in
      // production. `plannerAssistEnabled` (model-assisted suggestions) is
      // a separate rollout decision and stays OFF everywhere.
      practiceGeneratorEnabled: nonProd,
      plannerAssistEnabled: false,
      visionEnabled: false,
      visionSetupEnabled: false,
      visionHandTrackingEnabled: false,
      visionPoseTrackingEnabled: false,
      visionGuitarGeometryEnabled: false,
      visionPracticeIntegrationEnabled: false,
      visionSongIntegrationEnabled: false,
      visionTutorIntegrationEnabled: false,
      visionAnalysisIntegrationEnabled: false,
      visionExperimentalFineFretEnabled: false,
      visionLabCaptureEnabled: false,
      audioAnalysisV2Enabled: false,
      analysisBeatGridEnabled: false,
      analysisPitchEnabled: false,
      analysisPreprocessingExperimentalEnabled: false,
      analysisExperimentalFusionEnabled: false,
      analysisTechniqueProxiesEnabled: false,
      analysisComparisonEnabled: false,
      analysisPracticeIntegrationEnabled: false,
      analysisTutorIntegrationEnabled: false,
      recognitionRecoveryEnabled: false,
      // E14-R23/R24/R33/R41 (ADR 0542). Every recognition-recovery gate
      // resolves to OFF in EVERY environment, including non-production:
      // none of the SDD Ch14 §7 thresholds is green on the measured
      // baseline (`evaluation/recognition/baseline_manifest.json`: onset
      // F1@50 ms 0,674 vs. 0,82; chord accuracy 0,671 vs. 0,80; direction,
      // latency and calibration blocks `not-measured`). A `nonProd`
      // default here would make a dev build claim a rollout level no
      // measurement supports.
      recognitionShadowModeEnabled: false,
      recognitionChordShadowModeEnabled: false,
      recognitionPreprocessingEnabled: false,
      recognitionFieldSessionTaggingEnabled: false,
      // E14-R41: the opt-in beta telemetry SURFACE (the Privacy Center
      // consent row) follows the same `nonProd` boundary as
      // `diagnosticsEnabled`, because it is gated on that flag anyway.
      // Availability is not collection: nothing is recorded until the
      // user grants consent, which defaults to denied.
      betaTelemetryEnabled: nonProd,
      strumModelRolloutStage: RecognitionRolloutStage.off,
      chordModelRolloutStage: RecognitionRolloutStage.off,
      newLiveStageEnabled: false,
      // Epic 9 Community (E09-R01, ADR 0395). The compile-time kill switch is
      // read directly here so app_config.dart stays untouched — without a
      // dart-define, every environment resolves to `false`, which keeps the
      // feature completely absent from production until a deliberate flip.
      communityEnabled: const bool.fromEnvironment('STRUMSIGHT_COMMUNITY'),
      communityWritesEnabled: const bool.fromEnvironment(
        'STRUMSIGHT_COMMUNITY_WRITES',
      ),
      communityMediaEnabled: const bool.fromEnvironment(
        'STRUMSIGHT_COMMUNITY_MEDIA',
      ),
      communityLeaderboardEnabled: const bool.fromEnvironment(
        'STRUMSIGHT_COMMUNITY_LEADERBOARD',
      ),
      communityClubsEnabled: const bool.fromEnvironment(
        'STRUMSIGHT_COMMUNITY_CLUBS',
      ),
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

  /// Master switch for STRUM shadow recognition (SDD Ch14 Kör 23).
  ///
  /// **Semantics (ADR 0542 D2), so the flag can never be read two ways:**
  /// a shadow strum inference may run for a frame only when BOTH
  /// - [strumModelRolloutStage] `.runsInference` is true, AND
  /// - this switch is true.
  ///
  /// The AND is asymmetric on purpose — either half alone turns the path
  /// OFF, neither alone turns it ON — so an incident responder can kill
  /// shadow work with one boolean without having to reason about the
  /// rollout ladder. While the pair is off, the shadow path must cost
  /// ZERO extra inference calls, not "a cheap call whose result is
  /// dropped".
  ///
  /// **Consumed-by contract:** the shadow observer seam in
  /// `lib/features/live/**` (PKG-A's `RecognitionShadowObserver`) reads
  /// this pair and nothing else; the shadow output may reach the Lab panel
  /// and the diagnostics report only — never a `LiveFrame`, never a score,
  /// never a pixel (`RecognitionRolloutStage.shadow.isUserVisible` is
  /// `false`, and that is the machine-checked invariant).
  ///
  /// **Measured at this round:** still zero consumers in `lib/**` — the
  /// consumer lands in wave 2 (PKG-E). This round defines and tests the
  /// flag surface only.
  final bool recognitionShadowModeEnabled;

  /// Master switch for CHORD shadow recognition — the shipped
  /// `assets/ml/chord_crnn.bin` running alongside the live NNLS-chroma path
  /// (SDD Ch14 §4.5, Kör 26).
  ///
  /// Separate from [recognitionShadowModeEnabled] because the two bands
  /// have separate release gates (§7.2 vs. §7.4), separate corpora and
  /// separate failure modes: one band's shadow run must be killable without
  /// touching the other. Same asymmetric AND with
  /// [chordModelRolloutStage].
  final bool recognitionChordShadowModeEnabled;

  /// Whether the recognition-side quality-aware preprocessing and device
  /// adaptation path (SDD Ch14 Kör 31) may run.
  ///
  /// This is the ONE-SWITCH ROLLBACK for that path: flipping it off
  /// restores the shipped preprocessing without a new model asset and
  /// without an app release, so a preprocessing regression found in the
  /// field is a flag flip, not a store round-trip. Distinct from
  /// [analysisPreprocessingExperimentalEnabled], which governs the batch
  /// Audio Analysis V2 pipeline.
  final bool recognitionPreprocessingEnabled;

  /// Whether a Lab/diagnostics capture may carry the internal Alpha
  /// FIELD-SESSION tag (SDD Ch14 Kör 40).
  ///
  /// The tag is a study cohort marker, never an identity: it may carry the
  /// closed cohort value and the rotating pseudonymous id, and nothing
  /// else (`lib/core/telemetry/field_session_tag.dart`). It is OFF in every
  /// environment — a field study is a deliberate build, so enabling it is a
  /// source change reviewed together with the study protocol
  /// (`docs/release/ch14-r40-field-study.md`).
  final bool recognitionFieldSessionTaggingEnabled;

  /// Whether the OPT-IN beta telemetry surface exists in this build
  /// (SDD Ch14 Kör 41).
  ///
  /// Availability, not collection. Three independent conditions must all
  /// hold before a single aggregate event may leave the device
  /// (`TelemetryUploadGate`): this flag, [diagnosticsEnabled], and the
  /// user's explicit, revocable consent — which defaults to
  /// `TelemetryConsentState.notAsked`, i.e. denied. Flipping this flag off
  /// is the one-switch beta rollback.
  final bool betaTelemetryEnabled;

  /// The rollout ladder step of the STRUM recognition band (Kör 24).
  /// Defaults to [RecognitionRolloutStage.off] in every environment.
  ///
  /// Deliberately NOT catalogued in `featureFlagRegistry`: that registry
  /// and its machine audit (`tool/check_feature_flags.dart`) are defined
  /// over `final bool` fields, and inventing a bool-shaped entry for an
  /// enum field would make the audit's completeness claim false in both
  /// directions (ADR 0542 D4). The stage's own reviewed record is
  /// `docs/release/ch14-recognition-rollout.md`.
  final RecognitionRolloutStage strumModelRolloutStage;

  /// The rollout ladder step of the CHORD recognition band (Kör 33).
  /// Defaults to [RecognitionRolloutStage.off] in every environment; see
  /// [strumModelRolloutStage] for why it is not in the registry.
  final RecognitionRolloutStage chordModelRolloutStage;

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
      other.recognitionChordShadowModeEnabled ==
          recognitionChordShadowModeEnabled &&
      other.recognitionPreprocessingEnabled ==
          recognitionPreprocessingEnabled &&
      other.recognitionFieldSessionTaggingEnabled ==
          recognitionFieldSessionTaggingEnabled &&
      other.betaTelemetryEnabled == betaTelemetryEnabled &&
      other.strumModelRolloutStage == strumModelRolloutStage &&
      other.chordModelRolloutStage == chordModelRolloutStage &&
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
      recognitionChordShadowModeEnabled,
      recognitionPreprocessingEnabled,
      recognitionFieldSessionTaggingEnabled,
      betaTelemetryEnabled,
      // The two rollout stages are enums, not bools; "is it still at its
      // OFF default" is the bit that decides whether the legacy hash still
      // applies, and the stages themselves are hashed below so two
      // different non-off stages never collapse into one hash.
      strumModelRolloutStage != RecognitionRolloutStage.off,
      chordModelRolloutStage != RecognitionRolloutStage.off,
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
    return Object.hashAll(<Object?>[
      legacyHash,
      ...additionalBits,
      strumModelRolloutStage,
      chordModelRolloutStage,
    ]);
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
      'recognitionChordShadowModeEnabled: '
      '$recognitionChordShadowModeEnabled, '
      'recognitionPreprocessingEnabled: $recognitionPreprocessingEnabled, '
      'recognitionFieldSessionTaggingEnabled: '
      '$recognitionFieldSessionTaggingEnabled, '
      'betaTelemetryEnabled: $betaTelemetryEnabled, '
      'strumModelRolloutStage: ${strumModelRolloutStage.name}, '
      'chordModelRolloutStage: ${chordModelRolloutStage.name}, '
      'newLiveStageEnabled: $newLiveStageEnabled, '
      'communityEnabled: $communityEnabled, '
      'communityWritesEnabled: $communityWritesEnabled, '
      'communityMediaEnabled: $communityMediaEnabled, '
      'communityLeaderboardEnabled: $communityLeaderboardEnabled, '
      'communityClubsEnabled: $communityClubsEnabled, '
      'adaptiveShellEnabled: $adaptiveShellEnabled)';
}
