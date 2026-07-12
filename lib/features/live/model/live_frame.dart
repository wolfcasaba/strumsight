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
    this.strumSeq = 0,
    this.latestStrumTime = -1,
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

  /// Monotonically increasing id, bumped once per NEWLY detected strum. Lets a
  /// consumer (e.g. the play-along scorer) detect discrete strums even when two
  /// consecutive strokes share a direction — [latestStrum] alone can't.
  final int strumSeq;

  /// The [latestStrum]'s attack instant on the engine's own sample clock
  /// (seconds from session start; −1 while none). This is the r144-corrected
  /// StrumEvent time — batch consumers (Analyze) must use THIS rather than
  /// their feed position: frames arrive on a ~66 ms cadence plus a ~70 ms
  /// classification delay, so "when the frame arrived" runs 85–165 ms late
  /// with ±40 ms jitter (measured, r145).
  final double latestStrumTime;

  /// Confidence of the latest strum, or 0 if none.
  double get confidence => latestStrum?.confidence ?? 0;

  /// Copy with selected fields overridden (used to reflect the paused state).
  /// Note: nullable fields can only be kept, not cleared, which is all the UI
  /// needs here.
  LiveFrame copyWith({
    List<BeatSlot>? bar,
    double? bpm,
    double? inputLevel,
    double? tuningHz,
    bool? listening,
  }) {
    return LiveFrame(
      current: current,
      next: next,
      latestStrum: latestStrum,
      bar: bar ?? this.bar,
      bpm: bpm ?? this.bpm,
      inputLevel: inputLevel ?? this.inputLevel,
      tuningHz: tuningHz ?? this.tuningHz,
      listening: listening ?? this.listening,
      strumSeq: strumSeq,
      latestStrumTime: latestStrumTime,
    );
  }

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
