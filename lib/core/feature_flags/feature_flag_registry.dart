import 'feature_flag_definition.dart';

/// The catalog of every `lib/app/config/feature_flags.dart` field (ADR
/// 0446).
///
/// This file deliberately does NOT import `FeatureFlags` (ADR 0446 D5):
/// `lib/app/config/feature_flags.dart` itself imports a feature-domain type
/// (`lib/features/audio_analysis/domain/rollout/analysis_rollout_stage.dart`),
/// so importing `FeatureFlags` from here would make `lib/core/` transitively
/// depend on `lib/features/**`. Entries are keyed by field NAME only; the
/// binding to the real fields is made a machine-checked fact by
/// `tool/check_feature_flags.dart` (ADR 0446 D4), not by a type reference.
///
/// **Round measurement correction (E12-R05):** the round brief's pre-flight
/// (§0.0 R1) states 37 `final bool` fields (3 required + 34 defaulted). A
/// direct re-count against `main @ c37904d0` — the same commit the pre-flight
/// itself measured — finds **40** fields (3 required + 37 defaulted); see
/// `grep -c 'final bool ' lib/app/config/feature_flags.dart`. This does not
/// change how completeness is defined (ADR 0446 D4 derives it from parsing
/// the live source, not from a fixed count), so this registry catalogs all
/// 40 real fields — the count that keeps `dart run
/// tool/check_feature_flags.dart` green on the shipped tree (R5). See the
/// round's §10 handoff for the full note.
///
/// **`risk` heuristic (a judgement call, not a machine measurement):**
/// `FeatureFlagRisk.high` is used only where `feature_flags.dart` itself
/// either (a) participates in `usesNetwork` (`accountEnabled`,
/// `diagnosticsEnabled` — `feature_flags.dart:299`), or (b) its own doc
/// comment names a network/data-egress path in words ("cloud", "upload",
/// "accepted" writes/media). Everything else defaults to `medium` (a
/// user-reachable behaviour change, or a cross-feature integration surface)
/// or `low` (an internal pipeline stage, an experimental/Lab-only path, or a
/// flag with zero consumers outside `feature_flags.dart` today).
const List<FeatureFlagDefinition> featureFlagRegistry = [
  // ---------------------------------------------------------------------
  // Core availability (E01-R03) — lib/app/config/feature_flags.dart:135-141
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'accountEnabled',
    owner: 'lib/features/auth (account layer)',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    killSwitchPath:
        'STRUMSIGHT_ACCOUNT dart-define, read at '
        'lib/core/api/api_config.dart:19; already off by default — omit '
        'the define at build time to keep it off.',
  ),
  FeatureFlagDefinition(
    key: 'diagnosticsEnabled',
    owner: 'lib/features/diagnostics',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    killSwitchPath:
        'gated by `environment != AppEnvironment.production` at '
        'feature_flags.dart:76; a production release build already '
        'resolves this to false.',
  ),
  FeatureFlagDefinition(
    key: 'labModeAvailable',
    owner: 'lib/features/settings (Lab-mode toggle)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'gated by `environment != AppEnvironment.production` at '
        'feature_flags.dart:77; a production release build already '
        'resolves this to false.',
  ),

  // ---------------------------------------------------------------------
  // Practice Engine V2 / Learn / Song Trainer rollout boundary
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'practiceEngineV2Enabled',
    owner: 'lib/features/practice (Practice Engine V2)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    killSwitchPath:
        'gated by `environment != AppEnvironment.production` at '
        'feature_flags.dart:78; a production release build already '
        'resolves this to false.',
  ),
  FeatureFlagDefinition(
    key: 'migratedLearnEnabled',
    owner: 'lib/features/learn',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    killSwitchPath:
        'gated by `environment != AppEnvironment.production` at '
        'feature_flags.dart:79; a production release build already '
        'resolves this to false.',
  ),
  FeatureFlagDefinition(
    key: 'practiceDetailedHistoryEnabled',
    owner: 'lib/features/practice (detailed history store)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'gated by `environment != AppEnvironment.production` at '
        'feature_flags.dart:80; a production release build already '
        'resolves this to false.',
  ),
  FeatureFlagDefinition(
    key: 'songTrainerV2Enabled',
    owner: 'lib/features/song_trainer',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0197',
    killSwitchPath:
        'gated by `environment != AppEnvironment.production` at '
        'feature_flags.dart:81; a production release build already '
        'resolves this to false.',
  ),

  // ---------------------------------------------------------------------
  // AI Tutor
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'aiTutorEnabled',
    owner: 'lib/features/ai_tutor',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0132',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:82; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'aiTutorCloudEnabled',
    owner: 'lib/features/ai_tutor (cloud capability)',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    adr: '0213',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:83; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),

  // ---------------------------------------------------------------------
  // Practice Generator (ADR 0255/0270)
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'practiceGeneratorEnabled',
    owner: 'lib/features/practice_generator',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0491',
    killSwitchPath:
        'resolves to `nonProd` (`environment != AppEnvironment.production`) '
        'at feature_flags.dart:92 since E15-R07 (ADR 0491 D2) — ON by '
        'default outside production, OFF in production; no dart-define '
        'exists on purpose. The kill switch is reverting that line to '
        '`false` (ADR 0491), a source change.',
  ),
  FeatureFlagDefinition(
    key: 'plannerAssistEnabled',
    owner: 'lib/features/practice_generator (planner assist)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0270',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:85; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),

  // ---------------------------------------------------------------------
  // Vision (ADR 0178 privacy-by-default master gate + sub-capabilities)
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'visionEnabled',
    owner: 'lib/features/vision',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0178',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:86; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionSetupEnabled',
    owner: 'lib/features/vision (setup flow)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:87; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionHandTrackingEnabled',
    owner: 'lib/features/vision (hand tracking)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:88; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionPoseTrackingEnabled',
    owner: 'lib/features/vision (pose tracking)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:89; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionGuitarGeometryEnabled',
    owner: 'lib/features/vision (guitar geometry)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0187',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:90; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionPracticeIntegrationEnabled',
    owner: 'lib/features/vision (Practice integration)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:91; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionSongIntegrationEnabled',
    owner: 'lib/features/vision (Song Trainer integration)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:92; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionTutorIntegrationEnabled',
    owner: 'lib/features/vision (AI Tutor integration)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0194',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:93; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionAnalysisIntegrationEnabled',
    owner: 'lib/features/vision (Analyze integration)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0194',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:94; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionExperimentalFineFretEnabled',
    owner: 'lib/features/vision (experimental fine-fret)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:95; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'visionLabCaptureEnabled',
    owner: 'lib/features/vision (Lab-only camera capture diagnostics)',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:96; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),

  // ---------------------------------------------------------------------
  // Audio Analysis V2 (ADR 0220 master gate + sub-capabilities)
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'audioAnalysisV2Enabled',
    owner: 'lib/features/audio_analysis (V2 route)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0220',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:97; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisBeatGridEnabled',
    owner: 'lib/features/audio_analysis (beat-grid evidence)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0220',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:98; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisPitchEnabled',
    owner: 'lib/features/audio_analysis (pitch evidence)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0220',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:99; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisPreprocessingExperimentalEnabled',
    owner: 'lib/features/audio_analysis (experimental preprocessing)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:100; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisExperimentalFusionEnabled',
    owner: 'lib/features/audio_analysis (experimental DSP/ML fusion)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:101; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisTechniqueProxiesEnabled',
    owner: 'lib/features/audio_analysis (Lab technique-proxy calculators)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0236',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:102; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisComparisonEnabled',
    owner: 'lib/features/audio_analysis (session comparison/trend)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0246',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:103; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisPracticeIntegrationEnabled',
    owner: 'lib/features/audio_analysis (Practice evidence adapter)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:104; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'analysisTutorIntegrationEnabled',
    owner: 'lib/features/audio_analysis (Tutor evidence adapter)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:105; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),

  // ---------------------------------------------------------------------
  // Recognition recovery (ADR 0271) — measured zero consumers outside
  // feature_flags.dart today (grep, lib/): guarded, not yet wired.
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'recognitionRecoveryEnabled',
    owner: 'lib/features/live (recognition recovery, not yet wired)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0271',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:106; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'recognitionShadowModeEnabled',
    owner: 'lib/features/live (recognition recovery, not yet wired)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0271',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:107; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),
  FeatureFlagDefinition(
    key: 'newLiveStageEnabled',
    owner: 'lib/features/live (recognition recovery, not yet wired)',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    adr: '0271',
    killSwitchPath:
        'hardcoded to `false` in every environment at '
        'feature_flags.dart:108; no dart-define or environment boundary '
        'can turn it on today — enabling it requires a source change.',
  ),

  // ---------------------------------------------------------------------
  // Epic 9 Community (ADR 0395)
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'communityEnabled',
    owner: 'lib/features/community',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    adr: '0395',
    killSwitchPath:
        'STRUMSIGHT_COMMUNITY dart-define at feature_flags.dart:113; '
        'already off by default — omit the define at build time to keep '
        'the whole Community surface off.',
  ),
  FeatureFlagDefinition(
    key: 'communityWritesEnabled',
    owner: 'lib/features/community (writes)',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    adr: '0395',
    killSwitchPath:
        'STRUMSIGHT_COMMUNITY_WRITES dart-define at '
        'feature_flags.dart:114-116; already off by default — omit the '
        'define at build time.',
  ),
  FeatureFlagDefinition(
    key: 'communityMediaEnabled',
    owner: 'lib/features/community (media uploads)',
    risk: FeatureFlagRisk.high,
    failClosedDefault: false,
    adr: '0395',
    killSwitchPath:
        'STRUMSIGHT_COMMUNITY_MEDIA dart-define at '
        'feature_flags.dart:117-119; already off by default — omit the '
        'define at build time.',
  ),
  FeatureFlagDefinition(
    key: 'communityLeaderboardEnabled',
    owner: 'lib/features/community (leaderboard)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0395',
    killSwitchPath:
        'STRUMSIGHT_COMMUNITY_LEADERBOARD dart-define at '
        'feature_flags.dart:120-122; already off by default — omit the '
        'define at build time.',
  ),
  FeatureFlagDefinition(
    key: 'communityClubsEnabled',
    owner: 'lib/features/community (clubs)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0395',
    killSwitchPath:
        'STRUMSIGHT_COMMUNITY_CLUBS dart-define at '
        'feature_flags.dart:123-125; already off by default — omit the '
        'define at build time.',
  ),

  // ---------------------------------------------------------------------
  // Adaptive shell (ADR 0275)
  // ---------------------------------------------------------------------
  FeatureFlagDefinition(
    key: 'adaptiveShellEnabled',
    owner: 'lib/app (adaptive shell — home_shell.dart, routing/*)',
    risk: FeatureFlagRisk.medium,
    failClosedDefault: false,
    adr: '0275',
    killSwitchPath:
        'resolves to `nonProd` (`environment != AppEnvironment.production`) '
        'at feature_flags.dart:129 since E15-R02 (ADR 0467 D1) — ON by '
        'default in development/lab, OFF in production; no dart-define '
        'exists on purpose. The kill switch is reverting that line to '
        '`false` (ADR 0467 D8), a source change.',
  ),
];
