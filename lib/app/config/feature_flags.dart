import 'app_environment.dart';

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
      other.analysisPitchEnabled == analysisPitchEnabled;

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
      'analysisPitchEnabled: $analysisPitchEnabled)';
}
