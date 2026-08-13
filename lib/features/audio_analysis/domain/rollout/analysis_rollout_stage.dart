/// Deliberate release stages for the parallel Audio Analysis V2 path.
///
/// The build-time [FeatureFlags] mapping remains at [v1Default] throughout
/// Epic 6. Shadow execution is a separate, explicitly injected Lab/runtime
/// gate; it must not silently advance the shipping rollout stage.
enum AnalysisRolloutStage {
  /// V1 is the only shipping result and all V2 flags are disabled.
  v1Default,

  /// V2 may run only as Lab diagnostics beside an unchanged V1 result.
  v2ShadowLab,

  /// A separately approved user opt-in makes V2 reachable.
  v2OptIn,

  /// A separately approved rollout makes V2 the default path.
  v2Default,
}
