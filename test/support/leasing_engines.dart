import 'dart:async';

import 'package:strumsight/core/audio/mic_capture.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/live/engine/strum_engine.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/tuner/engine/tuner_engine.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';

/// Engine doubles that own a REAL [MicCapture], i.e. the real exclusive
/// microphone lease (E01-R09 §9.2).
///
/// `FakeStrumEngine`/`FakeTunerEngine` only count start/stop calls, so a test
/// built on them can prove "Pause was invoked" but never "the microphone was
/// actually free when the next owner asked for it" — which is the whole
/// question when one screen is pushed on top of another. These doubles keep
/// exactly that half of the real engines (the lease plus the start/stop
/// serialisation) and drop the DSP isolate, whose spawn future never completes
/// under `testWidgets`' fake clock.

/// The lease + lifecycle half of `RealStrumEngine`/`RealTunerEngine`.
class LeasedSession {
  LeasedSession(this._mic);

  final MicCapture _mic;

  /// THE lifecycle queue, the same shape the real engines run: one strict-FIFO
  /// future chain, and the ONLY thing outside it is the §9.3 cancel signal in
  /// [stop], which opens and closes nothing by itself. A double that stopped
  /// the mic eagerly and queued nothing but the teardown would keep passing a
  /// test the real engine fails, because a start queued in between would
  /// consume the stop and leave the microphone open (round-2 review).
  Future<void> _lifecycle = Future<void>.value();

  /// Every failure a start attempt came back with. `audioSessionBusy` here
  /// means the previous owner had not handed the microphone back yet.
  final List<AppFailure> failures = [];

  /// Anything a queued step threw — the real engines log these and carry on.
  final List<Object> lifecycleErrors = [];

  int startCalls = 0;
  int stopCalls = 0;

  Future<void> start() {
    startCalls++;
    return _enqueue(() async {
      final result = await _mic.start((_) {}, onRevoke: stop);
      if (result case Failure<int>(:final error)) failures.add(error);
    });
  }

  Future<void> stop() {
    stopCalls++;
    // Exactly the real engines' shape: the §9.3 cancel SIGNAL is fired outside
    // the queue (`MicCapture.stop` raises `_stopRequested` synchronously, so a
    // start parked on the permission dialog unwinds itself)…
    final signalled = _signalStop();
    return _enqueue(() async {
      // …and the queued step awaits THAT round-trip and then calls the
      // idempotent `_mic.stop()` again, which is what stops a microphone a
      // start queued in between has since opened. Both halves matter: a double
      // with only one of them measures a contract the engines do not have.
      await signalled;
      await _mic.stop();
    });
  }

  /// The cancel signal. Its failure is recorded, never swallowed — the engines
  /// log theirs in the same turn for the same reason: an un-awaited `stop()`
  /// must not turn a throwing platform teardown into an unhandled async error.
  Future<void> _signalStop() =>
      _mic.stop().catchError((Object error) => lifecycleErrors.add(error));

  Future<void> _enqueue(Future<void> Function() step) {
    final next = _lifecycle.then((_) async {
      try {
        await step();
      } catch (error) {
        // Mirrors the engines' `_enqueue`: a failed step must not poison the
        // chain, nor escape as an unhandled async error to an un-awaited stop.
        lifecycleErrors.add(error);
      }
    });
    _lifecycle = next;
    return next;
  }
}

/// A [StrumEngine] that leases the microphone for real, without a DSP isolate.
class LeasingStrumEngine implements StrumEngine {
  LeasingStrumEngine(MicCapture mic) : session = LeasedSession(mic);

  final LeasedSession session;
  final _controller = StreamController<LiveFrame>.broadcast();

  List<AppFailure> get failures => session.failures;
  int get startCalls => session.startCalls;
  int get stopCalls => session.stopCalls;

  @override
  Stream<LiveFrame> get frames => _controller.stream;

  @override
  Future<void> start() => session.start();

  @override
  Future<void> stop() => session.stop();

  @override
  Future<void> dispose() async {
    await session.stop();
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  void setExpectedChord(String? label) {}

  @override
  void setDiagnosticsCapture(bool on) {}

  @override
  (List<double>, int) recentPcm() => (const <double>[], 0);
}

/// A [TunerEngine] that leases the microphone for real, without a DSP isolate.
class LeasingTunerEngine implements TunerEngine {
  LeasingTunerEngine(MicCapture mic) : session = LeasedSession(mic);

  final LeasedSession session;
  final _controller = StreamController<TunerReading>.broadcast();

  List<AppFailure> get failures => session.failures;
  int get startCalls => session.startCalls;
  int get stopCalls => session.stopCalls;

  @override
  Stream<TunerReading> get readings => _controller.stream;

  @override
  Future<void> start({int a4 = 440}) => session.start();

  @override
  Future<void> stop() => session.stop();

  @override
  Future<void> dispose() async {
    await session.stop();
    if (!_controller.isClosed) await _controller.close();
  }
}
