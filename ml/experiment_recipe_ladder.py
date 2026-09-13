"""E18-R44 - the recipe LADDER: the shipped recipe and the settled recipe differ in SIX
ways, and the arc has been reasoning about two of them.

ADR 0569 D2 measured that the settled asset loses on Klangio - the deployment corpus - and
listed the candidate mechanisms as "the guitarist-disjoint split being harder, the GuitarSet
data's dominant effect, the two corpora's mic character, or capacity". Reading the two
training scripts against each other, that list is incomplete. `train_live_3c.py` and
`train_live_3c_settled.py` differ in:

  1. CORPORA         Klangio only               vs  Klangio + GuitarSet
  2. TRUNCATIONS     70 ms only                 vs  70 ms AND untruncated
  3. REGULARISATION  none (dropout=0, l2=0)     vs  AUG_REG (dropout .25 / rec .15 / l2 1e-4)
  4. FIT SCHEDULE    val_accuracy, 40 ep, bs32  vs  val_loss, 60 ep, bs64
  5. SPLIT           random 20 % of recordings  vs  guitarist '4' + GuitarSet player x tune
  6. VAL PROTOCOL    the eval fold IS the early-stop AND gate-calibration fold
                                                vs  group-wise 20 % out of TRAIN only

Only (1) and (2) were ever named as the difference. (3) in particular is the kind of change
that trades in-domain accuracy for generalisation in either direction, and it was never on
the list.

## What this measures

Five arms, each ONE factor away from the one before, all under the SETTLED split, one
instrument, one scorer, one gate rule:

  R0  Klangio, 70 ms, no reg, acc/40/32   <- the shipped RECIPE on the settled split
  R1  + the fit schedule                   (loss/60/64)
  R2  + regularisation                     (AUG_REG)
  R3  + GuitarSet
  R4  + the second truncation              <- the settled RECIPE

Held FIXED so they are not hidden factors: the split, the val protocol (group-wise, out of
TRAIN), normalisation stats and class weights from the fit fold only, the gate rule
(class-blind - ADR 0549's, what ships), the scorer (`train_live_3c_settled.score_direction`,
so a suppressed strum is no call and not a wrong call), and the eval cells.

(5) and (6) CANNOT be varied in this ladder: holding the settled split is what makes a clean
Klangio held-out fold exist at all, and the shipped protocol's eval fold is simultaneously
its early-stop and gate-calibration fold, so reproducing it would destroy the held-out cell.
Those two stay a stated difference, not a measured one.

## The bar

The shipped asset is measured on the SAME cells through `read_ssml.load_keras`, and its fold
bias is stated per row (ADR 0569 D4): it trained on most of guitarist 4's recordings, so on
the Klangio cell the SHIPPED asset is the advantaged one - an arm that matches it there has
cleared a hostile bar. It never saw GuitarSet at all, so that cell is pure OOD for it.

    GUITARSET_DIR=... python ml/experiment_recipe_ladder.py [--seed=42] [--arms=R0,R4]

Writes nothing to assets/. Prints the table; dumps JSON next to itself for the ADR.
"""
from __future__ import annotations

import gc
import json
import os
import sys
import time

import numpy as np

import guitarset as G
import honest_eval as H
import klangio as K
from read_ssml import load_keras
from train import build_model, set_seeds
from train_live_3c_settled import KLANGIO_TEST_GUITARIST, SETTLED_DEADLINE, score_direction

DOWN, UP, NO_STRUM = 0, 1, 2
SHIPPED_BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "assets", "ml", "strum_crnn_live_3c.bin")
SHIPPED_CALIBRATED_GATE = 0.4387717843055725  # live_3c_threshold.json, class-blind
SHIPPED_PRODUCTION_GATE = 0.85                # what LiveCrnnStrumClassifier hard-codes
COMMON_GATES = (0.439, 0.650, 0.850)
MARGIN_BANDS = ((0.0, 0.1), (0.1, 0.2), (0.2, 0.3), (0.3, 0.5), (0.5, 1.0))

