import 'dart:async';
import 'dart:math' as math;

import '../../../core/music/chord.dart';
import '../model/live_frame.dart';
import '../../../core/music/strum.dart';
import '../model/beat_slot.dart';
import 'strum_engine.dart';

/// A deterministic mock engine that loops a I–V–vi–IV progression with a
/// steady down/up strum pattern, so the Live UI is fully functional and
/// testable before the C++ DSP core exists.
///
/// [frameAt] is a pure function of elapsed time — it is what the unit tests
/// exercise; [frames] is just a timer that samples it.
class MockStrumEngine implements StrumEngine {
  MockStrumEngine({
    this.bpm = 96,
    this.tickInterval = const Duration(milliseconds: 60),
  });

  /// Simulated tempo.
  final double bpm;

  /// How often [frames] emits.
  final Duration tickInterval;

  static const _progression = [Chord('C'), Chord('G'), Chord('Am'), Chord('F')];

  // A common eighth-note pattern over "1 & 2 & 3 & 4 &"; null = no strum.
  static const _patternDirs = <StrumDirection?>[
    StrumDirection.down, // 1
    null, //               &
    StrumDirection.down, // 2
    StrumDirection.up, //  &
    null, //               3
    StrumDirection.up, //  &
    StrumDirection.down, // 4
    StrumDirection.up, //  &
  ];
  static const _labels = ['1', '&', '2', '&', '3', '&', '4', '&'];

  /// How long after an onset the mock "decides" the direction. The real
  /// pipeline confirms an ONSET ~70 ms before it has a direction verdict
  /// (r145), which is exactly the gap the Live strings band animates:
  /// [LiveFrame.onsetSeq] rings the strings, [LiveFrame.strumSeq] colours
  /// them. Reproducing the delay here is what makes demo/mock mode show the
  /// same two-stage behaviour as a live microphone.
  static const directionDelay = Duration(milliseconds: 70);

  /// Non-null entries of [_patternDirs] — how many strums one bar contains.
  static final int _strumsPerBar = _patternDirs
      .whereType<StrumDirection>()
      .length;

  StreamController<LiveFrame>? _controller;
  Timer? _timer;
  int _tick = 0;

  int get _barMicros => (4 * 60 / bpm * 1e6).round(); // 4 beats

  @override
  Stream<LiveFrame> get frames {
    _controller ??= StreamController<LiveFrame>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start() async {
    _controller ??= StreamController<LiveFrame>.broadcast();
    _timer?.cancel();
    _tick = 0;
    _timer = Timer.periodic(tickInterval, (_) {
      _tick++;
      _controller?.add(frameAt(tickInterval * _tick));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void setExpectedChord(String? label) {} // mock: no detector to hint

  @override
  void setDiagnosticsCapture(bool on) {} // mock: nothing to capture

  @override
  (List<double>, int) recentPcm() => (const <double>[], 0);

  @override
  Future<void> dispose() async {
    await stop();
    await _controller?.close();
    _controller = null;
  }

  /// Pure, deterministic frame for a given elapsed time — the unit of test.
  LiveFrame frameAt(Duration elapsed) {
    final barMicros = _barMicros;
    final elapsedMicros = elapsed.inMicroseconds;
    final barIndex = barMicros == 0 ? 0 : elapsedMicros ~/ barMicros;
    final posInBar = barMicros == 0
        ? 0.0
        : (elapsedMicros % barMicros) / barMicros; // 0..1

    final current = _progression[barIndex % _progression.length];
    final next = _progression[(barIndex + 1) % _progression.length];

    // Which eighth-note slot (0..7) are we in?
    final slot = (posInBar * 8).floor().clamp(0, 7);

    // Build the bar's 8 slots. Up-strokes are modelled as slightly less
    // confident than down-strokes — mirroring the real detector's weak point.
    final bar = <BeatSlot>[];
    for (var i = 0; i < 8; i++) {
      final dir = _patternDirs[i];
      Strum? s;
      if (dir != null) {
        final base = dir == StrumDirection.up ? 0.72 : 0.90;
        final wobble = 0.06 * math.sin((barIndex * 8 + i) * 1.3);
        s = Strum(
          direction: dir,
          confidence: (base + wobble).clamp(0.0, 1.0).toDouble(),
          accent: i == 0, // accent the downbeat
        );
      }
      bar.add(BeatSlot(label: _labels[i], isDownbeat: i.isEven, strum: s));
    }

    // Latest strum = the most recent slot at/before the current one.
    Strum? latest;
    for (var i = slot; i >= 0; i--) {
      if (bar[i].strum != null) {
        latest = bar[i].strum;
        break;
      }
    }

    // Simulated mic level: a gentle pulse that spikes on strums.
    final onStrum = bar[slot].strum != null;
    final level =
        (0.25 +
                0.4 * (0.5 + 0.5 * math.sin(posInBar * 2 * math.pi)) +
                (onStrum ? 0.25 : 0.0))
            .clamp(0.0, 1.0)
            .toDouble();

    return LiveFrame(
      current: current,
      next: next,
      latestStrum: latest,
      bar: bar,
      bpm: bpm,
      inputLevel: level,
      tuningHz: 440,
      listening: true,
      // Two-stage feedback: the hit is counted the instant it lands, the
      // verdict one [directionDelay] later. At the default 60 ms tick the two
      // therefore bump on DIFFERENT emitted frames, so the Live strings band
      // rings neutral first and only then picks up the direction colour.
      onsetSeq: _strumsStartedBy(elapsedMicros),
      strumSeq: _strumsStartedBy(elapsedMicros - directionDelay.inMicroseconds),
    );
  }

  /// How many pattern strums have been STRUCK at or before [micros] since the
  /// session start — a monotonic onset counter. Evaluating the same function
  /// one [directionDelay] earlier yields the verdict counter, which is why
  /// `onsetSeq` always runs exactly one classification delay ahead of
  /// `strumSeq` without either ever going backwards.
  int _strumsStartedBy(int micros) {
    final barMicros = _barMicros;
    if (micros < 0 || barMicros == 0) return 0;
    final slots = _patternDirs.length;
    var count = (micros ~/ barMicros) * _strumsPerBar;
    final rest = micros % barMicros;
    for (var i = 0; i < slots; i++) {
      if (_patternDirs[i] == null) continue;
      if (i * barMicros ~/ slots <= rest) count++;
    }
    return count;
  }
}
