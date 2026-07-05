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
