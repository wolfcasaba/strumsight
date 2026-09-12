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
rejected attempt). Cross-checked on TWO machines (ARM dev box + x86 CI trainer
`.github/workflows/ml-train.yml`), and the honest read is nuanced: the **live
degradation reproduced on both** (Oracle 0.606→0.529, CI 0.612→0.550, both
clearly down), but the **batch effect is WITHIN NOISE and machine-inconsistent**
(Oracle 0.707→0.699 flat, CI 0.676→0.727 slight up). Cause: high 3-fold variance
(only 3 guitarists) + different TF version/arch (Oracle TF 2.21 aarch64 vs CI
TF 2.16+ x86 — CI even read a lower same-player 3-way of 0.807 vs 0.852, so
ABSOLUTE numbers are machine-dependent; only the within-machine clean→aug DELTA
is comparable). Net: augmentation is not a dependable win and clearly hurts the
live path → still not shipped. (Earlier wording "reproduced the same negative"
was an over-claim: only the live-negative reproduced.)

Next lever (supersedes augmentation): the r172-roadmap's **multi-head learned
onset** (Klangio recipe — fixes false-onset confidence, replaces the heuristic
detector) and **per-user last-layer fine-tune**; more real guitarists would help
but no public strum-direction dataset beyond Klangio exists.

## r174 — a learned no-strum reject class BEATS the confidence gate (positive)

The r170-open problem: the heuristic onset detector fires ~1-in-6 FALSE onsets
(91 % recall / 83 % precision) and the direction CRNN is EQUALLY confident on
them (median raw 0.94) as on real strums (0.97), so confidence CANNOT gate noise.
r173 proved augmentation is the wrong lever; r174 tries the right one — give the
model a way to SAY "no strum here". Added a 3rd **no-strum class** (0=down /
1=up / 2=no-strum) trained with HARD NEGATIVES mined from the SAME recordings
(`ml/negatives.py`): spectral-flux onset PEAKS >120 ms from every labeled strum
(these approximate the detector's actual false positives) + easy interior gaps.
`build_model(n_classes=3)` (default 2 stays byte-identical — every fixture/export
parity test holds). Measured in `honest_eval.py` (`noreject_fast` / `noreject`):
each fold trains the r170 2-class baseline (positives only) AND the 3-class
reject model on the same split, and both gates are calibrated to keep **≥95 % of
TRUE strums**, then we compare how many false onsets each rejects.

**FAST proof (batch, 3-way split seed 42 — same fold as `threeway`):**

| metric | value |
|---|---|
| direction acc on TRUE strums, 2-class (r172) | 0.837 |
| direction acc on TRUE strums, 3-class | **0.815** (~2 pt cost) |
| no-strum recall (held-out negatives) | **0.979** |
| false-onset REJECTION @ ≥95 % retention — **reject head** | **0.938** |
| false-onset REJECTION @ ≥95 % retention — r170 **confidence gate** | **0.086** |

At equal 95 % true-strum retention the learned reject head suppresses **~94 % of
false onsets vs ~9 % for confidence gating — an ~11× win**, exactly the noise the
r170 finding said confidence could not touch. Cost on this single split: direction
on true strums ~2 pt (0.837 → 0.815). Dataset: 11 767 strums + 10 022 mined
negatives (balanced).

**LOGO (new-player) CONFIRMS it — and the direction cost vanishes on unseen players:**

| config | dir 2-class | dir 3-class (reject) | neg-reject HEAD | neg-reject r170 conf-gate |
|---|---|---|---|---|
| batch/Analyze | 0.678 | **0.681** (+, no cost) | **0.902 ± 0.058** | 0.070 ± 0.016 (~13×) |
| live-70 ms | 0.610 | **0.617** (+, no cost) | **0.866 ± 0.100** | 0.032 ± 0.014 (~27×) |

On the honest new-player folds the 3-class reject model does NOT hurt direction
(it's net-neutral-to-slightly-better both configs — the fast-proof's ~2-pt cost
did not generalize into a cost), while rejecting **~87–90 % of false onsets vs
~3–7 % for confidence** (per-fold no-strum recall 0.76–0.99). Honesty gate:
nothing tuned; reported as measured. This is a robust GO — confidence provably
cannot gate this noise, the learned class does, and it's free on direction.

Read: this is the **GO signal** for the r172-roadmap multi-head — the reject
capability confidence could never provide is real, large, and LOGO-confirmed at
zero direction cost. Next round (r175): wire it into the Dart live path — route
P(no-strum) as the arrow-suppression gate, retiring the heuristic detector's
precision job; then per-user fine-tune, then the real-guitar APK test.

## r175 — the learned no-strum reject is SHIPPED in the LIVE path (AS BUILT)

The r174 GO signal is now wired end-to-end. A FINAL 3-class LIVE model
(`build_model(n_classes=3)`, live-70 ms geometry) was trained ONCE on ALL
recordings (`ml/train_live_3c.py`: positives 7 228 down / 4 539 up + 10 022
mined hard negatives = 21 789 windows; split by recording → 18 069 train /
3 720 eval; train-fold norm + inverse-frequency class weights; EarlyStopping
best-val restore). Shipped asset: **`assets/ml/strum_crnn_live_3c.bin`** (SSML
v1, mirrors `export_live_weights.py`); the 2-class `strum_crnn_live.bin` is left
UNTOUCHED. Parity fixture `test/fixtures/crnn_live_3c_parity.json` (32 eval-fold
windows, 11 down / 11 up / 10 no-strum) locks the Dart 3-col softmax to Keras
`<=1e-3`.


> **E18-R25 frissítés (ADR 0549).** A fenti illesztett küszöb a modell **saját** eval
> foldján tart 95%-ot; független pengetés-anyagon (GuitarSet, 72 fájl) **59,6%**-ot. A
> szállított érték ezért **0,85**, az illesztett pedig `fittedNoStrumThreshold` néven
> marad meg a provenienciájáért. A tanulság nem a szám: **egy korpuszra illesztett kapu
> korpuszon kívül nem érvényes**, és minden új modellnél újra kell mérni — lehetőleg nem
> csak a saját foldján. Mérés:
> [`docs/eval/guitarset-strum-baseline.md`](../../eval/guitarset-strum-baseline.md).

**The suppression gate (measured on the held-out eval fold, n_pos=2013,
n_neg=1707):** the threshold on P(no-strum) that keeps **95.0 %** of TRUE strums
is **`no_strum_threshold = 0.43877`**; at that operating point it **rejects
93.0 % of false onsets** (no-strum recall 0.929; direction acc on true strums
0.807). Provenance: `ml/live_3c_threshold.json` (same rule as
`honest_eval._gate`, retention target 0.95). The value is hard-coded as
`LiveCrnnStrumClassifier.noStrumThreshold` — model-specific (per-fold thresholds
ranged 0.08–0.9998 in the r174 LOGO run, so it MUST be re-measured from the
shipped model, never reused from a fold). New-player generalisation is the r174
LOGO number: ~87 % false-onset rejection at 95 % retention vs ~3 % for the r170
confidence gate.

**Dart wiring (all behind the r139 seam):**
- `CrnnStrumNet` reads the class count from the Dense width (`nClasses`) and
  softmaxes over N — one parser serves both the 2-class and 3-class assets; the
  trunk is byte-identical, so every existing 2-class fixture/parity test still
  holds.
- `LiveCrnnStrumClassifier.classifyProbs` (pure/static, unit-tested without an
  asset) is the decision rule: 3-class + P(no-strum) > `noStrumThreshold` →
  `StrumClassification(suppressed: true)`; else emit the winning direction with
  the r170 calibration applied to the RENORMALISED down/up mass (confidence
  keeps meaning "P(arrow right | it is a strum)"). A 2-class vector never
  suppresses.
- `StrumAnalyzer.process` returns `null` on a suppressed classification, so NO
  `StrumEvent` reaches any consumer — the Live arrow, Learn scoring and streak
  all see nothing (consistent suppression). The seam is still consulted on
  every onset; suppression is a decision, not a bypass.
- `RealStrumEngine._liveCrnnWeights` prefers `strum_crnn_live_3c.bin`, falls
  back to `strum_crnn_live.bin`, then to the heuristic (null) — the model is an
  upgrade, never a dependency (r139/r169 fallback chain intact).

Kept honest: nothing was tuned to lift the gate; the threshold is the measured
95 %-retention quantile and is documented as such. The onset detector's
precision job is now BACKED by the learned reject (false onsets that slip
through SuperFlux draw no confident wrong arrow). **Acceptance remains the
real-guitar APK test** — synthetic/eval green is never "done" (HORIZON). r175 is
the last dev round before that gate.

## What limits direction accuracy (E18-R27, ADR 0550)

The live 3-class model's direction score on INDEPENDENT real strumming is far below its
own fold: macro-F1 **0.3876**, up-F1 **0.1905** on GuitarSet's Rock/Funk comping (the
shipped path, held-out players). Three rounds of scalar tuning are exhausted — the
no-strum gate moved it (ADR 0549), the down/up boundary did not (prior-matching, L664),
the margin gate never did (±0.0003).

