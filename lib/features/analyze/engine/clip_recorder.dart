import '../../../core/audio/mic_capture.dart';

/// How a recording attempt started (round 99 — a busy mic is NOT a denied
/// permission; the UI copy and the recovery differ).
enum MicStart { ok, denied, failed }

/// Records the microphone into an in-memory PCM buffer for offline analysis.
/// Reuses the same [MicCapture] the Live/Tuner engines use.
class ClipRecorder {
  /// [ensurePermission] is injectable for tests; defaults to the real check.
  ClipRecorder({Future<bool> Function()? ensurePermission})
      : _ensurePermission = ensurePermission ?? MicCapture.ensurePermission;

  final Future<bool> Function() _ensurePermission;
  final MicCapture _mic = MicCapture();
  final List<double> _buffer = [];
  int _sampleRate = 44100;
  bool _recording = false;
  Future<MicStart>? _inFlight;

  int get sampleRate => _sampleRate;
  int get sampleCount => _buffer.length;
  bool get isRecording => _recording;

  /// Elapsed recorded seconds (based on captured samples).
  double get elapsedSec => _sampleRate > 0 ? _buffer.length / _sampleRate : 0;

  /// Begin recording. A start FAILURE (busy mic / platform error) surfaces
  /// as [MicStart.failed] instead of throwing out of the button handler —
  /// and must never leave [_recording] stuck true (round 99, parity with the
  /// Live round-13 / Tuner round-68 fixes). SINGLE-FLIGHT: a second call
  /// while a start is awaiting joins the in-flight attempt instead of
  /// running a second mic start that would orphan the first subscription
  /// (round 101, review NOTE).
  Future<MicStart> start() {
    if (_recording) return Future.value(MicStart.ok);
    return _inFlight ??= _doStart().whenComplete(() => _inFlight = null);
  }

  Future<MicStart> _doStart() async {
    if (!await _ensurePermission()) return MicStart.denied;
    _buffer.clear();
    try {
      _sampleRate = await _mic.start((chunk) {
        if (_recording) _buffer.addAll(chunk);
      });
    } catch (_) {
      await _mic.stop();
      return MicStart.failed;
    }
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
