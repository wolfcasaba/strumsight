import 'dart:async';

import 'package:music_theory/features/live/engine/strum_engine.dart';
import 'package:music_theory/features/live/model/live_frame.dart';
import 'package:music_theory/features/tuner/engine/tuner_engine.dart';
import 'package:music_theory/features/tuner/model/tuner_reading.dart';

/// A timer-free StrumEngine for widget tests: emit frames on demand so
/// `pumpAndSettle` never hangs on a periodic timer.
class FakeStrumEngine implements StrumEngine {
  final _controller = StreamController<LiveFrame>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<LiveFrame> get frames => _controller.stream;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(LiveFrame frame) => _controller.add(frame);

  /// Simulate the mic failing to start (busy / platform error).
  void emitError(Object error) => _controller.addError(error);
}

/// A timer-free TunerEngine for widget tests (mirrors [FakeStrumEngine]).
class FakeTunerEngine implements TunerEngine {
  final _controller = StreamController<TunerReading>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<TunerReading> get readings => _controller.stream;

  @override
  Future<void> start({int a4 = 440}) async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(TunerReading reading) => _controller.add(reading);

  /// Simulate the mic failing to start (busy / platform error).
  void emitError(Object error) => _controller.addError(error);
}