# name -> (corpora, truncations, reg, monitor, epochs, batch, one-line what-changed)
ARMS = {
    # Descriptions name the RECIPE only. The split is a property of --data, printed once at
    # the top, so an arm label stays true in both modes.
    "R0": (("klangio",), ("70",), {}, "val_accuracy", 40, 32,
           "the SHIPPED recipe (no reg, val_accuracy/40/bs32)"),
    "R1": (("klangio",), ("70",), {}, "val_loss", 60, 64,
           "+ the fit schedule (val_loss / 60 ep / bs64)"),
    "R2": (("klangio",), ("70",), H.AUG_REG, "val_loss", 60, 64,
           "+ regularisation (dropout .25 / rec .15 / l2 1e-4)"),
    "R3": (("klangio", "guitarset"), ("70",), H.AUG_REG, "val_loss", 60, 64,
           "+ GuitarSet"),
    "R4": (("klangio", "guitarset"), ("70", "full"), H.AUG_REG, "val_loss", 60, 64,
           "+ the second truncation = the SETTLED recipe"),
    # Added only if the ladder points at one step; kept here so the file records the design.
    "R5": (("klangio", "guitarset"), ("70", "full"), {}, "val_loss", 60, 64,
           "the settled recipe WITHOUT regularisation"),
    # The `allklangio` ladder's endpoint: every settled factor EXCEPT the GuitarSet data, so
    # it can be scored against the shipped asset on GuitarSet as a genuine third corpus.
    "R2T": (("klangio",), ("70", "full"), H.AUG_REG, "val_loss", 60, 64,
            "+ the second truncation, Klangio only (settled recipe minus GuitarSet)"),
}
LADDER = ("R0", "R1", "R2", "R3", "R4")
# The matched-data ladder: Klangio-only arms, so GuitarSet stays a third corpus for all of
# them AND for the shipped asset. R3/R4 cannot appear here - they would train on the corpus
# that is supposed to be unseen.
MATCHED = ("R0", "R1", "R2", "R2T")


# ---------------------------------------------------------------------------------------
# Data: both corpora at both truncations, loaded once, kept RAW (each arm has its own stats)
# ---------------------------------------------------------------------------------------
TRUNCATIONS = {
    "70": (H.LIVE_DEADLINE_S, "klangio_live70.npz", "live70",
           "guitarset_live70.npz", "live70"),
    "full": (SETTLED_DEADLINE, "klangio_live_full.npz", "live_full",
             "guitarset_live_full.npz", "live_full"),
}


