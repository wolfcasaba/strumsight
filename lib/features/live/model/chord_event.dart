import 'package:flutter/foundation.dart';

import 'chord.dart';
import 'strum.dart';

/// One recognised chord in the Live timeline's rolling history.
///
/// Stored at **concert pitch** — the view transposes by `-capo` at render
/// time (exactly as the rest of the Live screen does). A [ChordEvent] is
/// created when a new/changed chord is detected and later updated in place
/// (via [copyWith]) when a strum lands on the same chord, so its [direction]
/// and [confidence] reflect the most recent stroke on that chord.
@immutable
class ChordEvent {
  const ChordEvent({
    required this.chord,
    this.direction,
    required this.confidence,
    required this.seq,
    required this.timeSec,
  });

  /// The recognised chord (concert pitch).
  final Chord chord;

  /// The strum direction played on this chord, or null until a strum lands.
  final StrumDirection? direction;

  /// Detector confidence, 0..1.
  final double confidence;

  /// Monotonic id, unique per card — lets the view key cards stably across
  /// the recede/enter animations even when the same label recurs (A→B→A).
  final int seq;

  /// Engine time of first detection in seconds (−1 when unknown).
  final double timeSec;

  /// Copy with the strum-driven fields overridden (chord/seq/timeSec are
  /// identity and never change once the card exists).
  ChordEvent copyWith({StrumDirection? direction, double? confidence}) {
    return ChordEvent(
      chord: chord,
      direction: direction ?? this.direction,
      confidence: confidence ?? this.confidence,
      seq: seq,
      timeSec: timeSec,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChordEvent &&
      other.chord == chord &&
      other.direction == direction &&
      other.confidence == confidence &&
      other.seq == seq &&
      other.timeSec == timeSec;

  @override
  int get hashCode => Object.hash(chord, direction, confidence, seq, timeSec);

  @override
  String toString() =>
      'ChordEvent(${chord.label}, dir=$direction, conf=$confidence, '
      'seq=$seq, t=$timeSec)';
}
