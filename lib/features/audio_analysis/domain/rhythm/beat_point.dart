/// Provenance of a beat-grid point (SDD Ch7 §14.1, §14.5).
enum BeatSource { estimated, target }

/// One beat in a [BeatGrid], with time and confidence (SDD Ch7 §14.1).
final class BeatPoint {
  BeatPoint({
    required this.index,
    required this.time,
    required this.confidence,
    required this.source,
  }) {
    if (index < 0) throw ArgumentError.value(index, 'index');
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final int index;
  final Duration time;
  final double confidence;
  final BeatSource source;
}

/// One bar boundary in a [BeatGrid] (SDD Ch7 §14.1).
final class BarPoint {
  BarPoint({
    required this.index,
    required this.time,
    required this.beatsPerBar,
  }) {
    if (index < 0) throw ArgumentError.value(index, 'index');
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (beatsPerBar <= 0) {
      throw ArgumentError.value(beatsPerBar, 'beatsPerBar');
    }
  }

  final int index;
  final Duration time;
  final int beatsPerBar;
}
