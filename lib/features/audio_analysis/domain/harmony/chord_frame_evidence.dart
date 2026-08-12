import '../analysis_segment.dart';

/// Whether frame evidence is measured or conservatively derived from V1 spans.
enum EvidenceCompleteness { derived, complete }

/// One ranked chord candidate for a decoder frame.
final class ChordLabelCandidate {
  ChordLabelCandidate({required this.label, required this.confidence}) {
    if (label.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final String label;
  final double confidence;
}

/// Immutable decoder evidence at one chord decision boundary.
///
/// [derived] evidence deliberately has no ranked probabilities: R11 can only
/// obtain it from finished V1 spans and must not manufacture top-k values.
final class ChordFrameEvidence {
  ChordFrameEvidence._({
    required this.time,
    required this.topLabel,
    required this.topConfidence,
    required List<ChordLabelCandidate> topK,
    required this.noChordProbability,
    required this.tonalness,
    required this.source,
    required this.evidenceCompleteness,
    this.modelManifestId,
  }) : topK = List<ChordLabelCandidate>.unmodifiable(topK) {
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    _validateProbability(topConfidence, 'topConfidence');
    _validateProbability(noChordProbability, 'noChordProbability');
    _validateProbability(tonalness, 'tonalness');
    if (topLabel != null && topLabel!.trim().isEmpty) {
      throw ArgumentError.value(topLabel, 'topLabel');
    }
    if (evidenceCompleteness == EvidenceCompleteness.derived &&
        (this.topK.isNotEmpty ||
            topConfidence != null ||
            noChordProbability != null)) {
      throw ArgumentError(
        'Derived evidence cannot claim ranked or no-chord probabilities.',
      );
    }
  }

  factory ChordFrameEvidence.derived({
    required Duration time,
    required String? topLabel,
    required DecoderSource source,
    double? tonalness,
    String? modelManifestId,
  }) => ChordFrameEvidence._(
    time: time,
    topLabel: topLabel,
    topConfidence: null,
    topK: const <ChordLabelCandidate>[],
    noChordProbability: null,
    tonalness: tonalness,
    source: source,
    evidenceCompleteness: EvidenceCompleteness.derived,
    modelManifestId: modelManifestId,
  );

  factory ChordFrameEvidence.complete({
    required Duration time,
    required String? topLabel,
    required double? topConfidence,
    List<ChordLabelCandidate> topK = const <ChordLabelCandidate>[],
    required double? noChordProbability,
    required double? tonalness,
    required DecoderSource source,
    String? modelManifestId,
  }) => ChordFrameEvidence._(
    time: time,
    topLabel: topLabel,
    topConfidence: topConfidence,
    topK: topK,
    noChordProbability: noChordProbability,
    tonalness: tonalness,
    source: source,
    evidenceCompleteness: EvidenceCompleteness.complete,
    modelManifestId: modelManifestId,
  );

  final Duration time;
  final String? topLabel;
  final double? topConfidence;
  final List<ChordLabelCandidate> topK;
  final double? noChordProbability;
  final double? tonalness;
  final DecoderSource source;
  final EvidenceCompleteness evidenceCompleteness;
  final String? modelManifestId;

  static void _validateProbability(double? value, String name) {
    if (value != null && (!value.isFinite || value < 0 || value > 1)) {
      throw ArgumentError.value(value, name, 'must be in [0, 1]');
    }
  }
}
