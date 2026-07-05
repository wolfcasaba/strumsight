import 'dart:async';

import 'package:audio_streamer/audio_streamer.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around the mic PCM stream + runtime permission (RAG chunk
/// 001). Both real engines share it; stop() actually releases the microphone.
class MicCapture {
  StreamSubscription<List<double>>? _sub;

  /// Whether mic permission is granted, requesting it if needed. Returns true
  /// in environments without the platform channel (tests, desktop dev).
  static Future<bool> ensurePermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;
      final result = await Permission.microphone.request();
      return result.isGranted;
    } catch (_) {
      return true; // no platform channel (tests) — treat as granted
    }
  }

  /// Start streaming; [onChunk] receives PCM chunks (-1..1, mono). Returns the
  /// ACTUAL sample rate (may differ from the requested 44.1 kHz — chunk 001).
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    final streamer = AudioStreamer();
    streamer.sampleRate = 44100;
    _sub = streamer.audioStream.listen(onChunk);
    return streamer.actualSampleRate;
  }

  /// Stop streaming and release the microphone.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
