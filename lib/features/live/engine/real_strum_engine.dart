import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/audio/mic_capture.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/debug_app_logger.dart';
import '../domain/recognition/device_audio_profile.dart';
import '../domain/recognition/recognition_mode.dart';
import '../model/live_frame.dart';
import 'dsp/live_pipeline.dart';
import 'dsp/quality_aware_preprocessor.dart';
import 'pcm_ring_buffer.dart';
import 'recognition_shadow_observer.dart';
import 'strum_engine.dart';

/// The REAL engine: microphone → DSP isolate (LivePipeline) → LiveFrames.
///
/// All analysis runs off the UI isolate (RAG chunk 010). stop() releases the
/// microphone AND kills the isolate — pause must truly stop detection.
class RealStrumEngine implements StrumEngine {
  /// [mic] carries the exclusive-session lease (E01-R09): the engine no longer
  /// owns a microphone, it owns a *lease* on the one microphone.
  ///
  /// [mode] is a CONSTRUCTION-time property (E14-R30, ADR 0544 D1), not a
  /// setter: an engine built for free play can never be talked into applying
  /// a lesson's expected-chord prior. It defaults to [RecognitionMode.free] —
  /// fail-closed, the regime with no outside influence on the verdict.
  ///
  /// [shadowObserverFactory] must be a **top-level or static** function (see
  /// [RecognitionShadowObserverFactory]): the observer is created INSIDE the
  /// DSP isolate, because that is where the frames are produced. Null (the
  /// default) installs the no-op observer, i.e. no shadow work at all.
  ///
  /// [preprocessingEnabled] is the projection of the
  /// `recognitionPreprocessingEnabled` feature flag (E14-R31, ADR 0552 D1):
  /// `false` — the shipped, fail-closed value — builds the pipeline with
  /// `LivePreprocessingConfig.disabled`, which hands every chunk through
  /// untouched. The engine takes a BOOL rather than the config object so
  /// the provider that reads the flag never has to import `engine/dsp/`.
  ///
  /// [deviceProfile] is the per-device correction the audio-setup wizard
  /// (E14-R14) is meant to produce. It defaults to
  /// [DeviceAudioProfile.identity] — 0 dB, no measured noise floor — and is
  /// inert while [preprocessingEnabled] is `false`.
  /// [logger] defaults to the app's OWN sink, not to [NoopAppLogger]: a
  /// [DebugAppLogger] prints redacted lines in debug builds and disables itself
  /// in release (`enabled ?? kDebugMode`), which is exactly what
  /// `createDefaultAppLogger` means by "the app's logger". A failing lifecycle
  /// step therefore leaves a trace even though `strumEngineProvider` does not
  /// inject `appLoggerProvider` yet — a silent default would make the handling
  /// below an empty catch in every build (§10).
  RealStrumEngine({
    required MicCapture mic,
    this.mode = RecognitionMode.free,
    this.preprocessingEnabled = false,
    this.deviceProfile = const DeviceAudioProfile.identity(),
    RecognitionShadowObserverFactory? shadowObserverFactory,
    AppLogger? logger,
  }) : _mic = mic, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _shadowObserverFactory = shadowObserverFactory,
       _logger = logger ?? DebugAppLogger();

  /// The regime this engine was constructed in (ADR 0544 D1).
  final RecognitionMode mode;

  /// Whether the quality-aware preprocessing stage may run (ADR 0552 D1).
  final bool preprocessingEnabled;

  /// The per-device audio correction handed to that stage (ADR 0552 D4).
  final DeviceAudioProfile deviceProfile;

  StreamController<LiveFrame>? _controller;
  final MicCapture _mic;
  final AppLogger _logger;
  final RecognitionShadowObserverFactory? _shadowObserverFactory;
  Isolate? _isolate;
  SendPort? _toDsp;
  ReceivePort? _fromDsp;
  final List<List<double>> _pendingChunks = [];
  bool _running = false;
  String? _expectedChord;

  /// THE lifecycle queue: ONE strict-FIFO future chain through which every
  /// [start] and [stop] runs. Resume (and every `ref.invalidate` of
  /// `liveFrameProvider`) disposes the provider — firing an UN-AWAITED
  /// `stop()` — and calls `start()` on the SAME engine in the same turn.
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

