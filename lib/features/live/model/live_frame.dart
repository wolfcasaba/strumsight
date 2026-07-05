import 'package:flutter/foundation.dart';

import 'chord.dart';
import 'strum.dart';

/// An immutable snapshot the engine emits many times per second, driving the
/// Live "mirror" screen.
@immutable
class LiveFrame {
  const LiveFrame({
    required this.current,
    required this.next,
    required this.latestStrum,
    required this.bar,
    required this.bpm,
    required this.inputLevel,
    required this.tuningHz,
    required this.listening,
  });

  /// Currently sounding chord (null before the first detection).
  final Chord? current;

  /// The upcoming chord, shown ghosted (null if unknown).
  final Chord? next;

  /// Most recent strum (drives the big arrow), null if none yet.
  final Strum? latestStrum;

  /// The last bar's rolling beat counter — 8 slots for 4/4 eighth notes.
  final List<BeatSlot> bar;

  /// Detected tempo in BPM.
  final double bpm;

  /// Microphone input level, 0..1 (drives the level meter).
  final double inputLevel;

  /// Tuning reference in Hz (A4), default 440.
  final double tuningHz;

  /// Whether the engine is actively listening.
  final bool listening;

  /// Confidence of the latest strum, or 0 if none.
  double get confidence => latestStrum?.confidence ?? 0;

  /// A neutral idle frame (nothing detected yet).
  static const empty = LiveFrame(
    current: null,
    next: null,
    latestStrum: null,
    bar: <BeatSlot>[],
    bpm: 0,
    inputLevel: 0,
    tuningHz: 440,
    listening: false,
  );
}
