import 'dart:async';
import 'dart:isolate';

import '../../../core/audio/mic_capture.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/audio/dsp/sliding_framer.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/debug_app_logger.dart';
import '../model/tuner_reading.dart';
import 'dsp/tuner_analyzer.dart';
import 'tuner_engine.dart';

/// The REAL tuner: microphone → DSP isolate (YIN) → TunerReadings.
class RealTunerEngine implements TunerEngine {
  /// [mic] carries the exclusive-session lease (E01-R09).
  ///
  /// [logger] defaults to the app's OWN sink, not to [NoopAppLogger]: a
  /// [DebugAppLogger] prints redacted lines in debug builds and disables itself
  /// in release (`enabled ?? kDebugMode`), which is exactly what
  /// `createDefaultAppLogger` means by "the app's logger". A failing lifecycle
  /// step therefore leaves a trace even though `tunerEngineProvider` does not
  /// inject `appLoggerProvider` yet — a silent default would make the handling
  /// below an empty catch in every build (§10).
  RealTunerEngine({required this._mic, AppLogger? logger})
    : _logger = logger ?? DebugAppLogger();

  StreamController<TunerReading>? _controller;
  final MicCapture _mic;
  final AppLogger _logger;
  Isolate? _isolate;
  SendPort? _toDsp;
  ReceivePort? _fromDsp;
  final List<List<double>> _pendingChunks = [];
  bool _running = false;

  /// THE lifecycle queue: ONE strict-FIFO future chain through which every
  /// [start] and [stop] runs. `tunerReadingProvider` watches
  /// `tuningReferenceProvider`, so an A4 change disposes the provider — firing
  /// an UN-AWAITED `stop()` — and calls `start()` on the SAME engine in the
  /// same turn.
  ///
  /// NOTHING touches the microphone, the ports or the isolate outside this
  /// chain, and that is the whole invariant:
  ///
  /// * a start queued behind a stop asks the coordinator for the session only
  ///   after the previous lease was actually handed back — no audioSessionBusy
  ///   on a restart;
  /// * a stop queued behind a start always stops the microphone THAT start
  ///   opened, so a mic can never outlive the stop that followed it (§5 /
  ///   E01-R09 §9.4: backgrounding must leave nothing recording);
  /// * a stale stop can only tear down the ports/isolate it snapshotted, never
  ///   the ones a later start created.
  ///
  /// The ONE thing that happens outside the chain is the cancel *signal* in
  /// [stop] — see [_signalStop]. It opens and closes nothing by itself; the
  /// queued step still calls the idempotent `MicCapture.stop()`, so the
  /// invariants above hold unchanged.
  Future<void> _lifecycle = Future<void>.value();

