# ML Chord-Recognition Track — Plan

> **Green-lit 2026-07-14** (user order, after the DSP full-band ceiling was measured at ~59 % on the
> CI real-audio probe — see `full-band-chord-ceiling` memory / HANDOFF r182). Goal: recognise chords
> in **full-band songs** (guitar + bass + drums), which is a deep-model problem, not a DSP knob.
> Built from a 3-agent research sweep (architecture, data strategy, infra reuse) — sources at the bottom.

## The one-paragraph plan
Train a **CQT → small CNN → BiGRU → 25-class majmin softmax** model in TensorFlow on x86 CI, decode
per-frame posteriors with the **existing `ViterbiChordDecoder`**, and infer in **pure Dart** exactly
like the shipped strum CRNN (forward-only stateful for Live, bidirectional batch for Analyze). Data =
a **MIT-licensed FluidSynth synthesis pipeline** (guitar+bass+drums, ±6-semitone transposition,
frame-perfect labels from MIDI) + the **CC-BY AAM** 3k-track corpus as the synthetic bulk, **fine-tuned
on real CC-BY GuitarSet**; evaluate ONLY on held-out real audio (leave-one-guitarist-out GuitarSet + a
self-recorded full-band set) with `mir_eval` MIREX metrics. Keep the shipped chroma-`ChordDictionary`
as a **secondary 7th/sus refiner** on top of the neural root+maj/min decision (hybrid). Synthetic green
is a CI tripwire only — the real-guitar/full-mix APK test stays the acceptance gate.

**Why this can work when the strum-synth transfer failed:** chord identity is *harmonic content*, which
survives synthesis; strum direction is *attack micro-timing*, which does not. The AAM study quantifies
it — synthetic as supplementary data lifted **real** Billboard Root accuracy 72.8 %→83.1 %.

---

