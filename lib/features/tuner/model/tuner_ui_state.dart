/// The tuner's visual/narrated state (brief §3, §0.0/R5.1). Five of the six
/// states the scope names — idle, listening, no-pitch — collapse into
/// [idle] (all three share the estimator's single `!hasSignal` branch, the
/// existing tuner behaviour); [unstable] is derived by [TunerStability]
/// (never by the estimator); [inTune]/[outOfTune] read `TunerReading.inTune`
/// directly. The reference-tone state is an orthogonal branch (a pinned
/// string), not a member of this enum.
enum TunerUiState { idle, unstable, inTune, outOfTune }

/// Pure mapping from the estimator's measured output (plus the UI-derived
/// [unstable] flag) to [TunerUiState] — the A1 acceptance surface.
TunerUiState tunerUiStateOf({
  required bool hasSignal,
  required bool inTune,
  required bool unstable,
}) {
  if (!hasSignal) return TunerUiState.idle;
  if (unstable) return TunerUiState.unstable;
  return inTune ? TunerUiState.inTune : TunerUiState.outOfTune;
}
