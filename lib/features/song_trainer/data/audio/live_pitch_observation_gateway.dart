import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strumsight/core/audio/dsp/yin_pitch_detector.dart';
import 'package:strumsight/core/audio/mic_capture.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_config.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_gateway.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

/// A timestamped PCM frame supplied by an injected microphone owner.
final class PitchPcmFrame {
  const PitchPcmFrame({required this.samples, required this.capturedAt});

  final Float64List samples;
  final DateTime capturedAt;
}

/// Source boundary owned by the microphone lifecycle layer.
abstract interface class PitchFrameSource {
  Stream<PitchPcmFrame> get frames;

  Future<AppResult<int>> start();

  Future<AppResult<void>> stop();

  Future<void> dispose();
}

/// Adapts a caller-owned [MicCapture] to timestamped PCM frames.
final class MicCapturePitchFrameSource implements PitchFrameSource {
  MicCapturePitchFrameSource({
    required this._micCapture,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MicCapture _micCapture;
  final DateTime Function() _now;
  final StreamController<PitchPcmFrame> _frames =
      StreamController<PitchPcmFrame>.broadcast();
  bool _running = false;
  bool _disposed = false;
  int _sampleRate = 0;

  @override
  Stream<PitchPcmFrame> get frames => _frames.stream;

  @override
  Future<AppResult<int>> start() async {
    if (_disposed) {
      return const Failure(AudioFailure(code: FailureCode.audioUnavailable));
    }
    if (_running) {
      return Success<int>(_sampleRate);
    }
    final result = await _micCapture.start((samples) {
      if (_running && !_frames.isClosed) {
        _frames.add(
          PitchPcmFrame(
            samples: Float64List.fromList(samples),
            capturedAt: _now(),
          ),
        );
      }
    });
    if (result case Success<int>(:final value)) {
      _running = true;
      _sampleRate = value;
      return Success<int>(value);
    }
    return Failure(result.failureOrNull!);
  }

  @override
  Future<AppResult<void>> stop() async {
    if (!_running) return const Success<void>(null);
    _running = false;
    await _micCapture.stop();
    return const Success<void>(null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _frames.close();
  }
}

/// Converts caller-owned PCM frames into confidence-gated pitch observations.
final class LivePitchObservationGateway implements PitchObservationGateway {
  LivePitchObservationGateway({required this._source, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final PitchFrameSource _source;
  final DateTime Function() _now;
  final StreamController<PitchObservation> _observations =
      StreamController<PitchObservation>.broadcast();
  final List<double> _recentFrequencies = <double>[];
  StreamSubscription<PitchPcmFrame>? _subscription;
  PitchObservationConfig? _config;
  YinPitchDetector? _detector;
  bool _running = false;
  bool _sourceRunning = false;
  bool _disposed = false;

  @override
  Stream<PitchObservation> get observations => _observations.stream;

  @override
  Future<AppResult<void>> start(PitchObservationConfig config) async {
    if (_disposed) {
      return const Failure(AudioFailure(code: FailureCode.audioUnavailable));
    }
    if (_running) return const Success<void>(null);
    if (!config.isValid) {
      return const Failure(
        ConfigurationFailure(code: FailureCode.configurationInvalid),
      );
    }
    _config = config;
    _recentFrequencies.clear();
    _subscription = _source.frames.listen(
      _handleFrame,
      onError: _handleSourceError,
      cancelOnError: false,
    );
    final started = await _source.start();
    if (started case Failure<int>(:final error)) {
      await _cancelSubscription();
      return Failure(error);
    }
    _sourceRunning = true;
    try {
      _detector = YinPitchDetector(sampleRate: (started as Success<int>).value);
    } catch (error, stackTrace) {
      await _teardown();
      return Failure(
        ConfigurationFailure(cause: error, stackTrace: stackTrace),
      );
    }
    _running = true;
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> stop() async {
    if (_disposed) {
      return const Failure(AudioFailure(code: FailureCode.audioUnavailable));
    }
    try {
      return await _teardown();
    } catch (error, stackTrace) {
      return Failure(AudioFailure(cause: error, stackTrace: stackTrace));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _teardown();
    } finally {
      await _source.dispose();
      await _observations.close();
    }
  }

  void _handleFrame(PitchPcmFrame frame) {
    if (!_running || _disposed) return;
    final config = _config;
    final detector = _detector;
    if (config == null ||
        detector == null ||
        frame.samples.length < detector.bufferSize) {
      return;
    }
    final rms = _rms(frame.samples);
    final frequency = detector.detect(frame.samples);
    if (frequency == null) {
      _recentFrequencies.clear();
      return;
    }
    final midi = 69 + 12 * (math.log(frequency / 440) / math.ln2);
    final nearestMidi = midi.round();
    final cents = ((midi - nearestMidi) * 100).clamp(-50.0, 50.0).toDouble();
    final latency = _now().difference(frame.capturedAt);
    final isCandidate =
        rms >= config.minimumRms &&
        detector.clarity >= config.minimumClarity &&
        frequency >= config.minimumFrequencyHz &&
        frequency <= config.maximumFrequencyHz &&
        latency <= config.maximumObservationLatency;
    if (!isCandidate) {
      _recentFrequencies.clear();
    } else {
      _recentFrequencies.add(frequency);
      if (_recentFrequencies.length > config.stableFrames) {
        _recentFrequencies.removeAt(0);
      }
    }
    final stable = isCandidate && _isStable(config);
    _observations.add(
      PitchObservation(
        observedAt: frame.capturedAt,
        frequencyHz: frequency,
        midiPitch: nearestMidi,
        centsFromNearest: cents,
        clarity: detector.clarity,
        rms: rms,
        stable: stable,
      ),
    );
  }

  void _handleSourceError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    if (!_observations.isClosed) {
      _observations.addError(
        AudioFailure(cause: error, stackTrace: stackTrace),
        stackTrace,
      );
    }
    unawaited(_teardown());
  }

  Future<AppResult<void>> _teardown() async {
    _running = false;
    _recentFrequencies.clear();
    await _cancelSubscription();
    if (!_sourceRunning) return const Success<void>(null);
    _sourceRunning = false;
    return _source.stop();
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  bool _isStable(PitchObservationConfig config) {
    if (_recentFrequencies.length < config.stableFrames) return false;
    final sorted = List<double>.of(_recentFrequencies)..sort();
    final median = sorted[sorted.length ~/ 2];
    return _recentFrequencies.every((frequency) {
      final cents = 1200 * math.log(frequency / median) / math.ln2;
      return cents.abs() <= config.stabilityCents;
    });
  }

  static double _rms(Float64List samples) {
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples.length);
  }
}
