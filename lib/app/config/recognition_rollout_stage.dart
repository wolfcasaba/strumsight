/// The controlled rollout ladder of one recognition model band
/// (SDD Ch14 §7.2/§7.4 gates, Kör 24 and Kör 33; ADR 0542).
///
/// This is a CLOSED enum on purpose. A percentage `double` or a free
/// `String` stage name would let a build claim a rollout level nobody
/// reviewed, and would make "which gate must be green here?" a runtime
/// question instead of a compile-time one. Each value names exactly one
/// reviewed step, and the ladder is ordered: a stage never implies the
/// permissions of a later one.
///
/// The ladder is deliberately fail-closed at both ends:
///
/// - [off] is the default of every environment on the shipped tree. It is
///   not "no opinion" — it means the band does not run at all, not even in
///   the background.
/// - [ga] never turns itself on. Moving a band up the ladder is a source
///   change plus the human decision recorded in
///   `docs/release/ch14-production-gate.md`.
///
/// **What this type does NOT decide:** whether the band's shadow inference
/// actually executes. That needs the stage AND the matching master switch
/// (`FeatureFlags.recognitionShadowModeEnabled` for strum,
/// `FeatureFlags.recognitionChordShadowModeEnabled` for chord) — an AND, so
/// either one alone can kill the path. See `feature_flags.dart`.
library;

enum RecognitionRolloutStage {
  /// The band is completely absent: no inference, no UI, no telemetry.
  off,

  /// The band runs alongside the shipped path and its output is compared
  /// against it, but NOTHING it produces may reach a `LiveFrame`, a score,
  /// or any pixel the user sees. The only sink is the Lab/diagnostics
  /// report.
  shadow,

  /// Internal alpha: the band's output is user-visible, but only in builds
  /// the team controls (`AppEnvironment.lab`/`development`). SDD Ch14 §7.2
  /// / §7.4 Alpha thresholds must be green.
  alpha,

  /// Opt-in beta: user-visible for testers who explicitly joined the beta.
  /// SDD Ch14 §7.3 / §7.5 Beta targets are the bar.
  beta,

  /// General availability: user-visible for everyone the build reaches.
  ga;

  /// Whether the band may run inference at all (shadow counts — it runs,
  /// it just may not be shown).
  bool get runsInference => switch (this) {
    RecognitionRolloutStage.off => false,
    RecognitionRolloutStage.shadow ||
    RecognitionRolloutStage.alpha ||
    RecognitionRolloutStage.beta ||
    RecognitionRolloutStage.ga => true,
  };

  /// Whether the band's output may reach the user interface.
  ///
  /// [shadow] is explicitly false here: that is the whole point of a shadow
  /// stage, and it is the invariant PKG-E's machine guard pins.
  bool get isUserVisible => switch (this) {
    RecognitionRolloutStage.off || RecognitionRolloutStage.shadow => false,
    RecognitionRolloutStage.alpha ||
    RecognitionRolloutStage.beta ||
    RecognitionRolloutStage.ga => true,
  };

  /// Whether this stage requires the SDD Ch14 §7.3/§7.5 Beta targets rather
  /// than the weaker §7.2/§7.4 Alpha minimums.
  bool get requiresBetaThresholds => switch (this) {
    RecognitionRolloutStage.off ||
    RecognitionRolloutStage.shadow ||
    RecognitionRolloutStage.alpha => false,
    RecognitionRolloutStage.beta || RecognitionRolloutStage.ga => true,
  };

  /// Parses a stage name coming from a build-time define or a release
  /// document, fail-closed: an unknown, misspelled or empty value resolves
  /// to `null` so the caller falls back to [off] rather than guessing at a
  /// more permissive neighbour.
  static RecognitionRolloutStage? tryParse(String? name) {
    if (name == null) return null;
    for (final stage in RecognitionRolloutStage.values) {
      if (stage.name == name) return stage;
    }
    return null;
  }
}
