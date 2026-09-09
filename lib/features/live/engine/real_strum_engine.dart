import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/audio/mic_capture.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../domain/recognition/recognition_mode.dart';
import '../model/live_frame.dart';
import 'dsp/live_pipeline.dart';
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
  RealStrumEngine({
    required MicCapture mic,
    this.mode = RecognitionMode.free,
    RecognitionShadowObserverFactory? shadowObserverFactory,
  }) : _mic = mic,
       _shadowObserverFactory = shadowObserverFactory;

  /// The regime this engine was constructed in (ADR 0544 D1).
  final RecognitionMode mode;

  StreamController<LiveFrame>? _controller;
  final MicCapture _mic;
  final RecognitionShadowObserverFactory? _shadowObserverFactory;
  Isolate? _isolate;
  SendPort? _toDsp;
  ReceivePort? _fromDsp;
  final List<List<double>> _pendingChunks = [];
  bool _running = false;
  String? _expectedChord;

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
  Future<void> start() async {
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
      await stop();
      final controller = _controller;
      if (controller != null && !controller.isClosed) {
        controller.addError(e, st);
      }
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _mic.stop(); // release the microphone
    _toDsp = null;
    _fromDsp?.close();
    _fromDsp = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _pendingChunks.clear();
    // Reset the Lab-mode capture buffer on stop (the capture toggle itself is
    // re-asserted by the Live screen on the next start).
    _capture.reset();
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
    this.crnnWeights,
    this.shadowObserverFactory,
  });

  final SendPort sendPort;
  final int sampleRate;

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
