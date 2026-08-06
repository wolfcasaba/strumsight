import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as plugin;

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import 'camera_capture.dart';
import 'camera_error_mapping.dart';
import 'camera_failure.dart';
import 'camera_format.dart';
import 'camera_frame.dart';
import 'camera_frame_binding.dart';
import 'camera_timestamp.dart';

/// Minimal camera boundary used to test the capture adapter without a device.
abstract interface class PlatformCameraController {
  Future<void> initialize();
  Future<void> startImageStream(
    void Function(PlatformCameraFrame frame) onFrame,
  );
  Future<void> stopImageStream();
  Future<void> dispose();
}

typedef PlatformCameraControllerFactory =
    Future<PlatformCameraController> Function();

/// Creates the production [CameraCapture] backed by the official camera plugin.
CameraCapture createPlatformCameraCapture() =>
    PluginCameraCapture(controllerFactory: _PluginCameraController.create);

/// Production adapter with latest-frame delivery and explicit buffer release.
final class PluginCameraCapture implements CameraCapture {
  PluginCameraCapture({
    required PlatformCameraControllerFactory controllerFactory,
  }) : this._(controllerFactory);

  PluginCameraCapture._(this._controllerFactory)
    : _frames = StreamController<CameraFrame>.broadcast(sync: true);

  final PlatformCameraControllerFactory _controllerFactory;
  final StreamController<CameraFrame> _frames;
  PlatformCameraController? _controller;
  PlatformCameraFrame? _pendingFrame;
  bool _dispatchScheduled = false;
  bool _isRunning = false;
  bool _isClosed = false;
  bool _isImageStreaming = false;
  bool _isInitialized = false;
  int _nextFrameId = 0;
  int _droppedFrameCount = 0;

  /// Number of frames replaced before the synchronous consumer received them.
  int get droppedFrameCount => _droppedFrameCount;

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  @override
  Future<AppResult<void>> start() async {
    if (_isClosed) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.closed),
      );
    }
    if (_isRunning) {
      return const AppResult<void>.success(null);
    }

    try {
      final existing = _controller;
      final controller = existing ?? await _controllerFactory();
      if (_isClosed) {
        await controller.dispose();
        return const AppResult<void>.failure(CancelledFailure());
      }
      if (existing == null) {
        _controller = controller;
      }
      if (!_isInitialized) {
        await controller.initialize();
        _isInitialized = true;
      }
      if (_isClosed) {
        await controller.dispose();
        return const AppResult<void>.failure(CancelledFailure());
      }
      _isRunning = true;
      await controller.startImageStream(_receivePlatformFrame);
      _isImageStreaming = true;
      return const AppResult<void>.success(null);
    } on Object catch (error, stackTrace) {
      _isRunning = false;
      return AppResult<void>.failure(CameraErrorMapping.map(error, stackTrace));
    }
  }

  @override
  Future<AppResult<void>> stop() async {
    if (_isClosed) {
      return AppResult<void>.failure(
        CameraFailureMapper.map(CameraFailureKind.closed),
      );
    }
    _isRunning = false;
    _releasePendingFrame();
    try {
      if (_isImageStreaming) {
        await _controller?.stopImageStream();
        _isImageStreaming = false;
      }
      return const AppResult<void>.success(null);
    } on Object catch (error, stackTrace) {
      return AppResult<void>.failure(CameraErrorMapping.map(error, stackTrace));
    }
  }

  @override
  Future<AppResult<void>> close() async {
    if (_isClosed) {
      return const AppResult<void>.success(null);
    }

    _isClosed = true;
    _isRunning = false;
    _releasePendingFrame();
    Object? closeError;
    StackTrace? closeStackTrace;
    final controller = _controller;
    if (controller != null) {
      if (_isImageStreaming) {
        try {
          await controller.stopImageStream();
          _isImageStreaming = false;
        } on Object catch (error, stackTrace) {
          closeError = error;
          closeStackTrace = stackTrace;
        }
      }
      try {
        await controller.dispose();
      } on Object catch (error, stackTrace) {
        closeError ??= error;
        closeStackTrace ??= stackTrace;
      }
    }
    await _frames.close();
    if (closeError != null) {
      return AppResult<void>.failure(
        CameraErrorMapping.map(closeError, closeStackTrace),
      );
    }
    return const AppResult<void>.success(null);
  }

  void _receivePlatformFrame(PlatformCameraFrame frame) {
    if (_isClosed || !_isRunning) {
      frame.release();
      return;
    }
    final replaced = _pendingFrame;
    _pendingFrame = frame;
    if (replaced != null) {
      _droppedFrameCount += 1;
      replaced.release();
    }
    if (_dispatchScheduled) {
      return;
    }
    _dispatchScheduled = true;
    scheduleMicrotask(_deliverLatestFrame);
  }

  void _deliverLatestFrame() {
    _dispatchScheduled = false;
    final platformFrame = _pendingFrame;
    _pendingFrame = null;
    if (platformFrame == null) {
      return;
    }
    try {
      if (_isClosed || !_isRunning) {
        return;
      }
      final frame = CameraFrameBinding.bind(
        platformFrame,
        frameId: _nextFrameId,
      );
      _nextFrameId += 1;
      _frames.add(frame);
      frame.invalidate();
    } on Object catch (error, stackTrace) {
      if (!_isClosed) {
        _frames.addError(CameraErrorMapping.map(error, stackTrace));
      }
    } finally {
      platformFrame.release();
    }
  }

  void _releasePendingFrame() {
    final pending = _pendingFrame;
    _pendingFrame = null;
    pending?.release();
  }
}

