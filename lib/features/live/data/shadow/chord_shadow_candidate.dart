/// Where the chord-band candidate verdict comes from (E14-R26, ADR 0549 D2).
///
/// Kept in its own file, as an interface plus a tiny value type, so the
/// observer does not depend on the CRNN and the CRNN runner does not depend
/// on the observer: `engine/ml/chord_crnn_shadow_runner.dart` implements it
/// over the shipped `chord_crnn.bin`, and a test implements it with fixed
/// labels and a call counter.
library;

abstract interface class ChordShadowCandidateSource {
  /// The candidate's verdict covering [timeSec] on the ENGINE's clock, or
  /// `null` when it has none yet (its analysis window has not filled, or no
  /// audio has reached it). `null` is recorded as "candidate unavailable",
  /// never as `N.C.` — not knowing is not the same as hearing silence.
  ChordShadowVerdict? verdictAtSeconds(double timeSec);
}

/// One chord-band candidate verdict.
class ChordShadowVerdict {
  const ChordShadowVerdict({
    required this.timeSec,
    required this.label,
    required this.posterior,
  });

  /// The verdict's own timestamp (seconds) on the candidate's frame grid.
  final double timeSec;

  /// A majmin label from the model's 25-class output (`N.C.`, `C`…`Bm`).
  final String label;

  /// The winning class's RAW posterior. NOT a calibrated confidence — no
  /// measured calibration exists for this head (ADR 0271: an uncalibrated
  /// number must not be presented as a confidence).
  final double posterior;
}
