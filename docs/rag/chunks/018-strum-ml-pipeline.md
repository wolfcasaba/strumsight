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
1. Add `flutter_litert` (researched 2026-07-12: tflite_flutter-compatible, 16 KB-page
   compliant, no win32 dep); inference in the existing DSP isolate.
2. ✅ **DONE round 139** — `StrumDirectionClassifier` seam
   (`lib/features/live/engine/dsp/strum_direction_classifier.dart`): streaming-shaped
   contract (`observe(rawFrame, features)` EVERY hop → the CRNN keeps GRU state /
   log-mel from the raw frame, the heuristic reads the analyzer's precomputed band
   features — no duplicate FFT; `classifyAt(onsetFrame, currentFrame)` when the
   analyzer's 12-frame evidence window elapses). `HeuristicStrumClassifier` = the
   chunk-006 fusion moved verbatim; behaviour pinned by the direction tests + the
   randomized gate; the seam contract pinned by an injected recording classifier.
3. Feed the on-device log-mel (standardised with `norm.npz`) to the stateful GRU.
4. **Acceptance = the real-guitar APK test**, never synthetic F1 (HORIZON).

## AS BUILT round 134 (2026-07-12) — the Dart front-end parity contract
`lib/features/live/engine/dsp/log_mel_extractor.dart` (`LogMelExtractor`) is the
on-device port of `features.py::log_mel` — identical params, sparse triangular
filters, `processFrame` as the streaming primitive. The contract is enforced by
a golden fixture (`ml/make_logmel_fixture.py` → `test/fixtures/logmel_parity.json`,
25 frames × 128 mels, max |dart−python| < 1e-3). Re-generate the fixture in the
SAME commit as any features.py change.

## Honest status (UPDATED 2026-07-12 — supersedes "the dataset does not exist")
**The ISMIR-2025 dataset/code/checkpoint went public** (API-verified):
`github.com/Klangio/guitar-strumming-transcription`, Apache-2.0, ~770 MB in-repo —
56 recording sets (90 min real audio, 3 guitarists, `_phone.wav` mic variant =
our deployment condition, `.strums` direction labels, IMU CSVs), training
scripts, pretrained checkpoint (f1=0.8225, Git-LFS). Correction to chunk 015:
the paper used 90 min real + 4 h VST-rendered synthetic (not 94 h); their
ablation: joint synth+real training BEATS sequential pretrain→finetune, and
VST-rendered synth ≫ pure Karplus-Strong (89.8 % vs 66 % synthetic-only on the
sibling task). A user recording session is now OPTIONAL domain adaptation.
Full plan: `docs/plans/ml-track.md`.

## AS BUILT round 140 (2026-07-12) — Klangio adapter (`ml/klangio.py`)
`.strums` format VERIFIED on real files: `time_s \t D|U \t chord-label`
(TAB-separated; e.g. `0.451 D C-major`). Adapter: strict parser (unknown
direction letter = loud ValueError, never a mislabel), `windows_for_recording`
cuts the chunk-018 log-mel window at each LABELED time (annotations are ground
truth — onset detection is NOT in the training loop), `build()` →
`klangio.npz` with the exact model-input shape. **Proven end-to-end on real
data:** sets 1001+1002 (fetched via raw.githubusercontent; `ml/data/` is
gitignored — third-party data stays out of the repo) → **162 windows
(15, 128) float32, 49 down / 113 up**. Dataset quirk worth knowing: takes are
direction-SEPARATED (1001 all-D, 1002 all-U) — draw train/eval splits across
MANY recording ids or the split leaks direction via recording identity.
Wavs are 44.1 kHz mono 16-bit; `prepare_dataset._read_wav` linear-resamples
to 16 kHz (documented approximation; upgrade to polyphase if accuracy stalls).

## Full label statistics (round 141 — all 82 .strums parsed)
**11 767 strums over 81.4 labeled minutes: 7 228 down / 4 539 up (38.6 % up —
up IS the minority class, as the papers warn; keep the class weight).**
70/82 recordings are mixed-direction (the r140 all-D/all-U pair was just the
first two takes). Guitarist id-prefixes 1/2/4 ≈ 4 069/3 977/3 721 strums.
Chord vocabulary (12): G 2 216 · C 1 982 · D 1 804 · A 1 546 · E 1 283 ·
F 1 024 · B 860 · F# 408 · Bb 284 · C# 138 · Bm 124 · Am 98 — heavily
major-biased; minor-chord strum audio is scarce (relevant if the joint
chord+direction head is ever trained). **Split rule (r141, enforced in code):
`klangio.npz` carries `rec` (recording id per window); `train.py` splits BY
RECORDING via `split_by_recording` (never window-level — identity leak).
Guitarist-level splits (id prefix) remain the stricter option if eval looks
too rosy.**

## r142 audit — the dataset is now REALLY consumable + guarded
All 82 `_phone.wav` takes downloaded (~300 MB, `ml/data/` local-only):
`build()` → **11 767 windows**; `split_by_recording` → train 9 754 (38.4 % up,
66 recs) / eval 2 013 (39.5 % up, 16 recs) — both folds direction-balanced.
Guards added after the audit's BLOCKER (the first two fetched takes were
all-D/all-U → a model would have trained on zero up-strums with green tests):
`assert_folds_trainable` (single-class fold = loud ValueError, called by
train.py), `split_by_recording` keeps BOTH sides non-empty (raises on <2
recordings), labels past the audio end are SKIPPED not zero-emitted, and
train.py computes norm.npz from the TRAIN fold only (eval-leak fix). The
ready `ml/klangio.npz` (82 MB, gitignored) sits on this box for the training
run. Deferred (recorded): an end-to-end isolate-plumbing test for the
expected-chord hint, re-checking the input-latency default against
SuperFlux's onset instant on the real-guitar gate.
✅ r143 closed the parity-fixture gap: `logmel_parity_cases.json` adds
clipped/DC-offset/near-floor adversarial cases (all ≤1e-3), and BOTH fixtures
now compute the Python reference from the ROUNDED pcm the JSON actually
ships (N2 — identical input on both sides).

