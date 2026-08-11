/// A point or region observed during analysis (SDD Ch7 §9.6).
sealed class AnalysisEvent {
  AnalysisEvent({
    required this.id,
    required this.time,
    required this.confidence,
    this.sampleIndex,
  }) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
    if (sampleIndex != null && sampleIndex! < 0) {
      throw ArgumentError.value(sampleIndex, 'sampleIndex');
    }
  }

  final String id;
  final Duration time;
  final double confidence;
  final int? sampleIndex;
}

final class OnsetEvent extends AnalysisEvent {
  OnsetEvent({
    required super.id,
    required super.time,
    required super.confidence,
    super.sampleIndex,
  });
}

enum StrumDirection { down, up, unknown }

final class StrumEvent extends AnalysisEvent {
  StrumEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required this.direction,
    super.sampleIndex,
  });
  final StrumDirection direction;
}

final class ChordChangeEvent extends AnalysisEvent {
  ChordChangeEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required this.label,
    super.sampleIndex,
  }) {
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label');
    }
  }
  final String label;
}

final class BeatEvent extends AnalysisEvent {
  BeatEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required this.beatIndex,
    super.sampleIndex,
  }) {
    if (beatIndex < 0) throw ArgumentError.value(beatIndex, 'beatIndex');
  }
  final int beatIndex;
}

final class NoteOnsetEvent extends AnalysisEvent {
  NoteOnsetEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required this.midiNote,
    super.sampleIndex,
  }) {
    if (midiNote < 0 || midiNote > 127) {
      throw ArgumentError.value(midiNote, 'midiNote');
    }
  }
  final int midiNote;
}

sealed class AnalysisRegionEvent extends AnalysisEvent {
  AnalysisRegionEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required this.end,
    super.sampleIndex,
  }) {
    if (end < time) throw ArgumentError('Region end cannot precede its start.');
  }
  final Duration end;
}

final class SilenceRegionEvent extends AnalysisRegionEvent {
  SilenceRegionEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required super.end,
    super.sampleIndex,
  });
}

final class ClippingRegionEvent extends AnalysisRegionEvent {
  ClippingRegionEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required super.end,
    super.sampleIndex,
  });
}