**The defect is cross-corpus transfer, not missing data.** `ml/probe_direction_headroom.py`
fits a plain logistic regression on 240 band-pooled features taken with the model's OWN
geometry (N_FFT 2048 @ 16 kHz, HOP 160, 15 frames) and reaches macro **0.7723**, up-F1
**0.6294**, AUC **0.8928** on a player- AND tune-disjoint GuitarSet split. A linear model
is a FLOOR on what is extractable, so the cue is present in the input the CRNN already
receives and the CRNN is not extracting it.

**The corpus deficit, named.** Klangio GST-MM-2025 is real, labelled, phone-mic data
(82 recordings, 11767 strums, 38 % up — a BETTER class balance than GuitarSet's 27 %),
but `guitarist_of(rid) = str(rid)[0]` and the blocks are `1xxx / 2xxx / 4xxx`:
**three guitarists.** Leave-one-guitarist-out cannot expose player-invariance failure
when all three share one room, guitar and microphone. GuitarSet's 3038 clean derived
sweeps add six more players, and those derived labels are now qualified as trainable
(ADR 0550 D2): a model fitted on them generalises to unseen players AND unseen tunes at
AUC 0.8928 while a shuffled-label control over 7 seeds sits at 0.41–0.59.

**Two measurement rules this established:**

1. **Score the direction head on a STRICTLY POST-ONSET window.** Audio strictly BEFORE
   the onset predicts direction at AUC **0.7128**, because comping alternates
   down-up-down-up — a model with pre-onset context scores by predicting alternation.
   The app's own patterns do not alternate (`D DU UDU` has two downs in a row,
   `reggae-skank` is nearly all upstrokes), so that cue is a lie here. A 128 ms window
   centred on the onset contains the attack in EVERY frame, so a frame-index ablation
   cannot separate the two — the arms must be cut by sample range. Honest post-onset
   figure: macro 0.6645, up-F1 0.4545.
2. **Do NOT raise the input's time resolution.** Measured, with feature count held equal:
   5.8 ms window / 3.7 ms hop scores macro 0.6435 vs 0.7723 for the model's own 128 ms
   geometry. On a microphone, direction reads off spectral balance rather than the sweep's
   string ordering — even though the sweep's median span is 22.2 ms and 40.7 % of sweeps
   fall inside two 10 ms frames.

### CORRECTION and the real constraint (E18-R28, ADR 0551)

The figure above — "macro 0.7723, up-F1 0.6294 on the model's OWN input" — is **wrong**,
and the error is instructive. `probe_direction_headroom.centred_starts` CENTRES each
analysis window on its frame (`onset - PRE_FRAMES*HOP - N_FFT//2`, i.e. onset−94 ms) and
applies no truncation; the shipped `experiment_deadline.window_truncated` STARTS each
window at its frame (onset−30 ms) and zeroes everything past onset+70 ms. The probe was
handed 64 ms of extra lead-in plus the post-deadline audio — and lead-in ALONE predicts
direction at AUC 0.7128 by alternation, the very cue the same round ruled inadmissible.
Parameters matched; window POSITION did not. **Measure on the array production eats**
(`guitarset_live70.npz`), not on a re-derivation with the same parameters.

At the model's real alignment and 70 ms cut, same labels, player- AND tune-disjoint:

