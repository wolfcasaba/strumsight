---
id: 022
topic: Dynamics and stroke-balance metrics, and their quality gate
tags: [audio-analysis, dynamics, accent, clipping, mad, noise-floor, confidence]
sources:
  - docs/sdd/07-epic-06-audio-analysis-2.md (§16.1–16.5, Round 16)
  - docs/adr/0234-dynamics-evidence-and-gating-boundary.md
built: 2026-08-12 (E06-R16)
---

# Dynamics and stroke balance — AS BUILT

E06-R16 measures within-session pluck force and accent control from the
**original**, unnormalized PCM (`PreprocessedAudio.originalSamples`, ADR
0206/0234) — never `canonicalSamples`, even when the R08 normalization flag
is on. All seven metrics are dimensionless ratios normalized to the
session's own median, so they are invariant to recording gain by
construction.

## Per-event clipped flag (ADR 0234 §2)

`StrumEvent` carries no `clipped` field. R16 derives it internally, reusing
the same `[t, t + 20 ms]` attack window R10's `EventTimelineBuilder` already
uses for `attackStrength`: any finite original sample in that window with
`abs(sample) >= 0.999` (the R07 `QualityThresholds.clippedSampleThreshold`
convention) marks the event clipped. A clipped event is excluded from every
strength statistic (median, CV, drift, outlier band) but still counts in
`dynamics.clipped_event_ratio.v1`.

## Normalized strength and the seven metrics

For the non-clipped events, `median = median(attackStrength)`; each event's
`normalizedStrength = attackStrength / median`. Because both the numerator
and the denominator come from the same original-sample measurements, scaling
the whole clip by a constant leaves every `normalizedStrength` — and every
metric derived from it — bit-identical.

- **`dynamics.stroke_strength_cv.v1`** — population `stddev(normalizedStrength)
  / mean(normalizedStrength)`. Descriptive; no preferred direction.
- **`dynamics.down_up_median_ratio.v1`** — `median(normalizedStrength for
  down) / median(normalizedStrength for up)`. Descriptive (SDD §16.4): the
  result is a `ScalarMetricValue`, never clamped to `[0, 1]`, and it is never
  framed as "lower is better" — an unbalanced down/up ratio is a fact, not a
  fault, without a target. `unavailable` if either group is empty.
- **`dynamics.drift.v1`** — `mean(normalizedStrength, second half) -
  mean(normalizedStrength, first half)` over the chronological non-clipped
  sequence (`n // 2` split). `unavailable` below 2 non-clipped events.
- **`dynamics.outlier_ratio.v1`** — MAD-based (brief OD-01): `MAD =
  median(|normalizedStrength - median|)`; an event is an outlier when
  `|normalizedStrength - median| > 2 * MAD` (`dynamicsOutlierMadMultiplier`).
  The band is **inclusive**: exactly `2 * MAD` is not an outlier.
- **`dynamics.accent_accuracy.v1`** — target-gated (brief OD-02, §5.2):
  `notApplicable` without an explicit expected-accent-event set, never a
  fabricated number; `available`/`degraded` with one. See below for
  detection.
- **`dynamics.quiet_region_ratio.v1`** — an event is "quiet" when its
  `localRms` (R10's `[t - 5 ms, t + 45 ms]` window) is below `0.3 *
  median(localRms)` (`dynamicsQuietRmsFraction`) over the non-clipped set.
- **`dynamics.clipped_event_ratio.v1`** — `clippedCount / totalEventCount`,
  computed over **all** events (clipped events are excluded everywhere else,
  but this is the one metric that measures them).

## Local accent detection (brief OD-02)

`detectLocalAccents` compares each event's `attackStrength` to a **centred,
edge-truncated moving-median window**: the preceding and following 4 events
(9 wide when not truncated at an edge). An event is an accent when
`attackStrength / localMedian > 1.2` (`dynamicsAccentThresholdRatio`). Using
the **session-wide** median instead (`windowRadius: events.length` collapses
the moving window into exactly that) turns a gradual global loudness ramp
into a run of false accents, because every early, quieter event reads as
"below the final session median" and every late one as "above it" — the
moving window tracks the local baseline and stays silent. This is why
accent detection must never fall back to the session median (SDD §16.5).

## `DynamicsGate` — fail-closed quality gate (ADR 0234 §3, OD-03)

Evaluated **before** any dynamics value is computed, in this priority order:

1. `SignalQualityReport.measured == false` → `unavailable(internalFailure)`.
   A legacy/fabricated quality report is never treated as a neutral zero.
2. `noiseFloorDbfs >= -25.0` → `unavailable(backingTrackDominant)`. This is a
   **provisional proxy**, not source identification (SDD §11.5) — real
   backing-track detection is out of scope until R29.
3. `clippedEventRatio > 0.05` → `unavailable(inputClipped)`. Exactly `0.05`
   stays `degraded` (inclusive).
4. `silentRatio >= 0.95` → `unavailable(inputTooNoisy)` (too quiet to trust).
5. Otherwise `degraded` if `noiseFloorDbfs >= -35.0` (inclusive) or
   `clippedEventRatio > 0.0`; else `available`.

Below `MetricGate`'s existing `minimumMatchedPairs` (8, unchanged — R16
introduces no parallel minimum), every metric is `unavailable` with
`insufficientEvents`, checked once against the full event count (for
`clipped_event_ratio`) and again against the non-clipped count (for the six
strength-based metrics) — a clip that is mostly clipping can fail the second
check while still reporting its own ratio.

All thresholds above are named constants pending real-recording calibration
at R29, per the same convention as `QualityThresholds` (R07).
