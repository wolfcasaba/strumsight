"""E18-R32 - train + export the TWO-TIER 3-class live strum model (ADR 0552/0554).

What this changes relative to `train_live_3c.py`, and nothing else:

  1. TWO CORPORA. Klangio GST-MM-2025 (3 guitarists) plus GuitarSet's derived sweeps
     (6 more players). Measured payoff: adding GuitarSet lifted BOTH held-out corpora,
     including the original Klangio domain (ADR 0552 D2).
  2. TWO TRUNCATIONS in one model. Every window is presented twice - truncated at the
     70 ms live deadline and whole - so ONE weight set serves both tiers (ADR 0554 D1).
     That arm WON the 70 ms tier over a dedicated 70 ms specialist and tied the 238 ms
     specialist, with the smallest seed spread; deadline augmentation regularises rather
     than compromising.

Everything else follows the shipped recipe deliberately: same architecture
(`train.build_model(n_classes=3)`), same window geometry (`window_truncated`, so the
tensor stays (15, 128) and `crnn_frontend` needs no change at all), same gate calibration
rule (the P(no-strum) quantile keeping >= 95 % of true strums on a held-out fold, ADR 0549),
same SSML export path.

## Why the tiers cannot just be "call the shipped model twice"

Measured over three seeds (`ml/experiment_deadline_augmentation.py`), both cross cells
collapse:

  * the 238 ms-trained head at 70 ms calls up 0.08 of the time against a true 0.38 on
    Klangio - and 70 ms is where the ARROW lives;
  * the 70 ms-trained head at 238 ms scores 0.4269 +/- 0.0063 on GuitarSet, BELOW the
    0.4468 majority baseline with a tiny spread - it gets worse with more audio because it
    never learned to use it.

That is also why the asset comes before the Dart seam: wiring a settled call backed by
today's weights would regress rhythm SCORING, the path where a wrong answer is a deduction
or a phantom credit (ADR 0549 D2).

## The split, and what it is held out against

  Klangio   guitarist block '4' - an unseen PLAYER in the original rig.
  GuitarSet players 03-05 x tunes Funk3/Rock3 - unseen player AND unseen progression,
            because every GuitarSet player plays all 12 tunes, so a player-only split
            leaves the progression shared (ADR 0550).

Negatives are split the same way, by the same keys, so no recording or take appears on both
sides of the line in any class.

    GUITARSET_DIR=/path/to/guitarset python ml/train_live_3c_settled.py [--seed=42]

Writes `weights_live_3c_settled.npz`, `live_3c_settled_threshold.json` and
`assets/ml/strum_crnn_live_3c_settled.bin`. **The shipped
`assets/ml/strum_crnn_live_3c.bin` is NOT touched** - swapping it over is the wiring round's
job, under AGENTS.md  9 (fixture + property + parity + real-audio measurement).
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

import guitarset as G
import honest_eval as H
import klangio as K
from export_dart_weights import NAMES, write_bin
from train import build_model, set_seeds

SEED = 42
EPOCHS = 60
BATCH = 64
PATIENCE = 8
KLANGIO_TEST_GUITARIST = "4"
SETTLED_DEADLINE = 10.0  # anything past the window's 238 ms reach = nothing thrown away
N_FIXTURE = 32

DOWN, UP, NO_STRUM = 0, 1, 2


def _klangio(deadline, pos_cache, neg_config):
    """Klangio positives + mined negatives at one truncation, with train/test masks."""
    px, py, prec = H.build_live(deadline_s=deadline, cache=pos_cache)
    nx, nrec = H.build_negatives(neg_config)
    X = np.concatenate([px, nx])
    y = np.concatenate([py, np.full(len(nx), NO_STRUM, dtype=py.dtype)])
    rec = np.concatenate([prec, nrec])
    held = np.array([K.guitarist_of(r) for r in rec]) == KLANGIO_TEST_GUITARIST
    return X, y, np.array([f"k{r}" for r in rec]), ~held, held


def _guitarset(deadline, pos_cache, neg_tag):
    """GuitarSet positives + mined negatives at one truncation, with train/test masks."""
    px, py, pplayer, ptune = G.build(deadline_s=deadline, cache=pos_cache)
    nx, nplayer, ntune = G.build_negatives(deadline, neg_tag)
    X = np.concatenate([px, nx])
    y = np.concatenate([py, np.full(len(nx), NO_STRUM, dtype=py.dtype)])
    player = np.concatenate([pplayer, nplayer])
    tune = np.concatenate([ptune, ntune])
    train, test = G.split_masks(player, tune)
    groups = np.array([f"g{p}_{t}" for p, t in zip(player, tune)])
    return X, y, groups, train, test


def build_dataset():
    """Both corpora at BOTH truncations, as one pool plus per-corpus held-out sets."""
    tiers = {
        "70 ms": (H.LIVE_DEADLINE_S, "klangio_live70.npz", "live70",
                  "guitarset_live70.npz", "live70"),
        "238 ms": (SETTLED_DEADLINE, "klangio_live_full.npz", "live_full",
                   "guitarset_live_full.npz", "live_full"),
    }
    pool_x, pool_y, pool_g, pool_tier = [], [], [], []
    tests = {}
    for tier, (deadline, k_pos, k_neg, g_pos, g_neg) in tiers.items():
        kx, ky, kg, k_train, k_test = _klangio(deadline, k_pos, k_neg)
        gx, gy, gg, g_train, g_test = _guitarset(deadline, g_pos, g_neg)
        pool_x += [kx[k_train], gx[g_train]]
        pool_y += [ky[k_train], gy[g_train]]
        pool_g += [kg[k_train], gg[g_train]]
        # The tier each row came from. Needed because the no-strum GATE is a Dart-side
        # scalar, not part of the asset, so it can be calibrated per tier for free - and
        # P(no-strum) has no reason to be distributed alike when the model has 70 ms of
        # audio versus 238 ms. One asset (ADR 0554) does not imply one threshold.
        pool_tier += [np.full(int(k_train.sum()), tier), np.full(int(g_train.sum()), tier)]
        tests[(tier, "Klangio (new player)")] = (kx[k_test], ky[k_test])
        tests[(tier, "GuitarSet (new player AND tune)")] = (gx[g_test], gy[g_test])
        print(f"  {tier:>7}: Klangio train {k_train.sum()} / test {k_test.sum()}, "
              f"GuitarSet train {g_train.sum()} / test {g_test.sum()}", flush=True)
    return (np.concatenate(pool_x), np.concatenate(pool_y),
            np.concatenate(pool_g), np.concatenate(pool_tier), tests)


def f1(true, predicted, positive):
    tp = int(((predicted == positive) & (true == positive)).sum())
    fp = int(((predicted == positive) & (true != positive)).sum())
    fn = int(((predicted != positive) & (true == positive)).sum())
    return 0.0 if tp == 0 else 2 * tp / (2 * tp + fp + fn)


def score_direction(probs, truth, threshold):
    """Direction macro-F1 on TRUE strums, with the shipped suppression applied.

    Suppressed strums are counted as errors rather than dropped: a stroke the gate hides is
    a stroke the rhythm grader never sees, so excluding them would grade the model on the
    subset it happened to like (ADR 0549).
    """
    suppressed = probs[:, NO_STRUM] > threshold
    called = np.where(suppressed, -1, probs[:, :2].argmax(axis=1))
    down, up = f1(truth, called, DOWN), f1(truth, called, UP)
    return down, up, (down + up) / 2, float(suppressed.mean())


def main(seed=SEED):
    import tensorflow as tf

    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")
    set_seeds(seed)

    X, y, groups, tier, tests = build_dataset()
    counts = np.bincount(y, minlength=3)
    print(f"\npool {X.shape}: {counts[DOWN]} down / {counts[UP]} up / "
          f"{counts[NO_STRUM]} no-strum, {len(set(groups.tolist()))} groups")

    # Validation for early stopping and gate calibration comes out of the TRAIN pool by
    # GROUP - whole recordings and takes. Windows inside one take are near-duplicates, so a
    # shuffled split would early-stop on material the model effectively trained on.
    rng = np.random.default_rng(seed)
    unique = np.array(sorted(set(groups.tolist())))
    rng.shuffle(unique)
    val_groups = set(unique[:max(1, round(len(unique) * 0.2))].tolist())
    val = np.array([g in val_groups for g in groups])
    fit = ~val
    print(f"group-wise val split: fit {fit.sum()} / val {val.sum()} windows, "
          f"{len(val_groups)} held-out groups")

    mean = X[fit].mean(axis=(0, 1))
    std = X[fit].std(axis=(0, 1)) + 1e-6
    Xn = (X - mean) / std
    fit_counts = np.bincount(y[fit], minlength=3).astype(float)
    fit_counts[fit_counts == 0] = 1.0
    weights = {c: float(fit_counts.sum() / (3 * fit_counts[c])) for c in range(3)}

    model = build_model(X.shape[1], X.shape[2], n_classes=3, **H.AUG_REG)
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    model.fit(Xn[fit], y[fit], epochs=EPOCHS, batch_size=BATCH, shuffle=True,
              class_weight=weights, verbose=2,
              validation_data=(Xn[val], y[val]),
              callbacks=[tf.keras.callbacks.EarlyStopping(
                  monitor="val_loss", patience=PATIENCE, restore_best_weights=True)])

    # ---- Gate calibration on the held-out VAL groups ---------------------------------
    # ADR 0549's rule is `class_blind` below: the P(no-strum) quantile retaining 95 % of
    # true strums, without asking which direction they were. That is textbook Chow (1970) -
    # whose threshold formula t = (C_r - C_c)/(C_e - C_c) carries NO class index, because it
    # assumes every error and every rejection costs the same. Measured here, that assumption
    # is false: upstrokes carry up to 5x the median P(no-strum), so the class-blind rule
    # spends its suppression budget 1.3-2.8x more often on them - silencing the very class
    # the direction head is weakest on.
    #
    # `class_conditional` is the per-class version: each direction's own 95 % quantile, and
    # the shipped threshold is their max so EVERY class retains at least the target. That is
    # Mondrian / label-conditional conformal prediction (Vovk et al. 2003; Vovk, Gammerman &
    # Shafer 2005), which gives an exact finite-sample per-class guarantee - available here
    # precisely because the conditioning set is a FINITE partition (Barber et al. 2021 prove
    # exact conditional coverage is impossible over continuous conditioning, achievable over
    # a finite one). Fumera, Roli & Giacinto (2000) had already shown per-class reject
    # thresholds Pareto-dominate single-threshold Chow.
    #
    # Both are computed and recorded. The class-blind number is kept because it is what
    # ADR 0549 shipped, and deleting it would erase the evidence for the comparison.
    val_pos, val_neg = val & (y < NO_STRUM), val & (y == NO_STRUM)
    p_pos = model.predict(Xn[val_pos], verbose=0)
    p_neg = model.predict(Xn[val_neg], verbose=0)
    y_pos = y[val_pos]
    gates = {"class_blind": H._gate(p_pos[:, NO_STRUM], p_neg[:, NO_STRUM])}
    per_class = {}
    for cls, name in ((DOWN, "down"), (UP, "up")):
        rows = y_pos == cls
        per_class[name] = H._gate(p_pos[rows, NO_STRUM], p_neg[:, NO_STRUM])
        print(f"[gate {name:>11}] threshold={per_class[name][0]:.6f}  "
              f"(n={int(rows.sum())}, median P(no-strum)="
              f"{np.median(p_pos[rows, NO_STRUM]):.4f})")
    worst = max(per_class, key=lambda k: per_class[k][0])
    thr = per_class[worst][0]
    gates["class_conditional"] = (
        thr, float((p_pos[:, NO_STRUM] < thr).mean()),
        float((p_neg[:, NO_STRUM] >= thr).mean()))
    for label, (t, ret, rej) in gates.items():
        print(f"[gate {label:>17}] threshold={t:.6f} keeps {ret:.3f} of true strums, "
              f"rejects {rej:.3f} of false onsets")
    print(f"  -> class_conditional is set by the HARDER class ({worst}); "
          f"shipped threshold = {thr:.6f}")

    # Held-out report under BOTH gates, and per class on the RETAINED set. The retained
    # precision is not optional: Jones et al. (NeurIPS 2020) and Cresswell et al. (ICLR
    # 2025) both show that equalising RETENTION across classes does not equalise the error
    # rate on what is kept, and can leave or worsen the disparity that matters. Matching
    # retention while retained precision collapses would be a fake win, and the only way to
    # see that is to print it.
    threshold = gates["class_conditional"][0]
    print("\n=== held-out direction, both gates, with per-class retained precision ===")
    print("  gate               tier     corpus      macro   up-F1   upPrec  upRec  suppUp")
    report = {}
    for label, (thr_g, _, _) in gates.items():
        for (tier_label, corpus), (Xt, yt) in tests.items():
            probs = model.predict((Xt - mean) / std, verbose=0)
            strums = yt < NO_STRUM
            p, truth = probs[strums], yt[strums]
            down, up, macro, supp = score_direction(p, truth, thr_g)
            kept = p[:, NO_STRUM] <= thr_g
            called_up = kept & (p[:, :2].argmax(axis=1) == UP)
            hits = int((called_up & (truth == UP)).sum())
            up_precision = hits / max(int(called_up.sum()), 1)
            up_recall = hits / max(int((truth == UP).sum()), 1)
            up_suppressed = float((~kept)[truth == UP].mean())
            report[f"{label} | {tier_label} | {corpus}"] = {
                "down_f1": down, "up_f1": up, "macro_f1": macro,
                "suppressed_fraction": supp, "n": int(strums.sum()),
                "up_retained_precision": up_precision,
                "up_retained_recall": up_recall,
                "up_suppressed_fraction": up_suppressed,
            }
            print(f"  {label:<17}  {tier_label:>7}  {corpus.split()[0]:<10} "
                  f"{macro:.4f}  {up:.4f}  {up_precision:.4f}  {up_recall:.4f}  "
                  f"{up_suppressed:.3f}")
    print("\n  majority baselines: GuitarSet 0.4468, Klangio 0.3836")
    print("  2-class arm C reference (no gate): GuitarSet 0.5934 @70 / 0.6659 @238, "
          "Klangio 0.5828 / 0.6675")

    # ---- Export, to a NEW asset. The shipped one is not touched. --------------------
    arrays = [w.astype(np.float32) for w in model.get_weights()]
    np.savez("weights_live_3c_settled.npz", *arrays,
             mean=mean.astype(np.float32), std=std.astype(np.float32))
    with open("live_3c_settled_threshold.json", "w") as handle:
        json.dump({
            "note": "E18-R32 two-tier 3-class live model (ADR 0552/0554): Klangio + "
                    "GuitarSet, trained on BOTH the 70 ms and the untruncated window so one "
                    "asset serves both tiers. Threshold = P(no-strum) quantile keeping "
                    ">=95% of TRUE strums on the held-out VAL GROUPS (ADR 0549's rule). "
                    "NOT yet wired: assets/ml/strum_crnn_live_3c.bin is unchanged.",
            "seed": seed, "retention_target": H.REJECT_RETENTION,
            "gates": {label: {"no_strum_threshold": thr,
                              "true_strum_retention": ret,
                              "false_onset_rejection": rej}
                      for label, (thr, ret, rej) in gates.items()},
            "no_strum_threshold": gates["class_conditional"][0],
            "shipped_gate_rule": "class_conditional",
            "gate_rule_note": "ADR 0549's class-blind rule is textbook Chow (1970), whose "
                              "threshold carries no class index because it assumes "
                              "symmetric costs. Measured here that fails: upstrokes carry "
                              "up to 5x the median P(no-strum), so the class-blind budget "
                              "silences them 1.3-2.8x more often. The shipped threshold is "
                              "the max of the per-class 95% quantiles - Mondrian / "
                              "label-conditional conformal prediction (Vovk et al. 2003), "
                              "exact in finite samples because the classes are a finite "
                              "partition (Barber et al. 2021). Fumera, Roli & Giacinto "
                              "(2000) showed per-class reject thresholds Pareto-dominate "
                              "single-threshold Chow.",
            "held_out": report,
        }, handle, indent=2)
    loaded = np.load("weights_live_3c_settled.npz")
    pairs = list(zip(NAMES, [loaded[f"arr_{i}"] for i in range(len(NAMES))]))
    pairs += [("mean", loaded["mean"]), ("std", loaded["std"])]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_bin = os.path.join(root, "assets", "ml", "strum_crnn_live_3c_settled.bin")
    write_bin(out_bin, pairs)
    print(f"\nwrote {out_bin} ({os.path.getsize(out_bin)} bytes)")

    # ---- Parity fixture: the Dart side must reproduce these rows to <=1e-3 ----------
    rng_fix = np.random.default_rng(seed)
    pick = rng_fix.choice(len(X), size=min(N_FIXTURE, len(X)), replace=False)
    fixture = {
        "note": "E18-R32. Rows are (15, 128) normalised windows and the 3-column softmax "
                "from strum_crnn_live_3c_settled.bin. Dart must match within 1e-3.",
        "no_strum_threshold": threshold,
        # RAW windows, never `Xn`: the Dart `CrnnStrumNet.forward` standardises
        # internally with the mean/std it parses out of the asset, so a normalised row
        # gets standardised TWICE and the parity can never hold. E18-R32 shipped `Xn`
        # here and nothing noticed for eleven rounds, because the round that wrote the
        # fixture wrote no test to read it (ADR 0568, LESSONS L683).
        "cases": [
            {"window": X[i].astype(np.float32).tolist(),
             "expected": model.predict(Xn[i:i + 1], verbose=0)[0].astype(float).tolist(),
             "label": int(y[i])}
            for i in pick
        ],
    }
    fixture_path = os.path.join(root, "test", "fixtures",
                                "crnn_live_3c_settled_parity.json")
    with open(fixture_path, "w") as handle:
        json.dump(fixture, handle)
    print(f"wrote {fixture_path} ({len(fixture['cases'])} cases)")


if __name__ == "__main__":
    arg = next((a for a in sys.argv[1:] if a.startswith("--seed=")), None)
    main(int(arg.split("=")[1]) if arg else SEED)
