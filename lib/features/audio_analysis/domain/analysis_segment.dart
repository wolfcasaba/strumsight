/// A deterministic time range in an [AnalysisTimeline].
sealed class AnalysisSegment {
  AnalysisSegment({
    required this.start,
    required this.end,
    required this.confidence,
  }) {
    if (start.isNegative || end.isNegative) {
      throw ArgumentError('Segment times cannot be negative.');
    }
    if (end < start) {
      throw ArgumentError('Segment end cannot precede its start.');
    }
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final Duration start;
  final Duration end;
  final double confidence;
}

/// Reproducible decoder provenance for a chord segment.
enum DecoderSource { dsp, ml, fused }

/// Explains how a chord segment confidence was derived.
enum ChordConfidenceSource { heuristic }

final class ChordSegment extends AnalysisSegment {
  ChordSegment({
    required super.start,
    required super.end,
    required super.confidence,
    required this.label,
    this.source = DecoderSource.dsp,
    this.confidenceSource = ChordConfidenceSource.heuristic,
    this.modelManifestId,
    String? id,
  }) : id = id ?? _defaultId(label, start, end) {
    if (label.trim().isEmpty) throw ArgumentError.value(label, 'label');
    if (this.id.trim().isEmpty) throw ArgumentError.value(id, 'id');
  }

  final String label;
  final String id;
  final DecoderSource source;
  final ChordConfidenceSource confidenceSource;
  final String? modelManifestId;

  static String _defaultId(String label, Duration start, Duration end) =>
      'chord-${start.inMicroseconds}-${end.inMicroseconds}-$label';
}

final class PitchSegment extends AnalysisSegment {
  PitchSegment({
    required super.start,
    required super.end,
    required super.confidence,
    required this.midiNote,
  }) {
    if (midiNote < 0 || midiNote > 127) {
      throw ArgumentError.value(midiNote, 'midiNote', 'must be in 0..127');
    }
  }

  final int midiNote;
}
