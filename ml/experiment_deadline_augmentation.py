"""E18-R31 - one asset invoked twice, or two specialised heads?

ADR 0552 established the two-tier direction decision: a provisional call at the 70 ms live
deadline for the arrow, a settled call at ~238 ms for rhythm scoring, worth +0.1429 macro-F1
and costing nothing architecturally because the shipped 15-frame window already reaches
238 ms past the onset.

What it did NOT decide is how that ships, and the naive reading is expensive. The tensor
shape is identical at both deadlines, but the two models were TRAINED on different
truncations, so "two tiers" reads as two weight sets, two assets, two loads, two parity
fixtures - and the Dart side has to pick the right one per call site.

The alternative is one model trained on BOTH truncations - every sweep presented twice, once
truncated at 70 ms and once whole - so a single set of weights learns to use whatever audio
is present, and the two tiers become two CALL TIMES rather than two models. That is cheaper
everywhere that matters: one asset, one parity fixture, one `tryLoad`.

Measured here, because building the two-asset version first and discovering this later would
be the expensive order:

    A  trained at 70 ms only       -> scored at 70 ms and at 238 ms
    B  trained at 238 ms only      -> scored at 70 ms and at 238 ms
    C  trained on BOTH truncations -> scored at 70 ms and at 238 ms

If C matches A at 70 ms and B at 238 ms, one asset serves both tiers and the two-asset plan
is dropped. If C is a compromise that loses at both, two heads are the honest cost.

Arms A and B also answer something the grid could not: what a 238 ms-trained model does when
the audio has NOT arrived yet. That is not hypothetical - it is exactly the arrow's situation,
and a settled head used there would be a model reading 168 ms of zeros it never saw in
training.

Direction only (2 classes), as in `experiment_cross_corpus.py`: the no-strum head is a
separate capability with its own calibrated gate (ADR 0549), and mixing them would make it
impossible to say which change moved which number. Held-out sets are fixed before any arm
runs - Klangio guitarist block '4' (unseen player, original rig) and GuitarSet players 03-05
x tunes Funk3/Rock3 (unseen player AND unseen progression).

    GUITARSET_DIR=/path/to/guitarset python ml/experiment_deadline_augmentation.py
"""
from __future__ import annotations

import os
import sys

import numpy as np

import guitarset as G
import honest_eval as H
import klangio as K
from train import build_model, set_seeds

# The repo's standard multi-seed sweep (honest_eval.STD_SEEDS). One seed cannot tell a
# collapse from a bad initialisation, and the decisive findings here ARE collapses.
SEEDS = H.STD_SEEDS
EPOCHS = 60
BATCH = 64
PATIENCE = 8
VAL_GROUP_FRAC = 0.2
KLANGIO_TEST_GUITARIST = "4"
REG = H.AUG_REG

DEADLINES = {
    "70 ms": (0.070, "klangio_live70.npz", "guitarset_live70.npz"),
    "238 ms": (10.0, "klangio_live_full.npz", "guitarset_live_full.npz"),
}


def f1(true, predicted, positive):
    tp = int(((predicted == positive) & (true == positive)).sum())
    fp = int(((predicted == positive) & (true != positive)).sum())
    fn = int(((predicted != positive) & (true == positive)).sum())
    return 0.0 if tp == 0 else 2 * tp / (2 * tp + fp + fn)


def macro(true, predicted):
    return (f1(true, predicted, 0) + f1(true, predicted, 1)) / 2


def load(deadline_label):
    """Both corpora at one deadline, with train/test masks and group keys."""
    deadline, k_cache, g_cache = DEADLINES[deadline_label]
    kx, ky, krec = H.build_live(deadline_s=deadline, cache=k_cache)
    k_guitarist = np.array([K.guitarist_of(r) for r in krec])
    k_train = k_guitarist != KLANGIO_TEST_GUITARIST
    gx, gy, g_player, g_tune = G.build(deadline_s=deadline, cache=g_cache)
    g_train, g_test = G.split_masks(g_player, g_tune)
    g_take = np.array([f"{p}_{t}" for p, t in zip(g_player, g_tune)])
    return {
        "train_x": np.concatenate([kx[k_train], gx[g_train]]),
        "train_y": np.concatenate([ky[k_train], gy[g_train]]),
        "train_g": np.concatenate([
            np.array([f"k{r}" for r in krec[k_train]]),
            np.array([f"g{t}" for t in g_take[g_train]])]),
        "tests": {
            "GuitarSet (new player AND tune)": (gx[g_test], gy[g_test]),
            "Klangio (new player, same rig)": (kx[~k_train], ky[~k_train]),
        },
    }


