---
id: 021
topic: Rhythm consistency and measured groove proxies
tags: [audio-analysis, rhythm, ioi, subdivision, swing, confidence]
sources:
  - docs/sdd/07-epic-06-audio-analysis-2.md (§15.6, Round 15)
  - docs/adr/0233-rhythm-consistency-and-groove-proxy-boundary.md
built: 2026-08-12 (E06-R15)
---

# Rhythm consistency and groove proxies — AS BUILT

E06-R15 adds deterministic, local rhythm proxies. It does **not** infer a
style and does not publish an aggregate “groove score”. The target path uses
only `rhythm.target_*` IDs; an estimated grid uses only `rhythm.inferred_*`
IDs. A run never mixes them.

## IOI consistency and stable sequence

For adjacent observed onset times, `IOI_i = t_i - t_(i-1)`. With `m` as the
median IOI and `σ` as the population standard deviation of the IOIs, the
consistency is:

```text
IOI consistency = clamp(1 - σ / m, 0, 1)
```

The median protects the reference interval from outliers. The longest stable
sequence is the longest consecutive IOI run satisfying
`|IOI_i - m| <= 0.10 * m`; the ±10% boundary is inclusive.

## Subdivision and phase proxies

Each event is assigned a phase in its containing beat. Candidates are `{1, 2,
3, 4}` subdivisions per beat. For each candidate, the analyzer computes the
population standard deviation of signed offsets to the nearest candidate phase;
the minimum wins. If the nearest non-equivalent candidate is no more than
`1.05` times the winner’s deviation (inclusive 5%), the result is ambiguous:
the subdivision and beat-phase metrics are `degraded`, not a claimed
subdivision. Exact multiples do not compete with their parent subdivision;
otherwise perfectly regular eighths would be indistinguishable from a
sixteenth grid that happens to have every other event absent.

The published subdivision and beat-phase consistency proxy is
`clamp(1 - 2 * selectedPhaseDeviation, 0, 1)`. Accent-position consistency is
the fraction of beats whose strongest observable onset is in the most common
bar-relative phase bin. `attackStrength` is used when present; otherwise event
confidence is the deterministic proxy.

## Target-only swing and confidence

The target-only `rhythm.target_swing_ratio.v1` is the larger divided by the
smaller of the alternating odd/even IOI medians. It is a measured long/short
ratio (for example 2:1), not a style classification. No swing value exists for
an inferred grid; its capability is `notApplicable`.

All metrics reuse `MetricGate` (`minimumMatchedPairs = 8`,
`minimumStreakMatchedPairs = 3`). Below the primary gate every metric is
`unavailable` with `insufficientEvents`, never a synthetic zero.

For inferred mode, confidence is
`mean(event confidence) * mean(confidence of actually used BeatPoint values)`,
clamped to `[0,1]`. It is therefore never higher than the supporting estimated
beat confidence mean. Target mode retains the mean observed-event confidence.
