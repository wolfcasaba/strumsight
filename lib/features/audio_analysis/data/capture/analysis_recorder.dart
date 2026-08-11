import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../../../core/audio/mic_capture.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/recording_level.dart';
import '../input/input_limits.dart';
import 'recording_run.dart';

/// A V2 microphone recorder which composes the shared [MicCapture] lease.
///
/// It owns only recording-local state. Permission, exclusivity, plugin errors,
/// and app-background revocation remain in [MicCapture] and its coordinator.
final class AnalysisRecorder {
  AnalysisRecorder({
    required this._mic,
    Duration maximumDuration = InputLimits.maxDuration,
    DateTime Function()? now,
    this._runIdGenerator,
  }) : _maximumDuration = maximumDuration,
       _now = now ?? DateTime.now {
    if (_maximumDuration <= Duration.zero) {
      throw ArgumentError.value(maximumDuration, 'maximumDuration');
    }
  }

  static const double clippingOnDbfs = -1.0;
  static const double clippingOffDbfs = -3.0;
  static const int _levelUpdatesPerSecond = 10;
  static const double _thresholdEpsilon = 1e-9;

  final MicCapture _mic;
  final Duration _maximumDuration;
  final DateTime Function() _now;
  final String Function()? _runIdGenerator;
  final List<double> _samples = [];
  final StreamController<RecordingLevel> _levels =
      StreamController<RecordingLevel>.broadcast();

  Future<AppResult<RecordingRun>>? _startInFlight;
  RecordingRun? _currentRun;
  String? _activeRunId;
  int _generatedRunCount = 0;
  int _droppedStaleChunks = 0;
  int _samplesSinceLevel = 0;
  bool _hasEmittedLevel = false;
  bool _isClipping = false;
  bool _disposed = false;

  RecordingRun? get currentRun => _currentRun;
  bool get isRecording => _activeRunId != null;
  int get droppedStaleChunks => _droppedStaleChunks;

  /// PCM captured for the current or last completed run. The view cannot be
  /// changed by a caller, so a completed maximum-length recording is ready for
  /// the later input boundary without a second copy.
  List<double> get samples => UnmodifiableListView(_samples);

  /// Preview updates are calculated at most ten times per recorded second.
  Stream<RecordingLevel> get levels => _levels.stream;

  /// Converts the duration policy into an inclusive sample limit.
  static int maximumSampleCount({
    required int sampleRate,
    Duration maximumDuration = InputLimits.maxDuration,
  }) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    return sampleRate *
        maximumDuration.inMicroseconds ~/
        Duration.microsecondsPerSecond;
  }

  /// Starts a new run, preserving MicCapture's single-flight behavior.
  Future<AppResult<RecordingRun>> start() {
    if (_disposed) {
      throw StateError('AnalysisRecorder has been disposed.');
    }
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final current = _currentRun;
    if (_activeRunId != null && current != null) {
      return Future.value(Success(current));
    }
    return _startInFlight = _start().whenComplete(() => _startInFlight = null);
  }

  Future<AppResult<RecordingRun>> _start() async {
    final runId = _newRunId();
    final started = await _mic.start(
      (chunk) => _acceptChunk(runId, chunk),
      onRevoke: () => _cancelFromRevocation(runId),
    );
    if (started case Failure<int>(:final error)) {
      return Failure(error);
    }

    final sampleRate = (started as Success<int>).value;
    _samples.clear();
    _droppedStaleChunks = 0;
    _samplesSinceLevel = 0;
    _hasEmittedLevel = false;
    _isClipping = false;
    _activeRunId = runId;
    final run = RecordingRun(
      id: runId,
      startedAt: _now(),
      sampleRate: sampleRate,
      status: RecordingRunStatus.recording,
      sampleCount: 0,
    );
    _currentRun = run;
    return Success(run);
  }

  /// Completes an active run and releases MicCapture's coordinator lease.
  Future<RecordingRun?> stop() async {
    final runId = _activeRunId;
    if (runId == null) return _currentRun;
    _complete(runId, RecordingRunStatus.completed);
    await _mic.stop();
    return _currentRun;
  }

  Future<void> _cancelFromRevocation(String runId) async {
    if (_activeRunId != runId) return;
    _complete(runId, RecordingRunStatus.cancelled);
    await _mic.stop();
  }

  void _acceptChunk(String runId, List<double> chunk) {
    final run = _currentRun;
    if (_activeRunId != runId || run == null) {
      _droppedStaleChunks++;
      return;
    }

    final maximumSamples = maximumSampleCount(
      sampleRate: run.sampleRate,
      maximumDuration: _maximumDuration,
    );
    final remaining = maximumSamples - _samples.length;
    if (remaining <= 0) {
      _complete(runId, RecordingRunStatus.maxDurationReached);
      unawaited(_mic.stop());
      return;
    }

    final acceptedCount = math.min(remaining, chunk.length);
    final levelInterval = math.max(1, run.sampleRate ~/ _levelUpdatesPerSecond);
    final emitLevel =
        !_hasEmittedLevel ||
        _samplesSinceLevel + acceptedCount >= levelInterval;
    var peak = 0.0;
    var squareSum = 0.0;
    for (var index = 0; index < acceptedCount; index++) {
      final sample = chunk[index];
      _samples.add(sample);
      if (emitLevel) {
        peak = math.max(peak, sample.abs());
        squareSum += sample * sample;
      }
    }
    _currentRun = run.copyWith(sampleCount: _samples.length);
    if (emitLevel && acceptedCount > 0) {
      _emitLevel(peak: peak, squareSum: squareSum, sampleCount: acceptedCount);
      _samplesSinceLevel = 0;
      _hasEmittedLevel = true;
    } else {
      _samplesSinceLevel += acceptedCount;
    }

    if (chunk.length >= remaining) {
      _complete(runId, RecordingRunStatus.maxDurationReached);
      unawaited(_mic.stop());
    }
  }

  void _emitLevel({
    required double peak,
    required double squareSum,
    required int sampleCount,
  }) {
    final peakDbfs = _toDbfs(peak);
    if (!_isClipping && peakDbfs >= clippingOnDbfs - _thresholdEpsilon) {
      _isClipping = true;
    } else if (_isClipping && peakDbfs <= clippingOffDbfs + _thresholdEpsilon) {
      _isClipping = false;
    }
    _levels.add(
      RecordingLevel(
        peakDbfs: peakDbfs,
        rmsDbfs: _toDbfs(math.sqrt(squareSum / sampleCount)),
        isClipping: _isClipping,
      ),
    );
  }

  void _complete(String runId, RecordingRunStatus status) {
    if (_activeRunId != runId) return;
    _activeRunId = null;
    final run = _currentRun;
    if (run != null) {
      _currentRun = run.copyWith(status: status, sampleCount: _samples.length);
    }
  }

  String _newRunId() =>
      _runIdGenerator?.call() ??
      'recording-${_now().microsecondsSinceEpoch}-${++_generatedRunCount}';

  static double _toDbfs(double amplitude) => amplitude == 0
      ? double.negativeInfinity
      : 20 * math.log(amplitude) / math.ln10;

  /// Releases the mic and closes the level stream.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _levels.close();
  }
}
