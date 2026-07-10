import 'dart:async';
import 'dart:isolate';

import '../../../core/audio/mic_capture.dart';
import '../../live/engine/dsp/sliding_framer.dart';
import '../model/tuner_reading.dart';
import 'dsp/tuner_analyzer.dart';
import 'tuner_engine.dart';

/// The REAL tuner: microphone → DSP isolate (YIN) → TunerReadings.
class RealTunerEngine implements TunerEngine {
  StreamController<TunerReading>? _controller;
  final MicCapture _mic = MicCapture();
  Isolate? _isolate;
  SendPort? _toDsp;
  ReceivePort? _fromDsp;
  final List<List<double>> _pendingChunks = [];
  bool _running = false;

  @override
  Stream<TunerReading> get readings {
    _controller ??= StreamController<TunerReading>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start({int a4 = 440}) async {
    if (_running) return;
    _controller ??= StreamController<TunerReading>.broadcast();

    if (!await MicCapture.ensurePermission()) {
      _controller?.add(TunerReading.silent);
      return;
    }
    _running = true;

    try {
      final actualRate = await _mic.start((chunk) {
        final port = _toDsp;
        if (port != null) {
          port.send(chunk);
        } else if (_pendingChunks.length < 64) {
          _pendingChunks.add(chunk);
        }
      });

      _fromDsp = ReceivePort();
      _isolate = await Isolate.spawn(
        _tunerEntry,
        _TunerInit(
            sendPort: _fromDsp!.sendPort, sampleRate: actualRate, a4: a4),
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
    await _mic.stop();
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
  final framer =
      SlidingFramer(window: analyzer.bufferSize, hop: analyzer.bufferSize ~/ 2);
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
