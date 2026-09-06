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
  /// - [previewAll] mirrors the `STRUMSIGHT_PREVIEW_ALL` dart-define (WP-E,
  ///   2026-09-06). It is a **non-production preview switch only**: see
  ///   [_withPreviewSurfacesEnabled] for the exact list of what it turns on,
  ///   what it deliberately leaves off, and why production ignores it. The
  ///   parameter exists so the semantics are testable — a `const
  ///   bool.fromEnvironment` cannot be varied at runtime — and it defaults to
  ///   the define, so no caller has to pass it.
  ///
  /// **Production is unaffected by [previewAll] on purpose.** A release APK
  /// must never ship experimental / unevaluated surfaces because a stray
  /// `--dart-define` leaked into a release build command; the production
  /// rollout gate is `docs/release/ga-scope.md` plus the per-capability ADRs
  /// (ADR 0220 Analysis V2, ADR 0271 recognition recovery, ADR 0395
  /// Community, ADR 0492 capability rollout), never a build-time convenience
  /// flag. The `environment == production` early return below is that rule.
  factory FeatureFlags.forEnvironment(
    AppEnvironment environment, {
    required bool accountEnabled,
    bool previewAll = const bool.fromEnvironment('STRUMSIGHT_PREVIEW_ALL'),
  }) {
    final defaults = _environmentDefaults(
      environment,
      accountEnabled: accountEnabled,
    );
    if (environment == AppEnvironment.production || !previewAll) {
      return defaults;
    }
    return defaults._withPreviewSurfacesEnabled();
  }

  /// The per-environment defaults, unchanged by [previewAll].
  ///
  /// This is the single canonical assignment list for every flag; the
  /// preview overlay is applied on top of its result, never inside it, so
  /// `tool/release/verify_ga_scope.py` and the capability-rollout coverage
  /// test keep reading the real production defaults out of this source.
  static FeatureFlags _environmentDefaults(
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
      // 2026-09-05: dart-define-olható, DE az alapérték változatlanul
      // hamis — a `bool.fromEnvironment` define nélkül `false`, tehát a
      // szállított viselkedés bájtra ugyanaz. A kapcsolóra azért van
      // szükség, mert a felvételi folyamat (`presentation/capture/`) e
      // nélkül EGYETLEN buildben sem volt bekapcsolható, így a
      // kézi teszteléshez sem. Az Epic 6 rollout-döntését ez NEM előlegzi
      // meg: a `false` marad az alapértelmezés minden környezetben.
      audioAnalysisV2Enabled: const bool.fromEnvironment(
        'STRUMSIGHT_ANALYSIS_V2',
      ),
      analysisBeatGridEnabled: false,
      analysisPitchEnabled: false,
      analysisPreprocessingExperimentalEnabled: false,
      analysisExperimentalFusionEnabled: false,
      analysisTechniqueProxiesEnabled: false,
      analysisComparisonEnabled: false,
      analysisPracticeIntegrationEnabled: false,
      analysisTutorIntegrationEnabled: false,
      recognitionRecoveryEnabled: false,
      recognitionShadowModeEnabled: false,
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

  /// The `STRUMSIGHT_PREVIEW_ALL` overlay: every hard-coded-`false` UI
  /// capability becomes available so ONE non-production build (the Lab APK,
  /// `lab_build.json`) can actually show what the tree has built. Reached
  /// only from [FeatureFlags.forEnvironment] and only outside production.
  ///
  /// **Turned ON** (all on-device, no egress, no cost): the local AI Tutor
  /// ([aiTutorEnabled] — ADR 0132 §4 keeps the *cloud* half separate; the
  /// local deterministic fallback is network-free), [plannerAssistEnabled],
  /// the ten non-capture Vision capabilities (ADR 0178 §1: processing is
  /// on-device, raw frames never leave), the nine Audio Analysis V2
  /// capabilities (ADR 0220 — a parallel V1 stays intact), and
  /// [recognitionRecoveryEnabled] + [newLiveStageEnabled] (ADR 0271).
  ///
  /// **Deliberately left OFF even under the define:**
  /// - [aiTutorCloudEnabled] — the only flag here that sends user data off
  ///   device (and costs model money). ADR 0132 §1/§3 requires separate
  ///   explicit consent, and `docs/release/capability-rollout.md` records
  ///   the open R-PRIV-01 blocker. A build-time convenience switch must not
  ///   stand in for consent.
  /// - [visionLabCaptureEnabled] — the one documented exception to ADR 0178
  ///   §2's no-raw-frame-persistence rule. It writes raw camera frames
  ///   (face, room) to disk and ADR 0178 §4 allows that only through an
  ///   explicit, consented Lab capture action, never as a blanket flip. It
  ///   is a diagnostics path, so leaving it off hides no product surface.
  /// - [recognitionShadowModeEnabled] — runs a second recognition pipeline
  ///   with zero UI change (pure battery/CPU cost during a real-guitar
  ///   test) and ADR 0271's activation contract (evaluation report,
  ///   baseline + candidate manifests, rollback recipe) is not met.
  /// - The five Community flags and [audioAnalysisV2Enabled]'s own define
  ///   are *define-driven*, not hard-coded `false`: ADR 0395 makes
  ///   `STRUMSIGHT_COMMUNITY*` the single audited kill switch, so the
  ///   overlay passes them through untouched and `lab_build.json` sets them
  ///   explicitly. ([audioAnalysisV2Enabled] is additionally forced on here
  ///   because the nine analysis sub-capabilities are meaningless while
  ///   their master route is unregistered.)
  ///
  /// Flags already `nonProd` (diagnostics, Lab, Practice V2, Learn, detailed
  /// history, Song Trainer V2, Practice Generator, adaptive shell) and the
  /// caller-supplied [accountEnabled] pass through unchanged.
  FeatureFlags _withPreviewSurfacesEnabled() => FeatureFlags(
    accountEnabled: accountEnabled,
    diagnosticsEnabled: diagnosticsEnabled,
    labModeAvailable: labModeAvailable,
    practiceEngineV2Enabled: practiceEngineV2Enabled,
    migratedLearnEnabled: migratedLearnEnabled,
    practiceDetailedHistoryEnabled: practiceDetailedHistoryEnabled,
    songTrainerV2Enabled: songTrainerV2Enabled,
    aiTutorEnabled: true,
    // OFF by design — data egress + cost (ADR 0132, R-PRIV-01).
    aiTutorCloudEnabled: aiTutorCloudEnabled,
    practiceGeneratorEnabled: practiceGeneratorEnabled,
    plannerAssistEnabled: true,
    visionEnabled: true,
    visionSetupEnabled: true,
    visionHandTrackingEnabled: true,
    visionPoseTrackingEnabled: true,
    visionGuitarGeometryEnabled: true,
    visionPracticeIntegrationEnabled: true,
    visionSongIntegrationEnabled: true,
    visionTutorIntegrationEnabled: true,
    visionAnalysisIntegrationEnabled: true,
    visionExperimentalFineFretEnabled: true,
    // OFF by design — raw-frame persistence (ADR 0178 §2/§4).
    visionLabCaptureEnabled: visionLabCaptureEnabled,
    audioAnalysisV2Enabled: true,
    analysisBeatGridEnabled: true,
    analysisPitchEnabled: true,
    analysisPreprocessingExperimentalEnabled: true,
    analysisExperimentalFusionEnabled: true,
    analysisTechniqueProxiesEnabled: true,
    analysisComparisonEnabled: true,
    analysisPracticeIntegrationEnabled: true,
    analysisTutorIntegrationEnabled: true,
    recognitionRecoveryEnabled: true,
    // OFF by design — cost without a visible surface (ADR 0271).
    recognitionShadowModeEnabled: recognitionShadowModeEnabled,
    newLiveStageEnabled: true,
    // Define-driven kill switch (ADR 0395) — passed through untouched.
    communityEnabled: communityEnabled,
    communityWritesEnabled: communityWritesEnabled,
    communityMediaEnabled: communityMediaEnabled,
    communityLeaderboardEnabled: communityLeaderboardEnabled,
    communityClubsEnabled: communityClubsEnabled,
    adaptiveShellEnabled: adaptiveShellEnabled,
  );

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
