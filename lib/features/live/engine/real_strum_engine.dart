import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/audio/mic_capture.dart';
import '../model/live_frame.dart';
import 'dsp/live_pipeline.dart';
import 'strum_engine.dart';

/// The REAL engine: microphone → DSP isolate (LivePipeline) → LiveFrames.
///
/// All analysis runs off the UI isolate (RAG chunk 010). stop() releases the
/// microphone AND kills the isolate — pause must truly stop detection.
class RealStrumEngine implements StrumEngine {
  StreamController<LiveFrame>? _controller;
  final MicCapture _mic = MicCapture();
  Isolate? _isolate;
  SendPort? _toDsp;
  ReceivePort? _fromDsp;
  final List<List<double>> _pendingChunks = [];
  bool _running = false;
  String? _expectedChord;

  @override
  void setExpectedChord(String? label) {
    _expectedChord = label;
    _toDsp?.send(_ExpectedChord(label));
  }

  @override
  Stream<LiveFrame> get frames {
    _controller ??= StreamController<LiveFrame>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _controller ??= StreamController<LiveFrame>.broadcast();

    if (!await MicCapture.ensurePermission()) {
      // No permission: stay silent; the Live screen shows the mic banner.
      _controller?.add(LiveFrame.empty);
      return;
    }
    _running = true;

    try {
      // Mic first — the actual sample rate is only known once capture runs.
      final actualRate = await _mic.start((chunk) {
        final port = _toDsp;
        if (port != null) {
          port.send(chunk);
        } else if (_pendingChunks.length < 64) {
          _pendingChunks.add(chunk); // buffer during isolate spin-up
        }
      });

      _fromDsp = ReceivePort();
      _isolate = await Isolate.spawn(
        _dspEntry,
        _DspInit(
          sendPort: _fromDsp!.sendPort,
          sampleRate: actualRate,
          crnnWeights: await _liveCrnnWeights(),
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
    this.crnnWeights,
  });

  final SendPort sendPort;
  final int sampleRate;

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
      _cachedLiveWeights =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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
  final pipeline = LivePipeline(
    sampleRate: init.sampleRate,
    crnnWeights: init.crnnWeights,
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
