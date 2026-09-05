---
id: live-signal-quality
topic: Live-side streaming signal-quality analyzer thresholds and hysteresis
tags: [live, dsp, signal-quality, hysteresis, dbfs, tonalness, cpu-budget]
sources:
  - docs/rounds/e14-r05-live-signal-quality-analyzer.md
  - docs/adr/0507-live-signal-quality-analyzer-reuse-route-and-hysteresis.md
  - docs/rag/chunks/019-signal-quality-metrics.md (the reused formulas)
built: 2026-09-04 (E14-R05)
---

# Live signal-quality analyzer — AS BUILT

`LiveSignalQualityAnalyzer` (`lib/features/live/engine/quality/`) fills the
`SignalQualitySnapshot` contract (E14-R04) on the Live streaming path. It
reuses the exact `SignalQualityMath` primitives that the batch (Analyze)
signal-quality stage uses — `peakDbfs`, `rmsDbfs`, `clippedSampleRatio`,
`noiseFloorDbfsForFrames`, `tonalness` — via the
`package:strumsight/features/audio_analysis/public.dart` barrel (ADR 0507
D1). **No DSP math is reimplemented here.** Only the orchestration (blocking,
rolling history, throttling, hysteresis) and the numeric thresholds below are
new — including a small nearest-rank-percentile helper that reuses
already-computed `rmsDbfs` values instead of letting
`noiseFloorDbfsForFrames` recompute them (see "Avoiding redundant
recomputation" below), and a fixed-size `Float64List` block accumulator in
place of the general-purpose `SlidingFramer` (this analyzer only ever needs
non-overlapping blocks).

## Why a separate `LiveQualityThresholds` (ADR 0507 D3)

The batch stage classifies pre-recorded clips using fixed 2048/1024-sample
(50%-overlap) analysis frames baked into `signal_quality_math.dart` itself
(not injectable — the per-sample clip threshold `0.999` and `silentSampleDbfs
= -60` also live there, fixed). The Live analyzer computes its rolling
statistics (`silentRatio`, `noiseFloorDbfs`) directly from its OWN block
granularity instead. The batch `QualityThresholds.standard` values are never
modified; the Live-specific numbers below live in their own versioned class.

## Block framing and the CPU-cost story (acceptance 5.)

| Name | Value | Reasoning |
| --- | ---: | --- |
| `frameSize` / `frameHop` | 4096 / 4096 samples | Non-overlapping (~93 ms @44.1 kHz). |
| `historyBlocks` | 4 | ~372 ms rolling window for `silentRatio`/`noiseFloorDbfs`/stability; also the buffer-fill gate for leaving `unknown` (ADR 0507 D5). |
| `statsStride` | 64 | Recompute EVERY metric — including the "cheap" per-block `peakDbfs`/`rmsDbfs`/`clippedSampleRatio` — only every 64th block (~5.95 s cadence), caching between updates. MEASURED necessary: even calling only these three primitives on every block, summed over a whole stream, measured ~5–7% of the pipeline's total per-block time on its own (isolated-analyzer benchmark, `historyStatsStride`/`tonalnessStride` both disabled: ~14 ms / 8 s clip vs a ~285–305 ms full-pipeline baseline). A live quality indicator does not need sub-block reaction time; nothing in this round's acceptance criteria requires it. |
| `tonalnessStride` | 4 | Gates a SECOND time on top of `statsStride` (effective cadence = `lcm(statsStride, tonalnessStride)`; with 4 dividing 64 this is simply every `statsStride` blocks — `tonalness` never runs MORE often than the other stats, only at most as often). |
| `tonalnessWindowSamples` | 4096 | The tail of the rolling history fed to `tonalness`, spanning 2 internal 2048-sample analysis frames instead of 1 — a single-frame snapshot measured UNRELIABLE on envelope-modulated audio (see "The speechLike phase-alignment bug" below). |

**Both throttles gate a CACHE, never the first computation** — the analyzer
tracks `_statsComputedOnce` / `_tonalnessComputedOnce` and forces the very
first post-buffer-fill computation regardless of the stride, specifically so
a buffer size that doesn't divide evenly into the stride can never leave a
metric at a fabricated `0` (ADR 0507 D6).

### CPU-cost measurement (median of 3 runs, same synthetic 8 s clip)

Command (temporarily toggling the one call site,
`lib/features/live/engine/dsp/live_pipeline.dart:185`,
`_signalQuality.addChunk(chunk);`, commented out vs active — this line is the
brief §7.1 falsification-style A/B, not a shipped flag):

```
flutter test <scratch bench file feeding an 8 s synthetic chord-like PCM
  through LivePipeline.addChunk in 1024-sample chunks, 2 discarded JIT
  warm-up runs then 3 measured runs, Stopwatch.elapsedMilliseconds>
```

Final back-to-back pair (`statsStride: 64`, `tonalnessStride: 4`,
`frameSize: 4096`, accumulator-based collector):

```
WITHOUT (_signalQuality.addChunk commented out): 304 ms, 305 ms, 293 ms → median 304 ms
WITH    (_signalQuality.addChunk active):        307 ms, 308 ms, 305 ms → median 307 ms
overhead = (307 − 304) / 304 ≈ 1.0%
```

This box is measured slow and noisy (`CLAUDE.md` build gotchas) and `flutter
test` runs on the JIT VM, not an AOT release build — repeated measurement
rounds during tuning swung ±5–10 ms run-to-run even with identical code. Two
optimizations got the overhead from the initial (correct but naive)
implementation's **~70%** down into this range, in order:

1. **Eliminated redundant recomputation** — the naive rolling-window stats
   called `SignalQualityMath.rmsDbfs` up to 3× per history frame per block
   (once directly, once inside `isSilentFrame`, once inside
   `noiseFloorDbfsForFrames`). `rmsDbfs` is now computed EXACTLY once per
   history block per stats update and reused for all three; `isSilentFrame`'s
   `<= silentSampleDbfs` comparison and `noiseFloorDbfsForFrames`'s
   nearest-rank 10th-percentile stay the exact same formulas (via
   `QualityThresholds.standard.silentSampleDbfs`), just applied to the
   already-known values instead of re-deriving them.
2. **Throttled the per-block level metrics too, and swapped `SlidingFramer`
   for a fixed `Float64List` accumulator** — `peakDbfs`/`rmsDbfs`/
   `clippedSampleRatio` moved under `statsStride` alongside the
   history-window stats (previously "never throttled" by design, until
   measurement showed that alone exceeded budget), and the general-purpose
   `SlidingFramer` (a growable, boxed `List<double>` — needed for the
   overlapping-window case elsewhere in Live, not needed here since
   `frameHop == frameSize` always) was replaced with a plain indexed
   `Float64List` accumulator local to this class. This is the "Live-oldali
   gyűjtő" (Live-side collector) the round brief asks this class to build —
   mechanical buffering, not DSP math, so it is NOT a D1 violation.

**Falsification of the naive approach** (kept as measured history, not
shipped): an EARLIER, per-block-unthrottled-level-metrics + `SlidingFramer`
version measured **~70% overhead** on the same 8 s clip/methodology before
any of the above were applied — the naive version is what a first-pass
implementation looks like, and it is exactly what the CPU-cost acceptance
cell (brief §6.1 row 6, "az elemző a per-frame forró úton FFT-t futtat minden
blokkra") is designed to catch, generalized here to the level metrics too.

### The `speechLike` phase-alignment bug (caught during tuning)

An earlier iteration computed `tonalness` from a single 2048-sample tail
slice of the LATEST block only. With `tonalnessStride` large enough for the
CPU budget, that single slice could land in a near-silent trough of the
`speechLike` fixture's ~6 Hz amplitude envelope by pure chance, misreading it
as `tooNoisy`. Widening `tonalnessWindowSamples` to span 2 internal analysis
frames (4096 samples ≈ 93 ms, drawn from the rolling history via
`_tailSamples`, not just the latest block) fixed it — confirmed against the
fixture-matrix test. This is the acceptance-1/acceptance-5 tension the round
brief's own mátrix table (row 6) predicted: a real risk, resolved by widening
the window rather than by shortening the stride (which would have blown the
CPU budget again).

### Latency trade-off (disclosed, not hidden)

At `statsStride = 64` and `frameSize = 4096`, a genuinely NEW quality problem
(say the player starts clipping) takes up to ~5.95 s to be reflected in
`LivePipeline.signalQuality` in the worst case. This round ships the analyzer
and the pipeline-side measurement ONLY (brief §1: "nem UI-t") — no screen
reads this snapshot yet. Whichever future round wires it into the UI should
re-examine this cadence against real UX needs and, if faster reaction is
required, revisit this trade-off with a real-device (AOT) profile rather than
this box's noisy JIT `flutter test` measurement.

## State thresholds — calibrated against `SignalQualityMath` on synthetic PCM

Measured directly against the real `SignalQualityMath` functions (not
guessed), 8192-sample buffers, 44.1 kHz:

| Fixture | peakDbfs | rmsDbfs | clip ratio | tonalness | block-RMS stdDev |
| --- | ---: | ---: | ---: | ---: | ---: |
| silence | -120.0 | -120.0 | 0 | 0.000 | — |
| quiet sine (amp 0.01) | -40.0 | -43.0 | 0 | 1.000 | 0.06 (steady) |
| normal sine (amp 0.3, "good") | -10.5 | -13.5 | 0 | 1.000 | 0.06 |
| loud sine (amp 0.9, "tooLoud") | -0.9 | -3.9 | 0 | 1.000 | — |
| hard-clipped square | 0.0 | 0.0 | 1.0000 | 0.633 | — |
| white noise (amp 0.3, "tooNoisy") | -10.5 | -15.3 | 0 | 0.154 | 0.08 (steady) |
| speech-like (AM formant mix, "speechLike") | -3.8 | -14.6 | 0 | 0.350 | 6.08 |
| unstable bursts (0.7 → silence → 0.05 → 0.8@900 Hz) | -1.9 | -8.5 | 0 | 0.788 | 47.16 |
| 6-tone chord proxy (open strings) | -12.3 | -21.2 | 0 | 1.000 | 0.48 |

From these measurements:

| Name | Value | Reasoning |
| --- | ---: | --- |
| `quietRmsDbfs` | -40.0 dBFS | Between "good" (-13.5) and the quiet-sine fixture (-43.0), well above the batch `silenceFloorDbfs` (-120) so it fires on a genuinely weak signal, not only dead silence. |
| `loudPeakDbfs` | -2.0 dBFS | Between "good" (-10.5) and the loud-sine fixture (-0.9); clipping is checked first so this only fires on headroom concerns short of hard clipping. |
| `clippedRatioThreshold` | 0.001 | Reused verbatim from `QualityThresholds.standard.clippedRatioWarning` (`019-signal-quality-metrics.md`) — inclusive on the clipping side, same notation as the batch warning. |
| `unstableRmsStdDevDb` | 15.0 dB | Between speech's natural envelope variation (6.08, must NOT trip this) and the unstable-burst fixture (47.16); steady tonal/noise signals sit at ≤0.08. |
| `noisyTonalnessMax` | 0.25 | Below white noise (0.154, must trip) and below speech (0.350, must NOT trip). |
| `speechTonalnessMax` | 0.5 | Above speech (0.350, must trip) and below every tonal fixture measured (sine 1.000, 6-tone chord proxy 1.000) — the chord proxy is checked specifically so a real multi-harmonic strum, not just a pure sine, still reads as `good`. |

## Classification priority (highest first)

1. **`clipping`** — `clippedSampleRatio >= clippedRatioThreshold`. Always
   worth flagging regardless of anything else.
2. **`unstable`** — stdDev of the last `historyBlocks` block-RMS values (dB)
   `>= unstableRmsStdDevDb`. Checked before quiet/loud because a wildly
   swinging level makes those two judgements unreliable for the current
   block.
3. **`tooQuiet`** — `rmsDbfs <= quietRmsDbfs`.
4. **`tooLoud`** — `peakDbfs >= loudPeakDbfs` (clipping already excluded).
5. **`tooNoisy`** — `tonalness <= noisyTonalnessMax`.
6. **`speechLike`** — `noisyTonalnessMax < tonalness <= speechTonalnessMax`.
7. **`good`** — everything else.

`unknown` is not part of this list: it is the state before `historyBlocks`
blocks have been seen (or after `reset()`), never derived from a
classification (ADR 0507 D5).

## Hysteresis (ADR 0507 D4)

- `enterFrames = 5` — consecutive identical raw classifications required to
  confirm a transition INTO any non-`good` state (fast attack).
- `exitFrames = 8` — consecutive identical raw `good` classifications
  required to confirm a transition INTO `good` (slow release). This is also
  what gates the very first `unknown` → `good` confirmation once the buffer
  fills (ADR 0507 D5 — `good` is never a silent default).
- The two counters are the ONLY anti-flicker mechanism. Thresholds are never
  widened to fight oscillation (ADR 0507 D4, brief §5.3).

## `speechLike` — the risk call (ADR 0507 D7, brief §9)

`speechLike` is a **spectral tonalness band only** (`(0.25, 0.5]` on the
Live `tonalness` proxy), never a speaker/source classifier. The synthetic
speech-like fixture (slow AM envelope over a few formant-like sines plus a
low noise floor) lands at tonalness 0.350 — clearly inside the band and
clearly separated from both white noise (0.154) and every tonal fixture
measured (≥0.633, and 1.000 for clean/chord-like signals). Because the
separation held up under measurement (not just assumption), this round ships
`speechLike` as a real state rather than folding it into `unknown` — but the
band stays intentionally narrow, and any fixture that fails to separate
cleanly under future real-audio calibration should widen the corridor toward
`unknown`, never toward a source classification.
