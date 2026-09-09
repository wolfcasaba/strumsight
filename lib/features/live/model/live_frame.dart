import 'package:flutter/foundation.dart';

import '../../../core/music/chord.dart';
import '../../../core/music/strum.dart';
import '../domain/recognition/recognition_decision.dart';
import 'beat_slot.dart';

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
    this.onsetTimeSec = -1,
    this.engineTimeSec = -1,
    this.chordDecision,
    this.chordRejectReason,
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

  /// The newest detected ONSET's attack instant on the same engine sample
  /// clock (−1 while none, and for producers that don't detect onsets).
  ///
  /// Deliberately NOT the same as [latestStrumTime] (E14-R28, ADR 0545 D2):
  /// that one only advances for a strum whose DIRECTION was confirmed, so an
  /// onset the direction model abstained on leaves it untouched. A chord
  /// change on such a strum is still a chord change on a strum, and the
  /// onset-alignment gate in `RecognitionStabilizer` must see it — hence a
  /// separate, classification-independent timestamp.
  final double onsetTimeSec;

  /// This frame's EMIT instant on the same engine sample clock (−1 when the
  /// producer doesn't track it, e.g. mocks). Together with [latestStrumTime]
  /// a consumer can subtract the classify-delay + emit-cadence lag — the
  /// cadence part is 0–66 ms of JITTER a constant latency calibration cannot
  /// absorb (r147; the live twin of the r145 Analyze fix).
  final double engineTimeSec;

  /// The typed chord verdict (ADR 0516 D1/D5) — `null` until a producer
  /// fills it in (the `LiveFrameAdapter` boundary keeps it `null` today,
  /// D7). Carried SEPARATELY from [confidence] (the STRUM confidence, ADR
  /// 0505): the two never share a source.
  final RecognitionDecision? chordDecision;

  /// Why [chordDecision] rejected or stayed uncertain, or `null` when
  /// [chordDecision] is `confirmed`/`null` (ADR 0516 D1/D5).
  final RecognitionRejectReason? chordRejectReason;

  /// Confidence of the latest strum, or 0 if none. Deliberately the RAW
  /// [latestStrum] (other producers — the onboarding first-win engine, the
  /// timeline fold — consume this as the engine's own number); the screens
  /// read [displayStrum] when they need the freshness/signal gate too.
  double get confidence => latestStrum?.confidence ?? 0;

  /// How long a strum indicator may stay on screen without a fresh detection
  /// (seconds) — the same window `LivePipeline._buildFrame` uses to drop its
  /// own `_latestStrum`, applied again here so an indicator expires even when
  /// no further frame arrives to run the producer-side drop.
  static const double strumHoldSec = 2.0;

  /// True when this frame's chord verdict was rejected because the SIGNAL
  /// itself is unusable — the six `signal*` reasons of ADR 0535 D1.
  ///
  /// While this holds, the screen may not present tempo or strum direction as
  /// measured readings: the app has just stated it cannot tell what it is
  /// hearing, and a confident arrow or BPM next to that statement is exactly
  /// the "weak confidence rendered as a confident claim" AGENTS.md §5 forbids.
  bool get hasUnusableSignal => switch (chordRejectReason) {
    RecognitionRejectReason.signalTooQuiet ||
    RecognitionRejectReason.signalTooLoud ||
    RecognitionRejectReason.signalClipping ||
    RecognitionRejectReason.signalTooNoisy ||
    RecognitionRejectReason.signalSpeechLike ||
    RecognitionRejectReason.signalUnstable => true,
    RecognitionRejectReason.lowConfidence ||
    RecognitionRejectReason.unstable ||
    RecognitionRejectReason.noChord ||
    RecognitionRejectReason.modelUnavailable ||
    RecognitionRejectReason.timeout => false,
    null => false,
  };

  /// True once [latestStrum] is older than [strumHoldSec] on the engine's own
  /// clock. Both timestamps are −1 for producers that don't track a clock
  /// (mocks), in which case nothing can be aged and this stays false.
  bool get strumExpired =>
      latestStrum != null &&
      engineTimeSec >= 0 &&
      latestStrumTime >= 0 &&
      engineTimeSec - latestStrumTime > strumHoldSec;

  /// The strum a screen may actually SHOW: [latestStrum] while it is still
  /// fresh and the signal is usable, `null` otherwise. A stale arrow left up
  /// during silence — or an arrow shown while the app says the signal is
  /// unusable — is a claim the engine is not making.
  Strum? get displayStrum =>
      (strumExpired || hasUnusableSignal) ? null : latestStrum;

  /// True when [bpm] is a real measurement. Zero BPM is the ABSENCE of a
  /// tempo, not a tempo of zero, and an unusable signal cannot have measured
  /// one either — the screen states that instead of printing "0 BPM".
  bool get hasMeasuredTempo => bpm > 0 && !hasUnusableSignal;

  /// The beat grid with expired strum marks removed. The bar's newest mark IS
  /// [latestStrum], so once that has expired every remaining mark is at least
  /// as old — they all go together.
  List<BeatSlot> get displayBar => displayStrum != null
      ? bar
      : [
          for (final slot in bar)
            BeatSlot(label: slot.label, isDownbeat: slot.isDownbeat),
        ];

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
      onsetTimeSec: onsetTimeSec,
      engineTimeSec: engineTimeSec,
      chordDecision: chordDecision,
      chordRejectReason: chordRejectReason,
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
