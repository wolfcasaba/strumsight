---
id: 019
topic: Offline signal-quality metrics for recorded PCM
tags: [audio-analysis, dsp, signal-quality, dbfs, clipping, spectral-flatness]
sources:
  - docs/sdd/07-epic-06-audio-analysis-2.md (§11.2–11.5, Round 7)
  - docs/adr/0224-signal-quality-stage-measurement-boundary.md
built: 2026-08-11 (E06-R07)
---

# Signal-quality metrics — AS BUILT

E06-R07 measures **recording conditions**, not the quality of the player's
performance and not the identity of any sound source. It is a deterministic,
local-only `AnalysisStage<ValidatedPcmAnalysisInput, SignalQualityStageResult>`.
The existing `SignalQualityReport` retains its seven public numeric values;
active-region ratio, degraded metric names, and the threshold version stay in
the stage result until a later heterogeneous work-state exists.

## Versioned thresholds

`QualityThresholds.standard` is `signal-quality-v1`. These values are
provisional until the E06-R29 real-recording evaluation, rather than hidden
DSP tuning:

| Name | Value | Meaning |
| --- | ---: | --- |
| `silenceFloorDbfs` | -120 dBFS | finite report floor for silent energy |
| `maximumReportDbfs` | +6 dBFS | defensive report ceiling |
| `clippedSampleThreshold` | 0.999 | inclusive absolute sample clipping boundary |
| `clippedRatioWarning` | 0.001 | inclusive ratio that raises a recording-clipped warning |
| `silentSampleDbfs` | -60 dBFS | inclusive frame-RMS silent boundary |
| `silentRatioWarning` | 0.95 | ratio for a recording-silent warning |
| frame / hop | 2048 / 1024 samples | 50%-overlap frame analysis |
| short clip | 250 ms | marks noise-floor and tonalness as degraded |

## Formulas

For PCM samples `x_i`, peak amplitude is `max(|x_i|)` and RMS amplitude is
`sqrt(sum(x_i²) / N)`. A positive amplitude `a` becomes
`20 * log10(a)` dBFS, then is clamped to `[-120, +6]`; zero maps directly to
`-120 dBFS`. Thus a full-scale sine has a 0 dBFS peak, while silence never
leaks `-Infinity` or `NaN` into the report.

The clipped ratio is the count of samples satisfying `|x_i| >= 0.999`, divided
by sample count. Silent and active-region ratios are computed from the same
2048-sample, 50%-overlap frame series: a frame is silent when RMS dBFS is
`<= -60`; active region is `1 - silentRatio`. The noise-floor proxy is the
nearest-rank 10th percentile of those frame RMS dBFS values. This intentionally
does not claim to separate noise from speech, drums, or background music.

Tonalness is `1 - mean(spectralFlatness)`. Spectral flatness uses a local
Hann-windowed radix-2 magnitude FFT per complete 2048-sample frame:
`exp(mean(log(magnitude))) / mean(magnitude)`, with a documented `1e-12`
magnitude floor. A tone-like spectrum tends toward larger tonalness and a
flat/noise-like spectrum toward lower tonalness. It is only a proxy and is
never surfaced as a source classification. The local FFT avoids importing the
real-time Live DSP feature across a forbidden feature boundary.

## Warning and grade policy

Warnings have stable recording-condition keys only:
`quality.recording_silent`, `quality.recording_low_level`,
`quality.recording_clipped`, and `quality.recording_short_clip`. No warning
labels a performance as bad, poor, wrong, sloppy, or weak.

`overall` begins at `1.0`; nearly entirely silent recordings become `0.25`,
low-level recordings `0.65`, clipping multiplies by `0.5`, and a short clip
multiplies by `0.85`. This compact grade is deliberately secondary: every raw
measurement remains present in `SignalQualityReport`. Short clips still report
peak, RMS, and clipping, while `noiseFloorDbfs` and `tonalness` are explicitly
listed as degraded in the stage result.
