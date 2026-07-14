---
id: 003
topic: Chromagram (12-dim pitch-class vector) from FFT magnitudes
tags: [chroma, chromagram, pitch class, bin mapping, smoothing, tuning]
sources:
  - https://www.audiolabs-erlangen.de/resources/MIR/FMP/C5/C5S2_ChordRec_Templates.html
  - https://github.com/adamstark/Chord-Detector-and-Chromagram
---

# Chromagram

**⚠ MEASURED (2026-07-05, synthesized triads): naive per-bin → pitch-class
mapping FAILS for guitar.** Below ~250 Hz a semitone (<8 Hz) is narrower than
a 4096-window bin (~10.8 Hz @44.1k): Hann-leakage bins land in NEIGHBOURING
pitch classes (spurious C#/F from a C-E-G triad) and low fundamentals collapse
to a single bin. Fix that works: **spectral PEAK picking + parabolic
interpolation** (sub-bin frequency precision) — implemented in
`chroma_extractor.dart`, verified: C-E-G triad → top-3 chroma = {C,E,G}.

Per frame:

1. Consider only **60–1600 Hz** (B1..G6): below = rumble/thump, above = mostly
   harmonics that blur the chroma.
2. Magnitudes for bins 0..n/2 (fftea `realFft` returns FULL length n — upper
   half is the conjugate mirror; use only the first half). Find **local
   maxima** above `0.002 × maxMag`.
3. Parabolic interpolation over (k−1, k, k+1) → fractional bin → true
   frequency `f` → MIDI `m = 69 + 12*log2(f/440)` → pitch class
   `pc = round(m) mod 12`, **only if |m − round(m)| ≤ 0.35**.
4. `chroma[pc] += peakMagnitude²` (energy — emphasizes strong partials).
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

## Tonalness gate (round 23 — reject speech/noise chords)

The matcher always returns *some* best template, so a diffuse (non-musical)
chroma faked a chord on speech/noise. Fix: `ChromaExtractor` exposes
`lastTonalness` = the summed energy of the **top-3 pitch classes** of the unit
chroma (squared entries sum to 1). The chord path (`LivePipeline`) only feeds a
frame to the matcher when `tonalness ≥ 0.7` (`DspConfig.chordMinTonalness`);
below that the frame is passed as silence (decays the chord).

MEASURED (synth): a clean triad ≈ **0.99**, white noise ≈ **0.55** — 0.7
separates them. Paired change (chunk 004): the matcher no longer bootstraps a
chord on a single frame — a report needs the hysteresis streak or an
instant-switch, so a lone stray-tonal noise frame (random label) shows nothing.
May need real-device tuning; the property gate asserts noise fakes a chord in
≤2/20 random trials.

## Musical-presence gate (round 176 — reject VOICE, not just noise)

**⚠ MEASURED on REAL audio (round 176 offline probe, `test/tools/real_audio_
probe_test.dart`): the tonalness gate above rejects broadband noise but NOT
voiced human speech / humming.** Field bug (user report): in Live mode the
chord label jumps around wildly on talking. Both speech and a sung vowel are
*harmonic* → their chroma concentrates in a few pitch classes → tonalness
clears 0.7. Measured P50 tonalness: speech ≈ **0.82–0.84**, a sustained hum ≈
**0.99** — overlapping real guitar (**0.85–0.95**). So tonalness cannot be the
voice/guitar discriminator (raising it kills guitar too).

**The feature that DOES separate is the chord-MATCH confidence** (chunk 012:
`winSim × (0.5 + 2·margin)`). A guitar chord is an unambiguous, high-margin,
*sustained* match; voiced speech matches many profiles weakly and only in brief
choppy spikes. Measured per-clip confidence:

| source | conf P50 | conf P90 |
|--------|---------:|---------:|
| real guitar (klangio phone takes) | 0.45–0.54 | **0.60–0.69** |
| synth speech / hum negatives      | 0.39–0.41 | **0.42–0.53** |

**Fix — a Schmitt trigger on the EMA-smoothed match confidence** gates the
DISPLAYED chord (`LivePipeline`, `DspConfig.chordConfRise/Release/EmaAlpha`):
the chord is surfaced once the smoothed confidence RISES past `chordConfRise`
and HELD until it FALLS below `chordConfRelease`. Guitar's confident strum
spike latches the display and rings out above the release floor; voice never
sustains past the rise gate, so the screen shows nothing (blank `—`) instead of
a phantom chord. The EMA (`α=0.35`, ~200 ms) is what stops a lone speech spike
from latching.

**AS BUILT (tuned on the real-audio probe — voice negatives vs 82 klangio
takes): `chordConfRise = 0.54`, `chordConfRelease = 0.22`.** At these values
chordShown% went: talking **79–85 % → 0 %**, sustained hum **85 % → 0 %**, pink
noise 0 % (already), while real guitar stays **~74 %** over full clips (incl.
rests). Talk alone is 0 % for any rise ≥ 0.46; the 0.54 rise is what also
rejects a steady hum, and the low 0.22 release holds a latched chord through
its ring-out. **Live display path only** — the Analyze batch timeline
(`decodeBatch`) is unchanged. Re-confirm on the real-guitar APK test; if guitar
chords drop out on a quieter mic, lower `chordConfRise` (the probe re-tunes it
in seconds).
