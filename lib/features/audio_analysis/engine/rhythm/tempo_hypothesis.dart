/// Half/double-time disambiguation for free-play tempo (SDD Ch7 §14.6, OD-02).
///
/// The preferred BPM band and confidence penalty are versioned constants,
/// provisional until the E06-R29 real-recording evaluation
/// (`docs/rag/chunks/020-beat-grid-tempo-curve.md`).
const double preferredTempoBandLowBpm = 60;
const double preferredTempoBandHighBpm = 180;
const double halfDoubleTimeConfidencePenalty = 0.7;

/// One candidate tempo, with whether it is the published value.
final class TempoHypothesis {
  TempoHypothesis({
    required this.bpm,
    required this.confidence,
    required this.isPublished,
  }) {
    if (!bpm.isFinite || bpm <= 0 || bpm > 400) {
      throw ArgumentError.value(bpm, 'bpm', 'must be finite and in (0, 400]');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final double bpm;
  final double confidence;
  final bool isPublished;
}

/// The full set of candidate tempo hypotheses for one clip (SDD Ch7 §14.6).
///
/// Ambiguity is never silently resolved: when the raw estimate falls
/// outside the preferred band, both the raw and the shifted value are kept.
final class TempoHypothesisSet {
  TempoHypothesisSet({required List<TempoHypothesis> hypotheses})
    : hypotheses = List<TempoHypothesis>.unmodifiable(hypotheses) {
    if (this.hypotheses.isEmpty) {
      throw ArgumentError('hypotheses must not be empty.');
    }
    if (this.hypotheses.where((h) => h.isPublished).length != 1) {
      throw ArgumentError('exactly one hypothesis must be published.');
    }
  }

  /// Resolves half/double-time ambiguity for a raw free-play BPM estimate.
  ///
  /// If [rawBpm] already lies in `[preferredTempoBandLowBpm,
  /// preferredTempoBandHighBpm]`, there is a single, unpenalised hypothesis.
  /// Otherwise it is shifted into the band by repeated ×2 / ÷2 steps; the
  /// shifted value publishes with its confidence multiplied by
  /// [halfDoubleTimeConfidencePenalty], and the original raw estimate is
  /// kept as a second, unpublished hypothesis.
  factory TempoHypothesisSet.resolve({
    required double rawBpm,
    required double rawConfidence,
  }) {
    if (!rawBpm.isFinite || rawBpm <= 0) {
      throw ArgumentError.value(rawBpm, 'rawBpm');
    }
    if (!rawConfidence.isFinite || rawConfidence < 0 || rawConfidence > 1) {
      throw ArgumentError.value(rawConfidence, 'rawConfidence');
    }
    var shifted = rawBpm;
    var didShift = false;
    while (shifted < preferredTempoBandLowBpm) {
      shifted *= 2;
      didShift = true;
    }
    while (shifted > preferredTempoBandHighBpm) {
      shifted /= 2;
      didShift = true;
    }
    if (!didShift) {
      return TempoHypothesisSet(
        hypotheses: <TempoHypothesis>[
          TempoHypothesis(
            bpm: rawBpm,
            confidence: rawConfidence,
            isPublished: true,
          ),
        ],
      );
    }
    return TempoHypothesisSet(
      hypotheses: <TempoHypothesis>[
        TempoHypothesis(
          bpm: rawBpm,
          confidence: rawConfidence,
          isPublished: false,
        ),
        TempoHypothesis(
          bpm: shifted,
          confidence: rawConfidence * halfDoubleTimeConfidencePenalty,
          isPublished: true,
        ),
      ],
    );
  }

  final List<TempoHypothesis> hypotheses;

  TempoHypothesis get published => hypotheses.firstWhere((h) => h.isPublished);
}
