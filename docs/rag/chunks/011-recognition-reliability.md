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
- **NNLS-Chroma / Chordino** — ✅ **IMPLEMENTED (round 25)**, `nnls_chroma.dart`,
  wired into `LivePipeline` for the chord path. STFT (window **16384** ≈0.37 s so
  a semitone resolves at low E) → **log-frequency spectrum** (3 bins/semitone,
  linear interp at bin centres) → **NNLS approximate transcription** against a
  **harmonic dictionary** (harmonic h at +12·log2(h) semitones, magnitude
  `0.7^(h-1)`, 12 harmonics, unit columns) solved by **non-negative
  multiplicative updates** `x ← x·(Dᵀs)/(DᵀDx+ε)`, 20 iters, DᵀD precomputed →
  fold activations to 12-bin chroma. This EXPLAINS each note's overtones, so a
  bass fundamental's partials don't leak into other pitch classes (verified: a
  220 Hz note with harmonics maps to A alone, its 3rd/5th partials — E/C# — stay
  <½ the peak). The cleaned chroma feeds the existing 24-triad matcher + the
  tonalness gate. Runs in the DSP isolate at nnlsHop=4096 (~11 fps) — cheap.
  - **GOTCHA (round 24, superseded):** a *naive greedy* harmonic SUBTRACTION on
    the old peak-chroma fought the triad templates (3rd harmonic = fifth, 5th =
    major third, so partials reinforce the template). Full NNLS transcription
    (round 25) fixes this properly — it re-synthesises fundamentals, so complete
    triads recover all three tones; incomplete synth voicings (G-B-G, F-C-F) may
    show a weak spurious 3rd class but the two real tones dominate.
  - **Still TODO:** per-frame tuning estimation, spectral whitening, and a chord
    DICTIONARY (chord profiles + HMM/Viterbi) for 7ths/inversions. ChromaExtractor
    (peak-pick) is retained as a lighter component but no longer on the chord path.
- **Tonalness gate**: a diffuse chroma (speech/noise) must not fake a chord.
  *Adopted round 23 (top-3 pitch-class energy ≥ 0.7) + matcher no longer
  bootstraps a chord on one frame.*
- **Chord DICTIONARY + Viterbi (Chordino-class)** — the concrete next port,
  spec'd in **chunk 012**: bass+treble split chroma (24-dim) → chord-profile
  similarity → HMM/Viterbi (+ no-chord state). This — not more note-templates —
  is what makes 7ths/inversions reliable (round 26 proved templates can't).
- **Deep chroma / CNN-on-CQT (madmom), transformer (BTC)**: learned pitch-class
  activations, SOTA robustness. **Feasible on-device** — competitor **Chord AI**
  (`com.chordai`) ships an **offline CNN**; TFLite ≈1–13 ms / 2.56 s input,
  quantizes ~9× smaller. Needs a labelled trainset + Mac-free export → deferred
  behind the pure-DSP port (chunk 012). **No rival detects strum direction —
  StrumSight's ↓/↑ moat.**

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
2. ✅ **Done (round 25):** CQT-ish log-freq + **NNLS chroma** (Chordino-class
   overtone suppression) on the chord path — the accuracy jump for chords.
3. **Tune round-23/25 thresholds + latency on real device** — the actual next
   step; needs the user's guitar (clarity 0.85, tonalness 0.7, ±30 cents,
   16384 window ≈370 ms chord latency).
4. **Chord dictionary (profiles + HMM/Viterbi)** on top of NNLS — 7ths,
   inversions, smoother chord track. **Full spec: chunk 012.** This is the
   biggest correctness win available in pure Dart, and the right answer to the
   round-26 extended-vocab failure.
5. **Mains-hum + per-octave noise pre-filter**; **SuperFlux onset** (log-freq
   max filter).
6. **On-device ML (SPICE/CREPE TFLite)** — only if pure-DSP tuning plateaus;
   trades the offline/pure-Dart purity for SOTA noise robustness.
