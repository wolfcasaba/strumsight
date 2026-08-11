---
id: 019
topic: Signal quality stage — formulas, framing, thresholds (E06-R07)
tags: [audio-analysis, signal-quality, dbfs, clipping, noise-floor, spectral-flatness, provenance]
sources:
  - docs/adr/0223-signal-quality-stage-metric-and-provenance-policy.md
  - docs/rounds/e06-r07-signal-quality-stage.md
  - lib/features/audio_analysis/domain/signal_quality_report.dart (R02 contract)
built: 2026-08-11 (E06-R07, sonnet-impl)
---

# Signal quality stage — AS BUILT

`SignalQualityStage` (`lib/features/audio_analysis/engine/quality/`) reports
**recording** facts, never a performance grade. It fills the closed R02
`SignalQualityReport` contract (`overall`, `peakDbfs`, `rmsDbfs`,
`noiseFloorDbfs`, `clippedSampleRatio`, `silentRatio`, `tonalness`, `measured`,
`warnings`) — no new domain field. `QualityThresholds.version` and
`SignalQualityStage.version` are both `1` and must always be bumped together;
the R04 pipeline records `stageVersions['signal_quality'] = '<version>'`, so
that single number is this policy's provenance.

**Status: PROVISIONAL.** None of the thresholds below are calibrated against
real guitar recordings yet — that is E06-R29's job. They are internally
consistent and documented so a future round can retune them from one place
(`QualityThresholds`) plus this chunk, without touching the math.

## dBFS convention

Full-scale sine → `0 dBFS` peak. Silence does not map to `-Infinity`; every
dBFS computation clamps to `QualityThresholds.silenceFloorDbfs = -120.0` at
the bottom and `QualityThresholds.maxDbfs = +6.0` at the top (small headroom
for measurement noise above full scale). `SignalQualityMath.linearToDbfs`
is the single conversion point:

```
dbfs(amplitude) = amplitude <= 0 ? floor : clamp(20 * log10(amplitude), floor, ceiling)
```

## Peak / RMS (whole-clip)

`peakDbfs` = `dbfs(max(|sample|))` over all samples.
`rmsDbfs` = `dbfs(sqrt(mean(sample^2)))` over all samples.

## Framing (shared by noise floor, silence, tonalness)

`frameSize = 2048` samples, `hopSize = 1024` (50 % overlap) — both named on
`QualityThresholds`. The last partial frame (shorter than `frameSize`) is
still measured over its own shorter length; no zero-padding for RMS. Every
frame yields a per-frame RMS in dBFS (same `dbfs()` conversion and floor).

Rationale for OD-01 (own FFT, not `lib/features/live/engine/dsp/`): importing
the live DSP FFT would need a new cross-feature allowlist entry, which is
disallowed (the allowlist only shrinks). The stage runs once per clip, not in
a real-time budget, so a small self-contained radix-2 FFT is an acceptable,
isolated duplication.

## Clipping

`clippedSampleRatio` = fraction of samples with `|sample| >= clippedSampleThreshold`
(`0.999`, **inclusive**). A `signal_quality.clipping_detected` warning fires
when `clippedSampleRatio >= clippedRatioWarning` (`0.001`, **inclusive**) — a
clip is "1000 clipped samples per million" or worse.

## Silence

A frame is silent when its per-frame RMS dBFS is `<= silentFrameDbfs`
(`-60.0`, **inclusive**). `silentRatio` = fraction of silent frames (not
samples — a single burst of energy inside a long silent frame does not make
the whole frame "not silent" until its RMS crosses the line, which matches
how a human would judge a quiet frame). The complementary "active region
ratio" (`activeRegionRatio = 1 - silentRatio`) is an **internal** primitive
only — the R02 contract has no field for it, per ADR 0223 §1. A
`signal_quality.mostly_silent` warning fires when `silentRatio >= mostlySilentRatioWarning`
(`0.95`).

