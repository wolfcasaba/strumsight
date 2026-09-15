---
id: 001
topic: Microphone capture → PCM stream on Android/iOS (Flutter)
tags: [mic, pcm, audio_streamer, permission, RECORD_AUDIO, capture, stream, buffer, chunk size, latency]
sources:
  - https://pub.dev/packages/audio_streamer
  - https://pub.dev/packages/permission_handler
---

# Mic capture → PCM

**Package: `audio_streamer` 4.3.x** (MIT, verified publisher cachet.dk).
Streams PCM as `Stream<List<double>>` (samples already normalized -1.0..1.0),
mono. Request the sampling rate via `AudioStreamer().sampleRate = 44100;` but
ALWAYS read back `await AudioStreamer().actualSampleRate` — Android devices may
deliver a different rate (48000 is common); all DSP must use the actual rate.

- Deliberately NOT `mic_stream` (GPL-3.0 — licence contamination for a public
  MIT-style repo) and NOT `flutter_recorder` (heavier miniaudio backend; we
  only need raw PCM).

**Permissions:**
- `permission_handler` (baseflow): `await Permission.microphone.request()`
  before starting; handle `denied` / `permanentlyDenied` (show a rationale and
  an "open settings" affordance — never a silent no-op).
- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`
  in `android/app/src/main/AndroidManifest.xml`.
- iOS: `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`.

**Buffering — the chunk size is a HARD-CODED plugin constant, not a knob**
(D4; read off the pinned 4.3.0 source in the pub cache, not estimated). The
Dart API sends exactly one argument to the platform side —
`receiveBroadcastStream({"sampleRate": sampleRate})` — so there is nothing to
pass a buffer size in:

| platform | plugin code | chunk | ms @44.1 kHz |
|---|---|---|---|
| Android | `bufferSize = 6400 * 2` bytes, loop blocks in `AudioRecord.read(ShortArray(6400), 0, 6400)` | 6400 samples | 145.1 |
| iOS | `installTap(onBus:bufferSize: 22050, format:)` — a hint AVAudioEngine may round | ≤22050 samples | ≤500 |

Android's chunk is a fixed sample COUNT, so it is rate-independent: requesting
48 kHz shortens it to ~133 ms, the only Dart-side lever that exists — and not a
free one, since it re-scales every DSP window duration (a 16384 NNLS window
drops 371 ms → 341 ms) and every threshold tuned on real audio. The earlier
"~1700–4096 samples" figure in this chunk was an estimate and is WRONG for
4.3.0. Getting to the 512–1024 samples (12–23 ms) the DSP would like needs a
plugin fork / upstream PR threading a `bufferSize` through the event-channel
argument map, or a different capture package. Composed cost: chunk 010.

Never assume chunk size == analysis frame size: push chunks into a ring buffer
and let the DSP pull fixed frames (chunk 010). `AudioStreamerCapture`
normalizes each delivered chunk to a `Float64List` ONCE at that boundary — the
plugin hands out a lazy `cast<double>()` view over boxed doubles, and every
later hop (Lab ring buffer, isolate `SendPort`, `SlidingFramer`) would
otherwise pay per-sample unboxing.

**Engine contract:** capture lives INSIDE RealStrumEngine/RealTunerEngine;
`start()` requests permission + subscribes, `stop()` cancels the subscription
(mic released — pause must actually stop capture, see review finding R5#1).