def load_cells(mode="heldout"):
    """`mode` picks WHAT the held-out cells are, and that choice is the whole design.

    "heldout" (ADR 0575's ladder): Klangio guitarist '4' and GuitarSet players 03-05 x
        Funk3/Rock3 are held out. Lets the recipe factors be compared to each other under one
        split, but NOT to the shipped asset - every Klangio cell favours the shipped asset
        (same-player, ADR 0573 D1) and every GuitarSet cell favours an arm that trained on
        GuitarSet (ADR 0573 D6).

    "allklangio" (ADR 0576): nothing is held out of Klangio, and GuitarSet is not trained on
        at all, so ALL 3056 of its sweeps become a THIRD corpus - unseen by the arms AND
        unseen by the shipped asset, which trained on Klangio only. That is the one cell
        where the shipped ARTEFACT can be compared to a candidate fairly, and it also removes
        the confound ADR 0573 D4 had to declare: the arms now train on all three Klangio
        guitarists, exactly as the shipped asset did, so a difference on GuitarSet is the
        RECIPE and not the missing third of the player diversity. The price is that the
        Klangio cell stops being a held-out number for the arms - it is reported and labelled,
        never read as one.
    """
    cells = {}
    for trunc, (deadline, k_pos, k_neg, g_pos, g_neg) in TRUNCATIONS.items():
        px, py, prec = H.build_live(deadline_s=deadline, cache=k_pos)
        nx, nrec = H.build_negatives(k_neg)
        X = np.concatenate([px, nx]).astype(np.float32)
        y = np.concatenate([py, np.full(len(nx), NO_STRUM, dtype=py.dtype)])
        rec = np.concatenate([prec, nrec])
        held = np.array([K.guitarist_of(r) for r in rec]) == KLANGIO_TEST_GUITARIST
        if mode == "allklangio":
            # Everything trains; the cell is reported only to show it is NOT held out.
            k_train, k_test = np.ones(len(y), bool), held
        else:
            k_train, k_test = ~held, held
        cells[("klangio", trunc)] = (X, y, np.array([f"k{r}" for r in rec]), k_train, k_test)

        px, py, pplayer, ptune = G.build(deadline_s=deadline, cache=g_pos)
        nx, nplayer, ntune = G.build_negatives(deadline, g_neg)
        X = np.concatenate([px, nx]).astype(np.float32)
        y = np.concatenate([py, np.full(len(nx), NO_STRUM, dtype=py.dtype)])
        player = np.concatenate([pplayer, nplayer])
        tune = np.concatenate([ptune, ntune])
        train, test = G.split_masks(player, tune)
        if mode == "allklangio":
            # Never trained on, so ALL of it is the third corpus - including the 1471
            # positives in the crossed player x tune combinations that `split_masks` leaves
            # unused, which no arm and no shipped asset has ever seen.
            train, test = np.zeros(len(y), bool), np.ones(len(y), bool)
        groups = np.array([f"g{p}_{t}" for p, t in zip(player, tune)])
        cells[("guitarset", trunc)] = (X, y, groups, train, test)
        for corpus in ("klangio", "guitarset"):
            _, yy, _, tr, te = cells[(corpus, trunc)]
            print(f"  {corpus:<9} {trunc:>4}: train {int(tr.sum()):5d} / "
                  f"held-out {int(te.sum()):5d}  "
                  f"({int((yy[te] < NO_STRUM).sum())} true strums)", flush=True)
        if mode == "allklangio":
            # The fairness of the GuitarSet cell IS this mask, so assert it rather than
            # trusting the print above: one GuitarSet row in training and the cell stops
            # being a third corpus, silently, and the comparison it exists to make becomes
            # the very thing ADR 0573 D6 rejected.
            _, _, _, g_tr, g_te = cells[("guitarset", trunc)]
            _, _, _, k_tr, _ = cells[("klangio", trunc)]
            assert not g_tr.any(), f"{trunc}: GuitarSet must not be trained on in this mode"
            assert g_te.all(), f"{trunc}: all of GuitarSet must be in the held-out cell"
            assert k_tr.all(), f"{trunc}: all of Klangio must be trained on in this mode"
    return cells


def predict(model, mean, std, X, chunk=4096):
    out = []
    for lo in range(0, len(X), chunk):
        out.append(model.predict((X[lo:lo + chunk] - mean) / std, verbose=0))
    return np.concatenate(out) if out else np.zeros((0, 3), dtype=np.float32)


def margin_of(probs):
    """|P(up) - P(down)| after renormalising the pair -- the Dart `_settleBelowMargin`
    quantity (`(down - up).abs()`), identical to probe_settled_tier_value's
    `|2 * p_up - 1|`."""
    pair = probs[:, :2]
    total = pair.sum(axis=1, keepdims=True)
    total[total == 0] = 1.0
    pair = pair / total
    return np.abs(pair[:, UP] - pair[:, DOWN])


def margin_table(probs, truth, gate):
    """Does a SHORT margin mean a likely error? Criterion (c) of the spec."""
    margin = margin_of(probs)
    kept = probs[:, NO_STRUM] <= gate
    rows = []
    for lo, hi in MARGIN_BANDS:
        band = kept & (margin >= lo) & ((margin < hi) if hi < 1.0 else (margin <= 1.0))
        n = int(band.sum())
        acc = (float((probs[band, :2].argmax(axis=1) == truth[band]).mean())
               if n else float("nan"))
        rows.append({"lo": lo, "hi": hi, "n": n, "fast_accuracy": acc})
    return rows


