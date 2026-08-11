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

final class ChordSegment extends AnalysisSegment {
  ChordSegment({
    required super.start,
    required super.end,
    required super.confidence,
    required this.label,
  }) {
    if (label.trim().isEmpty) throw ArgumentError.value(label, 'label');
  }

  final String label;
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
