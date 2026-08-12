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
    this.attackStrength,
    this.localRms,
    this.confidenceSource = EventConfidenceSources.heuristic,
    this.fallbackReason,
  }) {
    _validateNonNegativeFinite(attackStrength, 'attackStrength');
    _validateNonNegativeFinite(localRms, 'localRms');
    _validateConfidenceSource(confidenceSource);
    _validateFallbackReason(fallbackReason);
  }

  /// Absolute peak in the builder's `[t, t + 20 ms]` audio window.
  final double? attackStrength;

  /// RMS in the builder's `[t - 5 ms, t + 45 ms]` audio window.
  final double? localRms;

  /// Provenance of this event's uncalibrated confidence value.
  final String confidenceSource;

  /// Why the producing stage used a fallback, when applicable.
  final String? fallbackReason;
}

enum StrumDirection { down, up, unknown }

final class StrumEvent extends AnalysisEvent {
  StrumEvent({
    required super.id,
    required super.time,
    required super.confidence,
    required this.direction,
    super.sampleIndex,
    this.directionConfidence,
    this.onsetEventId,
    this.attackStrength,
    this.localRms,
    this.confidenceSource = EventConfidenceSources.heuristic,
    this.fallbackReason,
  }) {
    _validateUnitInterval(directionConfidence, 'directionConfidence');
    _validateNonNegativeFinite(attackStrength, 'attackStrength');
    _validateNonNegativeFinite(localRms, 'localRms');
    if (onsetEventId != null && onsetEventId!.trim().isEmpty) {
      throw ArgumentError.value(onsetEventId, 'onsetEventId');
    }
    _validateConfidenceSource(confidenceSource);
    _validateFallbackReason(fallbackReason);
  }

  final StrumDirection direction;

  /// Confidence in [direction], independent from the onset confidence.
  final double? directionConfidence;

  /// ID of the onset evidence paired with this strum, when available.
  final String? onsetEventId;

  /// Absolute peak in the builder's `[t, t + 20 ms]` audio window.
  final double? attackStrength;

  /// RMS in the builder's `[t - 5 ms, t + 45 ms]` audio window.
  final double? localRms;

  /// Provenance of this event's uncalibrated confidence value.
  final String confidenceSource;

  /// Why the producing stage used a fallback, when applicable.
  final String? fallbackReason;
}

/// The closed provenance vocabulary for uncalibrated event confidences.
abstract final class EventConfidenceSources {
  static const String heuristic = 'heuristic';
  static const String crnn = 'crnn';
  static const String calibrated = 'calibrated';

  static bool isKnown(String value) => switch (value) {
    heuristic || crnn || calibrated => true,
    _ => false,
  };
}

void _validateUnitInterval(double? value, String name) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    throw ArgumentError.value(value, name, 'must be finite and in [0, 1]');
  }
}

void _validateNonNegativeFinite(double? value, String name) {
  if (value != null && (!value.isFinite || value < 0)) {
    throw ArgumentError.value(value, name, 'must be finite and non-negative');
  }
}

void _validateConfidenceSource(String value) {
  if (!EventConfidenceSources.isKnown(value)) {
    throw ArgumentError.value(value, 'confidenceSource');
  }
}

void _validateFallbackReason(String? value) {
  if (value != null && value.trim().isEmpty) {
    throw ArgumentError.value(value, 'fallbackReason');
  }
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