final class _PluginCameraController implements PlatformCameraController {
  _PluginCameraController(this._controller);

  final plugin.CameraController _controller;
  final Stopwatch _clock = Stopwatch();
  int _lastTimestampUs = -1;

  static Future<PlatformCameraController> create() async {
    final cameras = await plugin.availableCameras();
    if (cameras.isEmpty) {
      throw plugin.CameraException('CameraNotFound', 'No camera is available.');
    }
    final description = cameras.firstWhere(
      (camera) => camera.lensDirection == plugin.CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    return _PluginCameraController(
      plugin.CameraController(
        description,
        plugin.ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: plugin.ImageFormatGroup.yuv420,
      ),
    );
  }

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<void> startImageStream(
    void Function(PlatformCameraFrame frame) onFrame,
  ) => _controller.startImageStream((image) {
    final elapsedUs = _clock.elapsedMicroseconds;
    final timestampUs = elapsedUs > _lastTimestampUs
        ? elapsedUs
        : _lastTimestampUs + 1;
    _lastTimestampUs = timestampUs;
    onFrame(
      PlatformCameraFrame(
        bytes: _copyPlanes(image),
        timestamp: CameraTimestamp(timestampUs),
        width: image.width,
        height: image.height,
        format: _formatFor(image.format.group),
        orientation: _orientationFor(_controller.description.sensorOrientation),
        mirror:
            _controller.description.lensDirection ==
            plugin.CameraLensDirection.front,
        crop: null,
        // The plugin exposes no manual image-buffer release API. Its bytes are
        // copied synchronously above; this closure releases the adapter's hold.
        release: () {},
      ),
    );
  });

  @override
  Future<void> stopImageStream() => _controller.stopImageStream();

  @override
  Future<void> dispose() => _controller.dispose();

  static Uint8List _copyPlanes(plugin.CameraImage image) {
    final length = image.planes.fold<int>(
      0,
      (total, plane) => total + plane.bytes.length,
    );
    final bytes = Uint8List(length);
    var offset = 0;
    for (final plane in image.planes) {
      bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }
    return bytes;
  }

  static CameraPixelFormat _formatFor(plugin.ImageFormatGroup format) =>
      switch (format) {
        plugin.ImageFormatGroup.yuv420 => CameraPixelFormat.yuv420,
        plugin.ImageFormatGroup.nv21 => CameraPixelFormat.nv21,
        plugin.ImageFormatGroup.bgra8888 => CameraPixelFormat.bgra8888,
        plugin.ImageFormatGroup.jpeg => CameraPixelFormat.jpeg,
        _ => CameraPixelFormat.yuv420,
      };

  static CameraOrientation _orientationFor(int degrees) =>
      switch ((degrees % 360 + 360) % 360) {
        90 => CameraOrientation.landscapeRight,
        180 => CameraOrientation.portraitDown,
        270 => CameraOrientation.landscapeLeft,
        _ => CameraOrientation.portraitUp,
      };
}
