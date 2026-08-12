---
id: 020
topic: Beat grid and tempo curve domain/engine building blocks
tags: [audio-analysis, dsp, tempo, beat-grid, rhythm, half-double-time]
sources:
  - docs/sdd/07-epic-06-audio-analysis-2.md (§14.1-14.6, Round 12)
  - docs/adr/0230-beat-grid-tempo-curve-boundary.md
built: 2026-08-12 (E06-R12)
---

# Beat grid and tempo curve — AS BUILT

E06-R12 adds a time-indexed `BeatGrid` (beat + bar points, each with a
`BeatSource`) and a `TempoCurve` (median BPM, IQR, drift, stable-region
ratio, half/double-time hypotheses) as pure domain/engine building blocks. It
does **not** wire either into `AnalysisDocument`, `AnalysisMetricResult`, or
any V1 output — those remain unchanged. See ADR 0230 for the naming and
boundary decisions (`TempoCurvePoint` vs the already-exported
`AnalysisTimeline.TempoPoint`; the R12-local `BeatGridTargetInput` vs the
not-yet-existing `AnalysisTarget`).

## Legacy BPM parity (`tempo.legacy_bpm.v1`)

This is a byte-parity adapter of `ClipAnalyzer._bpmFromStrums`
(`lib/features/analyze/engine/clip_analyzer.dart:229-240`), not a new
formula: fewer than 2 events yields `0`; consecutive-event intervals `dt`
with `dt <= 0.05` seconds are dropped; the remaining intervals are sorted and
the **upper median** (`intervals[intervals.length ~/ 2]`) is taken;
`(60 / median).clamp(30, 300)`. Fixing the clamp or merging this label with
`tempo.median_bpm.v1` is a scope violation (ADR 0230 §4).

## Own median tempo (`tempo.median_bpm.v1`)

A separate, R12-owned estimate over the same filtered intervals, used as the
basis for the tempo curve, drift, and stability metrics below. It is not
required to match the legacy value.

## Minimum event/duration threshold (ideiglenes, R29-ig)

The `tempoCurve` capability is only `available`/`degraded` when **both**
hold: at least **8** rhythm events (onset or strum) **and** a clip duration
of at least **4.0 s** — both bounds inclusive. Below either bound,
`tempoCurve` reports `CapabilityStatus.unavailable` with
`CapabilityUnavailableReason.insufficientEvents`; the beat grid itself may
still be produced as `degraded`. A single interval never yields a "drift"
value.

## Half/double-time hypotheses (ideiglenes, R29-ig)

Free-play mode never silently picks a tempo. The preferred band is
`[60, 180]` BPM. If the estimated median BPM falls outside that band, it is
shifted into the band by repeated `×2` / `÷2` steps; the shifted value is
published, **but the original (pre-shift) estimate is kept** as a second
`TempoHypothesis` in the list, and the published hypothesis's confidence is
multiplied by **0.7**. If the raw estimate is already inside `[60, 180]`,
there is exactly one hypothesis and no confidence penalty.

Example: a 55 BPM raw estimate is below the band, so it doubles to 110 BPM
(inside the band); the hypothesis list has two entries (55 and 110), the
published value is 110, and its confidence carries the `0.7` multiplier. A
120 BPM raw estimate is already inside the band: one hypothesis, no penalty.

## Stable-region ratio (median ±5 %, ideiglenes, R29-ig)

The fraction of tempo-curve time where the local BPM is within `±5 %` of the
overall median BPM (both bounds inclusive). For a 120 BPM median, the stable
band is `[114.0, 126.0]` (`120 * 0.95 = 114.0`, `120 * 1.05 = 126.0`); a
113.9 BPM point falls outside, a 114.0 BPM point counts as stable.

## Drift slope

The tempo curve's linear drift slope is reported in **BPM per minute**,
computed over the curve's `TempoCurvePoint`s (time, local BPM, confidence),
which are always strictly time-ordered and carry only finite BPM values in
`(0, 400]` and confidence in `[0, 1]`.

## Target-first beat grid

When a `BeatGridTargetInput` (ordered beat times + `beatsPerBar`) is
supplied, the target timebase is authoritative: every `BeatPoint.source` is
`BeatSource.target`, `beatsPerBar` reports `BeatsPerBarSource.target`, and
the free-play inference strategy is never invoked (measured via an
injectable, call-counting test seam on `BeatGridEstimator`, not a stub the
production code “trusts”). Re-estimating the target grid “as a check” is a
scope violation (ADR 0230 §5, SDD §14.5).

## No free-play metre inference

`BeatGridEstimator` never infers `beatsPerBar` in free-play mode in this
round — the free-play grid always reports `BeatsPerBarSource.legacyDefault`
with `beatsPerBar = 4`, and the `AnalysisCapability.meter` outcome for a
free-play grid is `CapabilityStatus.notApplicable`. Metre inference is an
explicitly out-of-scope, later experimental round (SDD §14.4).
