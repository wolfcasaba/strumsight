---
id: 009
topic: Dart/Flutter package selection for the real engine (+licences)
tags: [packages, fftea, audio_streamer, permission_handler, licence, pubspec]
sources:
  - https://pub.dev/packages/fftea
  - https://pub.dev/packages/audio_streamer
  - https://pub.dev/packages/permission_handler
---

# Package decisions (v0.2.0 real engine)

| need | package | version | licence | why |
|------|---------|---------|---------|-----|
| FFT/STFT | `fftea` | ^1.5.0 | Apache-2.0 | pure Dart, 160/160 points, any-size FFT, fast |
| mic PCM stream | `audio_streamer` | ^4.3.0 | MIT | verified publisher (cachet.dk), `Stream<List<double>>`, Android+iOS, actualSampleRate API |
| mic permission | `permission_handler` | ^12.0.0 | MIT | de-facto standard (baseflow) |

**Rejected:**
- `mic_stream` — **GPL-3.0**: would contaminate the public repo's licencing.
- `flutter_recorder` (miniaudio FFI) — heavier native backend; we need raw PCM
  only, and pure-Dart DSP keeps the build CI-simple (no NDK).
- `open_dspc` (native C FFI DSP) — capability overlap but tiny adoption (1
  like); fftea is the safer core. Reconsider only if Dart perf fails (chunk 010
  has the budget math — it shouldn't).

**Why pure Dart before C++/aubio:** the same algorithms, no NDK/CI complexity,
unit-testable on the dev box with synthesized PCM, and the CPU budget fits
(chunk 010). The C++/FFI port stays the optimization path if profiling on a
real device shows misses.