## Noise floor — 10th percentile, not the mean (OD-02)

`noiseFloorDbfs` = the `noiseFloorPercentile` (`0.10`) percentile of the
per-frame RMS dBFS distribution, using linear interpolation between the two
bracketing order statistics (`SignalQualityMath.percentile`, the common
"R-7" definition). A percentile is deliberately used instead of the mean:
white noise (fixture 5) has a fairly uniform per-frame RMS, so percentile and
mean nearly agree; silence-plus-one-loud-section (fixture 8) has a bimodal
distribution where the mean is dragged toward the loud section while the
10th percentile still reports the quiet floor — which is the number a
noise-floor estimate is for.

## Tonalness — energy-weighted spectral-flatness proxy

Per frame: apply a Hann window, run the self-contained radix-2 FFT (frame
size is a power of two so no padding is needed for the transform itself),
take the magnitude of bins `1..frameSize/2` (DC excluded), floor each
magnitude at a small epsilon to keep the geometric mean finite, and compute

```
flatness = geometric_mean(magnitude) / arithmetic_mean(magnitude)   // in (0, 1]
```

A pure tone concentrates energy in few bins → `flatness` near 0. White noise
spreads energy evenly → `flatness` near 1. `tonalness = 1 - flatness` per
frame, then **energy-weighted** across frames (weight = linear frame RMS, not
dB) so silent frames — whose flatness is numerically ~1 from the epsilon
floor, not because they carry noise — do not drag down the tonalness of a
clip that is mostly silence around one loud, tonal section (fixture 8). If
every frame has zero weight (pure digital silence), `tonalness = 0` rather
than dividing by zero.

This is explicitly **not** the same quantity as `NnlsChroma.lastTonalness`
(the V1 chord-gating tonalness in `lib/features/live/engine/dsp/`): that one
is a chroma-energy concentration measure computed on NNLS-analysed bass/treble
chroma at chord-detection frame rate, for a completely different purpose
(gating chord decisions in real time). This chunk's `tonalness` is a
whole-clip recording-quality proxy. Same word, two different measurements —
never conflate the two symbols in code review.

## Short clips

A clip shorter than `minReliableDurationSeconds` (`1.0`) still gets a full
peak/RMS/clipping measurement — those are reliable at any length. Only the
noise-floor/tonalness framing is statistically thin for very short clips, so
the stage adds a stable `signal_quality.short_clip` `inputQuality` warning
instead of inventing a new "degraded" field the R02 contract does not have
(ADR 0223 §3).

## Overall grade — visible sub-scores, not a black box

`overall` is a weighted average of four `[0, 1]` sub-scores (weights on
`QualityThresholds`, currently `0.25` each, sum `1.0`):

- `clippingScore = clamp(1 - clippedSampleRatio / clippingFullPenaltyRatio, 0, 1)`,
  `clippingFullPenaltyRatio = 0.05` (5 % of samples clipped → score bottoms at 0).
- `silenceScore = clamp(1 - silentRatio, 0, 1)` (same as `activeRegionRatio`).
- `dynamicRangeScore = clamp((rmsDbfs - noiseFloorDbfs) / fullDynamicRangeDb, 0, 1)`,
  `fullDynamicRangeDb = 40.0`.
- `tonalnessScore = tonalness` (already `[0, 1]`).

`overall` never replaces the sub-metrics: every one of `peakDbfs`, `rmsDbfs`,
`noiseFloorDbfs`, `clippedSampleRatio`, `silentRatio`, `tonalness` stays on
the published report (ADR 0223 §1 / SDD Kör 7 §3).

## What this stage is NOT allowed to say

No warning key names a playing quality ("bad_playing" etc.) and no field
claims a sound source ("speech", "drums", "another instrument") — `tonalness`
and the flatness it is built from are signal-statistics proxies only, per
ADR 0223's rejected alternatives. `DspConfig` and every V1 DSP constant are
untouched by this stage; a shipping-DSP retune is out of scope by design.
