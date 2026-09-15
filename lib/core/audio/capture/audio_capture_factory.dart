import 'dart:async';
import 'dart:typed_data';

import 'package:audio_streamer/audio_streamer.dart';

import 'audio_capture.dart';

/// Creates a fresh [AudioCapture]. One capture object per session — a stopped
/// one is never reused, so a cancelled subscription can never be resurrected.
typedef AudioCaptureFactory = AudioCapture Function();

/// The real capture, backed by `audio_streamer` (RAG chunk 001).
///
/// **Capture buffer size is NOT configurable in audio_streamer 4.3.0** (D4,
/// read off the pinned plugin source in the pub cache, not guessed):
///
/// * the Dart API sends exactly one argument to the platform side —
///   `receiveBroadcastStream({"sampleRate": sampleRate})`; there is no buffer
///   or chunk-size parameter to pass;
/// * Android (`AudioStreamerPlugin.kt`) hard-codes `bufferSize = 6400 * 2`
///   bytes and blocks in `AudioRecord.read(ShortArray(6400), 0, 6400)`, so it
///   delivers **6400 samples per chunk ≈ 145 ms @ 44.1 kHz / 133 ms @ 48 kHz**,
///   independent of the requested rate;
/// * iOS (`SwiftAudioStreamerPlugin.swift`) hard-codes
///   `installTap(onBus:bufferSize: 22050, …)` — a hint AVAudioEngine may round,
///   but again a plugin constant with no Dart-side knob.
///
/// So the 512–1024 sample (12–23 ms) capture buffer this round targeted cannot
/// be *requested*: it needs a plugin change (fork / upstream PR to thread a
/// `bufferSize` argument through the event-channel map, or a different capture
/// package). Nothing here pretends otherwise — the honest number is in the
/// chunk-010 latency budget. The one supported lever, requesting 48 kHz so the
/// fixed 6400-sample chunk spans ~12 ms less wall time, is deliberately NOT
/// taken here: it would re-scale every window duration in the DSP (a 16384
/// NNLS window drops 371 ms → 341 ms) and every threshold tuned on real audio,
/// which is a measured round of its own, not a latency micro-fix.
///
/// The safe fallback that IS already in place: [start] returns the device's
/// ACTUAL sample rate and every DSP constant is sample-count based, so the
/// pipeline stays correct whatever the platform decides to hand back.
final class AudioStreamerCapture implements AudioCapture {
  AudioStreamerCapture({this.requestedSampleRate = 44100});

  final int requestedSampleRate;

  StreamSubscription<List<double>>? _sub;

  @override
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    final streamer = AudioStreamer();
    streamer.sampleRate = requestedSampleRate;
    _sub = streamer.audioStream.listen((chunk) => onChunk(_normalize(chunk)));
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

/// Normalizes a delivered chunk to a [Float64List] ONCE, at the single
/// mic → app boundary (D4).
///
/// `audio_streamer` hands out `(platformList as List<dynamic>).cast<double>()`
/// — a lazy cast VIEW over boxed doubles, so every later read pays a type
/// check and an unbox. That list then crosses three more hops per chunk: the
/// Lab ring buffer, the DSP isolate `SendPort` (which copies a plain list
/// element-by-element, but ships typed data as a block), and `SlidingFramer`'s
/// `setRange`. Converting here turns all three into typed copies for the cost
/// of one allocation the mic path was already paying inside the framer.
Float64List _normalize(List<double> chunk) =>
    chunk is Float64List ? chunk : Float64List.fromList(chunk);

/// The production factory.
AudioCapture createPlatformAudioCapture() => AudioStreamerCapture();
