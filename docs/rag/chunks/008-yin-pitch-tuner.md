---
id: 008
topic: YIN pitch detection for the chromatic tuner
tags: [yin, pitch, tuner, cmndf, parabolic, cents, f0, guitar]
sources:
  - https://hyuncat.com/blog/yin/
  - https://github.com/ashokfernandez/Yin-Pitch-Tracking/blob/master/Yin.c
  - https://pitchdetector.com/autocorrelation-vs-yin-algorithm-for-pitch-detection/
---

# YIN (time-domain f0) for the tuner

Chosen over plain autocorrelation: fewer octave errors, strong at low pitches
(guitar low E2 = 82.4 Hz).

**Steps (buffer w, max lag T):**
1. Difference: `d(τ) = Σ_{j=0}^{w-1} (x[j] − x[j+τ])²` for τ in 1..T.
2. CMNDF: `d'(τ) = d(τ) * τ / Σ_{i=1}^{τ} d(i)`; `d'(0)=1`.
3. Absolute threshold **0.12** (range 0.10–0.15): first τ where `d'(τ)` dips
   below it; then descend to the local minimum.
4. **Parabolic interpolation** around that τ (3 points) → fractional period.
5. `f0 = sr / τ_frac`. If no dip < threshold → no pitch (tuner shows
   "Play a string…").

**Sizing for guitar (down to ~70 Hz):** buffer **4096** samples @44.1 kHz
(93 ms), `T = sr/60 ≈ 735` (~60 Hz floor). d(τ) is O(w·T) ≈ 3M mul-adds per
frame — fine at the tuner's 10–15 Hz update rate (runs only on the Tuner
screen). Hop = 2048.

**Display mapping:**
- MIDI note `m = 69 + 12*log2(f0/440)`; nearest note = `round(m)`;
- cents off = `(m − round(m)) * 100`, clamp ±50 for the gauge;
- in-tune = |cents| ≤ 5 (matches TunerReading.inTune);
- Note name = pitch class of round(m); show octaveless letter (E, A, D…).

**Stability:** median of the last 3 readings before display; drop frames whose
RMS is below the silence gate.

## Voice / noise rejection (round 23 — see McLeod "clarity", YIN aperiodicity)

The bare RMS gate lets voiced speech (which is periodic, in the guitar range)
read as a note. Real tuners gate on **clarity + stability**, not just level.
`TunerAnalyzer` now applies four gates before showing a note; fail any → silent:

1. **Level** — `rms ≥ 0.014` (raised from the shared 0.008 silence floor).
2. **Clarity** — YIN now exposes `clarity = 1 − d'(τ)` (tone-likeness, McLeod's
   measure). Require `clarity ≥ 0.85`. A cleanly plucked string is ~0.95+;
   consonants/noise are lower.
3. **Range** — `70 ≤ f0 ≤ 1320 Hz` (guitar E2…E6).
4. **Stability** — keep the last **4** accepted f0; only lock when they all sit
   within **±30 cents** of their median (≈185 ms of agreement). Speech glides
   constantly → never stable → rejected; a held string locks. The reported
   pitch is that median (jitter-free). Any failing frame clears the window.

MEASURED (property gate, 20 random trials/seed): held in-range tones lock ≥17,
gliding (speech-like) pitches lock ≤2.
