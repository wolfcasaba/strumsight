---
id: 018
topic: Strum-direction ML pipeline — dataset, training, on-device deployment
tags: [strum, ml, crnn, tflite, dataset, imu, log-mel, pipeline, ml-dir]
sources:
  - https://arxiv.org/abs/2508.07973 (Joint Transcription of Guitar Strumming + Chords, ISMIR 2025)
  - docs/rag/chunks/015-strum-direction-ml.md (the research)
  - ml/ (the implementation: features.py, prepare_dataset.py, train.py, test_pipeline.py)
built: 2026-07-10 (round after 64; data pipeline verified, TF step specced)
---

# Strum-direction ML pipeline — AS BUILT (data path) + spec (model path)

Chunk 015 established WHY (heuristic maxed ~88 %, round 60) and WHAT (a small
streaming CRNN → up-strum ~79 %). This chunk is the concrete pipeline, in `ml/`.

## The blocker, solved: a labeled dataset from a worn IMU
No public dataset has per-strum down/up labels. Build one cheaply: **wear any
Wear OS watch / motion earbud on the strumming wrist while recording** — the
wrist accelerometer swings opposite ways for down vs up, giving free labels
aligned to audio onsets (exactly how the ISMIR-2025 team labeled 94 h). The
watch is a *labeling tool*, never shipped.

Per take: `<name>.wav` (mono, any sr) + `<name>.accel.csv` (`t_seconds,axis`,
200 Hz). `axis` = the wrist channel that reverses sign between strokes; fixed
per rig at collection (negate it if labels invert).

## Features (MUST match on device)
`ml/features.py`, pure NumPy: **16 kHz, 2048-win / 160-hop (10 ms), 128 mel from
30 Hz, log**. A model-input window is `PRE_FRAMES=3` (30 ms) + `POST_FRAMES=12`
(120 ms) = 15 frames around each onset. The Dart inference path MUST compute the
identical log-mel and apply the trained per-mel mean/std (`norm.npz`) — the
`StrumAnalyzer` already owns the FFT, so this is a mel-filterbank + log on top.

## Auto-labeling
`label_direction_from_accel(t, axis, onset_s)` = sign of the mean wrist-axis over
a 120 ms window at the onset (`+`→down, `−`→up, ~0→skip as ambiguous). Onsets for
alignment come from a simple spectral-flux detector (`spectral_flux_onsets`);
the on-device detector stays authoritative at runtime.

## Model (spec — `ml/train.py`, needs TF, run in CI/Colab)
log-mel window → 3 conv blocks (16/32/48, pool freq only) → **GRU(128)** →
Dense(2 softmax). Class-weight up-strums (minority + harder). Export TFLite with
default (int8-ish) optimization. **Deploy streaming**: run the GRU **stateful**,
one 10 ms hop at a time, conv lookahead tiny (<30 ms) — so latency stays inside
the live budget. Augment with **±6-semitone pitch shift** before training
(gave +14 % rel. up-strum in the paper).

## AS BUILT / AS VERIFIED (this round)
- `ml/features.py`, `ml/synth.py`, `ml/prepare_dataset.py` — the NumPy data
  pipeline (verifiable on the ARM64 dev box).
- `ml/test_pipeline.py` — **PASSES** (7/7): log-mel shape/finiteness, onset
  found near the attack, IMU auto-label recovers BOTH down and up on synthetic
  data, model-input window shape. Run: `python3 ml/test_pipeline.py`.
- `ml/train.py` + `ml/requirements.txt` — TF trainer + TFLite export, gated to
  x86_64 (the ARM64 dev VM can't run TF, same as it can't build the APK).

## On-device integration (spec — the next code round once a model exists)
1. Add `tflite_flutter` — **keep ONE win32 major** (repo gotcha); inference in
   the existing DSP isolate.
2. `StrumDirectionClassifier` seam: heuristic impl (today) ↔ TFLite impl (new),
   behind a flag, heuristic as fallback.
3. Feed the on-device log-mel (standardised with `norm.npz`) to the stateful GRU.
4. **Acceptance = the real-guitar APK test**, never synthetic F1 (HORIZON).

## Honest status
The dataset does not exist yet (needs a recording session with a worn IMU). The
pipeline that turns it into a trained, deployable model is built + smoke-tested.
This converts "we have no data path" into "record takes → run three commands".
