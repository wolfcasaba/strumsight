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

## Latency budget — MEASURED (D4), target <80 ms felt

The synthetic probe `test/features/live/engine/capture_latency_probe_test.dart`
feeds a strum whose attack is at a KNOWN sample into `LivePipeline` in fixed
chunks and records how far the feed cursor has advanced when the carrying
`LiveFrame` comes out. Feed position IS wall time for a real capture (a chunk
exists only once its last sample was captured), so these are honest in-app
latencies; the platform's own input latency sits on top and is not observable
from Dart. All figures @44.1 kHz.

| hop | samples | ms | source |
|---|---|---|---|
| mic chunk — Android | 6400 | 0–**145.1** | `audio_streamer` 4.3.0 hard-codes `bufferSize = 6400*2` bytes (chunk 001); a verdict waits for the chunk that completes its frame |
| mic chunk — iOS | 22050 | 0–500.0 | hard-coded `installTap(bufferSize: 22050)` (a hint AVAudioEngine may round) |
| isolate `SendPort` hop | — | not measured | typed-data copy; normalized to `Float64List` at the capture boundary so it ships as a block |
| onset confirm | 896 | **20.3** | `onsetWindow` 1024 + SuperFlux `_postFrames` 2 hops − the r144 −2.5-hop attack offset |
| direction (classify) window | 3456 | **78.4** | `onsetWindow` 1024 + `StrumAnalyzer._classifyAfterFrames` 12 hops @ `onsetHop` 256, minus the same offset |
| chord (NNLS) window | 16384 | 371.4 | `nnlsWindow`/`nnlsHop` = 16384/4096 — the slow path, by design (chunk 011/016) |
| frame emit cadence | 2910 | ≤66 | **0 ms for onset/direction**: `addChunk` emits IMMEDIATELY on either, so the cadence only bounds level/chord refresh |

**Composed** (worst case = the attack landing just after a chunk boundary, i.e.
`(fixed + chunk) / rate`; the probe's own numbers, printed on every run, are for
one fixed attack phase and sit inside these):

| mic chunk | onset-first (strings react) | direction arrow |
|---|---|---|
| 512 (11.6 ms) — the target | 31.9 ms | 90.0 ms |
| 1024 (23.2 ms) — the target | 43.5 ms | 101.6 ms |
| 4096 (92.9 ms) | 113.2 ms | 171.2 ms |
| **6400 (145.1 ms) — Android today** | **165.4 ms** | **223.5 ms** |
| 22050 (500 ms) — iOS tap request | 520.3 ms | 578.4 ms |

**Verdict:** the <80 ms target is met by the DSP path alone (20 ms onset-first,
78 ms direction) and is MISSED on-device purely because of the capture buffer —
145 of the 165 ms a user waits for the strings to react is the mic chunk. The
arrow lags the strum by roughly an eighth at 120 BPM: acceptable for a mirror,
NOT for a game. The buffer is a hard-coded plugin constant with no Dart-side
knob (chunk 001), so the only lever is a plugin fork/PR or a different capture
package — not a DSP retune, and not the 48 kHz request either (that saves ~12 ms
but re-scales every window duration and every threshold tuned on real audio).

**LiveFrame emission:** ~15 Hz timer in the isolate aggregates newest state;
emitting per-DSP-frame (170 Hz) would waste UI rebuilds (review finding #14).

**Determinism for tests:** the DSP classes are PURE (samples in → events out),
isolate-free; the isolate is only plumbing. Tests synthesize PCM (Karplus-
Strong-ish plucks, triads with harmonics) and assert events — same pattern as
the Python plan's ground-truth tests.
