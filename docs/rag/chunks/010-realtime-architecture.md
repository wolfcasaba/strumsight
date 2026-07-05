---
id: 010
topic: Real-time architecture — isolate, ring buffer, dual pipeline, latency/CPU budget
tags: [architecture, isolate, ring buffer, latency, budget, silence gate, pipeline]
sources:
  - https://arxiv.org/html/2508.07973v1
  - https://pub.dev/packages/fftea
---

# Real-time architecture (RealStrumEngine)

```
mic (audio_streamer, main isolate)
  → SendPort → DSP ISOLATE:
      RingBuffer (float64, ~2 s)
      ├─ fast path  : 1024/256  → flux → onset → ±90ms window → direction
      ├─ slow path  : 4096/1024 → chroma (EMA) → chord + confidence
      └─ aggregator : onsets+chord+bpm+level → LiveFrame @ ~15 Hz
  → SendPort → main isolate → StreamController<LiveFrame> (same StrumEngine API)
```

**Isolate is mandatory:** ~170 FFT-1024 + ~43 FFT-4096 per second ≈ well under
10% of one mid-range core in Dart (fftea ~µs-scale for these sizes), but ANY
main-isolate work competes with 60 fps UI — keep DSP off the UI thread.
`Isolate.spawn` once in `start()`; kill in `stop()` (mic must actually release
— review R5#1 rule).

**Ring buffer:** single-writer/single-reader, plain `Float64List` with wrap;
mic chunk sizes vary (chunk 001), frames are pulled at fixed hops.

**Silence gate:** frame RMS < **0.008** (≈ -42 dBFS) → level meter only; no
chroma normalize, no onset, chord decays to null after ~1.5 s of silence.
Tune on-device (phone mics differ); expose in Settings later if needed.

**Latency budget (target <80 ms felt):** mic chunk ~23–46 ms + onset confirm
~12 ms + frame emit ≤66 ms (15 Hz) → arrow lags the strum by roughly one
eighth at 120 BPM in the worst case; acceptable for a mirror, NOT for a game.

**LiveFrame emission:** ~15 Hz timer in the isolate aggregates newest state;
emitting per-DSP-frame (170 Hz) would waste UI rebuilds (review finding #14).

**Determinism for tests:** the DSP classes are PURE (samples in → events out),
isolate-free; the isolate is only plumbing. Tests synthesize PCM (Karplus-
Strong-ish plucks, triads with harmonics) and assert events — same pattern as
the Python plan's ground-truth tests.
