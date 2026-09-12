"""E18-R28 - does adding a SECOND corpus fix the direction head's transfer failure?

ADR 0550 measured the defect: the live model scores direction macro-F1 0.3876 (up-F1
0.1905) on GuitarSet while a plain logistic regression on the model's OWN input geometry
reaches 0.7723 / 0.6294 on a player- AND tune-disjoint split. The cue is in the input and
the CRNN does not extract it. The named cause is the training corpus: Klangio
GST-MM-2025 is real, labelled, phone-mic data, but it is **three guitarists** in one
room on one guitar through one microphone (`klangio.guitarist_of` is the leading digit of
the recording id; the blocks are 1xxx / 2xxx / 4xxx). A model never asked to generalise
past three players has no reason to have learned a player-invariant cue.

This trains the SAME architecture (`train.build_model`) on the SAME train==serve geometry
(`experiment_deadline.window_truncated`, audio zeroed past onset+70 ms) and changes
exactly one thing: which corpora are in the training pool.

    GUITARSET_DIR=/path/to/guitarset python ml/experiment_cross_corpus.py

## The protocol, and why it is shaped like this

Three arms, each evaluated on BOTH held-out corpora:

    A  Klangio only            - reproduces today's situation inside this harness, so
                                 arm B is compared against a number measured the same way
                                 rather than against a number from another script
    B  Klangio + GuitarSet     - the candidate
    C  GuitarSet only          - the control that keeps B honest: if C alone matched B,
                                 then B would be "GuitarSet works" rather than "two
                                 corpora work", and Klangio would be dead weight

Held-out sets, fixed before any arm runs:

    Klangio   guitarist block '4' - an unseen PLAYER in the original domain. An arm that
                                    improves GuitarSet by wrecking this has not fixed
                                    anything, it has moved the failure.
    GuitarSet players 03-05 x tunes Funk3/Rock3 - unseen player AND unseen progression.

GuitarSet's crossed combinations (train players on test tunes, and the reverse) are
DISCARDED, about 1471 of 3056 sweeps. That is expensive and it is the point: keeping them
would leave either the player or the tune shared with the test set, and a direction score
that can be reached through "which chord, how far into this tune" is not a direction
score (ADR 0550).

Normalisation statistics, class weights and early stopping all come from the TRAIN pool
only (the r142 no-leak discipline). Validation for early stopping is carved out BY GROUP
- whole Klangio recordings, whole GuitarSet takes - never by shuffling windows, because
windows from one take are near-duplicates of each other and a shuffled split would let
the model early-stop on material it had effectively trained on.

Direction only (2 classes). The no-strum head is a separate capability with its own
calibrated gate (ADR 0549) and mining its negatives for a second corpus is a second
problem; mixing the two would make it impossible to say which change moved which number.
Shipping is therefore NOT this script's job - it reports whether the corpus fix works.
"""
from __future__ import annotations

import os
import sys

import numpy as np

import honest_eval as H
import klangio as K
from train import build_model, set_seeds

SEED = 42
EPOCHS = 60
BATCH = 64
PATIENCE = 8
VAL_GROUP_FRAC = 0.2
KLANGIO_TEST_GUITARIST = "4"
# r173 regularisation, a-priori and NOT tuned here (honest_eval.AUG_REG): the documented
# train-0.99 / val-0.84 overfit on ~364k params is exactly what a small corpus produces,
# and this experiment makes the corpus bigger, so leaving it off would confound the two.
REG = H.AUG_REG


def f1(true, pred, positive):
    tp = int(((pred == positive) & (true == positive)).sum())
    fp = int(((pred == positive) & (true != positive)).sum())
    fn = int(((pred != positive) & (true == positive)).sum())
    return 0.0 if tp == 0 else 2 * tp / (2 * tp + fp + fn)


def group_val_split(groups, rng):
    """Hold out whole GROUPS for early stopping - never individual windows."""
    unique = np.array(sorted(set(groups.tolist())))
    rng.shuffle(unique)
    n_val = max(1, int(round(len(unique) * VAL_GROUP_FRAC)))
    val_groups = set(unique[:n_val].tolist())
    is_val = np.array([g in val_groups for g in groups])
    return ~is_val, is_val


