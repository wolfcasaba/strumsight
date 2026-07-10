---
id: 016
topic: On-device pitch/chord detection — priors, CQT, and a neural lead mode
tags: [pitch, chord, cqt, vqt, pesto, spice, basic-pitch, priors, latency, onset]
sources:
  - https://engineering.atspotify.com/2022/6/meet-basic-pitch (Spotify basic-pitch)
  - https://arxiv.org/html/2508.01488v1 (PESTO real-time pitch)
  - https://www.tensorflow.org/hub/tutorials/spice (Google SPICE TFLite)
  - https://www.chordai.net/next-level-chord-recognition/ (Chord AI on-device CNN)
  - https://arxiv.org/pdf/2212.03023 (TabCNN / FretNet guitar tablature)
researched: 2026-07-10 (4-agent Hermes sweep)
---

# Pitch & chord — how the leaders win, and our upgrade path

**How the market actually hits its numbers.** Rocksmith/Yousician game-mode
accuracy comes largely from a **score/expected-note prior** — the algorithm only
decides "did the *expected* note happen on time?", not open-vocabulary "what note
is this?". Rocksmith's other edge is a clean DI signal (Real Tone Cable); mic +
acoustic + noise + polyphony is the hard case where even leaders drop to ~85 %.
**Chord AI** ships an offline on-device CNN chord stack (>300 chords, batch /
whole-song) — proof the DL path fits a phone; it is NOT sub-400 ms streaming,
which is the design lever we have.

## Fastest wins — PURE DART, no ML
1. **Score/expected-target priors (biggest lever).** In lessons/songs/exercises
   we KNOW the target chord/note → bias chroma-similarity / Viterbi / f0 search
   toward the expected label ± neighbors. Grade *expected vs actually played*;
   keep an explicit **off-chart** state so the prior never masks a real mistake.
2. **Onset-aligned updates.** Trigger chord/note re-estimation at strum attacks
   (SuperFlux onset, chunk 015), hold the decoded chord between onsets, and
   **drop the Viterbi self-transition penalty right after an onset** (switch fast
   on a real strum, stable between). Cuts *perceived* latency; near-free.
3. **Expand vocabulary** (power5/sus2/dim/aug + fix the dom7→triad collapse) =
   chord-dictionary + Viterbi state additions (chunk 012), not new DSP. Require
   the distinguishing partial (b7 / tritone) to exceed a threshold before
   committing; add per-chord priors so more states don't add confusion.

## Structural upgrade — CQT/VQT front-end
Our 370 ms window exists because low-E (82 Hz) needs a long *linear* STFT window.
**CQT** uses long windows only at low frequencies, short at high → keeps low-E
resolution while mid/high partials (the 3rd/5th/7th that set chord *quality*)
update fast. Config: **24 bins/oct, ~6 octaves**; precompute the sparse kernel
once → sparse matrix multiply on the FFT (feasible in Dart). Enables a
**short-window (~80–120 ms) provisional chord + long-window bass-refine** split →
perceived chord latency **~150–200 ms** (bass firmed a beat later) without losing
low-E. Optional **median-filter HPSS** pre-stage → cleaner harmonic chroma +
the percussive residual doubles as the onset/strum-direction cue.

## Neural LEAD mode (Rocksmith-style "hit the right note in time")
- Raw mono pitch is essentially solved on clean single notes: **PESTO** (~130k
  params, **<10 ms**, streamable via cached convs, ~97.7 % RPA) is the best
  2024–25 fit; **SPICE** ships as official Android TFLite (relative pitch → needs
  calibration) as the safe drop-in; **CREPE-tiny** the accuracy fallback. YIN
  (what we have) is fine but weaker on onsets/low-string octave errors.
- The hard parts are NOT pitch: **string/octave disambiguation** (same pitch =
  several string/fret spots — needs a guitar model like **FretNet** for true
  tab, OR constrain by the expected tab position) and **polyphony bleed** (gate
  lead detection to onset windows, take the strongest/expected pitch). With an
  expected-note prior, even YIN gets into the 90s.
- Stack: PESTO/CREPE-tiny f0 + spectral-flux onset + expected-note prior →
  sub-30 ms decision; the bottleneck becomes audio I/O buffering, not the algo.

## Polyphonic transcription (a "show the notes / confirm" layer only)
**Spotify basic-pitch** (ONNX, ~16.8k params, <20 MB) is the on-device
workhorse but has a **~2 s streaming-context floor** → run it as a slow
background *confirmer / notes-view*, never the live path. **MT3** = offline
GPU-class, reference only.

## Ranked recommendations (effort × impact)
1. **[Tier 1, pure Dart] Expected-target priors** for chord/lead grading. *medium, biggest accuracy lever.*
2. **[Tier 1] Onset-aligned updates + post-onset Viterbi penalty drop.** *low, cuts perceived latency.*
3. **[Tier 1] Vocabulary expansion via dictionary/Viterbi states.** *low–medium.*
4. **[Tier 2] CQT/VQT front-end** (24 bins/oct) + short-treble/long-bass split. *higher, solves the latency/low-E tradeoff.*
5. **[Tier 2] Neural mono pitch (PESTO / SPICE-TFLite) for a lead mode.** *higher.*
6. **[Tier 2] Median-filter HPSS** pre-chroma. *medium.*
7. **[Tier 3 roadmap] basic-pitch confirm layer; FretNet guitar model for true string/tab.** *large.*

**Pitfalls:** any retuned window/CQT/onset/Viterbi param is DSP truth → same
commit to `docs/rag/chunks/`; run neural inference in a separate isolate; mic +
acoustic + noise is where leaders drop to ~85 % — prioritize noise robustness;
validate on a real acoustic guitar via the CI APK (synthetic green ≠ done).
