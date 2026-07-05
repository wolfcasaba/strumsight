import 'dart:async';
import 'dart:math' as math;

import '../model/tuner_reading.dart';
import 'tuner_engine.dart';

/// A deterministic mock tuner: cycles through the six open-string notes, with
/// the cents offset drifting toward zero so the in-tune state is reachable.
class MockTunerEngine implements TunerEngine {
  MockTunerEngine({this.tickInterval = const Duration(milliseconds: 80)});

  final Duration tickInterval;

  static const _strings = ['E', 'A', 'D', 'G', 'B', 'E'];
  static const _freqs = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];

  StreamController<TunerReading>? _controller;
  Timer? _timer;
  int _tick = 0;

  @override
  Stream<TunerReading> get readings {
    _controller ??= StreamController<TunerReading>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start() async {
    _controller ??= StreamController<TunerReading>.broadcast();
    _timer?.cancel();
    _tick = 0;
    _timer = Timer.periodic(tickInterval, (_) {
      _tick++;
      _controller?.add(readingAt(tickInterval * _tick));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller?.close();
    _controller = null;
  }

  /// Pure, deterministic reading for a given elapsed time — the unit of test.
  TunerReading readingAt(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    final idx = (ms ~/ 3000) % _strings.length; // change string every 3 s
    // Damped drift toward 0 cents, clamped to the ±50 display range.
    final phase = (ms % 3000) / 3000; // 0..1 within a string
    final cents =
        (30 * math.sin(ms / 500) * (1 - phase)).clamp(-50.0, 50.0).toDouble();
    return TunerReading(
      note: _strings[idx],
      cents: cents,
      frequencyHz: _freqs[idx],
    );
  }
}