def train_arm(name, X, y, groups, tests):
    """Fit one arm and score it on every held-out set. Returns {test name: metrics}."""
    import tensorflow as tf

    set_seeds(SEED)
    rng = np.random.default_rng(SEED)
    fit_mask, val_mask = group_val_split(groups, rng)
    # Norm stats from the FITTING slice only - not the validation slice, not the tests.
    mean = X[fit_mask].mean()
    std = X[fit_mask].std() or 1.0
    counts = np.bincount(y[fit_mask], minlength=2).astype(np.float64)
    weights = {c: float(counts.sum() / (2 * max(counts[c], 1))) for c in (0, 1)}
    print(f"\n=== arm {name}: fit {fit_mask.sum()} / val {val_mask.sum()} windows, "
          f"{len(set(groups.tolist()))} groups, "
          f"{100 * (y[fit_mask] == 0).mean():.0f}% down, "
          f"class weights {weights[0]:.2f}/{weights[1]:.2f}", flush=True)

    model = build_model(X.shape[1], X.shape[2], n_classes=2, **REG)
    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy",
                  metrics=["accuracy"])
    model.fit(
        (X[fit_mask] - mean) / std, y[fit_mask],
        validation_data=((X[val_mask] - mean) / std, y[val_mask]),
        epochs=EPOCHS, batch_size=BATCH, class_weight=weights, verbose=2,
        callbacks=[tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=PATIENCE, restore_best_weights=True)],
    )

    out = {}
    for test_name, (Xt, yt) in tests.items():
        pred = model.predict((Xt - mean) / std, verbose=0).argmax(axis=1)
        down, up = f1(yt, pred, 0), f1(yt, pred, 1)
        out[test_name] = {
            "down": down, "up": up, "macro": (down + up) / 2,
            "n": len(yt), "called_up": float((pred == 1).mean()),
            "truth_up": float((yt == 1).mean()),
        }
    return out


def main():
    import guitarset as G

    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")

    kx, ky, krec = H.build_live()
    k_guitarist = np.array([K.guitarist_of(r) for r in krec])
    k_train = k_guitarist != KLANGIO_TEST_GUITARIST
    k_test = ~k_train

    gx, gy, g_player, g_tune = G.build()
    g_train_mask, g_test_mask = G.split_masks(g_player, g_tune)
    g_take = np.array([f"{p}_{t}" for p, t in zip(g_player, g_tune)])

    print(f"Klangio  : train {k_train.sum():5d} windows "
          f"(guitarists {sorted(set(k_guitarist[k_train].tolist()))}), "
          f"test {k_test.sum():5d} (guitarist {KLANGIO_TEST_GUITARIST}), "
          f"{100 * (ky[k_test] == 0).mean():.0f}% down in test")
    print(f"GuitarSet: train {g_train_mask.sum():5d} windows, "
          f"test {g_test_mask.sum():5d}, "
          f"{100 * (gy[g_test_mask] == 0).mean():.0f}% down in test; "
          f"{(~(g_train_mask | g_test_mask)).sum()} crossed windows DISCARDED")

    tests = {
        "GuitarSet (new player AND new tune)": (gx[g_test_mask], gy[g_test_mask]),
        "Klangio (new player, same rig)": (kx[k_test], ky[k_test]),
    }
    arms = {
        "A Klangio only": (kx[k_train], ky[k_train],
                           np.array([f"k{r}" for r in krec[k_train]])),
        "B Klangio + GuitarSet": (
            np.concatenate([kx[k_train], gx[g_train_mask]]),
            np.concatenate([ky[k_train], gy[g_train_mask]]),
            np.concatenate([np.array([f"k{r}" for r in krec[k_train]]),
                            np.array([f"g{t}" for t in g_take[g_train_mask]])]),
        ),
        "C GuitarSet only": (gx[g_train_mask], gy[g_train_mask],
                             np.array([f"g{t}" for t in g_take[g_train_mask]])),
    }

    results = {name: train_arm(name, *data, tests) for name, data in arms.items()}

    print("\n" + "=" * 78)
    print("DIRECTION F1 (2-class, live 70 ms geometry, held-out by player and tune)")
    for test_name in tests:
        print(f"\n  {test_name}")
        print("    arm                      down      up    macro   called up / truth")
        for name, per_test in results.items():
            row = per_test[test_name]
            print(f"    {name:<22} {row['down']:.4f}  {row['up']:.4f}  "
                  f"{row['macro']:.4f}   {row['called_up']:.2f} / {row['truth_up']:.2f}"
                  f"   (n={row['n']})")
    print("\n  shipped 3-class CRNN on GuitarSet, same clean labels: "
          "down 0.5848  up 0.1905  macro 0.3876")
    print("  linear floor on the same input (ADR 0550):   "
          "down 0.9152  up 0.6294  macro 0.7723")


if __name__ == "__main__":
    main()
