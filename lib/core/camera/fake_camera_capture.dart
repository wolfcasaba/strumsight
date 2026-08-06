import 'dart:async';
import 'dart:typed_data';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import 'camera_capture.dart';
import 'camera_failure.dart';
import 'camera_format.dart';
import 'camera_frame.dart';
import 'camera_timestamp.dart';

/// Deterministic, plugin-free [CameraCapture] for lifecycle and failure tests.
///
/// Set [frameInterval] to schedule repeatable frames. The timestamps advance by
/// [timestampStep] per frame, independent of wall-clock scheduling jitter.
final class FakeCameraCapture implements CameraCapture {
  FakeCameraCapture({
    this.startFailure,
    this.frameFailure,
    this.startGate,
    this.frameInterval,
    this.timestampStep = const Duration(microseconds: 33333),
    this.frameBytes = const <int>[0],
    this.width = 1,
    this.height = 1,
    this.format = CameraPixelFormat.yuv420,
    this.orientation = CameraOrientation.portraitUp,
  }) : assert(!timestampStep.isNegative),
       assert(width > 0),
       assert(height > 0),
       _frames = StreamController<CameraFrame>.broadcast(sync: true);

  final CameraFailureKind? startFailure;
  final CameraFailureKind? frameFailure;
  final Future<void>? startGate;
  final Duration? frameInterval;
  final Duration timestampStep;
  final List<int> frameBytes;
  final int width;
  final int height;
  final CameraPixelFormat format;
  final CameraOrientation orientation;
  final StreamController<CameraFrame> _frames;

  Timer? _scheduledFrames;
  bool _isRunning = false;
  bool _isClosed = false;
  int _nextFrameId = 0;
  int _nextTimestampUs = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int closeCalls = 0;

  bool get isRunning => _isRunning;
  bool get isClosed => _isClosed;

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  @override
  Future<AppResult<void>> start() async {
    startCalls += 1;
    if (_isClosed) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.closed),
      );
    }
    if (startFailure != null) {
      return AppResult<void>.failure(CameraFailureMapper.map(startFailure!));
    }

    try {
      await startGate;
    } on Object catch (error, stackTrace) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(
          CameraFailureKind.initialization,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    if (_isClosed) {
      return const AppResult<void>.failure(CancelledFailure());
    }

    _isRunning = true;
    _startScheduledFrames();
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls += 1;
    if (_isClosed) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.closed),
      );
    }
    _stopScheduledFrames();
    _isRunning = false;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> close() async {
    closeCalls += 1;
    if (_isClosed) {
      return const AppResult<void>.success(null);
    }

    _isClosed = true;
    _isRunning = false;
    _stopScheduledFrames();
    await _frames.close();
    return const AppResult<void>.success(null);
  }

  /// Delivers one deterministic frame, or the configured frame failure.
  ///
  /// The frame is invalidated immediately after synchronous stream listeners
  /// return, matching a platform adapter that releases a borrowed image buffer.
  AppResult<void> emitFrame() {
    if (_isClosed) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.closed),
      );
    }
    if (!_isRunning) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.initialization),
      );
    }
    if (frameFailure != null) {
      final failure = CameraFailureMapper.map(frameFailure!);
      _frames.addError(failure);
      return AppResult<void>.failure(failure);
    }

    final frame = CameraFrame(
      bytes: Uint8List.fromList(frameBytes),
      frameId: _nextFrameId,
      timestamp: CameraTimestamp(_nextTimestampUs),
      width: width,
      height: height,
      format: format,
      orientation: orientation,
    );
    _nextFrameId += 1;
    _nextTimestampUs += timestampStep.inMicroseconds;
    _frames.add(frame);
    frame.invalidate();
    return const AppResult<void>.success(null);
  }

  /// Simulates a platform interruption and makes the session inactive.
  AppResult<void> interrupt() {
    if (_isClosed) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.closed),
      );
    }
    _isRunning = false;
    _stopScheduledFrames();
    final failure = CameraFailureMapper.map(CameraFailureKind.interrupted);
    _frames.addError(failure);
    return AppResult<void>.failure(failure);
  }

  void _startScheduledFrames() {
    final interval = frameInterval;
    if (interval == null) {
      return;
    }
    _scheduledFrames = Timer.periodic(interval, (_) {
      emitFrame();
    });
  }

  void _stopScheduledFrames() {
    _scheduledFrames?.cancel();
    _scheduledFrames = null;
  }
}