```
  shipped log-mel 128, 70 ms cut  <- the CRNN's input   down 0.7857  up 0.3913  macro 0.5885
  16 geometric bands, 70 ms cut                         down 0.8817  up 0.3457  macro 0.6137
  trained CRNN (Klangio+GuitarSet), 70 ms cut           down 0.5835  up 0.4199  macro 0.5017
```

So the CRNN sits 0.087 below the linear floor of its own input, not 0.39. It is not the
dominant defect.

**The binding constraint is the 70 ms live deadline** (`ml/probe_direction_budget.py`):

```
  audio kept after onset    40 ms   70 ms  100 ms  150 ms  250 ms
  macro                    0.6165  0.6137  0.6200  0.6133  0.7326
  up-F1                    0.3584  0.3457  0.3506  0.3356  0.5466
```

Between 150 ms and 250 ms macro gains 0.12 and up-F1 nearly doubles; adding FRAMES without
audio buys nothing (28 frames scores below 15). **Direction on a microphone is a DECAY
feature, not an attack transient** — which strings keep ringing and how the pick's travel
shapes them. That also explains, after the fact, why higher time resolution measured worse
and why the 128 ms analysis window was never the problem.

Product consequence (ADR 0551 D4): the 70 ms budget exists for the live ARROW. Rhythm
SCORING has no latency requirement and is where a wrong answer actually costs the learner
(ADR 0549 D2). The fix is a two-tier decision — provisional at 70 ms for the arrow,
settled at ~250 ms for scoring — on the existing `StrumDirectionClassifier` /
`StrumAnalyzer` seam.

**Corpus diversity stands** and is unaffected by the alignment error
(`ml/experiment_cross_corpus.py` uses `window_truncated` throughout). Shipped
architecture, three arms, each scored on both held-out corpora:

```
  arm                     GuitarSet macro   Klangio macro   called-up / truth
  A Klangio only               0.3552          0.4080        0.76/0.19 · 0.73/0.38
  B Klangio + GuitarSet        0.5017          0.5979        0.64/0.19 · 0.58/0.38
  C GuitarSet only             0.5068          0.3832        0.06/0.19 · 0.00/0.38
```

B improves BOTH corpora, including the original domain. C's macro BEATS B while calling
nothing up on Klangio — it collapsed onto the majority class of an 81 %-down test set, so
**macro-F1 alone would have selected the worse model**. Always print the predicted class
rate beside the true one. Two hypotheses died here as well: shrinking the model (10k and
4k parameters) collapses it to one class, and per-window energy normalisation hurts both
the CRNN (0.5017 → 0.4065) and the linear reader (0.5885 → 0.5763).

### The baseline that was missing, and the measured two-tier payoff (E18-R29, ADR 0552)

**Quote this first, always.** Every direction figure above was compared to an earlier
direction figure, never to the trivial strategy on the same test set:

```
  majority baseline ("always down")
    GuitarSet test (n=530,  81% down):  down 0.8935  up 0.0000  macro 0.4468
    Klangio  test (n=3721, 62% down):  down 0.7673  up 0.0000  macro 0.3836

  SHIPPED 3-class CRNN, end to end, on GuitarSet:                  macro 0.3876
```

The shipped direction output is **below** a system that ignores the audio. Four rounds
measured it without that line, so "0.43 -> 0.50" read as progress when both sit around
guessing. `probe_direction_budget.py` now prints the baseline before any result row.

**AUC is the wrong metric on this corpus.** A predictor that knows nothing about the stroke
— only which take it came from, ranking by that take's up-rate — reaches **AUC 0.7386**,
because recognising the recording is enough to order the corpus. Any AUC below ~0.74 here
is no evidence of direction discrimination, and several figures in ADR 0551 sit at or under
it. Read macro-F1 (the oracle scores only 0.4468 there, being unable to emit upstrokes).

That same oracle **refuted my own mechanism label**: ADR 0550 D3 measured pre-onset audio
predicting direction at AUC 0.7128 and called it "alternation". Consecutive strokes share a
direction 61.4 % of the time in GuitarSet (45.4 % in Klangio) — there is no strong
alternation to guess. The mechanism is take identification plus that take's class prior.
The decision to exclude pre-onset context is unchanged and better founded; the argument
beside it was wrong, including the claim that `D DU UDU` "does not alternate" (it flips
60 %, i.e. MORE than the corpus). The real argument is that a context prior belongs to the
corpus's repertoire and misleads on any other.

**The grid.** Three training pools x two deadlines, every cell on both held-out corpora.
Only the truncation differs: the shipped 15-frame window already reaches 238 ms past the
onset, so both blocks use the same (15, 128) tensor and the same network — the deadline
lever costs nothing architecturally.

```
  GuitarSet (new player AND tune, n=530)            baseline 0.4468
    A Klangio only          70 ms   macro 0.3552   calledUp 0.76/0.19
    A Klangio only         238 ms   macro 0.3415   calledUp 0.82/0.19
    B Klangio + GuitarSet   70 ms   macro 0.5017   calledUp 0.64/0.19
    B Klangio + GuitarSet  238 ms   macro 0.6446   calledUp 0.29/0.19   <- chosen
    C GuitarSet only        70 ms   macro 0.5068   calledUp 0.06/0.19
    C GuitarSet only       238 ms   macro 0.6514   calledUp 0.20/0.19

  Klangio (new player, same rig, n=3721)            baseline 0.3836
    A Klangio only          70 ms   macro 0.4080     B  70 ms  macro 0.5979
    A Klangio only         238 ms   macro 0.6213     B 238 ms  macro 0.6321   <- chosen
    C GuitarSet only        70 ms   macro 0.3832     C 238 ms  macro 0.5525
```

**The two levers do not substitute for each other.** Extra audio alone lifts the ORIGINAL
domain hard (Klangio 0.4080 -> 0.6213, +0.2133) and transfers NOTHING (GuitarSet 0.3552 ->
0.3415, both below baseline). The second corpus alone transfers (+0.1465 on GuitarSet) but
leaves the audio budget unspent. Together: 0.6446 / 0.6321. More audio improves the model
on what it already knows; more corpora make it transferable.