## r163 — the model is TRAINED and shipping IN PURE DART (2026-07-13)

The "ARM64 box can't run TF" premise was stale: **TF 2.21 ships official
linux/aarch64 wheels** — installed into `~/tf-venv`, and `ml/train.py` ran the
full training HERE (no PAT, no Colab). Results on klangio.npz (11 767 windows,
recording-level split): **val_accuracy 0.867** (best epoch 9, EarlyStopping
patience 8, `restore_best_weights=True` — added after observing epoch-8
overfit: train .98 / val .84 / val_loss rising). Class weights up-weight the
minority up-strums.

**Shipping path is PURE DART, not tflite_flutter** (P1.3 revised): the net is
~350 k params ≈ 1.4 MB float32 → `ml/export_dart_weights.py` writes
`assets/ml/strum_crnn.bin` (SSML v1 binary: named arrays + train-fold
mean/std) + a 32-window eval-fold parity fixture. Dart side:
`CrnnStrumNet` (conv×3 + reset-after GRU + softmax, parity ≤1e-3 vs Keras
locked by test), `CrnnFrontend` (linear resample 44.1→16 k + `window_at`
port, both parity-pinned), `StrumCrnn` facade (clip → per-onset verdicts,
`tryLoad` → null = heuristic fallback). Real-domain accuracy gate: ≥0.75 on
the 32 fixture windows (measured 0.91). The keras TFLite converter CRASHES on
the GRU TensorList lowering in TF 2.21 — non-fatal now (weights export first;
`strum_model.keras` saved for re-exports); the tflite artifact is optional.

**A/B finding (P1.4, measured, 24 randomized synth strums):** heuristic
24/24; CRNN 9/24 (seed 42) / 8/24 (seed 7123) — the real-guitar-trained model
is systematically WRONG on the synthetic stagger cue while at 0.867 on real
phone-mic eval. Consequence: **the synth suite cannot arbitrate
heuristic-vs-model**; deployment needs the reverse measurement — the
HEURISTIC evaluated on the real Klangio eval recordings (r164) — before the
Analyze path may switch. The CRNN window needs ~240 ms post-onset audio, so
the LIVE path (70 ms verdict deadline) keeps the heuristic regardless;
deployment target is the batch/Analyze path.
