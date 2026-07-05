---
id: 002
topic: FFT / STFT / windowing in pure Dart (fftea)
tags: [fft, stft, hann, window, hop, fftea, spectrum, magnitude]
sources:
  - https://pub.dev/packages/fftea
  - https://www.audiolabs-erlangen.de/resources/MIR/FMP/C5/C5S2_ChordRec_Templates.html
---

# FFT / STFT

**Package: `fftea` 1.5.x** (Apache-2.0, 160/160 pub points). Pure Dart, fast
(composite-size FFT). Use `FFT(n)` + `realFft(Float64List)` → `Float64x2List`
complex output; magnitude of bin k = `sqrt(re²+im²)`. Only bins `0..n/2` are
meaningful for real input.

**Two analysis rates** (dual pipeline, chunk 010):

| purpose | window | hop | @44.1 kHz | rationale |
|---------|--------|-----|-----------|-----------|
| chroma/chord | 4096 | 1024 | 93 ms / 23 ms | ~10.8 Hz bin width resolves E2=82.4 Hz from B2=123.5 Hz; chords change slowly |
| onset/direction envelope | 1024 | 256 | 23 ms / 5.8 ms | time precision for strum transients and sub-band rise order |

At 48 kHz actual rate keep the SAME sample counts (windows shrink ~8% in time —
fine); bin→Hz mapping must use the actual rate: `f_k = k * sr / n`.

**Window function: Hann**, `w[i] = 0.5 - 0.5*cos(2πi/(N-1))`. Apply before FFT
to stop spectral leakage smearing chroma. Precompute once per size.

**Gotchas:**
- fftea's `realFft` output length is n/2 (packed); index carefully — verify
  with a unit test: FFT of a pure 440 Hz sine must peak at bin `round(440*n/sr)`.
- Reuse FFT objects and scratch buffers — no per-frame allocation in the hot
  path (GC pauses = dropped frames).
