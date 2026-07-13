"""Generate ml/model_card.json from honest_results.json + dataset facts (r172).

The card is the provenance record: dataset SHA + row counts, seeds, split
definitions, and every measured number of the honest-measurement round —
regenerate it whenever honest_eval.py is re-run, never hand-edit numbers.

Usage: /home/ubuntu/tf-venv/bin/python make_model_card.py
"""
from __future__ import annotations

import json
import os
from datetime import date

import numpy as np

import klangio

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    with open(os.path.join(HERE, "honest_results.json")) as fh:
        r = json.load(fh)

    d = np.load(os.path.join(HERE, "klangio.npz"))
    y, rec = d["y"], d["rec"]
    recs = sorted(set(rec.tolist()))
    per_g = {}
    for g in sorted({klangio.guitarist_of(x) for x in recs}):
        per_g[g] = {
            "recordings": sum(1 for x in recs if klangio.guitarist_of(x) == g),
            "windows": int(sum(1 for x in rec.tolist()
                               if klangio.guitarist_of(x) == g)),
        }

    card = {
        "model": "StrumSight strum-direction CRNN (down/up)",
        "generated": str(date.today()),
        "round": 173,
        "architecture": "3x[Conv2D 3x3 + ReLU + MaxPool(1,2)] -> GRU(128) -> "
                        "Dense(2 softmax); ~364k params; input (15, 128) "
                        "log-mel window (PRE 3 / POST 12 frames, 10 ms hop)",
        "configs": {
            "batch": "full window (~240 ms post-onset audio) — Analyze path",
            "live70": "audio zeroed past onset+70 ms — Live path "
                      "(train == serve, ml/experiment_deadline.py geometry)",
        },
        "dataset": {
            "name": "Klangio GST-MM 2025 (ISMIR 2025, arXiv:2508.07973)",
            "repo": klangio.DATASET_REPO,
            "pinned_commit": klangio.DATASET_SHA,
            "path": klangio.DATASET_PATH,
            "license": "Apache-2.0",
            "variant": "phone-mic wavs (deployment condition)",
            "recordings": len(recs),
            "windows": int(len(y)),
            "down": int((y == 0).sum()),
            "up": int((y == 1).sum()),
            "per_guitarist": per_g,
            "guitarist_id_rule": "leading digit of recording id (1/2/4)",
        },
        "training": {
            "seeding": "tf.keras.utils.set_random_seed + PYTHONHASHSEED "
                       "(ml/train.py::set_seeds); --seed arg, default 42",
            "recipe": "Adam 1e-3, batch 32, <=40 epochs, EarlyStopping on "
                      "val_accuracy (patience 8, restore_best_weights), "
                      "class-weighted up-strums, train-fold-only norm stats",
            "r173_augment_reg": "logo_aug / threeway_aug results add PCM-domain "
                                "augmentation (augment.py: pitch ±6 st varispeed "
                                "[Murgul optimum] + synthetic-RIR reverb + phone "
                                "mic-sim EQ/band-limit + gain/noise, n_aug=2) to "
                                "the TRAIN fold ONLY, plus build_model "
                                "regularization (dropout 0.25 + GRU "
                                "recurrent_dropout 0.15 + L2 1e-4). Val/test stay "
                                "CLEAN and identical to the r172 folds, so the "
                                "numbers are directly comparable. Default "
                                "build_model (all reg args 0) stays byte-"
                                "identical for fixture back-compat.",
            "splits": {
                "legacy_2way": "split_by_recording seed 42 (80/20) — kept for "
                               "fixture back-compat; its 'eval' fold was BOTH "
                               "early-stopping val and headline test pre-r172 "
                               "(the source of the optimistic 0.867/0.799)",
                "3way": "split_by_recording_3way seed 42 "
                        "(val 15% / test 15% by recording); VAL early-stops, "
                        "TEST touched once",
                "logo": "leave-one-guitarist-out; VAL carved from the "
                        "remaining guitarists' recordings (seed 42)",
            },
        },
        "measured": {
            "old_claims_superseded": {
                "batch_0.867": "single fold = val = test = calibration fit",
                "live70_0.799": "same single fold",
            },
            **{k: v for k, v in r.items() if not k.startswith("_")},
        },
        "timing_seconds": r.get("_timing", {}),
    }
    out = os.path.join(HERE, "model_card.json")
    with open(out, "w") as fh:
        json.dump(card, fh, indent=2)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
