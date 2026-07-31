import 'dart:async';

import 'package:strumsight/features/live/public.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/platform/microphone_permission.dart';
import '../application/practice_observation_gateway.dart';
import '../domain/model/practice_observation.dart';
import 'adapters/legacy_chord_label.dart';

/// Adapts the public Live frame stream to Practice observations.
///
/// The Live frame's confidence is a strum confidence. Chord observations use
/// `1.0` because LiveFrame has no chord-confidence field; that value means
/// "not measured" on this adapter path, so [PracticeObservationConfig.chordMinConfidence]
/// does not filter them.
final class LivePracticeObservationGateway
    implements PracticeObservationGateway {
  LivePracticeObservationGateway({
    required this._engine,
    required this._permissions,
    required this._timelineNow,
    required this._logger,
  });

  final StrumEngine _engine;
  final MicrophonePermissionGateway _permissions;
  final Duration Function() _timelineNow;
  final AppLogger _logger;
  final StreamController<PracticeObservation> _observationsController =
      StreamController<PracticeObservation>.broadcast();

  StreamSubscription<LiveFrame>? _frameSubscription;
  Future<void>? _pendingStreamTeardown;
  PracticeObservationConfig? _config;
  String? _expectedChord;
  bool _running = false;
  bool _disposed = false;

  int _lastSeenStrumSeq = -1;
  int _nextObservationSequence = 0;
  Duration _lastEmittedAt = Duration.zero;
  bool _hasEmittedChord = false;
  String? _lastChordLabel;
  Duration _lastChordEmittedAt = Duration.zero;
  Duration? _lastLagWarningAt;

  @override
  Stream<PracticeObservation> get observations =>
      _observationsController.stream;

  @override
  Future<AppResult<void>> start({
    required PracticeObservationConfig config,
  }) async {
    if (_disposed) {
      return const Failure(
        AudioFailure(code: FailureCode.practiceObservationGatewayDisposed),
      );
    }
    final pendingTeardown = _pendingStreamTeardown;
    if (pendingTeardown != null) await pendingTeardown;
    if (_running) return const Success(null);

    final validation = config.validate();
    if (validation.isNotEmpty) {
      return Failure(
        ConfigurationFailure(
          code: FailureCode.configurationInvalid,
          cause: validation,
        ),
      );
    }

    var permissionState = await _permissions.currentState();
    if (!permissionState.isGranted) {
      permissionState = await _permissions.request();
    }
    if (!permissionState.isGranted) {
      _logger.warning(
        'practice_observation_permission_denied',
        error: permissionState.failure,
        fields: <String, Object?>{'state': permissionState.name},
      );
      return Failure(permissionState.failure!);
    }

    _config = config;
    _resetObservationState();
    _running = true;
    _frameSubscription = _engine.frames.listen(
      _handleFrame,
      onError: _handleStreamError,
      cancelOnError: false,
    );

    try {
      await _engine.start();
    } catch (error, stackTrace) {
      _running = false;
      await _stopActiveCapture();
      final failure = AudioFailure(
        code: FailureCode.practiceObservationStreamFailed,
        cause: error,
        stackTrace: stackTrace,
      );
      _logger.error(
        'practice_observation_start_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(failure);
    }

    if (_running) {
      _engine.setExpectedChord(_expectedChord);
      _logger.info('practice_observation_capture_started');
    }
    return const Success(null);
  }

  @override
  void setExpectedChord(String? chord) {
    if (_disposed) return;
    _expectedChord = chord;
    if (_running) _engine.setExpectedChord(chord);
  }

  @override
  Future<AppResult<void>> stop() async {
    if (_disposed) {
      return const Failure(
        AudioFailure(code: FailureCode.practiceObservationGatewayDisposed),
      );
    }
    final pendingTeardown = _pendingStreamTeardown;
    if (!_running) {
      if (pendingTeardown != null) await pendingTeardown;
      return const Success(null);
    }

    _running = false;
    try {
      await _stopActiveCapture();
      return const Success(null);
    } catch (error, stackTrace) {
      _logger.error(
        'practice_observation_stop_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        AudioFailure(
          code: FailureCode.audioCaptureFailed,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pendingTeardown = _pendingStreamTeardown;
    if (pendingTeardown != null) await pendingTeardown;
    _running = false;
    try {
      await _stopActiveCapture();
    } finally {
      await _observationsController.close();
    }
  }

  void _resetObservationState() {
    _lastSeenStrumSeq = -1;
    _nextObservationSequence = 0;
    _lastEmittedAt = Duration.zero;
    _hasEmittedChord = false;
    _lastChordLabel = null;
    _lastChordEmittedAt = Duration.zero;
    _lastLagWarningAt = null;
  }

  void _handleFrame(LiveFrame frame) {
    if (!_running || _disposed) return;
    final config = _config;
    if (config == null) return;

    final timelineNow = _timelineNow();
    final lag = _frameDeliveryLag(frame, config, timelineNow);
    final strum = frame.latestStrum;
    var emitStrum = false;
    if (strum != null && frame.strumSeq > _lastSeenStrumSeq) {
      _lastSeenStrumSeq = frame.strumSeq;
      emitStrum =
          strum.confidence.isFinite &&
          strum.confidence >= config.strumMinConfidence;
    }

    final chordLabel = legacyPracticeChordLabel(frame.current?.label);
    final emitChord =
        !_hasEmittedChord ||
        chordLabel != _lastChordLabel ||
        timelineNow - _lastChordEmittedAt >= config.chordStableDuration;
    if (!emitStrum && !emitChord) return;

    final at = _observationAt(timelineNow, lag);
    if (emitStrum) {
      _observationsController.add(
        StrumObservation(
          at: at,
          sequence: _nextObservationSequence++,
          direction: strum!.direction,
          confidence: strum.confidence,
        ),
      );
    }
    if (emitChord) {
      _hasEmittedChord = true;
      _lastChordLabel = chordLabel;
      _lastChordEmittedAt = timelineNow;
      _observationsController.add(
        ChordObservation(at: at, label: chordLabel, confidence: 1.0),
      );
    }
  }

  Duration _frameDeliveryLag(
    LiveFrame frame,
    PracticeObservationConfig config,
    Duration timelineNow,
  ) {
    final engineTime = frame.engineTimeSec;
    final latestStrumTime = frame.latestStrumTime;
    if (engineTime < 0 || latestStrumTime < 0) return Duration.zero;

    final lagSec = engineTime - latestStrumTime;
    if (lagSec <= 0) return Duration.zero;
    final maxLagSec = config.maxFrameDeliveryLag.inMicroseconds / 1000000;
    if (lagSec >= maxLagSec) {
      _warnAboutLagOncePerSecond(
        lagSec,
        config.maxFrameDeliveryLag,
        timelineNow,
      );
      return Duration.zero;
    }
    return Duration(microseconds: (lagSec * 1000000).round());
  }

  void _warnAboutLagOncePerSecond(
    double lagSec,
    Duration maximumLag,
    Duration timelineNow,
  ) {
    final lastWarning = _lastLagWarningAt;
    if (lastWarning != null &&
        timelineNow - lastWarning < const Duration(seconds: 1)) {
      return;
    }
    _lastLagWarningAt = timelineNow;
    _logger.warning(
      'practice_observation_frame_lag_out_of_range',
      fields: <String, Object?>{
        'lagMicroseconds': (lagSec * 1000000).round(),
        'maximumLagMicroseconds': maximumLag.inMicroseconds,
      },
    );
  }

  Duration _observationAt(Duration timelineNow, Duration lag) {
    final raw = timelineNow - lag;
    var at = raw < Duration.zero ? Duration.zero : raw;
    if (at < _lastEmittedAt) at = _lastEmittedAt;
    _lastEmittedAt = at;
    return at;
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (!_running || _disposed) return;
    _running = false;
    final mapped = error is AppFailure
        ? error
        : AudioFailure(
            code: FailureCode.practiceObservationStreamFailed,
            cause: error,
            stackTrace: stackTrace,
          );
    _logger.warning(
      'practice_observation_stream_failed',
      error: mapped,
      stackTrace: stackTrace,
      fields: <String, Object?>{'code': mapped.code},
    );
    if (!_observationsController.isClosed) {
      _observationsController.addError(mapped, stackTrace);
    }
    final teardown = _stopActiveCapture();
    _pendingStreamTeardown = teardown;
    unawaited(teardown);
  }

  Future<void> _stopActiveCapture() async {
    final subscription = _frameSubscription;
    if (subscription == null && !_running) return;
    _frameSubscription = null;
    await subscription?.cancel();
    _engine.setExpectedChord(null);
    await _engine.stop();
    _logger.info('practice_observation_capture_stopped');
  }
}