## Architecture (v1)
- **Front-end — CQT.** 22.05 kHz · **24 bins/oct × 6 oct from C1 = 144 bins** · hop **2048** (~93 ms,
  = the existing chord hop) · log-amplitude + per-bin normalization. Implement as a **precomputed sparse
  kernel × FFT** (cheap in Dart). Parity-contracted Python `ml/features.py::cqt` ↔ Dart `CqtExtractor`,
  same golden-fixture pattern as `log_mel_extractor_test.dart`. (Chunk 016 rec #4 already pre-authorised CQT.)
- **Model (TF).** 3 conv blocks (16/32/32, 3×3, ReLU, BatchNorm, MaxPool **1×2** = pool freq only) →
  flatten per frame → Dense 128 → **BiGRU 96–128** → Dense **25** softmax (per frame). ~150–400k params
  (same order as the strum CRNN). `return_sequences=True` + TimeDistributed head.
- **Vocab — majmin-25.** 12 major + 12 minor + **N.C.** Maps 1:1 to `ChordDictionary` labels; collapse
  the model target of richer qualities to their triad (Cmaj7→C). 7ths/sus stay alive via the secondary
  chroma-dictionary refiner. (v2 = McFee/Bello structured root/quality/bass multi-head for large vocab.)
- **Decode — reuse `ViterbiChordDecoder`.** Feed 25-dim **log-posteriors** instead of chroma cosine;
  the self-bonus, `expectedPrior`, onset-boost, online + `decodeBatch` all work unchanged. Re-fit
  `selfBonus` for the log-posterior scale (the one knob). Online forward-only GRU = Live; batch bi-GRU = Analyze.
- **Augmentation.** ±6-semitone transposition = an **integer CQT bin-roll + label transpose** (×12 data,
  key-invariance). The single biggest robustness lever.
- **Realistic ceiling:** ~**75–82 % majmin WCSR** on full-band pop; large-vocab strict caps ~66 %.

## Data (all license-clean to ship)
1. **Synthetic full-band core (~80 %).** `ml/chords/synth_songs.py`: render ~2–5k tracks with FluidSynth
   + **FluidR3_GM (MIT)** / **MuseScore_General (MIT)** — guitar + bass + drums, progressions drawn from
   the *statistics* of the free Billboard/RWC label sets, tempo/voicing/dynamics randomised, frame-perfect
   labels from the source MIDI. + post-render aug: ±6-semitone, multi-soundfont, reverb/EQ/mix/noise.
2. **AAM (CC-BY-4.0, 3k tracks)** — ready-made synthetic full-band chord data (Zenodo 5794629); drop in.
3. **GuitarSet (CC-BY-4.0, ~3 h real guitar)** — the real-audio anchor to close the synth→real gap.
4. *(research-only, non-redistributable)* RWC-Popular + Cho-Bello labels for extra real fine-tuning.
   **Excluded from training:** Isophonics/Billboard/USPOP/JAAH audio (copyright) → used only for their
   free Harte label vocabulary + `mir_eval` metrics. SoundCloud-title clips → held-out qualitative sanity
   only (copyright + weak labels), never training truth.
- **Recipe:** pretrain on (1)+(2) synthetic → fine-tune / mix in (3) GuitarSet [+ optional (4) RWC].
- **On-box now:** the **Klangio `.strums` files already carry per-strum chord labels** the current
  pipeline parses then discards (`klangio.py:70`) — real solo-guitar chord data, free, for the first
  end-to-end pipeline shakedown before the full synthesis corpus exists.

## Evaluation (the honest gate)
- Held-out **real audio only**: leave-one-guitarist-out **GuitarSet** (new-player, mirrors the strum LOGO)
  + a small **self-recorded full-band** set (known progressions over backing) hand-labelled.
- `mir_eval` MIREX metrics: **Root / MajMin / MajMinBass / Sevenths**.
- Synthetic randomized-property test (`PROPERTY_SEED`, %-threshold) = CI regression tripwire ONLY.
- **Acceptance = the real-guitar APK test.** Synthetic/CI green ≠ done (HORIZON).

## Infra reuse (~90 % — see the 3-agent map)
Reusable ~verbatim: `train.py` loop (split-by-recording, best-val restore, train-only norm, class-weight,
`weights.npz` export, `set_seeds`), the SSML `write_bin` binary + `CrnnStrumNet.parse` (name/shape-generic,
`nClasses` auto), the Dart conv/pool/dense/softmax ops, `klangio.split_by_recording`/`logo_folds`/`_read_wav`,
`ml-train.yml` (SHA-pinned fetch, x86 TF, artifacts), `ViterbiChordDecoder`.
Net-new: CQT front-end (Py + Dart parity), a frame-wise chord-label→class mapper (Harte→25), a
`return_sequences` GRU variant in Dart (today's `_gruLastState` emits last-state only), a `ChordCrnn`
Dart facade, generalise `assert_folds_trainable` beyond `{0,1}`, and a clone of `ml-train.yml` for chords.

## Phases
- **P0 — Data + features groundwork (pure Python/NumPy + Dart parity).**
  - P0.1 `ml/chords/labels.py` — Harte/dictionary label → 25-class majmin index (+ transpose), + pytest.
  - P0.2 `ml/chords/synth_songs.py` — FluidSynth guitar+bass+drums renderer + frame-perfect labels (runs
    on CI: `apt-get install fluidsynth` + a MIT soundfont). Small smoke corpus first.
  - P0.3 CQT: `ml/features.py::cqt` (NumPy) + a golden fixture; Dart `CqtExtractor` parity port + test.
  - P0.4 Klangio chord-label adapter (`windows_for_chord`) for a first real-data shakedown.
- **P1 — Train v1 on CI.** `ml/chords/train_chord.py` (reuse `train.py`), synthetic bulk + GuitarSet
  fine-tune, ±6 aug, export `assets/ml/chord_crnn.bin` + parity fixture. `mir_eval` LOGO report.
- **P2 — Dart inference + decode.** `ChordCrnn` (per-frame GRU) → log-posteriors → `ViterbiChordDecoder`;
  wire behind the Analyze/import path first (batch, bidirectional) with a heuristic fallback seam
  (model is an upgrade, never a dependency — the r139/r165 pattern).
- **P3 — Hybrid + Live.** Secondary chroma-dictionary 7th/sus refiner on the model's root+maj/min;
  forward-only Live variant; A/B vs the DSP path on the CI real-audio probe + the APK test.
- **v2 (later):** structured root/quality/bass multi-head (sevenths/inversions); self-train pseudo-labels
  on MTG-Jamendo (55k CC tracks) to scale real-domain coverage.

## Sources
Korzeniowski & Widmer 2016 (arXiv 1612.05082, WCSR 82.9 % majmin, CNN+CRF) · McFee & Bello 2017 ISMIR
(structured root/quality/bass) · BTC 2019 (arXiv 1907.02698, CQT 22.05k/24-bin/6-oct/hop-2048/25-class) ·
Lardet 2025 (CRNN BiGRU, GRU +5.2 pts, ~66 % large-vocab ceiling) · "Training chord recognition models on
artificially generated audio" 2025 (arXiv 2508.05878, synth-supplement 72.8→83.1 % real Root) · GuitarSet
CC-BY (Zenodo 3371780) · AAM CC-BY (Zenodo 5794629) · FluidSynth + FluidR3_GM/MuseScore_General (MIT) ·
`mirdata`/`mir_eval` · MTG-Jamendo CC (Zenodo 3826813). Internal: `docs/rag/chunks/016-pitch-chord-sota.md`,
`viterbi_chord_decoder.dart`, `chord_dictionary.dart`, `ml/klangio.py`, `ml/train.py`.
