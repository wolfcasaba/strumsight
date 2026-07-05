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

**Feature — spectral flux** on the fast pipeline (1024/256, chunk 002):

`flux[n] = Σ_k max(0, |X_k(n)| − |X_k(n−1)|)` (half-wave rectified — only
energy INCREASES). Log-compress: `flux' = log(1 + 10*flux)` to tame dynamics.

**Adaptive threshold (median-based, causal):**
`thr[n] = δ + λ * median(flux'[n−M .. n])` with **M ≈ 20 frames (~115 ms)**,
start at **δ = 0.05, λ = 1.4**; tune on real strums. Median (not mean) resists
the spike itself inflating the threshold.

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