def group_val_split(groups, rng):
    """Hold out whole groups - recordings and takes - never individual windows."""
    unique = np.array(sorted(set(groups.tolist())))
    rng.shuffle(unique)
    held = set(unique[:max(1, int(round(len(unique) * VAL_GROUP_FRAC)))].tolist())
    is_val = np.array([g in held for g in groups])
    return ~is_val, is_val


def train_arm(name, X, y, groups, all_tests, seed):
    import tensorflow as tf

    set_seeds(seed)
    fit_mask, val_mask = group_val_split(groups, np.random.default_rng(seed))
    mean = X[fit_mask].mean()
    std = X[fit_mask].std() or 1.0
    counts = np.bincount(y[fit_mask], minlength=2).astype(np.float64)
    weights = {c: float(counts.sum() / (2 * max(counts[c], 1))) for c in (0, 1)}
    print(f"\n=== arm {name} seed {seed}: fit {fit_mask.sum()} / val "
          f"{val_mask.sum()} windows, {len(set(groups.tolist()))} groups", flush=True)

    model = build_model(X.shape[1], X.shape[2], n_classes=2, **REG)
    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy")
    model.fit((X[fit_mask] - mean) / std, y[fit_mask],
              validation_data=((X[val_mask] - mean) / std, y[val_mask]),
              epochs=EPOCHS, batch_size=BATCH, class_weight=weights, verbose=0,
              callbacks=[tf.keras.callbacks.EarlyStopping(
                  monitor="val_loss", patience=PATIENCE, restore_best_weights=True)])

    out = {}
    for deadline_label, tests in all_tests.items():
        for test_name, (Xt, yt) in tests.items():
            predicted = model.predict((Xt - mean) / std, verbose=0).argmax(axis=1)
            out[(deadline_label, test_name)] = {
                "down": f1(yt, predicted, 0), "up": f1(yt, predicted, 1),
                "macro": macro(yt, predicted), "n": len(yt),
                "called_up": float((predicted == 1).mean()),
                "truth_up": float((yt == 1).mean()),
            }
    return out


def main():
    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")

    data = {label: load(label) for label in DEADLINES}
    all_tests = {label: d["tests"] for label, d in data.items()}
    for label, d in data.items():
        print(f"{label:>7}: train {len(d['train_y'])} windows, "
              + ", ".join(f"{k} n={len(v[1])}" for k, v in d["tests"].items()))

    arms = {
        "A trained @70 ms": (data["70 ms"]["train_x"], data["70 ms"]["train_y"],
                             data["70 ms"]["train_g"]),
        "B trained @238 ms": (data["238 ms"]["train_x"], data["238 ms"]["train_y"],
                              data["238 ms"]["train_g"]),
        # Every sweep twice, once per truncation. Group keys are duplicated too, so the
        # validation split still cuts by recording/take and a sweep cannot appear in both
        # halves under its two truncations.
        "C trained @BOTH": (
            np.concatenate([data["70 ms"]["train_x"], data["238 ms"]["train_x"]]),
            np.concatenate([data["70 ms"]["train_y"], data["238 ms"]["train_y"]]),
            np.concatenate([data["70 ms"]["train_g"], data["238 ms"]["train_g"]]),
        ),
    }
    results = {}
    for name, payload in arms.items():
        per_seed = [train_arm(name, *payload, all_tests, seed) for seed in SEEDS]
        results[name] = {
            key: {metric: np.array([run[key][metric] for run in per_seed])
                  for metric in ("macro", "up", "called_up", "truth_up", "n")}
            for key in per_seed[0]
        }

    print("\n" + "=" * 96)
    print(f"DIRECTION macro-F1 (2-class), mean +/- sd over seeds {SEEDS}. "
          f"Rows = TRAINED, columns = SEEN.")
    for test_name in data["70 ms"]["tests"]:
        print(f"\n  {test_name}")
        print("    arm                   scored @70 ms              scored @238 ms")
        for name, per_cell in results.items():
            cells = []
            for deadline_label in ("70 ms", "238 ms"):
                c = per_cell[(deadline_label, test_name)]
                cells.append(f"{c['macro'].mean():.4f}+/-{c['macro'].std():.4f} "
                             f"(up {c['up'].mean():.4f}, "
                             f"calledUp {c['called_up'].mean():.2f}/"
                             f"{c['truth_up'][0]:.2f})")
            print(f"    {name:<20} {cells[0]:<44} {cells[1]}")
    print("\n  majority baselines: GuitarSet 0.4468, Klangio 0.3836")
    print("  ADR 0552's chosen cell (trained and scored @238 ms): GuitarSet 0.6446")
    print("\n  Read it as: does C match A in the @70 column AND B in the @238 column?")
    print("  If yes, ONE asset serves both tiers. If C loses in both, two heads are the cost.")


if __name__ == "__main__":
    main()
