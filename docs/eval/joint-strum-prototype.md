# Joint streaming onset+direction prototype — measurement report (E14-R18, ADR 0517)

**Question:** does a **joint** head — one CRNN classifying a causal +
small-lookahead log-mel window directly into `{down-onset, up-onset,
no-event}` — beat the legacy **two-stage** pipeline
(`lib/features/live/engine/dsp/superflux_onset_detector.dart` ->
`strum_direction_classifier.dart`), where an onset-detector miss can never
be recovered by the direction stage (ADR 0312, Chapter 14 §4.4/§5.1)?

**Scope.** This is an offline research prototype (`ml/joint_prototype/`).
Nothing here ships into the app: no weight, checkpoint or feature cache from
this round lives under the repository tree (ADR 0517 D5), and no `lib/`
file was touched.

## 1. Corpus identity (ADR 0517 D6 — "one table, same corpus-hash")

`evaluate_prototype.py` computes the SHA-256 of `ml/data/klangio` (sorted
`*.wav` then sorted `*.strums`, each preceded by its own `"<basename>\n"` —
the identical algorithm `tool/benchmarks/real_audio_dsp_baseline.dart
::_corpusChecksum` used to anchor the legacy baseline) and refuses to run
the comparison on a mismatch. Measured:

```
4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827
```

This is byte-for-byte the `corpusSha256` anchored in
`evaluation/recognition/baseline_manifest.json` (82 recordings, 11,767
events) — same corpus, machine-verified before any number below was read.

## 2. The lookahead number (ADR 0517 D1)

| | frames | ms |
|---|---:|---:|
| Causal context (`PRE_FRAMES`) | 3 | 30 |
| **Controlled lookahead (`LOOKAHEAD_FRAMES`)** | **4** | **40** |
| Total window | 7 | 70 |

Audio is zeroed past `onset + 40ms` **before** the log-mel is computed
(`train_prototype.py::joint_window`, same discipline as
`ml/experiment_deadline.py::window_truncated`) — train == serve, a
genuinely lookahead-limited window, not a full window merely truncated by
frame count. For comparison, the legacy direction classifier's window is 15
frames / 150 ms (`ml/features.py::PRE_FRAMES=3, POST_FRAMES=12`) — the joint
prototype's total window is under half that.

## 3. Split and leakage evidence (ADR 0517 D2)

Leave-one-guitarist-out (`ml/klangio.py::guitarist_of`/`logo_folds`; 3
guitarists in this corpus, ids `1`/`2`/`4`). **One representative LOGO
fold** was trained and evaluated — not the full 3-fold sweep — per the
round's documented ≤20-minute compute budget (round brief §0.0/R8). The
held-out guitarist is the first fold in sorted guitarist-id order
(deterministic, not cherry-picked for a favorable score): **guitarist `1`**
(55 train / 27 test recordings).

`evaluate_prototype.py` does **not** trust `train_prototype.py`'s
provenance for this: it independently re-derives the guitarist-id partition
from `ml/data/klangio` and asserts the train/test guitarist-id sets are
disjoint and that the test set is exactly the held-out guitarist, before
computing or printing anything.

**Fail-closed gate, demonstrated for real** (not just asserted — both
commands below were actually run):

```
$ /home/ubuntu/tf-venv/bin/python -c "
import sys; sys.path.insert(0, 'ml/joint_prototype')
import evaluate_prototype as ep
ep.assert_no_leakage(['1001','1002'], ['4001','2001'], '4')
"
GuitaristLeakageError: guitarist/recording leakage detected: recording_overlap=[],
guitarist_overlap=[], test_guitarists=['2', '4'] (expected only '4') —
aborting before any document is written (ADR 0517 D2)
```

```
$ /home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py \
    --workdir /tmp/e14r18-work \
    --baseline-manifest /tmp/fake_baseline_manifest.json \
    --output /tmp/e14r18-work/leakage_probe_output.json
error: corpus hash mismatch: .../ml/data/klangio hashes to 4880face...5827,
but /tmp/fake_baseline_manifest.json anchors corpusSha256=00000...0 —
refusing to compare against a different corpus (ADR 0517 D6); no document written
exit=1
$ ls /tmp/e14r18-work/leakage_probe_output.json
ls: cannot access '...': No such file or directory
```

