---
id: 001
topic: Microphone capture → PCM stream on Android/iOS (Flutter)
tags: [mic, pcm, audio_streamer, permission, RECORD_AUDIO, capture, stream]
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

**Buffering:** audio_streamer delivers chunks of a platform-dependent size
(~1700–4096 samples). Never assume chunk size == analysis frame size: push
chunks into a ring buffer and let the DSP pull fixed frames (chunk 010).

**Engine contract:** capture lives INSIDE RealStrumEngine/RealTunerEngine;
`start()` requests permission + subscribes, `stop()` cancels the subscription
(mic released — pause must actually stop capture, see review finding R5#1).
