# Joint streaming onset+direction prototype (E14-R18, ADR 0517)

Offline research prototype: does a **joint** head (one CRNN classifying a
causal + small-lookahead window directly into `{down, up, no-event}`) beat
the legacy **two-stage** pipeline (`superflux_onset_detector.dart` ->
`strum_direction_classifier.dart`), where an onset-detector miss can never be
recovered by the direction stage (ADR 0312, Chapter 14 §4.4/§5.1)?

**Not a shippable artifact.** No weight, checkpoint or feature cache from
this prototype is ever written under the repository tree (ADR 0517 D5) —
everything run-related goes to `--workdir`, which must resolve outside the
repo. Nothing here is wired into `lib/`.

## Environment

The **system** `python3` has no TensorFlow. Both scripts run **only** under
the pinned venv:

```bash
/home/ubuntu/tf-venv/bin/python -c "import tensorflow; print(tensorflow.__version__)"
# 2.21.0
```

The Klangio corpus is fetched separately (see `ml/klangio.py`'s docstring)
into `ml/data/klangio/` (gitignored). This prototype does not fetch it.

## Architecture

Same conv+GRU trunk as the shipped models (`ml/train.py::build_model`,
imported — not re-implemented) so the comparison is about the head, window
geometry and split, not a different network family. What differs from the
legacy 2-class direction classifier:

- **window:** `PRE_FRAMES=3` (30 ms causal context) + `LOOKAHEAD_FRAMES=4`
  (40 ms controlled lookahead) = 7 frames (70 ms) total — far below the
  legacy direction classifier's 15-frame (150 ms, PRE=3/POST=12) window.
  Audio is zeroed past `onset+lookahead` before the log-mel is computed
  (`train_prototype.py::joint_window`, same discipline as
  `ml/experiment_deadline.py::window_truncated`) so train==serve: a
  genuinely lookahead-limited model, not a full window merely truncated by
  frame count.
- **head:** 3-class softmax (down-onset / up-onset / no-event) trained on
  positive windows at every labeled strum plus mined no-event negatives
  (`ml/negatives.py`, same >=120 ms margin discipline as
  `ml/train_live_3c.py`'s reject head) — one forward pass decides "is this
  an onset, and if so which direction" without depending on an externally
  detected onset time.

## Split

Leave-one-guitarist-out (`ml/klangio.py::guitarist_of` / `logo_folds`,
3 guitarists in this corpus: ids `1`/`2`/`4`). **Only ONE representative
fold is trained per run** — held-out guitarist defaults to the first fold in
sorted guitarist-id order (deterministic, not cherry-picked) — not the full
3-fold sweep, per the round's <=20-minute compute budget (round brief
§0.0/R8). `train_prototype.py` asserts the train/test guitarist-id sets are
disjoint before writing anything; `evaluate_prototype.py` independently
RE-derives and re-checks that same split rather than trusting the training
run's provenance (ADR 0517 D2).

## Running it

```bash
# 1. Train (writes weights + provenance to --workdir, NEVER under the repo):
/home/ubuntu/tf-venv/bin/python ml/joint_prototype/train_prototype.py \
    --workdir /tmp/e14r18-work

# 2. Evaluate (re-checks the corpus hash + the split, scans every TEST
#    recording's full audio, prints a schema-conformant JSON document):
/home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py \
    --workdir /tmp/e14r18-work
```

Both scripts refuse a `--workdir` that resolves inside this repository.

## Measured configuration and wall-clock (one documented run, 2026-09-05)

| | |
|---|---:|
| Held-out guitarist | `1` (55 train / 27 test recordings) |
| Epochs configured / run (EarlyStopping, patience 4) | 12 / 6 |
| Batch size | 32 |
| Seed | 42 |
| Model parameters | 363,891 (identical trunk to the shipped 3-class model) |
| Training wall-clock | ~144 s |
| Evaluation (full-timeline scan, 27 test recordings) wall-clock | ~119 s |
| **Total documented run** | **~5 minutes** (well under the 20-minute budget) |

Exact numbers and the full metric comparison are in
[`docs/eval/joint-strum-prototype.md`](../../docs/eval/joint-strum-prototype.md).

## Known limitation of this evaluation protocol

`evaluate_prototype.py` scans **every 10 ms frame** across each test
recording's full audio (a genuine streaming-style scan, never cheating by
only looking at already-known onset times). The model's negative-mining
distribution during training (hard flux-peak negatives + easy interior
negatives, `ml/negatives.py`) is much narrower than "every frame of
continuous audio" — the measured run shows this as a large false-positive
count during full-timeline scanning (documented in the report). This is a
genuine finding about the training recipe, not a bug: any follow-up round
that wants a stronger prototype would need to train against continuous-
stream negatives (or add temporal hysteresis / a higher decision threshold),
not just re-run this configuration.