  @override
  Stream<TunerReading> get readings {
    _controller ??= StreamController<TunerReading>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start({int a4 = 440}) => _enqueue('start', () => _start(a4: a4));

  /// Appends [step] to [_lifecycle] and returns THAT step's future, so a
  /// caller who awaits `start()`/`stop()` awaits its own operation, not the
  /// tail of the queue.
  ///
  /// The step's failures are handled here, never outside: a throwing platform
  /// teardown must neither poison the chain (every later start/stop would
  /// inherit the error) nor surface as an unhandled async error for the
  /// callers that deliberately drop the future (`dispose`, `ref.onDispose`,
  /// the Live screen's background hook).
  Future<void> _enqueue(String op, Future<void> Function() step) {
    final next = _lifecycle.then((_) async {
      try {
        await step();
      } catch (error, stackTrace) {
        _logger.error(
          'tuner.engine.lifecycle_failed',
          error: error,
          stackTrace: stackTrace,
          fields: {'op': op},
        );
      }
    });
    _lifecycle = next;
    return next;
  }

  Future<void> _start({int a4 = 440}) async {
    if (_running) return;
    _controller ??= StreamController<TunerReading>.broadcast();

    // Set BEFORE the first await (§9.3 start/start race).
    _running = true;

    final started = await _mic.start((chunk) {
      final port = _toDsp;
      if (port != null) {
        port.send(chunk);
      } else if (_pendingChunks.length < 64) {
        _pendingChunks.add(chunk);
      }
    }, onRevoke: stop);
    if (started case Failure<int>(:final error)) {
      _running = false;
      switch (error) {
        case PermissionFailure():
          _controller?.add(TunerReading.silent);
        case CancelledFailure():
          break; // the screen left during the handshake — nothing is running
        default:
          final controller = _controller;
          if (controller != null && !controller.isClosed) {
            controller.addError(error, error.stackTrace ?? StackTrace.current);
          }
      }
      return;
    }
    final actualRate = (started as Success<int>).value;

    try {
      _fromDsp = ReceivePort();
      _isolate = await Isolate.spawn(
        _tunerEntry,
        _TunerInit(
          sendPort: _fromDsp!.sendPort,
          sampleRate: actualRate,
          a4: a4,
        ),
      );
      _fromDsp!.listen((message) {
        if (message is SendPort) {
          _toDsp = message;
          for (final c in _pendingChunks) {
            _toDsp!.send(c);
          }
          _pendingChunks.clear();
        } else if (message is TunerReading) {
          _controller?.add(message);
        }
      });
    } catch (e, st) {
      // Mic unavailable (busy, revoked mid-capture, platform channel error):
      // surface it on the stream so the Tuner screen shows an honest error —
      // never a silent idle. Leave the engine stopped so Retry can restart.
      // Mirrors RealStrumEngine (round 13).
      // The private teardown, not the queued stop(): this already runs INSIDE
      // the lifecycle chain, so queuing behind itself would deadlock.
      await _stop();
      final controller = _controller;
      if (controller != null && !controller.isClosed) {
        controller.addError(e, st);
      }
    }
  }

  /// Stops the engine and hands the microphone lease back.
  ///
  /// The returned future completes only once the platform capture is closed
  /// and the lease is released, so anything handing the microphone to another
  /// owner must await it. Callers that must not block (`dispose`,
  /// `ref.onDispose`) may drop it: the work still runs, in order.
  ///
  /// THE INVARIANT: a stop enqueued after a start always stops the microphone
  /// THAT start opened. The eager cancel signal fired outside the queue
  /// ([_signalStop]) cannot break it, because it opens and closes nothing by
  /// itself — whatever a start queued in between opens is closed by the
  /// idempotent `_mic.stop()` inside [_stop], which runs in THIS step, behind
  /// that start. The signal only unwinds a start parked on the dialog (§9.3).
  @override
  Future<void> stop() {
    final signalled = _signalStop();
    return _enqueue('stop', () => _stop(signalled));
  }

  /// The §9.3 cancel SIGNAL — the only thing this engine does outside
  /// [_lifecycle], and deliberately so.
  ///
  /// `MicCapture.stop()` raises its `_stopRequested` flag SYNCHRONOUSLY, and
  /// that flag is the only thing that makes a start parked on the permission
  /// dialog unwind itself instead of opening a microphone nobody is watching.
  /// It is not an edge case: on Android the runtime permission dialog pauses
  /// the activity, so "the screen is gone / the app is backgrounded while the
  /// dialog is up" is the ordinary first-run path, and a mic opened after the
  /// user answers would be opened with the screen already gone.
  ///
  /// It is ONLY a signal. `MicCapture.start` clears the flag again, so what
  /// actually closes a microphone a QUEUED start opens is the second,
  /// idempotent `_mic.stop()` inside [_stop] — an engine that consumed the
  /// signal here and queued nothing but the teardown left that microphone
  /// open with the lease held forever (the round-2 regression).
  ///
  /// The failure is logged HERE, in the turn the call was made: [_stop] may
  /// only reach its `await` several queued operations later, and a future
  /// whose error finds no listener within its own turn becomes an unhandled
  /// async error — which an un-awaited `stop()` (`dispose`, `ref.onDispose`)
  /// must never produce.
  Future<void> _signalStop() =>
      _mic.stop().catchError((Object error, StackTrace stackTrace) {
        _logger.error(
          'tuner.engine.lifecycle_failed',
          error: error,
          stackTrace: stackTrace,
          fields: {'op': 'stop.signal'},
        );
      });

  /// Runs as ONE step of [_lifecycle], never on its own — which is what makes
  /// "the microphone this closes is the one the preceding start opened" true.
  ///
  /// [signalled] is the platform round-trip [_signalStop] already started;
  /// awaiting it HERE keeps it inside the step, so `await stop()` keeps
  /// meaning "the stream is closed and the lease is back", never "closing has
  /// begun". The spawn-failure path in [_start] passes nothing.
  Future<void> _stop([Future<void>? signalled]) async {
    _running = false;
    // Snapshot and clear the ports/isolate BEFORE the first await (the same
    // rule MicCapture.stop follows for its capture+lease, round 114): should
    // this continuation ever resume after a new session was spun up, it tears
    // down only what it captured — never the NEW port or the NEW isolate.
    final fromDsp = _fromDsp;
    final isolate = _isolate;
    _toDsp = null;
    _fromDsp = null;
    _isolate = null;
    try {
      await signalled;
      // Idempotent, and NOT redundant: this is the call that closes a
      // microphone a start queued behind the signal has since opened, and the
      // one that hands back a lease the signal abandoned when the platform
      // stop threw.
      await _mic.stop();
    } finally {
      // Runs on EVERY path, a throwing platform stop included. The snapshot
      // above is already unreachable from the fields, so NO later stop() could
      // ever free it: skipping this once leaks the ReceivePort and the DSP
      // isolate for the rest of the process — the app keeps burning battery
      // with the screen gone (§7: every lifecycle resource is freed on every
      // path). The error itself still propagates to [_enqueue], which logs it.
      fromDsp?.close();
      isolate?.kill(priority: Isolate.immediate);
      _pendingChunks.clear();
      await _releaseLease();
    }
  }

  /// The last-ditch lease release, run from [_stop]'s `finally`.
  ///
  /// `MicCapture.stop()` releases the exclusive session only AFTER
  /// `capture.stop()` has returned, so a platform teardown that THROWS skips
  /// the release and the lease stays held. On the `dispose` path — which calls
  /// `stop()` exactly once — that is for the rest of the process, and every
  /// later microphone owner then gets `audioSessionBusy` (§5).
  ///
  /// This second call is idempotent and cannot repeat the platform failure:
  /// the first `MicCapture.stop()` already cleared its `_capture` before
  /// awaiting it, so there is no stream left to close and only the lease is
  /// handed back.
  ///
  /// Its own failure is LOGGED, never rethrown: this runs inside a `finally`,
  /// where throwing would REPLACE the original platform error that [_enqueue]
  /// must see (§10 — handled, not swallowed).
  Future<void> _releaseLease() async {
    try {
      await _mic.stop();
    } catch (error, stackTrace) {
      _logger.error(
        'tuner.engine.lifecycle_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'op': 'stop.release'},
      );
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller?.close();
    _controller = null;
  }
}

class _TunerInit {
  const _TunerInit({
    required this.sendPort,
    required this.sampleRate,
    required this.a4,
  });

  final SendPort sendPort;
  final int sampleRate;
  final int a4;
}

void _tunerEntry(_TunerInit init) {
  final analyzer = TunerAnalyzer(sampleRate: init.sampleRate, a4: init.a4);
  final framer = SlidingFramer(
    window: analyzer.bufferSize,
    hop: analyzer.bufferSize ~/ 2,
  );
  final inbox = ReceivePort();
  init.sendPort.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is List<double>) {
      for (final frame in framer.add(message)) {
        init.sendPort.send(analyzer.process(frame));
      }
    }
  });
}
