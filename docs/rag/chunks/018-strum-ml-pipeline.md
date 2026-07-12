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
