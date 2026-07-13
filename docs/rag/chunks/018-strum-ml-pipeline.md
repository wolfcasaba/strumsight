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

## r164 — the REAL-recording A/B: the heuristic collapses on real guitar

`test/tools/klangio_real_ab_test.dart` (auto-skips without the local dataset)
ran both classifiers over the SAME 16 eval recordings / 2 013 labeled strums:

| | detection | direction accuracy |
|---|---|---|
| heuristic (full StrumAnalyzer stream) | 1 477/2 013 matched (73 %) | **38.9 %** |
| CRNN (full Dart serving chain) | verdict at every label | **86.7 %** |

Two hard findings:
1. **The heuristic's sub-band rise cue does not survive real phone-mic
   recordings** — 38.9 % is BELOW coin-flip (systematically anti-correlated),
   while the same code is 100 % on the synth suite. Symmetric with the CRNN's
   38 % on synth: the two domains share almost no cue structure. Every
   heuristic direction number ever measured on synth (r59/r60 ~88 %) says
   NOTHING about real-world accuracy. The confidence tier kept this honest in
   the UI, but the moat feature on real guitars effectively starts with the
   CRNN.
2. **The Dart serving chain reproduces the Python eval EXACTLY** (86.7 % vs
   0.8669) — resample + log-mel + window + forward have zero drift; the
   parity-fixture discipline paid off end-to-end.

Also honest: SuperFlux matched only 73 % of labeled strums in continuous real
strumming (±0.12 s window) — onset recall on real audio is its own next
thread (may be masking/legato labels, needs listening, not assumed a bug).

Deployment decision (r165): the ANALYZE path switches to the CRNN (full clip
available, no deadline) with heuristic fallback when the asset is missing;
the LIVE path keeps the heuristic verdict at 70 ms (the 240 ms window can't
make the arrow deadline) — the candidate fix there is a delayed-refine pass
(arrow updates ~170 ms later when the CRNN disagrees) which needs on-device
UX testing, or the streaming-GRU variant (chunk 015).

## r167 — the latency-accuracy curve (local trainings, real fold)

True deadline-limited models (audio zeroed past onset+D — a naive
POST_FRAMES=7 frame cut scored 0.844 but leaks ~118 ms of future audio via
the 2048-sample FFT tail; only audio-truncated numbers are honest):
**70 ms → 0.799**, **188 ms → 0.856**, full ~240 ms → 0.867; the heuristic's
real-audio 0.389 is the live baseline. At DEPLOYED (detected, r144-corrected)
event times the shipped model scores 85.9 %; an extra +15 ms window shift
gains +0.4 only → not applied (eval-fold-fitting risk). Detector-vs-label
median offset: raw SuperFlux time −42 ms (the r144 +2.5-hop correction
covers most of it). Experiments: ml/experiment_deadline.py /
experiment_short_window.py; probes kept as auto-skip harnesses in
test/tools/. r168 = ship the true-70 ms model behind the live classifier
seam (arrow timing unchanged, 38.9 %→~80 %); 188 ms refine optional later.
Ops lesson: never pipe a background training through `tail` — the first
run's 70 ms RESULT line was lost and cost a 15-minute retrain.

## r168 — the LIVE model is built and serve-proven (integration pending)

`weights_live_d70.npz` (eval 0.7968, best-epoch restore) → export via
`ml/export_live_weights.py` → `assets/ml/strum_crnn_live.bin` + an
audio-truncated 32-window parity fixture. Dart: `LiveCrnnFrontend` (raw ring
fed per fast hop; at classify time rebuilds `window_truncated` EXACTLY — the
truncation IS the audio availability at onset+12 hops; window centre =
onset+2.5 hops, the r144 reported-time instant) + `LiveCrnnStrumClassifier`
behind the r139 seam, tryLoad→null = heuristic. **Serve-chain proof on the
eval fold: 79.8 % vs 79.9 % training eval** (zero drift through ring +
slice-resample + zero-tail rows; harness
`test/tools/live_crnn_serve_harness_test.dart`, floor 0.70). Heuristic serve
was 39.2 %. NOT yet wired into the app: LivePipeline constructs
StrumAnalyzer inside the DSP isolate, so the asset bytes must travel at
engine start (r169) — same bytes-through-compute pattern as the r165
Analyze wiring.

