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
  /// - Practice V2 + detailed history are available outside production;
  ///   migrated Learn stays OFF everywhere until the parity rollout decision.
  ///   None of the practice flags has a dart-define override.
  /// - [songTrainerV2Enabled] is OFF in every environment and is NOT
  ///   influenced by `nonProd`. It is a hand-rolled rollout boundary for the
  ///   Epic 3 SongDocument V2 / file+asset storage / importer / Practice
  ///   Engine integration work; even debug and test builds default OFF so
  ///   an opt-in must always be explicit (E03-R01 §5.1).
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
      migratedLearnEnabled: false,
      practiceDetailedHistoryEnabled: nonProd,
      songTrainerV2Enabled: false,
      aiTutorEnabled: false,
      aiTutorCloudEnabled: false,
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
  final bool migratedLearnEnabled;

  /// Whether the versioned, detailed Practice history store may be written.
  final bool practiceDetailedHistoryEnabled;

  /// Whether the parallel Song Trainer V2 (SongDocument V2 + file/asset
  /// storage + importer + Practice Engine integration) is reachable in this
  /// build. Defaults to OFF in every environment — including debug and test
  /// builds — so a rollout must always be an explicit opt-in, never an
  /// implicit side-effect of running outside production (E03-R01 §5.1,
  /// SDD Ch4 §3). The flag has no dart-define override.
  final bool songTrainerV2Enabled;

  /// Whether the AI Tutor feature is available. Defaults to OFF.
  final bool aiTutorEnabled;

  /// Whether cloud AI Tutor capabilities are available. Defaults to OFF.
  final bool aiTutorCloudEnabled;

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
      other.aiTutorCloudEnabled == aiTutorCloudEnabled;

  @override
  int get hashCode => Object.hash(
    accountEnabled,
    diagnosticsEnabled,
    labModeAvailable,
    practiceEngineV2Enabled,
    migratedLearnEnabled,
    practiceDetailedHistoryEnabled,
  );

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
      'aiTutorCloudEnabled: $aiTutorCloudEnabled)';
}
