---
id: 023
topic: Decoding imported audio files to PCM (WAV in Dart, everything else on the platform)
tags: [audio, decoding, codec, mediacodec, mediaextractor, platform-channel, pcm, import]
sources:
  - docs/adr/0535-platform-audio-decoder.md
  - lib/core/audio/codec/platform_audio_decoder.dart
  - lib/core/audio/codec/wav_decoder.dart
  - android/app/src/main/kotlin/com/wolfcasaba/strumsight/audio/AudioDecoderChannel.kt
built: 2026-09-17 (K2)
---

# Audio file decoding — AS BUILT

Two paths, one output shape: **mono float32 PCM in `[-1, 1]` + a sample rate**.

| input | decoder | where |
|---|---|---|
| WAV (PCM16 / float32, mono or stereo) | `WavDecoder` / `WavDecoderAdapter` | pure Dart, in-process |
| MP3, AAC, M4A, MP4 soundtrack, OGG, FLAC (+ WAV) | `PlatformAudioDecoder` | Android `MediaExtractor` + `MediaCodec` |

The WAV path is unchanged and still the only one that works with no native
side. `WavDecoder` returns `(List<double>, int)`; the platform path returns the
named `DecodedPcm { sampleRate, samples: Float32List }`, whose `channelCount`
is **always 1**.

## Channel contract — `strumsight/audio_decoder`

`probe(path)` → `{durationMs, sampleRate, channelCount, mime}`; **no frame is
decoded**. `durationMs` is negative when the container declares no duration
(streamed OGG, some FLAC) — callers must not read that as "zero length".

`decodeToPcm(path, targetSampleRate?, maxSeconds?)` →
`{sampleRate, channelCount: 1, frames, pcm}`, where `pcm` is a **Uint8List of
little-endian float32** (4 bytes/frame, half of what a Float64List would cost).

- `targetSampleRate` omitted ⇒ the decoder's own output rate survives, nothing
  is resampled. Given ⇒ linear interpolation on the native side.
- `maxSeconds` **stops the decode early**, it does not fail. Absent, a clip
  longer than 10 minutes is refused with `too_long`.
- Every source channel is averaged into one float per frame.
- Only the FIRST track whose MIME starts with `audio/` is selected — an MP4's
  picture track is never read (guarded by
  `tools/tests/test_k2_audio_decoder_track_filter.py`).
- Work runs on a `HandlerThread`, replies are posted to the main looper.
  Codec and extractor are released in `finally`.

## Failure codes

`no_audio_track` → `audio.no_audio_track` · `unsupported_container` →
`audio.unsupported_container` · `decoder_failed` → `audio.decoder_failed` ·
`file_not_found` → `audio.file_not_found` · `too_long` →
`audio.clip_too_long` · unknown → `audio.decoder_failed`.

Non-Android, or a build where the native side is not registered
(`MissingPluginException`) → **`audio.unsupported_platform`**, and the channel
is never invoked. iOS has no implementation yet.

## Dart-side guards run BEFORE the channel

Order: platform → file exists → `size ≤ 64 MiB` → `probe()` →
`min(probedDuration, maxSeconds) ≤ 10 min`. `AudioDecoderLimits` duplicates
`InputLimits` because `tool/check_architecture.dart` forbids
core → features imports; a cell fails if the two drift apart.

## Not done on purpose

- No decoded-WAV cache: playback uses the ORIGINAL bytes, so one file never has
  two sources of truth.
- No FFI / minimp3 core: the repo has no native C++ core and the platform
  decoder is hardware-backed and free (ADR 0535 §1).
- No manifest permission: SAF paths already grant per-file access.