## r169 — the live model is WIRED: the app's arrow now comes from the CRNN

`RealStrumEngine.start()` loads `assets/ml/strum_crnn_live.bin` on the main
isolate (cached per app run) and ships the BYTES in `_DspInit`;
`LivePipeline(crnnWeights:)` parses them and puts `LiveCrnnStrumClassifier`
behind the r139 seam (null/garbage → heuristic, wiring pinned by
live_pipeline_ml_wiring_test). Every live consumer upgrades at once: the
Live arrow, Learn scoring, streak crediting — real-guitar direction goes
38.9 % → ~79.8 % at UNCHANGED arrow timing. The batch/Analyze path keeps its
own full-window model (0.867). Still open: 188 ms delayed-refine (85.6 %) as
a second stage; the real-guitar APK test remains the final gate.

## r170 — live confidence CALIBRATED; confidence cannot gate noise

Fold measurement (2 018 matched strums): the raw softmax is overconfident —
p<0.7 → 58 % correct, 0.7–0.9 → 63 %, 0.9–0.97 → 74 %, ≥0.97 → 86 % — and
FALSE-ALARM onsets score the same raw confidence as real strums (median 0.94
vs 0.97), so confidence can NOT be used to suppress noise arrows (that stays
the onset detector's precision job; r166 trade-off holds). Fix shipped:
`LiveCrnnStrumClassifier.calibrate` — piecewise-linear raw→P(correct) through
the measured knots, so the emitted confidence keeps the heuristic-era meaning
and the UI tiers (≥0.75 high / ≥0.45 mid) regain semantics ("high" ≈ raw
≥0.94 ≈ 74–86 % real accuracy). Batch/Analyze model calibration NOT yet
measured (different model) — its confidences feed share cards/timeline only.

## r171 — cost measured + conv repack; batch confidences calibrated

(a) Learn scorer × confidence: CLEAN — the scorer consumes direction only,
never confidence; the r170 calibration cannot affect scoring.
(b) Live classify cost (JIT test VM, this box): windowAt 1.9 ms + forward
42.6 ms/strum → **33 ms** after repacking the conv kernels per-tap to [o][c]
(the original [c][o] layout strided the kernel by outC on every inner step).
~16.5 M MACs; AOT release is typically 3–5× faster, verdicts run once per
strum (≥150 ms apart) — a few fast-hops of inbox backlog per strum, drains
immediately; acceptable, bound locked at <60 ms JIT in the cost harness.
observe() = 8.7 µs/hop (ring append, trivial).
(c) BATCH model calibration (eval fold, labeled times): <0.7 → 62 %,
0.7–0.9 → 64 %, 0.9–0.97 → 73 %, 0.97–0.995 → 83 %, ≥0.995 → 96 % (n=1203,
60 % of verdicts) — far better top-end than the live model (the full window
is decisive), still overconfident below 0.97. `StrumCrnn.calibrate` shipped
(same piecewise pattern as r170) so timeline/share percentages read as
P(correct).

## r172 — HONEST MEASUREMENT: the reported numbers were optimistic (no new data)

Before r172 ONE seed-42 fold did quadruple duty — EarlyStopping validation,
headline test, hyperparameter selection (deadline/window), AND the calibration
fit — and all three guitarists sat in both train and eval. So 0.867/0.799 were
"new take, SAME player" numbers, restore-best-over-epochs, calibrated in-sample.
`ml/honest_eval.py` repriced everything on the box (10 real trainings; results
in `ml/model_card.json`, dataset pinned to Klangio SHA `929e403f`):

- **Proper 3-way split (val early-stops, test touched once), batch/Analyze:**
  test **0.852** (was 0.867). Seed-stable: 3 seeds → **0.853 ± 0.003** (the fold,
  not the seed, is the variance). Cluster-bootstrap over the 12 test recordings:
  95 % CI **[0.768, 0.909]** — wide, because n=12 recordings, not 1614 windows.
- **Leave-one-guitarist-out CV — the honest NEW-PLAYER number** (each of players
  1/2/4 held out entirely):
  - batch/Analyze **0.707 ± 0.017** (folds 0.714 / 0.722 / 0.684)
  - live-70 ms **0.606 ± 0.055** (folds 0.651 / 0.639 / **0.529** — the worst
    unseen guitarist is near coin-flip on up/down).
  The ~15-point same-player→new-player drop is the real deployment gap and is
  the case for the r172-roadmap's multi-guitarist data + per-user last-layer
  fine-tune. It does NOT change the shipped model — it prices it.
- **Calibration hygiene:** refit the live piecewise map on VAL, scored ECE on
  TEST → raw softmax ECE **0.150 → calibrated 0.088**. The method generalises
  out-of-sample (halves ECE). The VAL-fitted knots are NOT written back to the
  Dart: they are measured on LABELED onsets, whereas the shipped
  `live_crnn_classifier.dart` knots are fit on DETECTED onsets (which include
  false alarms that lower P(correct) at every confidence) — different
  populations, not interchangeable. A production re-fit needs the detected-onset
  probe on a held-out fold, which the r172-roadmap's learned onset head enables.

Kept honest: no parameter was tuned to lift the LOGO number; it is reported as
measured. Repro: seeds via `train.py::set_seeds`; splits
`klangio.split_by_recording_3way` / `logo_folds` (8 pytest guards, no
recording- or guitarist-straddle). `ml/model_card.json` is the provenance record
(regenerate, never hand-edit). The legacy seed-42 two-way split stays only for
fixture back-compat.

## r173 — augmentation tried against the new-player gap: MEASURED NEGATIVE, not shipped

Hypothesis (research chunk lever): multiply the 3 real guitarists with audio
augmentation to close the r172 new-player gap. Built `ml/augment.py` (pure-NumPy:
varispeed pitch-shift ±6 [Murgul's spectrogram optimum], synth-RIR reverb,
mic-sim EQ/band-limit, gain, additive noise), AUG_N=2 augmented copies + clean
per TRAIN recording, plus dropout 0.25 / recurrent-dropout 0.15 / L2 1e-4
regularization. Re-ran the SAME `logo_folds` splits (`honest_eval.py` sections
`logo_aug`/`threeway_aug`). Result — it did NOT help; it slightly HURT:

| LOGO (new-player) | r172 clean | r173 augmented |
|---|---|---|
| batch/Analyze | 0.707 ± 0.017 | **0.699 ± 0.009** (flat, within noise) |
| live-70 ms | 0.606 ± 0.055 | **0.529 ± 0.095** (worse AND noisier) |
| same-player 3-way (batch) | 0.852 | 0.845 |

Why it backfires (the honest read): the pitch-shift is **varispeed** — it
stretches/compresses TIME as it shifts pitch, and reverb+noise smear the strum's
sub-band onset envelope, which is the exact temporal cue up/down direction is
read from. The live-70 ms model, with only 70 ms of context, is hurt most (0.61
→ 0.53). So naive audio augmentation is the wrong lever for a *timing*-based
direction task. **Not shipped** — the production model stays the r168/r172 one;
`augment.py` is kept as an evaluated-and-rejected experiment (HORIZON: log the
rejected attempt). Verified on TWO independent machines: the ARM dev box and the
x86 CI trainer (`.github/workflows/ml-train.yml`) reproduced the same negative.

Next lever (supersedes augmentation): the r172-roadmap's **multi-head learned
onset** (Klangio recipe — fixes false-onset confidence, replaces the heuristic
detector) and **per-user last-layer fine-tune**; more real guitarists would help
but no public strum-direction dataset beyond Klangio exists.