def evaluate(model, mean, std, cells, gate_for, label):
    """Every cell, one scorer. `gate_for(trunc)` returns (gate, gate_label)."""
    result = {}
    for (corpus, trunc), (X, y, _, _, test) in cells.items():
        Xt, yt = X[test], y[test]
        probs = predict(model, mean, std, Xt)
        strums = yt < NO_STRUM
        p, truth = probs[strums], yt[strums]
        gate, gate_label = gate_for(trunc)
        down, up, macro, supp = score_direction(p, truth, gate)
        neg = probs[~strums]
        result[f"{corpus}|{trunc}"] = {
            "n_strums": int(strums.sum()), "gate": gate, "gate_label": gate_label,
            "macro_f1": macro, "down_f1": down, "up_f1": up,
            "retention": 1.0 - supp,
            "neg_rejection": (float((neg[:, NO_STRUM] >= gate).mean())
                              if len(neg) else float("nan")),
            "common_gates": {f"{g:.3f}": score_direction(p, truth, g)[2]
                             for g in COMMON_GATES},
            "margin_bands": margin_table(p, truth, gate),
        }
        print(f"    {label:<22} {corpus:<9} {trunc:>4}  gate {gate:.4f} ({gate_label:<11}) "
              f"macro {macro:.4f}  down {down:.4f}  up {up:.4f}  keep {1 - supp:.4f}",
              flush=True)
    return result


def run_arm(name, cells, seed):
    import tensorflow as tf

    corpora, truncs, reg, monitor, epochs, batch, what = ARMS[name]
    print(f"\n=== {name}: {what} ===", flush=True)
    print(f"    corpora {corpora}  truncations {truncs}  reg {reg or 'none'}  "
          f"{monitor} / {epochs} ep / bs{batch}", flush=True)
    set_seeds(seed)

    xs, ys, gs, ts = [], [], [], []
    for corpus in corpora:
        for trunc in truncs:
            X, y, groups, train, _ = cells[(corpus, trunc)]
            xs.append(X[train])
            ys.append(y[train])
            gs.append(groups[train])
            ts.append(np.full(int(train.sum()), trunc))
    X = np.concatenate(xs)
    y = np.concatenate(ys)
    groups = np.concatenate(gs)
    tier = np.concatenate(ts)
    del xs, ys, gs, ts
    counts = np.bincount(y, minlength=3)
    print(f"    pool {X.shape}: {counts[DOWN]} down / {counts[UP]} up / "
          f"{counts[NO_STRUM]} no-strum, {len(set(groups.tolist()))} groups", flush=True)

    rng = np.random.default_rng(seed)
    unique = np.array(sorted(set(groups.tolist())))
    rng.shuffle(unique)
    val_groups = set(unique[:max(1, round(len(unique) * 0.2))].tolist())
    val = np.array([g in val_groups for g in groups])
    fit = ~val
    mean = X[fit].mean(axis=(0, 1))
    std = X[fit].std(axis=(0, 1)) + 1e-6
    Xn = ((X - mean) / std).astype(np.float32)
    fit_counts = np.bincount(y[fit], minlength=3).astype(float)
    fit_counts[fit_counts == 0] = 1.0
    weights = {c: float(fit_counts.sum() / (3 * fit_counts[c])) for c in range(3)}

    model = build_model(X.shape[1], X.shape[2], n_classes=3, **reg)
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    started = time.time()
    history = model.fit(
        Xn[fit], y[fit], epochs=epochs, batch_size=batch, shuffle=True,
        class_weight=weights, verbose=2, validation_data=(Xn[val], y[val]),
        callbacks=[tf.keras.callbacks.EarlyStopping(
            monitor=monitor, patience=8, restore_best_weights=True)])
    trained_epochs = len(history.history["loss"])
    print(f"    fit: {trained_epochs} epochs in {time.time() - started:.0f}s", flush=True)

    # ---- gate: ADR 0549's class-blind rule, PER TRUNCATION, from the val groups -------
    gates = {}
    for trunc in truncs:
        rows = val & (tier == trunc)
        pos = rows & (y < NO_STRUM)
        neg = rows & (y == NO_STRUM)
        p_pos = model.predict(Xn[pos], verbose=0)
        p_neg = model.predict(Xn[neg], verbose=0)
        thr, ret, rej = H._gate(p_pos[:, NO_STRUM], p_neg[:, NO_STRUM])
        gates[trunc] = thr
        print(f"    [gate {trunc:>4}] {thr:.6f} keeps {ret:.3f} of true strums, "
              f"rejects {rej:.3f} of false onsets (n={int(pos.sum())}/{int(neg.sum())})",
              flush=True)
    del Xn
    gc.collect()

    def gate_for(trunc):
        if trunc in gates:
            return gates[trunc], "own, blind"
        return gates[truncs[0]], "CROSS-TIER"

    cellwise = evaluate(model, mean, std, cells, gate_for, name)
    out = {"arm": name, "what_changed": what, "corpora": list(corpora),
           "truncations": list(truncs), "reg": reg, "monitor": monitor,
           "epochs_budget": epochs, "epochs_trained": trained_epochs, "batch": batch,
           "seed": seed, "gates": gates, "cells": cellwise}
    del model
    gc.collect()
    return out