C is not the winner despite scoring highest on GuitarSet (0.6514 vs 0.6446): it is 0.08
worse on Klangio and collapses entirely at 70 ms (calledUp 0.00). Klangio is not dead
weight. And at 70 ms macro-F1 alone would again have picked C — print the predicted class
rate beside the true one.

**Alpha gate (Ch14 §7.2, macro-F1 >= 0.80) is NOT met**: 0.6446. The linear floor at 238 ms
is 0.7326, so the CRNN sits 0.088 under it — the same distance as at 70 ms (0.5017 vs
0.5885), meaning it converts the extra audio at unchanged efficiency. Real capability, not
an artefact, and the remaining gap is unchanged.

**Next:** a wiring round under AGENTS.md §9 — a second, delayed classification on the
existing `StrumDirectionClassifier` / `StrumAnalyzer` seam, the arrow taking the provisional
call and rhythm SCORING the settled one (scoring has no latency requirement and is where a
wrong answer costs the learner, ADR 0549 D2). It needs the 3-class asset retrained with the
chosen configuration; these experiments are deliberately 2-class, because the no-strum head
is a separate capability with its own calibrated gate and mixing them would make it
impossible to say which change moved which number.

### The remaining gap is DATA, not the model and not the features (E18-R30, ADR 0553)

The "0.088 gap" conflated two inputs: the 0.7326 floor was measured on 16 geometric
magnitude bands, the CRNN's 0.6446 on 128 log-mels. Measured separately, at 238 ms, on the
player- and tune-disjoint split:

```
  linear floor on the CRNN's OWN input (128 log-mel)   macro 0.6601  95% CI [0.6088, 0.7108]
  trained CRNN (Klangio + GuitarSet, 238 ms)           macro 0.6446
```

**The model side is closed.** 0.0155 is well inside the interval: the CRNN already sits at
the linear ceiling of its own input, so more epochs, more parameters and more regularisation
have nowhere to work — and shrinking it collapses it (ADR 0551 D5). Treat any further
capacity/architecture proposal for direction as requiring evidence that headroom exists.

**"Coarser bands are better" did not replicate, and cross-validation is what caught it.** On
one split the linear floor improved monotonically (128 -> 8 bands: 0.6601 -> 0.7160), with a
good story attached (1920 features for ~1055 training sweeps; direction is a broad spectral
cue). Over 14 usable folds — every player held out, crossed with three rotations of the tune
split, always disjoint in both — it is not even ordered:

```
  128 log-mel  0.6715 +/- 0.0828     32 bands  0.7090 +/- 0.0802
   16 bands    0.6731 +/- 0.0897      8 bands  0.6931 +/- 0.1063
  16 geometric magnitude bands  0.7270 +/- 0.0821  (13 folds)
```

16 scores below 32, and every value sits inside every other's spread. A monotone trend over
k points is not k pieces of evidence — it is one sample read k times. Acting on it would have
bought a change to `ml/features.py` plus its Dart twin `crnn_frontend.dart` under the r134
parity discipline, for nothing.

**The representation is a CEILING.** Gradient boosting scores WORSE than logistic regression
on every representation (0.6492 vs 0.6715 on log-mel; 0.6822 vs 0.7270 on geometric bands).
A stronger reader extracting less means overfitting, i.e. no unexploited non-linear
structure. ~0.73 is the ceiling, not a floor.

**Geometric vs log-mel is unproven, and the two tests disagreeing IS the result.** Paired
over 13 folds: mean +0.0636 (sd 0.0981, SE 0.0272), normal 95% CI [+0.0103, +0.1170] which
excludes zero, sign test p = 0.27 with 4 of 13 folds negative and one fold contributing
+0.3096. The CI is carried by the tail, so normality is the assumption that fails — not the
distribution-free test. When a paired comparison is reported, print the per-fold signs and
the largest single contribution; `probe_direction_representation.py` prints both on purpose.

**Where that leaves direction:**

```
  majority baseline                                   macro 0.4468
  shipped 3-class CRNN today (end to end)             macro 0.3876
  trained CRNN, Klangio + GuitarSet, 238 ms           macro 0.6446
  ceiling of this representation over folds           macro ~0.73
  Chapter 14 7.2 Alpha gate                           macro 0.80
```

Quote all five together: with the model at its ceiling and the features exhausted, "we are
still tuning it" is not an available answer. The gate needs DATA — and corpus diversity is
the one lever that demonstrably transferred (ADR 0552 D2). There are nine guitarists in
total (Klangio 3 + GuitarSet 6). Next measurement step is collection, not modelling: the
user's own phone recording (exact labels, target hardware, no licence question, and it also
closes L660's open item), plus further direction-labelled or hexaphonic corpora.

**And the single split starves training, so 0.6446 is a LOWER bound.** GuitarSet's crossed
player/tune cells — 1471 of 3056 sweeps — cannot be added to training: 886 share a player
with the test set, 585 share a tune, and **zero** share neither. What the check did reveal is
that the single split withholds three players AND eight tunes at once, while a CV fold
withholds one player and one tune group:

```
  18-fold CV training size:  min 1296   median 1635   max 2100
  the single split:                                   1055
```

So ADR 0552's 0.6446 describes what the configuration manages from 1055 sweeps, not its
capability. Report held-out direction performance over FOLDS from now on, not over one
split; a shipping model trains on everything and takes its estimate from the CV.

The next BUILD step is unchanged: wiring ADR 0552's two-tier decision (+0.1429 measured, no
architecture cost).

### One asset serves both direction tiers (E18-R31, ADR 0554)

ADR 0552's "no architecture cost" holds for the INPUT (the shipped 15-frame window already
reaches 238 ms past the onset; the tensor stays (15, 128)) but not for the WEIGHTS: the two
tiers were models trained on different truncations, which reads as two assets, two
`tryLoad`s, two parity fixtures and per-call-site model selection in Dart.

Measured over the repo's `honest_eval.STD_SEEDS = [42, 1, 2]`, three arms x two deadlines x
two held-out corpora (`ml/experiment_deadline_augmentation.py`), macro-F1 mean +/- sd:

```
  GuitarSet (baseline 0.4468)        @70 ms              @238 ms
    A trained @70 ms          0.4690 +/- 0.0603   0.4269 +/- 0.0063   <- BELOW baseline
    B trained @238 ms         0.5865 +/- 0.0358   0.6954 +/- 0.0362
    C trained @BOTH           0.5934 +/- 0.0127   0.6659 +/- 0.0172

  Klangio (baseline 0.3836)
    A trained @70 ms          0.4879 +/- 0.0854   0.5205 +/- 0.0248
    B trained @238 ms         0.4795 +/- 0.0924   0.6593 +/- 0.0193
    C trained @BOTH           0.5828 +/- 0.0385   0.6675 +/- 0.0195
```

**Ship ONE asset, trained on both truncations (arm C).** It WINS the 70 ms tier on both
corpora — beating the dedicated 70 ms specialist — with the smallest seed spread
(+/- 0.0127 vs A's +/- 0.0603), and ties the specialist at 238 ms. Deadline augmentation
regularises rather than compromising. The two tiers become two CALL TIMES, not two models.

**The tiers cannot be "today's model called twice."** Both cross cells collapse, stably
across seeds: B at 70 ms calls up 0.08 of the time against a true 0.38 on Klangio (up-F1
0.1912) — that is the ARROW's position; and A at 238 ms scores 0.4269 +/- 0.0063 on
GuitarSet, below the 0.4468 majority baseline with a tiny spread, so the current head gets
WORSE with more audio because it never learned to use it.

**Order: ASSET FIRST, WIRING SECOND.** With today's asset a "settled" call sits below the
majority baseline, so wiring the seam early would regress rhythm SCORING — the path where a
wrong answer is a deduction or a phantom credit (ADR 0549 D2). A seam whose model is worse is
not neutral infrastructure.

**ADR 0552's "+0.1429" conflated two changes** (tier AND training: A@70 -> B@238). On the
weights that would actually ship, the tier gain is +0.0725 (GuitarSet) and +0.0847 (Klangio),
against a seed spread of +/- 0.017-0.020 — real, but not what it looked like. And its
single-seed figures erred in BOTH directions: A@70 GuitarSet 0.5017 -> 0.4690 +/- 0.0603
(optimistic), B@238 0.6446 -> 0.6954 +/- 0.0362 (pessimistic). One seed is a sample whose
direction is not predictable; `STD_SEEDS` existed for this.

`crnn_frontend` needs NO change: its ring is 1 s and `windowAt(onsetFrame, currentFrame)`
zero-fills whatever has not arrived, so the settled call is the same call made later.

### The two-tier asset, and the gate that was silencing upstrokes (E18-R32, ADR 0555/0556)

`ml/train_live_3c_settled.py` trains the 3-class live model on BOTH corpora at BOTH
truncations (ADR 0554) and exports `assets/ml/strum_crnn_live_3c_settled.bin` plus
`test/fixtures/crnn_live_3c_settled_parity.json`. **The shipped `strum_crnn_live_3c.bin` is
untouched**, and the new binary is deliberately NOT declared in `pubspec.yaml` or
`model_manifest.json`, so it is in the repo but not in the APK - wiring it is a separate
round under AGENTS.md 9.

**The gate is now class-conditional.** ADR 0549's rule is the P(no-strum) quantile retaining
95 % of true strums, class-blind. Measured, that silences upstrokes 1.3-2.8x more often,
because they carry up to 5x the median P(no-strum):

```
  per-class fitted threshold:   down 0.041166     up 0.292900     (7x apart)

  gate               threshold   retains  rejects
  class_blind        0.124528     0.950    0.974     (ADR 0549's rule)
  class_conditional  0.292900     0.971    0.960     (shipped, = max of per-class quantiles)
```

Held out, the class-conditional gate is better in ALL four cells - GuitarSet macro
0.5117 -> 0.5262 @70 ms and 0.6000 -> 0.6061 @238 ms, Klangio 0.4922 -> 0.5055 and
0.6267 -> 0.6363 - for 1.4 points of false-onset rejection. Upstroke suppression drops from
0.225 to 0.127 (GuitarSet @70) and 0.098 to 0.078 (@238). The product reason: `reggae-skank`
is nearly all upstrokes, so a class-blind gate makes the engine's silence the learner's
deduction - ADR 0549 D2's lie, turned by class.

**This is named prior art, not our idea.** The class-blind rule is textbook Chow (1970),
whose threshold `t = (C_r - C_c)/(C_e - C_c)` carries no class index because it assumes
symmetric costs; the fix is Mondrian / label-conditional conformal prediction (Vovk et al.
2003; Vovk, Gammerman and Shafer 2005) with an exact finite-sample per-class guarantee,
available because the classes are a FINITE partition (Barber et al. 2021 prove continuous
conditioning is impossible, finite achievable); and Fumera, Roli and Giacinto (2000) already
proved per-class reject thresholds Pareto-dominate single-threshold Chow.

**Required check, per that failure mode:** Jones et al. (NeurIPS 2020) and Cresswell et al.
(ICLR 2025) show equalising RETENTION does not equalise error rate on what is RETAINED and
can worsen the disadvantaged class. Measured: upstroke retained PRECISION moves
-0.005..+0.003 (flat) while RECALL moves +0.020..+0.063 - no backfire, but visible in
miniature. The trainer therefore reports per-class retained precision AND recall under both
gates; a measurement watching only retention cannot see this trade.

**Still open (ADR 0555 D4):** a retention quantile is the wrong frame when false-silence and
false-positive costs differ - the classical answer is a cost-ratio-derived threshold
(Tortorella; Pietraszek 2005; Charoenphakdee et al. 2021), and ADR 0549 D2 named both costs
in prose before choosing a quantile anyway. Separate round, plus precision/recall reject
curves (Fischer and Wollstadt 2023) for imbalanced reporting.

**Price of the no-strum capability:** 2-class arm C without a gate scores GuitarSet 0.5934
@70 / 0.6659 @238 and Klangio 0.5828 / 0.6675; the shippable 3-class path with the gate
scores 0.5262 / 0.6061 and 0.5055 / 0.6363 - so 0.03-0.07 macro, with 7.8-13.7 % of true
strums suppressed and counted as errors.

**The number to quote:** on GuitarSet the retained upstroke precision is 0.40 and recall
0.31 - roughly a third of unseen players' upstrokes are found at all - against 0.857 / 0.865
for downstrokes. That is ADR 0553's data diagnosis, unchanged.

### Presentation rule: the arrow never flips (ADR 0556)

The two tiers must not surface as a visibly self-correcting arrow. The closest studied
analogue is live captioning (Du et al., CHI 2023), where visible revision of a fast,
uncertain output is a MEASURED cost even when the final output is right; trust research adds
the cry-wolf effect (Hoff and Bashir 2015). But the naive alternative - arrow shows the
provisional call, scoring uses the settled one, disagreement invisible - grades the learner
against something they never saw, a third lie on top of ADR 0549 D2's two.

So: the fast call shows a direction ONLY when its margin is adequate; otherwise a
direction-NEUTRAL stroke mark ("a stroke happened, I am not saying which way"). The settled
call supplies direction for SCORING and the post-bar review. No flip, and no direction claim
the grader will contradict. The seam already exists - `StrumPrediction.decision`'s margin
gate (ADR 0512), and a null direction already emits a StrumEvent.

Honest status (ADR 0556 D5): the guidance-hypothesis literature (Salmoni, Schmidt and Walter
1984; Winstein and Schmidt 1990) is strong but manipulated frequency at SECOND-scale, not
70 ms vs 240 ms, so it does not settle this. The decision is a justified choice under
uncertainty and must be measured on our own learners for RETENTION, not in-session accuracy.

### Next data step: Guitar-TECHS

[Zenodo 14963133](https://zenodo.org/records/14963133) /
[arXiv:2501.03720](https://arxiv.org/abs/2501.03720) - CC-BY-4.0, 5h12m, THREE professional
guitarists distinct from ours, explicit alternate chord strumming, and per-string MIDI from a
Fishman Triple Play pickup, so direction is derivable exactly as for GuitarSet. Takes the
pool from 9 players to 12.

Ruled out by the same search: `KLANGIO-GST-MM-T` (same players, earlier snapshot);
arXiv 2508.07973 (it IS the GST-MM-2025 paper, not another corpus); IDMT-SMT-Guitar
(CC BY-NC-ND, no derivatives); EGDB and EG-IPT (one player each); GAPS (licence conflict,
classical solo); the Francois Leduc set (restricted, one player); GIHME (empty placeholder);
Zenodo 6470236 (36 players, CC-BY, but strumming NOT confirmed and no hexaphonic channels).

### The metric channel: position in the beat predicts direction better than the audio does (E18-R33, ADR 0557)

`ml/probe_direction_metric.py` reads GuitarSet's `beat_position` grid next to the
hexaphonic note annotation - no audio, no model - and the headline feature has NO
fitted parameter: `score = -|distance from the nearest sixteenth offbeat|`.

```
  channel                                        held-out AUC
  METRIC    (position in the beat, 0 params, 0 ms)   0.9797   n=526
  ACOUSTIC  (CRNN at the 70 ms live deadline)        0.7484   (probe_direction_budget)
```

Player- AND tune-disjoint split. `P(up | phase)` is legible: ~0.03-0.07 on the eighths
(phase .0 and .5), ~0.89-0.96 on the sixteenth offbeats (.25 and .75) - textbook
sixteenth-note strumming, the hand a continuous pendulum.

**Controls.** Label leak through the sweep's own time is ruled out: sweep spread is
21.8 ms (down) / 23.5 ms (up), differing by 1.7 ms, against a 134 ms sixteenth (~6x).
Shuffling phase WITHIN each test take (tempo, style and class balance preserved) drops
0.9797 -> 0.5604 - the residual 0.06 is the control's own ceiling, since shuffling keeps
each take's phase distribution. Not a binning artefact: the parameter-free continuous
feature reproduces the 8-bin table (0.9783 vs 0.9797). Per unseen player 0.9044 / 1.0000
/ 0.9923. Rock<->Funk transfer (0.9888 / 0.9560) measures STYLE, not subdivision - both
GuitarSet styles are sixteenth-based. **One "control" controlled nothing:** distance from
the nearest EIGHTH scored identically because it is an affine transform of the same score
(`d8 = 0.25 - d16`) and AUC is monotone-invariant (LESSONS L671 section 2).

**The subdivision is pattern-specific, so the map comes from the LESSON, not a corpus.**
A 2-bin (eighth-note) table scores 0.5426, near chance - in a lesson prescribing eighths
the GuitarSet-fitted table would read BACKWARDS. The app knows its prescribed pattern
(`strum_patterns.dart`, `D DU UDU`), so the map is notation, not a fitted parameter.

**Timing scatter, the product number** (displacing the grid is the same relative
displacement as the learner playing off a perfect grid): +-0 ms 0.9797, +-20 ms 0.9804,
+-30 ms 0.9599, +-50 ms 0.8427, +-80 ms 0.6285. So the metric channel on a SLOPPY learner
still beats the acoustic channel on a professional. GuitarSet's players are professionals
on a backing track; beginners are NOT measured.

**The binding rule (ADR 0557 D4): the metric channel NEVER decides alone what the learner
is told they played.** It is strongest from the PRESCRIBED pattern, so letting it settle
direction would grade the learner against the answer key and confirm a pattern they did
not play - the forbidden false teaching, worse than a missing signal because it is
confident. Therefore: the ARROW fuses both channels (low stakes, latency-critical);
SCORING uses the acoustic channel only, with abstention; the metric channel may raise or
lower the abstention bar but never flips the call; and channel DISAGREEMENT under a
confident acoustic call is itself the pedagogical output ("your strumming hand left the
pendulum here"), reported after the bar per ADR 0556 D4.

**ADR 0551's binding constraint is dissolved, not managed.** The metric channel has NO
deadline - phase is known at the onset instant, not 70 or 238 ms later.

**The rail already exists in production:** `TempoTracker.bpm` + `_placeInBar` compute the
phase today and throw it away as a direction cue. Wiring means refining that grid from
eighths to sixteenths and keeping the phase continuous.

**And the unwelcome half (ADR 0557 D5): the corpus barely contains the error class the app
exists to detect.** 96 % of strokes obey the pendulum; the TRAIN split holds 41 violations
in 1037 sweeps (3.95 %), of which 39 are upstrokes played off the grid. Those are exactly
the strokes where the metric channel is WRONG and the acoustic channel must decide alone.
So upstroke recall 0.31 is not only "too few players" (ADR 0553) - the corpus's upstrokes
are METRICALLY STEREOTYPED, and **Guitar-TECHS (9 -> 12 players) cannot fix it, because
professionals do not make this mistake.** The data needed is LEARNERS breaking the
pendulum, and the only known source is our own labelled recording.

**Not claimed:** the fusion gain is UNMEASURED. Two AUCs do not combine into one number;
the joint posterior's held-out performance is a separate round needing the cache rebuilt
with onset times. Until it runs, the fusion is a justified plan, not a result.

### The fusion rule, measured -- and it differs by tier (E18-R34, ADR 0558)

`ml/probe_direction_fusion.py` supplies the combined number ADR 0557 deliberately did not
claim. Held-out GuitarSet (unseen player AND tune): 530 rows, metric channel available on
99.2 %, pendulum-obeying 519, **pendulum-violating 11**.

Alignment is PROVEN, not assumed: `guitarset.build` is deterministic, so onset times are
replayed from the annotation, and the probe EXITS unless both the row count and the full
(player, tune) sequence match the cache -- a future change to either loop fails loudly
instead of silently pairing a stroke with another stroke's phase.

`lam` is the confidence given to the prescribed grid: one swept scalar, not a corpus-fitted
table (ADR 0557 D3). `lam = 0.5` IS the acoustic-only rule, so the baseline is a point on
the same curve rather than a separate code path.

```
  tier     rule                        macro   downF1  upF1    accAll  accObey  accVIOL
  70 ms    C  acoustic only            0.5262  0.7743  0.2780  0.6377  0.6435   0.3636
  70 ms    A  full fusion  lam=0.99    0.9168  0.9518  0.8817  0.9000  0.9152   0.1818
  70 ms    B  ties only    m<0.30      0.6497  0.8409  0.4585  0.7321  0.7418   0.2727
 238 ms    C  acoustic only            0.6061  0.8605  0.3516  0.7585  0.7649   0.4545
 238 ms    A  full fusion  lam=0.99    0.9226  0.9709  0.8743  0.9377  0.9538   0.1818
 238 ms    B  ties only    m<0.30      0.6784  0.8876  0.4693  0.8019  0.8092   0.4545
```

A suppressed stroke stays suppressed under every rule: the metric channel says WHICH
direction a stroke had, never WHETHER one happened. Letting it resurrect a suppressed onset
would decide EXISTENCE from the answer key.

**The headline is inflated, and the corpus does it.** 98 % of held-out strokes obey the
pendulum, so a rule that trusts the grid is largely asked to predict the grid from the grid.
A learner complies less, and their expected accuracy is a straight line in compliance c:
`acc(c) = c*accObey + (1-c)*accViol`. Each rule crosses the acoustic-only baseline once, and
THAT crossing is the shippability test:

```
  tier     rule                      break-even c*   acc at c = 0.95 / 0.80 / 0.60 / 0.40
  70 ms    A  full fusion lam=0.99      0.401        0.8786  0.7685  0.6219  0.4752
  70 ms    B  ties only   m<0.30        0.481        0.7184  0.6480  0.5542  0.4604
 238 ms    A  full fusion lam=0.99      0.591        0.9152  0.7994  0.6450  0.4906
 238 ms    B  ties only   m<0.30        0.000        0.7915  0.7383  0.6674  0.5964
```

**What this selects.** At 238 ms (SCORING) the tie-break rule has `c* = 0.000` -- it never
loses at any compliance, while gaining +0.0723 macro. Pareto, shippable now, and it
coincides with ADR 0557 D4's ethical constraint ("the metric channel may move the abstention
bar but never flips the call") -- **coincidence, not derivation**: D4 was declared BEFORE the
measurement and would bind either way. At 70 ms (the ARROW) full fusion lifts accuracy
0.6377 -> 0.9000 and beats acoustic-only above 0.401 compliance, which even a struggling
beginner exceeds -- but it rests on ELEVEN strokes, so it goes behind a feature gate.

**And the rule designed to be "conservative" was WORSE on the fast tier.** Rule B was the
design intuition for safety (never override a confident acoustic call). At 238 ms that was
right (`c* = 0.000`); at 70 ms it inverts -- 0.481 against full fusion's 0.401. The
mechanism is transparent afterwards: when the acoustic call is confident AND wrong, which at
70 ms it often is, the "do not override the confident one" guard is exactly what PRESERVES
the error. The margin does not measure reliability at 70 ms (LESSONS L672 section 2).

**Not claimed:** 0.9168 / 0.9226 are NOT generalisation estimates for a learner -- the
break-even curve is, and it rests on 11 strokes (every accViol a multiple of 1/11; the
measured harm 0.3636 -> 0.1818 is TWO strokes). Bounds, not operating points. The linear
compliance model also assumes a learner's violations look like GuitarSet's; a beginner's
probably differ in kind (whole-pattern drift, not a stray stroke). `lam` is a swept
confidence scalar, not a calibrated probability.

### The SHIPPED rule, and the Dart unit that cannot drift from it (E18-R35, ADR 0558 correction)

Every number in ADR 0557/0558 was measured with the MEASUREMENT rule ("up if the distance
from the nearest sixteenth offbeat is <= 0.09375 beats"). The SHIPPED rule is the nearest
slot of the lesson's PRESCRIBED pattern, because the offbeat rule encodes one corpus's
pattern while a lesson's pattern is whatever its notation says (ADR 0557 D3). Measuring one
rule and shipping another measures a different system (LESSONS L662/L673).

```
  rule                            accuracy   violating strokes
  measurement (|d16| <= 0.09375)    0.9791         11
  SHIPPED     (nearest slot)        0.9848          8
```

They disagree on 0.95 % of held-out rows (5 / 526). The shipped rule is BETTER -- and that
SHRINKS the violating subset from 11 to 8, i.e. the only place fusion can do harm now has
fewer samples. The harm estimate got THINNER, not stronger: every accViol is a multiple of
1/8 and the measured harm is TWO strokes. (A general trap: when risk is measured on the
model's own mistakes, every improvement removes the evidence you need to bound the risk.)

Re-measured under the shipped rule: **D1 is unchanged** -- at 238 ms the tie-break rule
still has `c* = 0.000` and +0.0723 macro, so the shippable rule survived. **D2 got worse**:
the arrow's full fusion break-even moved 0.401 -> 0.475, materially closer to 0.5, which
STRENGTHENS the feature-gate decision. D3 holds (0.557 vs 0.475).

`lib/features/live/engine/dsp/strum_metric_channel.dart` is the unit: parameter-free,
Flutter-independent, and it takes the pattern from OUTSIDE rather than fitting it. Three
states kept deliberately distinct, because collapsing them is what would make the class a
lie -- `available == false` (no tempo grid: free play, a normal mode), `available &&
direction == null` (on the grid but the pattern prescribes a REST there, so no opinion; a
stroke on a rest is itself a pattern violation for the post-bar review), and `hasOpinion`
(the prescribed direction). The class doc states loudly what it must NEVER be used for: the
direction it returns is the ANSWER KEY, so reporting it as the learner's stroke, or letting
it flip a confident acoustic call, is the forbidden false teaching (ADR 0557 D4).

AGENTS.md 9, item by item: **fixture** `test/fixtures/strum_metric_channel_parity.json`
(180 cases -- 120 real held-out GuitarSet onset phases plus synthetic edges: slot boundary,
the wrap at 1.0, NEGATIVE phase, a rest slot, a 3/4 pattern); **parity** -- the fixture is
generated by the SAME arithmetic the probe measures with, so shipped and measured rule
cannot diverge; **property** (randomized) -- a slot centre lands on that slot, offsetSlots
stays in [-0.5, 0.5], a whole-bar shift changes nothing, a one-slot shift advances the slot
AND flips the arrow (the pendulum itself), a displacement under half a slot keeps the slot;
**real-audio measurement** -- `probe_direction_metric.py` section 4b over 72 real GuitarSet
recordings (held-out accuracy 0.9848) plus `probe_direction_fusion.py` running the trained
model on that audio.

The half-slot property is the geometric twin of the measured timing-scatter row: at 120 bpm
a sixteenth is 125 ms, so the channel tolerates +-62.5 ms of learner error before reading
the neighbouring slot -- and measured AUC is 0.8427 at +-50 ms, 0.6285 at +-80 ms. The knee
sits where the geometry says it should.

12/12 tests green. **Shipped behaviour is unchanged: the unit is NOT wired** -- `LivePipeline`
does not call it, so this is a clean new surface.

### The settled tier is built, and deliberately DARK (E18-R36, ADR 0559)

`StrumAnalyzer` now has a second, delayed classification (ADR 0556 D3). The instant is
DERIVED, not written down: `LiveCrnnFrontend.framesUntilComplete` computes it from the
model geometry (row count, preFrames, modelHop, FFT size) and comes out at 41 analyzer
frames = 238 ms for the shipped framing -- the same 238 ms the settled tier is measured
at. The `+ 1` frame absorbs the centre rounding in `_buildWindow`, because arriving EARLY
would restore exactly the zero-padding the tier exists to remove.

Proven rather than assumed (`test/features/live/dsp/strum_settled_tier_test.dart`): at the
settled instant the streamed window equals the whole-signal reference to 1e-9, and at the
fast instant the window's last row is the log-mel of SILENCE -- one constant across all
128 mels. So the truncation is real and the tier removes it.

`StrumRevision` revises DIRECTION and nothing else. It cannot create a strum, cannot
retract one, and says nothing about whether a stroke happened. Its identity is an INTEGER
frame index, not a timestamp: at 200 bpm sixteenths strokes are ~13 frames apart while
settling takes 41, so up to three are in flight, and an epsilon wide enough for float
rounding could reach the neighbouring stroke.

The three ADR 0556 hazards, each with a test: a revision never creates a strum (one onset →
exactly one event plus one revision; the heuristic path emits zero revisions); it never
overwrites a NEWER stroke (3+ in flight, every revision names its own onsetFrame, strictly
increasing); a SUPPRESSED onset never comes back (no event, no revision, and the seam is
consulted once but never twice). Plus the mirror case: a SETTLED suppression does not
retract an already-reported strum -- the event reached every consumer, deleting it would
remove a stroke the learner SAW, which is the visible self-correction ADR 0556 D1 forbids.

Queue order matters and is tested, not hoped for: the SETTLED queue is drained BEFORE the
fast one, because the fast branch returns and one frame can carry a settled verdict for an
earlier stroke together with a fast verdict for a later one. A stroke's fast verdict is due
12 frames after its onset and its settled verdict 41 frames after, so the collision needs a
gap of 29 frames, not 41; the test sweeps 28/29/30 and REQUIRES the collision to occur at
least once, reporting that the ordering was never exercised otherwise.

**The tier is OFF by default (`settledTier: false`), and that is the point.** With the live
CRNN behind the seam `settleAfterFrames` is 41, so enabling it means a SECOND model forward
per strum, and nothing reads `settledRevision` yet -- the cost would buy a learner's phone
nothing. On this JIT test harness one forward is ~29 ms; that is NOT an on-device figure and
the two are not comparable (release AOT is substantially faster), so no on-device number is
claimed. What is claimed: the doubling is not free, its magnitude is unknown, and at 200 bpm
sixteenths there are ~13 strums a second. The flag is not a user feature toggle -- it is the
seam that keeps an unconsumed computation from shipping, and it is flipped by the round that
both consumes the revision (ADR 0558 D1) and measures the cost in a profile build. A test
guards it: without opting in, the second forward is not merely ignored, it is never issued.

`settleAfterFrames` is a REQUIRED seam member with no default, so eight test doubles had to
say they have no settled tier. Deliberate: a default would silently opt future classifiers
into the safe value and hide the decision. For two of them it was not a formality -- the
recorders in `guitarset_direction_boundary_test.dart` and
`guitarset_threshold_sweep_test.dart` delegate to the REAL classifier and append every call
to `calls`, so delegating would have added one extra verdict per strum, at a different
truncation, to the very pass every threshold in those measurements is rescored from.

`StrumEvent` gained an additive `onsetFrame`. Its only construction site is the analyzer;
the same-named domain event in `features/audio_analysis` is a DIFFERENT class and is
untouched.