Both gates abort with a nonzero exit and **no document is written** —
matching round §6 AC6 exactly.

## 4. Configuration and measured wall-clock (round brief §0.0/R8)

| | |
|---|---:|
| Held-out guitarist | `1` |
| Train / test recordings | 55 / 27 |
| Dataset (all windows, full corpus) | 21,789 — 7,228 down / 4,539 up / 10,022 no-event |
| Epochs configured / actually run (EarlyStopping, patience 4) | 12 / 6 |
| Batch size | 32 |
| Seed | 42 |
| Model parameters | 363,891 (same conv+GRU trunk as `ml/train.py::build_model`, imported not re-implemented) |
| Training wall-clock | 137.9 s |
| Evaluation wall-clock (full-timeline scan, 27 test recordings, every 10ms hop) | 125.7 s |
| **Total documented run** | **~4.4 minutes** — well inside the 20-minute budget |
| Interpreter | `/home/ubuntu/tf-venv/bin/python` (TF 2.21.0) — the system `python3` has no TensorFlow |

## 5. Comparison table

| Metric | Prototype | Legacy | Alpha gate | Comparison |
|---|---:|---:|---:|---|
| Onset F1 @50ms | **0.3824** (n=16,962) | 0.6739 (n=16,411, anchored) | 0.82 | below |
| End-to-end direction macro-F1 | **0.2240** (n=20,972) | not-measured — 0.6739 upper bound only | 0.80 | below |
| Algorithmic verdict latency | 40 ms (lookahead only) | not measured (no real-time legacy number exists on this corpus) | — | — |

- **Prototype onset F1 @50ms** — precision/recall/F1 of peak-picked
  joint-model onset events (`1 - P(no-event)` local maxima, ≥60ms apart)
  against expected onset events, matched within an inclusive 50ms tolerance
  via greedy nearest-available one-to-one matching, ignoring predicted
  direction. Measured: 4,010 true positives, 12,893 false positives, 59
  false negatives (precision 0.237, recall 0.986).
