import '../../../core/audio/mic_capture.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';

/// How a recording attempt started (round 99 — a busy mic is NOT a denied
/// permission; the UI copy and the recovery differ).
enum MicStart { ok, denied, failed }

/// Records the microphone into an in-memory PCM buffer for offline analysis.
/// Holds an `analyzeRecorder` lease on the one shared microphone session.
class ClipRecorder {
  ClipRecorder({required this._mic});

  final MicCapture _mic;
  final List<double> _buffer = [];
  int _sampleRate = 44100;
  bool _recording = false;

  int get sampleRate => _sampleRate;
  int get sampleCount => _buffer.length;
  bool get isRecording => _recording;

  /// Elapsed recorded seconds (based on captured samples).
  double get elapsedSec => _sampleRate > 0 ? _buffer.length / _sampleRate : 0;

  /// Begin recording. A start FAILURE (busy mic / platform error) surfaces
  /// as [MicStart.failed] instead of throwing out of the button handler —
  /// and must never leave [_recording] stuck true (round 99, parity with the
  /// Live round-13 / Tuner round-68 fixes). The single-flight guarantee that
  /// used to live here now lives in [MicCapture.start], so an overlapping
  /// call joins the same attempt instead of opening a second capture
  /// (round 101).
  Future<MicStart> start() async {
    if (_recording) return MicStart.ok;
    _buffer.clear();
    final started = await _mic.start((chunk) {
      if (_recording) _buffer.addAll(chunk);
    });
    return switch (started) {
      Success<int>(:final value) => _begin(value),
      Failure<int>(error: PermissionFailure()) => MicStart.denied,
      Failure<int>() => MicStart.failed,
    };
  }

  MicStart _begin(int sampleRate) {
    _sampleRate = sampleRate;
    _recording = true;
    return MicStart.ok;
  }

  /// Stop and return a copy of the captured PCM (mono, -1..1).
  Future<List<double>> stop() async {
    _recording = false;
    await _mic.stop();
    return List<double>.of(_buffer);
  }
}