  // Lab-mode rolling capture (r199): a drop-oldest ring of recent mic PCM,
  // only populated while enabled. Off by default → the default Live path
  // allocates and appends nothing.
  final PcmRingBuffer _capture = PcmRingBuffer();

  /// E14-R30 (ADR 0544 D2): the label is normalised through
  /// [ExpectedChordHint.forMode] BEFORE it is retained or sent across the
  /// isolate boundary, so in [RecognitionMode.free] a hint never leaves this
  /// method — the DSP isolate is not merely told to ignore it, it is never
  /// told about it. The pipeline on the other side applies the same filter
  /// again (defence in depth: neither side trusts the other's mode).
  @override
  void setExpectedChord(String? label) {
    _expectedChord = ExpectedChordHint.forMode(mode, label)?.label;
    _toDsp?.send(_ExpectedChord(_expectedChord));
  }

  @override
  void setDiagnosticsCapture(bool on) {
    _capture.enabled = on;
    if (!on) _capture.clear(); // release the buffer the moment it's off
  }

  @override
  (List<double>, int) recentPcm() => _capture.recent();

  @override
  Stream<LiveFrame> get frames {
    _controller ??= StreamController<LiveFrame>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start() => _enqueue('start', _start);

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
          'live.engine.lifecycle_failed',
          error: error,
          stackTrace: stackTrace,
          fields: {'op': op},
        );
      }
    });
    _lifecycle = next;
    return next;
  }

  Future<void> _start() async {
    if (_running) return;
    _controller ??= StreamController<LiveFrame>.broadcast();

    // Set BEFORE the first await: a second start() landing during the mic
    // handshake must not run a parallel spin-up (§9.3 start/start race).
    _running = true;

    // Mic first — the actual sample rate is only known once capture runs.
    // The session is exclusive: a busy mic comes back as a failure here
    // instead of silently stealing the Tuner's capture.
    final started = await _mic.start((chunk) {
      // Lab-mode rolling capture: append + drop-oldest past ~30 s. Entirely
      // skipped when capture is off (default) — zero overhead.
      _capture.add(chunk);
      final port = _toDsp;
      if (port != null) {
        port.send(chunk);
      } else if (_pendingChunks.length < 64) {
        _pendingChunks.add(chunk); // buffer during isolate spin-up
      }
    }, onRevoke: stop);
    if (started case Failure<int>(:final error)) {
      _running = false;
      switch (error) {
        case PermissionFailure():
          // No permission: stay silent; the Live screen shows the mic banner.
          _controller?.add(LiveFrame.empty);
        case CancelledFailure():
          // stop() won the race (screen left during the handshake) — nothing
          // to report, and nothing is running.
          break;
        default:
          // Busy microphone or a capture error: an honest error on the stream,
          // never a screen that pretends to listen (round 13 lesson).
          final controller = _controller;
          if (controller != null && !controller.isClosed) {
            controller.addError(error, error.stackTrace ?? StackTrace.current);
          }
      }
      return;
    }
    final actualRate = (started as Success<int>).value;

    try {
      _capture.sampleRate = actualRate;

      _fromDsp = ReceivePort();
      _isolate = await Isolate.spawn(
        _dspEntry,
        _DspInit(
          sendPort: _fromDsp!.sendPort,
          sampleRate: actualRate,
          crnnWeights: await _liveCrnnWeights(),
          mode: mode,
          preprocessingEnabled: preprocessingEnabled,
          deviceProfile: deviceProfile,
          shadowObserverFactory: _shadowObserverFactory,
        ),
      );
      _fromDsp!.listen((message) {
        if (message is SendPort) {
          _toDsp = message;
          // Re-assert the expected-chord hint: the isolate is fresh (a lesson
          // may have set it before/while the mic was starting).
          if (_expectedChord != null) {
            _toDsp!.send(_ExpectedChord(_expectedChord));
          }
          for (final c in _pendingChunks) {
            _toDsp!.send(c);
          }
          _pendingChunks.clear();
        } else if (message is LiveFrame) {
          _controller?.add(message);
        }
      });
    } catch (e, st) {
      // Mic unavailable (busy, revoked mid-capture, platform channel error):
      // surface it on the stream so the Live screen shows an honest error —
      // never a silent no-op. Leave the engine stopped so Resume can retry.
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
  /// `ref.onDispose`, the background hook) may drop it: the work still runs,
  /// in order.
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
  /// async error — which an un-awaited `stop()` (`dispose`, `ref.onDispose`,
  /// the Live screen's background hook) must never produce.
  Future<void> _signalStop() =>
      _mic.stop().catchError((Object error, StackTrace stackTrace) {
        _logger.error(
          'live.engine.lifecycle_failed',
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
      await _mic.stop(); // release the microphone
    } finally {
      // Runs on EVERY path, a throwing platform stop included. The snapshot
      // above is already unreachable from the fields, so NO later stop() could
      // ever free it: skipping this once leaks the ReceivePort and the DSP
      // isolate for the rest of the process — the app keeps burning battery
      // with the screen gone — and leaves up to ~30 s of recorded PCM in the
      // Lab-mode ring buffer after the microphone was supposed to be released
      // (§5/§7). The error itself still propagates to [_enqueue], which logs it.
      fromDsp?.close();
      isolate?.kill(priority: Isolate.immediate);
      _pendingChunks.clear();
      // Reset the Lab-mode capture buffer on stop (the capture toggle itself is
      // re-asserted by the Live screen on the next start).
      _capture.reset();
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
        'live.engine.lifecycle_failed',
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

class _DspInit {
  const _DspInit({
    required this.sendPort,
    required this.sampleRate,
    required this.mode,
    required this.preprocessingEnabled,
    required this.deviceProfile,
    this.crnnWeights,
    this.shadowObserverFactory,
  });

  final SendPort sendPort;
  final int sampleRate;

  /// The E14-R31 flag projection and the device profile (ADR 0552 D1/D4).
  /// Both are plain immutable values (a bool and three scalars), so they
  /// copy across the isolate boundary the same way [mode] does.
  final bool preprocessingEnabled;
  final DeviceAudioProfile deviceProfile;

  /// The regime the pipeline inside the isolate is CONSTRUCTED with
  /// (ADR 0544 D1) — an enum value, so it copies across the boundary.
  final RecognitionMode mode;

  /// A top-level/static function reference (sendable) that builds the shadow
  /// observer inside the DSP isolate; null → the no-op observer.
  final RecognitionShadowObserverFactory? shadowObserverFactory;

  /// The live strum model's weights bytes (r169): loaded on the MAIN isolate
  /// (rootBundle doesn't exist in the DSP isolate) and parsed inside. Null →
  /// the pipeline keeps the heuristic.
  final Uint8List? crnnWeights;
}

/// Loaded once per app run; null where the asset is absent (stripped builds)
/// or the bundle is unavailable — the heuristic path then stands.
Future<Uint8List?> _liveCrnnWeights() async {
  if (_cachedLiveWeights != null) return _cachedLiveWeights;
  // r175: prefer the 3-class model (down/up + learned no-strum reject) so the
  // live path can SUPPRESS false-onset arrows; fall back to the 2-class live
  // model, then to the heuristic (null). CrnnStrumNet reads the class count
  // from the weights, so both assets parse; the classifier only suppresses for
  // a 3-class one (r139 seam).
  for (final asset in const [
    'assets/ml/strum_crnn_live_3c.bin',
    'assets/ml/strum_crnn_live.bin',
  ]) {
    try {
      final data = await rootBundle.load(asset);
      _cachedLiveWeights = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      break;
    } catch (_) {
      // Try the next asset; keep null if none load (retried next start).
    }
  }
  return _cachedLiveWeights;
}

Uint8List? _cachedLiveWeights;

/// Control message: the lesson's expected chord (round-137 prior).
class _ExpectedChord {
  const _ExpectedChord(this.label);

  final String? label;
}

void _dspEntry(_DspInit init) {
  final observerFactory = init.shadowObserverFactory;
  final pipeline = LivePipeline(
    sampleRate: init.sampleRate,
    crnnWeights: init.crnnWeights,
    mode: init.mode,
    preprocessing: init.preprocessingEnabled
        ? const LivePreprocessingConfig.standard()
        : const LivePreprocessingConfig.disabled(),
    deviceProfile: init.deviceProfile,
    shadowObserver: observerFactory == null
        ? const NoopRecognitionShadowObserver()
        : observerFactory(),
  );
  final inbox = ReceivePort();
  init.sendPort.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is List<double>) {
      for (final frame in pipeline.addChunk(message)) {
        init.sendPort.send(frame);
      }
    } else if (message is _ExpectedChord) {
      pipeline.setExpectedChord(message.label);
    }
  });
}
