---
id: 005
topic: Onset detection — half-wave-rectified spectral flux + median adaptive threshold
tags: [onset, spectral flux, adaptive threshold, median, peak picking, strum]
sources:
  - https://arxiv.org/html/2508.07973v1 (spectral flux F1≈79.5% on real strums)
  - https://www.audiolabs-erlangen.de/resources/MIR/FMP/C6/C6S1_PeakPicking.html
  - https://link.springer.com/article/10.1007/s11042-020-08780-2
---

# Onset detection

**⚠ MEASURED (2026-07-05, synthesized strums): raw spectral flux FAILS on
sustained polyphony.** Inter-string beating during ring-out floods the flux
baseline (log-flux ~5–7 vs attack ~7.5) and re-strums never cross a
median-scaled threshold. Also: a λ-multiplier on LOG-compressed flux is
mathematically wrong (multiplying a log = exponentiating the raw value).

**Fix that works — adaptive whitening (Stowell & Plumbley) + LINEAR flux:**
each bin is normalised by its recent peak `P_k = max(m_k, r·P_k)` with
**r = 0.995** per 5.8 ms frame (floor 1e-4); flux is computed on the whitened
magnitudes, NO log compression:

`flux[n] = Σ_k max(0, w_k(n) − w_k(n−1))`, `w_k = m_k / max(P_k, floor)`

**Adaptive threshold (median-based, causal, linear):**
`thr[n] = δ + λ * median(flux[n−M .. n])` with **M = 20 frames (~115 ms)**,
**δ = 1.0, λ = 2.0** (measured: ring-out whitened flux ~1–4, attacks ~20–270).
Median (not mean) resists the spike itself inflating the threshold.

**Synth-test gotcha:** a test signal that ends in a hard cutoff produces a
broadband click that reads as a false onset — synthesized notes need a ~10 ms
release ramp (real strings never stop instantaneously).

**⚠ MEASURED (2026-07-05, randomized property gate):** two more guards are
required on top of the threshold:
- **Release hysteresis:** a new onset is only eligible after flux < thr for
  **≥3 consecutive frames** (~17 ms) — one strum = one continuous flux
  plateau; without it a slow rake (≥12 ms/string) splits into two onsets.
- **Attack-relative gate:** candidate flux must be **≥15% of a decaying
  recent-peak tracker** (decay 0.985/frame, halves in ~270 ms) — ring-out
  beating spikes (~5–10) otherwise sneak over the median threshold in the
  tail, 60+ ms after the strum.
Both found by the RANDOMIZED property tests, not the deterministic suite —
keep the randomized CI gate.

**Peak picking:** onset at n when `flux'[n] > thr[n]`, `flux'[n]` is a local
max over ±2 frames, and **≥ 60 ms since the previous onset** (a strum's string
hits span ~10–40 ms and must count as ONE onset; 16th notes at 180 BPM are
83 ms apart, so 60 ms never merges real events).

**Reality check from the 2025 strumming paper (arXiv 2508.07973):** plain
spectral flux hits **F1 ≈ 79.5%** on real guitar strums at 16 kHz — that is the
practical ceiling for this class of detector; report missed/extra onsets as a
confidence matter, don't chase 100%.

**Latency:** onset confirmed 2 frames after the peak (~12 ms) — inside the
50–80 ms budget (chunk 010).

## r166 — SuperFlux threshold retuned on REAL recordings (2026-07-13)

The synth-tuned adaptive threshold (delta 20, lambda 2.0) missed **27 %** of
the 2 013 labeled strums on the Klangio eval takes (±0.12 s): fast strumming
raises the 0.4 s median-flux floor so the threshold SELF-MASKS (56 % of the
misses sat <0.25 s after the previous label), and real phone-mic attacks are
far weaker in flux than synthetic ones (the "soft attack ≥100" premise did
not transfer). Detector-level sweep on the real fold:

| delta, lambda | recall@0.12 | precision |
|---|---|---|
| 20, 2.0 (old) | 72 % | 87 % |
| 12, 2.0 | 84 % | 85 % |
| **12, 1.0 (new)** | **90 %** | 83 % |
| 8, 1.0 | 94 % | 78 % |

(12, 1.0) shipped: streaming-context recall 73 %→**91 %** (worst take
26 %→74 %), every synth pin (vibrato immunity, one-strum-one-onset, 180-BPM
16ths, ring-out silence, randomized property gate) still green. "False
alarms" on real takes include unlabeled real sounds (fret noise, ghosts) —
an upper bound. Locked by the real-A/B harness: matched/labels ≥ 0.85 when
the local dataset is present. delta/lambda are now ctor-injectable for future
sweeps (production passes nothing). Real-device feel remains the final gate.

## HEAL E14-R19 — band-spread gate: the price the r166 retune left unpaid (2026-09-05)

The r166 retune above bought 18 pts of real recall by dropping delta 20 → 12,
and that put the threshold UNDER the ring-out beating bumps this chunk's own
"attack-relative peak gate" section describes. MEASURED on clean
main@4e633b80, without any round diff: a SINGLE strum still sounding ~0.63 s
after the attack fires a **phantom second onset** — a spurious strum arrow and
a spurious Learn scoring event for a user who just holds the chord. On the
(lowFirst × stagger 6–14 ms × ring 0.5–0.9 s) grid the randomized property gate
draws from, **31 of 1458 points double-fire**; that ~2 % is why
`PROPERTY_SEED=33975939211` scored 17/20 against the ≥18 bar.

**Magnitude cannot fix it, spread can.** At the phantom frames:

| | flux | bands that rise (of 64) |
|---|---|---|
| true attack | 325–483 | **64** |
| ring-out beating peak | 12.5–16.8 | **11–13** |

Flux overlaps the soft real attacks delta=12 was lowered for; band SPREAD does
not — a pluck excites the whole spectrum at once, beating only moves energy
between neighbouring partials. So the gate is a **band count**, not a level:
`SuperFluxOnsetDetector.minRiseBands`.

Sweep, 2 013 labeled Klangio strums (real) + the 246-point synth grid:

| minRiseBands | real recall@0.12 | real precision | synth double-fires |
|---|---|---|---|
| 0 (pre-heal) | 89.6 % | 76.2 % | 6 |
| 12 | 89.6 % | 76.2 % | 2 |
| 14 | 89.5 % | 76.3 % | 0 |
| **16 (shipped)** | **89.6 %** | **76.7 %** | **0** |
| 20 | 89.0 % | 77.4 % | 0 |
| 24 | 87.2 % | 79.6 % | 0 |
| 32 | 69.4 % | 87.4 % | 0 |

**16 = a quarter of the bands.** Zero real-recall cost, 16 fewer false
detections, and 2 bands of headroom over the loudest measured beating bump
(13). This is NOT a free knob: past 20 it starts eating soft real attacks, and
at 64 it detects nothing at all. Ctor-injectable like delta/lambda; production
passes nothing. Pinned by `test/features/live/dsp/superflux_ring_out_phantom_test.dart`
(the 31 measured grid points, plus a recall counter-weight so a
detect-nothing "fix" cannot pass). Real-device feel remains the final gate.
