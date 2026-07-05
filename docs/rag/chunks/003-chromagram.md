---
id: 003
topic: Chromagram (12-dim pitch-class vector) from FFT magnitudes
tags: [chroma, chromagram, pitch class, bin mapping, smoothing, tuning]
sources:
  - https://www.audiolabs-erlangen.de/resources/MIR/FMP/C5/C5S2_ChordRec_Templates.html
  - https://github.com/adamstark/Chord-Detector-and-Chromagram
---

# Chromagram

Map each FFT magnitude bin to a pitch class and accumulate:

1. Consider only **60–1600 Hz** (B1..G6): below = rumble/thump, above = mostly
   harmonics that blur the chroma.
2. Bin k → frequency `f = k*sr/n` → MIDI `m = 69 + 12*log2(f/440)` →
   pitch class `pc = round(m) mod 12`, **only if |m - round(m)| ≤ 0.35**
   (skip energy that falls between semitones — inharmonic noise).
3. `chroma[pc] += magnitude²` (energy, not magnitude — emphasizes strong
   partials over noise floor).
4. **Octave weighting:** weight bins by `1/octave` above C4 to soften the
   harmonic series pull toward the dominant (simple alternative to full HPS;
   good enough for clean guitar per adamstark's approach).
5. Normalize L2. If the pre-normalization energy is below the silence gate
   (chunk 010) emit a zero chroma — never normalize noise.

**Temporal smoothing:** exponential moving average over frames,
`smoothed = α*current + (1-α)*previous`, α≈0.25 at 23 ms hop (~4-frame
memory ≈ 90 ms). Chord decisions read the SMOOTHED chroma; onset/direction
read raw frames.

**Tuning reference:** fixed A4=440 for v1 (Settings already shows A=440).
Detune tolerance comes from the ±0.35 semitone window.
