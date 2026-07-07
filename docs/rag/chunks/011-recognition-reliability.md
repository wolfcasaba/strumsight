---
topic: How production tuner / chord apps get reliable, noise-robust recognition — techniques studied and what we adopted
sources: McLeod & Wyvill "A Smarter Way to Find Pitch"; de Cheveigné & Kawahara YIN; Mauch & Dixon pYIN; Kim et al. CREPE; Gfeller et al. SPICE; Mauch & Dixon NNLS-Chroma/Chordino; Böck & Widmer SuperFlux; chciken HPS tuner; TensorFlow SPICE-TFLite
---

Reference notes for making StrumSight's detection reliable, distilled from how
GuitarTuna/Fender Tune/Chordino/Yousician-class apps and the MIR literature do
it. Guides current tuning and future work. **Final acceptance is always the
user's real-guitar on-device test** — synthetic green is necessary, not
sufficient.

## The core principle (what every reliable detector shares)

Do NOT gate on loudness — speech/noise is loud too. Gate on **periodicity
(clarity) + temporal stability**, restrict to the **instrument's range**, and
**suppress overtones/noise** before deciding. Confidence, not just a value.

## Pitch / tuner techniques

- **YIN** (time-domain difference → CMNDF → threshold → parabolic interp).
  Fewer octave errors than raw autocorrelation. *We use this.*
- **Clarity / aperiodicity** = `1 − CMNDF[τ]` (McLeod's "clarity"). The
  voiced/unvoiced (tone vs noise) gate. *Adopted round 23 (≥0.85).*
- **Pitch stability / median smoothing** over N frames; "sticky" pitch; ~150 ms
  needle smoothing; "wait for the waveform to settle after a pluck". Speech
  glides ⇒ never stable ⇒ rejected. *Adopted round 23 (4 frames, ±30 cents,
  report the median).*
- **HPS (Harmonic Product Spectrum)**: downsample spectrum ×2..5 and multiply →
  peak at F0. Fixes the "2nd harmonic louder than fundamental" octave error of
  FFT-peak methods. Guitar pickups differentiate → strong 2nd/3rd harmonic.
  *Not adopted — YIN already handles octaves; HPS is a possible cross-check.*
- **Mains-hum (<62 Hz) zeroing + per-octave white-noise thresholding** (zero
  bins below 0.2× the octave's mean) before pitch detection. *Candidate.*
- **Dual-algorithm confidence**: HPS and Cepstrum/YIN agreeing within ~few % ⇒
  near-100% confidence. *Candidate.*
- **CREPE / SPICE** (deep-learning F0, SPICE is self-supervised + noise-robust,
  runs on-device via **TFLite**, 16 kHz mono). SOTA below 10 dB SNR. *Would
  break the pure-Dart offline design — only if a tuning/latency wall demands it.*

## Chroma / chord techniques

- **CQT (Constant-Q Transform)**: log-frequency, wide windows for low notes →
  the right resolution where a semitone is < 1 FFT bin. Standard front-end for
  chroma. *We approximate it with spectral peak-picking + parabolic interp
  (chunk 003) — a lighter workaround; a real CQT is the principled upgrade.*
- **NNLS-Chroma / Chordino**: approximate note transcription with **non-negative
  least squares** against a dictionary of notes whose harmonics decay
  geometrically (spectral shape 0.7), to **suppress overtones** before folding
  to chroma; + spectral whitening (running mean/std); + chord DICTIONARY
  profiles + HMM/Viterbi. **GOTCHA we hit (round 24 attempt):** naive greedy
  harmonic subtraction *fights* our 24-triad-template matcher — for guitar
  triads the 3rd harmonic lands on the fifth and the 5th harmonic on the major
  third, so partials REINFORCE the correct template. Subtracting them broke the
  G(G-B-G voicing → D-from-harmonic) match. Real NNLS works only WITH harmonic
  chord profiles, not bare triad templates. *Reverted; needs the full pipeline.*
- **Tonalness gate**: a diffuse chroma (speech/noise) must not fake a chord.
  *Adopted round 23 (top-3 pitch-class energy ≥ 0.7) + matcher no longer
  bootstraps a chord on one frame.*
- **Deep chroma / CNN-on-CQT (madmom)**: learned pitch-class activations, very
  robust. ML infra — out of scope for pure-Dart v1.

## Onset / strum techniques

- **Spectral flux + adaptive whitening** (Stowell & Plumbley). *We use this.*
- **SuperFlux (max-filter vibrato suppression)**: max-filter the reference
  spectrum across a log-frequency band before the flux difference ⇒ up to 60%
  fewer false onsets from vibrato/pitch wobble. *Candidate — needs a
  log-frequency filterbank to do properly; a naive linear-bin max filter would
  disturb the already-tuned onset path, so defer until validated on device.*

## Front-end (helps everything)

- **Spectral subtraction / adaptive noise floor** (EMA noise estimate, spectral
  floor to avoid "musical noise"; Wiener filter). Improves SNR before analysis.
  *Candidate; must not raise latency or starve quiet guitar.*

## Priority for StrumSight (biggest reliability per unit risk)

1. ✅ **Done (round 23):** clarity + stability gates (tuner), tonalness gate
   (chord), no single-frame chord bootstrap. Directly fixes "reacts to speech".
2. **Tune round-23 thresholds on real device** (clarity 0.85, tonalness 0.7,
   ±30 cents) — the actual next step; needs the user's guitar.
3. **Mains-hum + per-octave noise pre-filter** (cheap, low-risk).
4. **Proper CQT chroma + NNLS + chord profiles** (Chordino-class) — the real
   accuracy jump for chords, but a sizeable rework.
5. **SuperFlux onset** (log-frequency max filter).
6. **On-device ML (SPICE/CREPE TFLite)** — only if pure-DSP tuning plateaus;
   trades the offline/pure-Dart purity for SOTA noise robustness.
