# ML research synthesis — 2026-07-13 (3 Opus-4.8 agents: best practices, pre-trained models, pipeline gap audit)

Question: how should StrumSight's ML be set up properly — copy how others do it, or adopt a ready-made model?

## Verdict

**No pre-trained model is worth adopting. Keep our CRNN; copy the Klangio ISMIR-2025 recipe
(arXiv:2508.07973) — which is our architecture's published twin — and fix our measurement statistics first.**

## The one paper that reframes everything

Murgul et al., *Joint Transcription of Acoustic Guitar Strumming Directions and Chords* (ISMIR 2025,
arXiv:2508.07973; data+code: zenodo.org/records/17706490). Same front-end as ours (16 kHz log-mel,
229 bins, hop 160), CRNN with a **shared trunk and multiple heads**: strum-activation (onset),
up/down direction, 24 maj/min chords. Results on real audio: **90.06% chords, 97.6% strum-onset F1
— vs 79.3–79.5% F1 for heuristic onset detectors** (spectral flux / superflux / CD-ODF).
We already train on their GST-MM dataset (`ml/klangio.py`).

**Implication:** our heuristic onset detector (91% recall / 83% precision) and the
"model equally confident on false onsets" problem (r170) are the exact things they fixed by making
onset a *learned head of the same network*. Rejection/confidence must move off the chord/direction
softmax onto a supervised strum-present head.

## Pre-trained model survey (why "adopt" loses)

| Candidate | Blocker |
|---|---|
| Klangio 2025 CRNN (90.06%) | no published weights — but full recipe + dataset public |
| autochord (CC-BY) | 67.3% — below our 86.7%; GPL NNLS-Chroma front-end |
| BTC transformer (MIT) | bi-directional → non-causal, unusable at 70 ms live; heavy |
| madmom | model weights CC BY-**NC**-SA — blocks any commercial path |
| Essentia models | CC BY-**NC-ND** — no shipping, no distillation |
| Chordino/NNLS | GPL-2; template-class method our CRNN already beats |
| Spotify basic-pitch (Apache-2.0, <17k params, TFLite) | notes not chords; optional offline-Analyze spike / teacher only |

## Gap audit of our own pipeline (P0s first)

Full audit in the r171 round notes. Ranked findings:

- **P0 — one fold does everything:** the seed-42 eval fold is simultaneously early-stopping
  validation, headline test set, hyperparameter selector (70 ms deadline, window length), and the
  calibration fit set (`train.py:82`, `experiment_*.py`, `live_crnn_classifier.dart:161`).
  0.867 / 0.799 are optimistically biased; the calibration is in-sample.
- **P0 — no held-out guitarist:** all 3 players are in both train and eval → the "new user"
  accuracy is unmeasured. Fix: leave-one-guitarist-out CV.
- **P1 — irreproducible:** no `tf.random.set_seed`, single-run point estimates, no CIs
  (windows cluster within recordings → cluster-bootstrap over recordings, not windows).
- **P1 — no regularization** beyond (leaky) early stopping on 364k params / ~9.7k correlated
  windows (95% of params in one GRU input kernel); observed train 0.99 vs val 0.84.
- **P1 — no no-strum class / hard negatives:** ~1 in 6 live arrows is a false-alarm onset the
  model confidently labels.
- **P2 — augmentation is a README TODO, not code.** Proven recipe: pitch-shift ±6 st (Murgul
  ablation optimum), RIR+noise, mic-sim EQ/band-limit; augment the REAL recordings, synth is
  supplement only (their synth-only up-strum F1: 52.6%).
- **P2 — data/model versioning:** Klangio fetch unpinned (main), no dataset hash / model card.
- Strengths confirmed: Dart↔Keras parity fixtures, by-recording split, fold-only norm stats —
  serving chain is trustworthy.

## Datasets to add

- Murgul Zenodo release (17706490) — only public strum-direction corpus; check vs what klangio.py already pulls.
- **GuitarSet** (CC-BY 4.0, 6 players, 3 h, hexaphonic, chord labels) — player/guitar diversity.
- IDMT-SMT-Guitar subset 4 + IDMT-SMT-Chords — chord+rhythm eval.
- EGDB (DI + amp renders) — timbre augmentation.

## Roadmap (agreed order)

1. **r171 — honest measurement (no new data needed):** framework seeds; train/val/test 3-way split;
   leave-one-guitarist-out CV (3 folds, mean±std); cluster-bootstrap CIs; refit calibration on val,
   report ECE on test; pin Klangio commit + model card. This reprices every number we quote.
2. **r172 — multi-head CRNN (Klangio recipe):** shared trunk → strum-activation head (+ hard
   negatives mined from non-onset regions) + direction head; causal GRU for live; rejection &
   confidence move to the strum head (temperature scaling on P(true onset); UI confidence =
   P(strum)×P(dir|strum)).
3. **r173 — data:** augmentation in the dataset builder (pitch ±6, RIR, noise, mic-sim, SpecAugment);
   pull GuitarSet/IDMT; dropout + weight decay on the trunk.
4. **later:** "calibrate my guitar" per-user last-layer fine-tune (frozen trunk), gated on the
   LOGO gap measured in r171; basic-pitch offline spike only if Analyze needs a cross-check.
