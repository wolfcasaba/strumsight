import 'package:strumsight/core/audio/capture/audio_capture.dart';

/// An [AudioCapture] whose `stop()` takes real asynchronous time, the way a
/// platform audio stream does.
///
/// [FakeAudioCapture] stops within a microtask, which hides every engine
/// restart race: by the time the next `start()` asks the coordinator for the
/// session, the previous lease has already been given back. On a device the
/// platform channel round-trip is not free, so a `stop()` that is still in
/// flight is exactly the window in which a restart (an A4 change, a
/// `ref.invalidate`) lands.
class SlowStoppingAudioCapture implements AudioCapture {
  SlowStoppingAudioCapture({
    this.sampleRate = 44100,
    this.stopDelay = const Duration(milliseconds: 20),
  });

  final int sampleRate;

  /// How long the platform takes to close the stream (and therefore how long
  /// the microphone lease stays held after `stop()` was called).
  final Duration stopDelay;

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
    await Future<void>.delayed(stopDelay);
    isRunning = false;
  }

  /// Delivers a chunk through the most recent start's callback.
  void emit(List<double> chunk) {
    if (_callbackHistory.isEmpty) return;
    _callbackHistory.last(chunk);
  }
}