def run_shipped(cells, mode="heldout"):
    print("\n=== SHIPPED asset (assets/ml/strum_crnn_live_3c.bin) ===", flush=True)
    if mode == "allklangio":
        print("    bias: NONE on the GuitarSet cell - neither it nor any arm here has seen "
              "that corpus,", flush=True)
        print("          and both trained on all three Klangio guitarists. This is the fair "
              "cell.", flush=True)
        print("          The Klangio cell is training data for the arms: ignore it.",
              flush=True)
    else:
        print("    bias: it trained on most of guitarist 4's recordings, so the Klangio cell "
              "FAVOURS it;", flush=True)
        print("          it never saw GuitarSet, so that cell is pure OOD for it.", flush=True)
    model, mean, std = load_keras(SHIPPED_BIN)
    out = {}
    for gate, label in ((SHIPPED_CALIBRATED_GATE, "own, blind"),
                        (SHIPPED_PRODUCTION_GATE, "production")):
        out[label] = evaluate(model, mean, std, cells,
                              lambda _t, g=gate, l=label: (g, l), f"shipped @{gate:.3f}")
    del model
    gc.collect()
    return out


def main():
    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")
    seed = 42
    mode = "heldout"
    arms = None
    for arg in sys.argv[1:]:
        if arg.startswith("--seed="):
            seed = int(arg.split("=", 1)[1])
        elif arg.startswith("--arms="):
            arms = [a.strip() for a in arg.split("=", 1)[1].split(",") if a.strip()]
        elif arg.startswith("--data="):
            mode = arg.split("=", 1)[1].strip()
    if mode not in ("heldout", "allklangio"):
        sys.exit(f"--data must be heldout or allklangio, not {mode!r}")
    if arms is None:
        arms = list(LADDER if mode == "heldout" else MATCHED)
    if mode == "allklangio":
        bad = [a for a in arms if "guitarset" in ARMS[a][0]]
        if bad:
            sys.exit(f"--data=allklangio needs Klangio-only arms; {bad} train on GuitarSet, "
                     "which is the corpus that has to stay unseen")
    print(f"E18-R44 recipe ladder, seed {seed}, data={mode}, arms {arms}")
    print("")
    if mode == "heldout":
        print("cells (the SETTLED split: Klangio guitarist '4' out, "
              "GuitarSet players 03-05 x Funk3/Rock3 out)")
    else:
        print("cells (MATCHED DATA: nothing held out of Klangio - so its cell is NOT a "
              "held-out number -\n       and ALL of GuitarSet is a THIRD corpus, unseen by "
              "the arms AND by the shipped asset)")
    cells = load_cells(mode)

    suffix = "" if mode == "heldout" else f"_{mode}"
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        f"recipe_ladder{suffix}_seed{seed}.json")
    # MERGE, never clobber. Running `--arms=R5` alone used to overwrite the file holding the
    # five-arm ladder, which would have destroyed the provenance record three seeds of
    # training produced. The filename carries the seed and the data mode, so merging can only
    # ever combine arms measured under identical conditions.
    report = {"seed": seed, "data_mode": mode, "arms": {}}
    if os.path.exists(path):
        with open(path) as handle:
            prior = json.load(handle)
        if prior.get("seed") == seed and prior.get("data_mode", "heldout") == mode:
            report["arms"] = prior.get("arms", {})
            print(f"  merging into {len(report['arms'])} existing arm(s) in {path}")
        else:
            sys.exit(f"{path} holds seed={prior.get('seed')} "
                     f"data_mode={prior.get('data_mode')}, refusing to merge")
    report["shipped"] = run_shipped(cells, mode)
    for name in arms:
        report["arms"][name] = run_arm(name, cells, seed)
        with open(path, "w") as handle:
            json.dump(report, handle, indent=2)
        print(f"    -> {path}", flush=True)

    # ---- the table ------------------------------------------------------------------
    print("")
    print("=== THE LADDER: direction macro-F1, each model at its OWN class-blind gate ===")
    print("  (the @70 column is decisive: the tier the arrow and the gate live in)")
    print("")
    print("  arm  what changed                                  "
          "Klangio@70  GSet@70   Klangio@full  GSet@full")
    # Every arm the FILE holds, in a canonical order, not only the ones this run measured —
    # so an accumulating file prints a complete table instead of a one-row fragment.
    order = [a for a in ARMS if a in report["arms"]]
    ship = report["shipped"]["own, blind"]
    note = ("   <- GSet cells are the FAIR ones here" if mode == "allklangio"
            else "   <- Klangio cell FAVOURS it")
    print(f"  {'SHIP':<4} {'the shipped asset (own gate 0.439)':<45} "
          f"{ship['klangio|70']['macro_f1']:.4f}      {ship['guitarset|70']['macro_f1']:.4f}"
          f"    {ship['klangio|full']['macro_f1']:.4f}        "
          f"{ship['guitarset|full']['macro_f1']:.4f}{note}")
    prod = report["shipped"]["production"]
    print(f"  {'':<4} {'the same asset at the PRODUCTION gate 0.85':<45} "
          f"{prod['klangio|70']['macro_f1']:.4f}      {prod['guitarset|70']['macro_f1']:.4f}"
          f"    {prod['klangio|full']['macro_f1']:.4f}        "
          f"{prod['guitarset|full']['macro_f1']:.4f}")
    for name in order:
        arm = report["arms"][name]
        c = arm["cells"]
        print(f"  {name:<4} {arm['what_changed']:<45} "
              f"{c['klangio|70']['macro_f1']:.4f}      {c['guitarset|70']['macro_f1']:.4f}"
              f"    {c['klangio|full']['macro_f1']:.4f}        "
              f"{c['guitarset|full']['macro_f1']:.4f}")
    print("")
    print("  a 'full' cell for an arm that trained at 70 ms only is CROSS-TIER "
          "(experiment_deadline_augmentation.py: that cell collapses) -- not a comparison.")
    if mode == "allklangio":
        print("  the Klangio cells above are TRAINING DATA for every arm -- not held-out "
              "numbers. Do not read them.")

    print("")
    read_cell = "klangio|70" if mode == "heldout" else "guitarset|70"
    label = ("the DEPLOYMENT corpus (Klangio @70)" if mode == "heldout"
             else "the THIRD corpus (GuitarSet @70) -- unseen by the arms AND by SHIP")
    print(f"=== step by step, on {label} ===")
    if mode == "allklangio":
        print(f"  SHIP  {ship[read_cell]['macro_f1']:.4f}   the shipped asset, same data, "
              f"same corpus unseen -- the bar, fairly")
    prev = None
    for name in order:
        value = report["arms"][name]["cells"][read_cell]["macro_f1"]
        delta = "" if prev is None else f"   {value - prev:+.4f}"
        print(f"  {name:<4}  {value:.4f}{delta}   {report['arms'][name]['what_changed']}")
        prev = value
    print("")
    print("wrote", f"recipe_ladder{suffix}_seed{seed}.json")


if __name__ == "__main__":
    main()