- **Prototype direction macro-F1** — macro-averaged per-direction (down/up)
  F1: per-class true positives come only from time-matched onset pairs
  whose expected and detected direction both equal that class; false
  positives/negatives are counted over the FULL detected/expected
  populations for that class (same definition as
  `recognition_metrics.dart`'s `directionF1`, ADR 0509). Per-class: down F1
  0.299 (TP 1,753 / FP 7,515 / FN 701), up F1 0.149 (TP 689 / FP 6,946 / FN
  926).
- **Legacy onset F1 @50ms** — anchored from
  `evaluation/recognition/baseline_manifest.json`
  (`tolerance50000us.f1 = 0.6739121651650438`, n=16,411), ADR 0354.
- **Legacy end-to-end direction — upper bound, not a measurement** (ADR
  0517 D6): the corpus's `.strums` files carry no direction ground truth
  along the legacy Dart annotation path that `baseline_manifest.json`
  measured against (`metricBlocks.direction.status = "not-measured"`). A
  correct end-to-end direction call requires a correctly time-matched onset
  first (`TP_direction ⊆ TP_onset`), so end-to-end direction macro-F1 can
  never exceed onset F1 @50ms — the table restates that onset F1
  (0.6739121651650438) as an explicit ceiling. **This number does not
  support a "prototype beats legacy" conclusion of any kind** — it is a
  ceiling on the legacy side, not a measurement of either side's direction
  accuracy.
- **Algorithmic latency** — both numbers are algorithmic (derived from
  window/lookahead constants), not real-time on-device measurements; the
  legacy manifest's own `latency` block is `not-measured` for the same
  reason ("offline batch run ... not a real-time on-device run").

## 6. Go/no-go verdict (ADR 0517 D4, Chapter 14 §7.2 Strum Alpha gate)

```
onset F1 @50ms = 0.3824  is BELOW  the 0.82 Alpha gate
direction macro-F1 = 0.2240  is BELOW  the 0.80 Alpha gate
decision: NO-GO
```

The threshold is inclusive (at-or-above on **both** metrics is required for
"go"; below on either — including a near-miss — is "no-go", ADR 0517 D4).
Neither prototype metric is close to its threshold, so this is an
unambiguous no-go, not a borderline case.

**Full measured IO document** (conforms to
`evaluation/recognition/joint_io_schema.json`; produced by
`evaluate_prototype.py`, printed here verbatim from the real run):

```json
{
  "schemaVersion": "1.0",
  "generatedAt": "2026-09-05T06:48:26Z",
  "corpus": {
    "corpusId": "ml/data/klangio",
    "corpusSha256": "4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827",
    "recordingCount": 82,
    "matchesBaselineManifest": true,
    "baselineManifestPath": "evaluation/recognition/baseline_manifest.json"
  },
  "lookahead": {
    "preFrames": 3,
    "lookaheadFrames": 4,
    "hopMs": 10.0,
    "lookaheadMs": 40.0,
    "causal": false,
    "note": "30ms causal context + 40ms controlled lookahead (7 frames total) — far below the legacy direction classifier's 120ms post-onset window (PRE=3/POST=12 frames, ml/features.py)."
  },
  "splitStrategy": {
    "method": "leave-one-guitarist-out",
    "heldOutGuitarist": "1",
    "trainRecordingCount": 55,
    "testRecordingCount": 27,
    "leakageCheckPassed": true,
    "leakageCheckMethod": "evaluate_prototype.py::assert_no_leakage recomputed the guitarist-id partition independently of the training run's provenance and asserted the train/test guitarist-id sets are disjoint and the test set is exactly the held-out guitarist (ADR 0517 D2)."
  },
  "config": {
    "epochs": 6,
    "batchSize": 32,
    "seed": 42,
    "modelParamCount": 363891,
    "wallClockSeconds": 137.8945541381836
  },
  "metrics": {
    "prototypeOnsetF1At50ms": {
      "value": 0.3824146481022315,
      "n": 16962,
      "definition": {
        "text": "Precision/recall/F1 of peak-picked joint-model onset events (1-P(no-event) local maxima, >=60ms apart) against expected onset events, matched within an inclusive 50ms tolerance via greedy nearest-available one-to-one matching, ignoring predicted direction.",
        "higherIsBetter": true
      }
    },
    "prototypeDirectionMacroF1": {
      "value": 0.22403434521366614,
      "n": 20972,
      "definition": {
        "text": "Macro-averaged per-direction (down/up) F1: per-class true positives come only from time-matched onset pairs whose expected and detected direction both equal that class; false positives/negatives are counted over the FULL detected/expected populations for that class (same definition as recognition_metrics.dart's directionF1, ADR 0509).",
        "higherIsBetter": true
      }
    },
    "prototypeAlgorithmicLatencyMs": {
      "value": 40.0,
      "n": 1,
      "definition": {
        "text": "Algorithmic verdict latency: the model cannot commit to a down/up/no-event verdict until it has observed lookaheadFrames*hopMs of audio after the candidate time — not a real-time on-device measurement (no device clock was sampled).",
        "higherIsBetter": false
      }
    },
    "legacyOnsetF1At50ms": {
      "value": 0.6739121651650438,
      "n": 16411,
      "sourceFile": "evaluation/recognition/baseline_manifest.json",
      "definition": {
        "text": "Legacy two-stage pipeline's SuperFlux onset detector F1 at 50ms tolerance, anchored from the merged baseline manifest (ADR 0354), same corpus (hash-verified by this script before any number was read).",
        "higherIsBetter": true
      }
    },
    "legacyDirectionF1UpperBound": {
      "value": 0.6739121651650438,
      "n": 16411,
      "sourceFile": "evaluation/recognition/baseline_manifest.json",
      "bound": "upper",
      "derivation": "The legacy end-to-end direction macro-F1 is not measured on this corpus (baseline_manifest.json metricBlocks.direction.status = not-measured). A correct end-to-end direction call requires a correctly time-matched onset first (TP_direction is a subset of TP_onset), so end-to-end direction macro-F1 cannot exceed onset F1 @50ms — this row restates that onset F1 as an explicit ceiling, never a direction measurement, and never grounds a claim that the prototype beats the legacy pipeline on direction.",
      "definition": {
        "text": "Upper bound on the legacy pipeline's end-to-end direction macro-F1, derived from its onset F1 @50ms via the onset-precedes-direction inequality.",
        "higherIsBetter": true
      }
    }
  },
  "verdict": {
    "alphaThresholds": {
      "onsetF1At50ms": 0.82,
      "directionMacroF1": 0.8
    },
    "onsetF1Comparison": "below",
    "directionF1Comparison": "below",
    "decision": "no-go",
    "rationale": "onset F1 @50ms=0.3824 is below the 0.82 Alpha gate; direction macro-F1=0.2240 is below the 0.80 Alpha gate. Decision is \"go\" iff BOTH meet or exceed their threshold (ADR 0517 D4, inclusive boundary)."
  }
}
```

## 7. Reproduction

```bash
/home/ubuntu/tf-venv/bin/python ml/joint_prototype/train_prototype.py \
    --workdir /tmp/e14r18-work
/home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py \
    --workdir /tmp/e14r18-work
```

Deterministic per seed (42): the dataset build, the LOGO fold choice
(first in sorted guitarist-id order), and TensorFlow's own seeding
(`ml/train.py::set_seeds`) are all seeded; the numbers above reproduced
byte-for-byte across two independent runs during this round (the only
change between them was adding the `generatedAt` timestamp field).

## 8. Honest limitations of this measurement

- **Full-timeline scanning is out of the training distribution.** The
  model was trained on positive windows at labeled strum times plus MINED
  no-event negatives (`ml/negatives.py`: hard flux-peak + easy interior
  negatives, the same recipe `ml/train_live_3c.py`'s reject head uses) —
  not on "every 10ms frame of continuous audio." Scanning the full
  timeline at evaluation time exposes the model to a far broader
  no-event distribution than it trained on, and the measured
  precision/recall skew (0.237 / 0.986 for onset detection) shows it: the
  model rarely MISSES a real onset, but produces roughly 3× as many false
  detections as true ones. This is a genuine finding about this training
  recipe's mismatch with a real streaming deployment, not a bug in the
  measurement — a follow-up round that wants a stronger prototype would
  need to train against continuous-stream negatives (or add temporal
  hysteresis / a higher decision threshold), not just rerun this
  configuration with different hyperparameters.
- **Matching is greedy, not Kuhn's maximum-cardinality algorithm.**
  `evaluate_prototype.py::match_events` uses greedy nearest-available
  one-to-one matching, a documented simplification of the production
  matcher (`recognition_metrics.dart::_matchEvents`). Adequate for this
  prototype's own internal comparison; not claimed to be optimal.
- **One LOGO fold, not the full 3-fold sweep** (compute budget, round brief
  §0.0/R8) — held-out guitarist `1` only. A future round wanting a
  generalization estimate across all three guitarists would need the full
  sweep.
- **No calibration, no confidence-based abstention** — the peak-picking
  threshold (0.5) and minimum gap (60ms) are fixed constants carried over
  from `ml/features.py::spectral_flux_onsets`'s peak-picking discipline,
  not tuned against this task.

## 9. Recommendation

**No-go against the Chapter 14 §7.2 Strum Alpha gate**, on both measured
metrics, by a wide margin (not a near-miss). The joint-head architectural
idea (avoiding the two-stage error-propagation path, ADR 0312) is not
falsified by this result — what this one documented run falsifies is
*this specific training recipe* (mined-negative training evaluated against
continuous-stream scanning) as a way to realize it. See
`docs/rounds/e14-r18-joint-streaming-prototype.md` §10 for the full
implementation handoff, and the corresponding ADR for the formal go/no-go
decision record.
