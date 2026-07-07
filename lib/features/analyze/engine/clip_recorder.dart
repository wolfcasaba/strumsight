import '../../../core/audio/mic_capture.dart';

/// Records the microphone into an in-memory PCM buffer for offline analysis.
/// Reuses the same [MicCapture] the Live/Tuner engines use.
class ClipRecorder {
  final MicCapture _mic = MicCapture();
  final List<double> _buffer = [];
  int _sampleRate = 44100;
  bool _recording = false;

  int get sampleRate => _sampleRate;
  int get sampleCount => _buffer.length;
  bool get isRecording => _recording;

  /// Elapsed recorded seconds (based on captured samples).
  double get elapsedSec => _sampleRate > 0 ? _buffer.length / _sampleRate : 0;

  /// Begin recording. Returns false if mic permission was denied.
  Future<bool> start() async {
    if (_recording) return true;
    if (!await MicCapture.ensurePermission()) return false;
    _buffer.clear();
    _recording = true;
    _sampleRate = await _mic.start((chunk) {
      if (_recording) _buffer.addAll(chunk);
    });
    return true;
  }

  /// Stop and return a copy of the captured PCM (mono, -1..1).
  Future<List<double>> stop() async {
    _recording = false;
    await _mic.stop();
    return List<double>.of(_buffer);
  }
}
