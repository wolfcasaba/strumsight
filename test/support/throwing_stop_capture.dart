import 'package:strumsight/core/audio/capture/audio_capture.dart';

/// An [AudioCapture] whose `stop()` FAILS the way a real platform stream can.
///
/// This is not a hypothetical: `MicCapture.stop()` has no try/catch around
/// `await capture?.stop()`, and on the device that call is a
/// `StreamSubscription.cancel()` on the `audio_streamer` EventChannel — which
/// throws when the channel is already gone (activity destroyed, plugin
/// detached, the app killed while backgrounding). Everything an engine does
/// AFTER that await is then skipped, so this double is what proves the
/// teardown of the ports, the DSP isolate and the buffered PCM still happens,
/// and that the exclusive microphone lease still comes back (§5, §7).
class ThrowingStopAudioCapture implements AudioCapture {
  ThrowingStopAudioCapture({this.sampleRate = 44100, this.throwOnStop = true});

  final int sampleRate;

  /// Whether the next `stop()` throws. Tests turn it off to prove the engine
  /// RECOVERED rather than merely survived the failure once.
  bool throwOnStop;

  int startCalls = 0;
  int stopCalls = 0;
  bool isRunning = false;

  final List<void Function(List<double> chunk)> _callbackHistory = [];

  /// Every callback handed to a start attempt, newest last.
  List<void Function(List<double> chunk)> get callbackHistory =>
      List.unmodifiable(_callbackHistory);

  @override
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    startCalls++;
    _callbackHistory.add(onChunk);
    isRunning = true;
    return sampleRate;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    // The stream is detached either way — a platform stop that throws has
    // still torn the subscription down, which is why no caller can usefully
    // "retry" it and why the engine must free everything else regardless.
    isRunning = false;
    if (throwOnStop) {
      throw StateError('platform capture stop failed');
    }
  }

  /// Delivers a chunk through the most recent start's callback.
  void emit(List<double> chunk) {
    if (_callbackHistory.isEmpty) return;
    _callbackHistory.last(chunk);
  }
}
