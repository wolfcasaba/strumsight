import 'dart:async';
import 'dart:isolate';

import '../../../core/audio/mic_capture.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/audio/dsp/sliding_framer.dart';
import '../model/tuner_reading.dart';
import 'dsp/tuner_analyzer.dart';
import 'tuner_engine.dart';

/// The REAL tuner: microphone → DSP isolate (YIN) → TunerReadings.
class RealTunerEngine implements TunerEngine {
  /// [mic] carries the exclusive-session lease (E01-R09).
  RealTunerEngine({required this._mic});

  StreamController<TunerReading>? _controller;
  final MicCapture _mic;
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
