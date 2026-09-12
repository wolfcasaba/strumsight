"""E18-R28/R29 - two levers on the direction head: a SECOND corpus, and the DEADLINE.

Run as a grid: three training pools x two live deadlines, every cell scored on both
held-out corpora. The second axis was added once ADR 0551 D3 measured that the cue needs
150-250 ms of post-onset audio while the shipped path zeroes everything past 70 ms.

The deadline axis costs nothing architecturally, which is the point: the shipped 15-frame
window ALREADY reaches 238 ms past the onset, so both blocks use the same (15, 128) tensor
and the same network, and only the truncation moves. A "settled" direction head therefore
needs no new frontend and no Dart parity work - just a second invocation once the audio
has arrived.

What the grid decides: whether the two-tier decision of ADR 0551 D4 (provisional at 70 ms
for the live arrow, settled at ~250 ms for rhythm scoring) is worth wiring. The 0.7326 in
ADR 0551 is a LINEAR floor; if the CRNN cannot convert the extra audio into accuracy, the
plumbing buys nothing and must not be built.

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

Arm C earned its place immediately: at the 70 ms deadline its macro-F1 (0.5068) BEAT the
candidate's (0.5017) while it called nothing up on Klangio - it had collapsed onto the
majority class of an 81 %-down test set. Macro-F1 alone would have selected the worse
model. That is why every row prints `calledUp/truth`, the predicted up-rate beside the true
one: a collapsed model is invisible in macro-F1 and obvious in that column (LESSONS L666,
and the same prior trap as L664 one level up - there it would have mis-set a threshold,
here it would have chosen which model ships).

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

# The second axis, added after ADR 0551 D3 measured that the cue needs 150-250 ms of
# post-onset audio while the live path zeroes everything past 70 ms. No architecture
# changes between these two: the shipped 15-frame window already REACHES 238 ms after the
# onset, so the tensor stays (15, 128) and only the truncation moves. `ARRIVED` is any
# deadline past that reach, i.e. the window with nothing thrown away.
DEADLINES = {"70 ms (shipped)": 0.070, "238 ms (full window)": 10.0}
CACHES = {0.070: ("klangio_live70.npz", "guitarset_live70.npz"),
          10.0: ("klangio_live_full.npz", "guitarset_live_full.npz")}
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


def build_grid(deadline):
    """Both corpora at one deadline, with the three arms and the two held-out sets."""
    import guitarset as G

    k_cache, g_cache = CACHES[deadline]
    kx, ky, krec = H.build_live(deadline_s=deadline, cache=k_cache)
    k_guitarist = np.array([K.guitarist_of(r) for r in krec])
    k_train, k_test = k_guitarist != KLANGIO_TEST_GUITARIST, None
    k_test = ~k_train

    gx, gy, g_player, g_tune = G.build(deadline_s=deadline, cache=g_cache)
    g_train, g_test = G.split_masks(g_player, g_tune)
    g_take = np.array([f"{p}_{t}" for p, t in zip(g_player, g_tune)])
    k_groups = np.array([f"k{r}" for r in krec[k_train]])
    g_groups = np.array([f"g{t}" for t in g_take[g_train]])

    tests = {
        "GuitarSet (new player AND tune)": (gx[g_test], gy[g_test]),
        "Klangio (new player, same rig)": (kx[k_test], ky[k_test]),
    }
    arms = {
        "A Klangio only": (kx[k_train], ky[k_train], k_groups),
        "B Klangio + GuitarSet": (
            np.concatenate([kx[k_train], gx[g_train]]),
            np.concatenate([ky[k_train], gy[g_train]]),
            np.concatenate([k_groups, g_groups]),
        ),
        "C GuitarSet only": (gx[g_train], gy[g_train], g_groups),
    }
    return arms, tests, (k_train.sum(), k_test.sum(), g_train.sum(), g_test.sum(),
                         (~(g_train | g_test)).sum())


def main():
    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")

    results = {}
    tests_seen = None
    for label, deadline in DEADLINES.items():
        arms, tests, sizes = build_grid(deadline)
        tests_seen = tests
        print(f"\n##### deadline {label}: Klangio train {sizes[0]} / test {sizes[1]}, "
              f"GuitarSet train {sizes[2]} / test {sizes[3]} "
              f"({sizes[4]} crossed windows DISCARDED)", flush=True)
        for name, data in arms.items():
            results[(label, name)] = train_arm(f"{name} @ {label}", *data, tests)

    print("\n" + "=" * 94)
    print("DIRECTION F1 (2-class, shipped 15x128 geometry, held out by player and tune)")
    print("Only the TRUNCATION differs between the two deadline blocks - same tensor "
          "shape, same network.")
    for test_name in tests_seen:
        print(f"\n  {test_name}")
        print("    arm                     deadline               down      up    macro"
              "   calledUp/truth")
        for (label, name), per_test in results.items():
            row = per_test[test_name]
            print(f"    {name:<22}  {label:<20} {row['down']:.4f}  {row['up']:.4f}  "
                  f"{row['macro']:.4f}   {row['called_up']:.2f}/{row['truth_up']:.2f}"
                  f"  (n={row['n']})")
    print("\n  shipped 3-class CRNN on GuitarSet (end to end): "
          "down 0.5848  up 0.1905  macro 0.3876")
    print("  linear floor, shipped input @  70 ms (ADR 0551): "
          "down 0.7857  up 0.3913  macro 0.5885")
    print("  linear floor, 16 bands    @ 238 ms (ADR 0551): "
          "down 0.9186  up 0.5466  macro 0.7326")


if __name__ == "__main__":
    main()
