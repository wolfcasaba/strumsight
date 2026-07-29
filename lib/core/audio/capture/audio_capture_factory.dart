import 'dart:async';

import 'package:audio_streamer/audio_streamer.dart';

import 'audio_capture.dart';

/// Creates a fresh [AudioCapture]. One capture object per session — a stopped
/// one is never reused, so a cancelled subscription can never be resurrected.
typedef AudioCaptureFactory = AudioCapture Function();

/// The real capture, backed by `audio_streamer` (RAG chunk 001).
final class AudioStreamerCapture implements AudioCapture {
  AudioStreamerCapture({this.requestedSampleRate = 44100});

  final int requestedSampleRate;

  StreamSubscription<List<double>>? _sub;

  @override
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    final streamer = AudioStreamer();
    streamer.sampleRate = requestedSampleRate;
    _sub = streamer.audioStream.listen(onChunk);
    return streamer.actualSampleRate;
  }

  @override
  Future<void> stop() async {
    // Only null the field if it still points at the subscription WE are
    // cancelling — a start() racing this await may already have installed a
    // new one, and blindly nulling would orphan it live (round 114).
    final sub = _sub;
    await sub?.cancel();
    if (identical(_sub, sub)) _sub = null;
  }
}

/// The production factory.
AudioCapture createPlatformAudioCapture() => AudioStreamerCapture();
