# -*- coding: utf-8 -*-
"""Is the SETTLED tier worth its CPU, with no grid and no fusion involved?

ADR 0562 closed the fusion: the metric channel cannot reach the scoring path without
making the grader compare the grid to itself. The two-TIER decision survives that
untouched, because it is purely acoustic -- the same model, the same window, just more
audio arrived (ADR 0552/0554). This probe measures whether lighting it is worth the
second forward pass `StrumAnalyzer.settledTier` currently refuses to spend (ADR 0559 D3).

The design under test is ADR 0556 D3, which is the only arrangement that does not grade
a learner against something they never saw:

  * fast call with an ADEQUATE margin -> the arrow shows that direction, and the grader
    must use the SAME one, or the arrow lied;
  * fast call with a SHORT margin     -> the arrow shows a direction-NEUTRAL stroke mark,
    and the grader uses the SETTLED direction, because the learner was shown no claim to
    contradict.

Two things fall out that change the cost calculus in ADR 0559:

  1. Only the SHORT-margin strokes need a second forward. The cost is not "double", it is
     "double on that fraction", and the fraction is measured here.
  2. The UX price is the fraction of strokes whose arrow shows no direction at all. That is
     a real cost to a learner and is reported on every row, not buried.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_settled_tier_value.py

Needs TensorFlow and `ml/weights_live_3c_settled.npz`.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

import guitarset as G
from probe_direction_fusion import aligned_onsets, load_model
from train_live_3c_settled import DOWN, NO_STRUM, UP, f1

THRESHOLD_JSON = "live_3c_settled_threshold.json"

#: `LiveCrnnStrumClassifier.noStrumThreshold` -- what the SHIPPED asset gates at.
SHIPPED_GATE = 0.85


def pick_corpus(argv):
    """(truth, mask, label, cache70, cache_full) for the requested corpus.

    `--corpus=klangio` exists because ADR 0569 showed GuitarSet and Klangio can disagree in
    SIGN about a change, and Klangio is the deployment condition (phone mic). The Klangio
    corpus audio is not on this machine, so this is an ORACLE-window measurement — which
    ADR 0571 D4 corroborated for exactly this kind of question: the settled tier's DELTA
    agreed within 0.024 between the oracle and in-situ instruments, while the LEVELS
    differed by ~0.05.

    `--fold=` picks which Klangio rows: `eval` (default) is `split_by_recording`'s held-out
    fold, which is the SHIPPED asset's own clean fold; `guitarist4` is the settled asset's.
    A within-model fast-vs-settled delta is far more robust to contamination than a
    between-model comparison -- the exposure moves both columns -- but the clean fold is
    still the one to report.
    """
    which = next((a.split("=", 1)[1] for a in argv if a.startswith("--corpus=")),
                 "guitarset")
    if which == "guitarset":
        # Only the GuitarSet path replays the annotation, so only it needs the corpus.
        if not os.environ.get("GUITARSET_DIR"):
            sys.exit("set GUITARSET_DIR (or pass --corpus=klangio, which reads caches)")
        _times, y, player, tune = aligned_onsets()
        _train, test = G.split_masks(player, tune)
        return (y, test, "GuitarSet (unseen player AND tune)",
                "guitarset_live70.npz", "guitarset_live_full.npz")
    if which != "klangio":
        sys.exit("--corpus must be guitarset or klangio")

    import klangio as K

    here = os.path.dirname(__file__)
    fast = np.load(os.path.join(here, "klangio_live70.npz"))
    full = np.load(os.path.join(here, "klangio_live_full.npz"))
    # The zip below is an assumption -- same row, same stroke, two truncations -- and it is
    # CHECKED, because a silent misalignment would compare one stroke's fast call with
    # another's settled one and still print a plausible table.
    if not ((fast["y"] == full["y"]).all() and (fast["rec"] == full["rec"]).all()):
        sys.exit("the two Klangio truncation caches are NOT row-aligned")
    fold = next((a.split("=", 1)[1] for a in argv if a.startswith("--fold=")), "eval")
    if fold == "eval":
        _train, mask = K.split_by_recording(fast["rec"])
        label = "Klangio (split_by_recording eval fold -- the SHIPPED asset's own)"
    elif fold == "guitarist4":
        mask = np.array([K.guitarist_of(r) for r in fast["rec"]]) == "4"
        label = "Klangio (guitarist 4 -- the SETTLED asset's held-out)"
    else:
        sys.exit("--fold must be eval or guitarist4")
    return (fast["y"], mask, label,
            "klangio_live70.npz", "klangio_live_full.npz")


def pick_model(argv):
    """(model, mean, std, gate, label) -- which asset is under test, and at which gate.

    Default reproduces ADR 0563 exactly: the settled weights and their class-conditional
    gate. `--asset=PATH [--gate=X]` measures an SSML `.bin` instead, which is what ADR 0569
    made possible and necessary: the two-tier decision was only ever measured on the
    SETTLED asset, and that asset is not shippable (it regresses on Klangio, the deployment
    corpus). A decision about the shipped path has to be measured on the shipped asset.
    """
    asset = next((a.split("=", 1)[1] for a in argv if a.startswith("--asset=")), None)
    gate_arg = next((a.split("=", 1)[1] for a in argv if a.startswith("--gate=")), None)
    if asset is None:
        model, mean, std = load_model()
        with open(os.path.join(os.path.dirname(__file__), THRESHOLD_JSON)) as handle:
            gate = json.load(handle)["no_strum_threshold"]
        return model, mean, std, gate, "weights_live_3c_settled.npz (ADR 0563 default)"
    from read_ssml import load_keras

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = asset if os.path.isabs(asset) else os.path.join(root, asset)
    model, mean, std = load_keras(path)
    gate = float(gate_arg) if gate_arg else SHIPPED_GATE
    return model, mean, std, gate, f"{asset} @ gate {gate}"


def direction_probs(probs):
    """P(up) renormalised over the down/up mass, as the shipped Dart path does."""
    total = probs[:, DOWN] + probs[:, UP]
    total = np.where(total > 0, total, 1.0)
    return probs[:, UP] / total


def score(called, truth):
    down, up = f1(truth, called, DOWN), f1(truth, called, UP)
    return (down + up) / 2, down, up


def main():
    y, test_mask, corpus_label, cache_fast, cache_full = pick_corpus(sys.argv[1:])
    model, mean, std, threshold, asset_label = pick_model(sys.argv[1:])
    print(f"ASSET UNDER TEST: {asset_label}")
    print(f"CORPUS:           {corpus_label}")
    print("  (a table that does not say which asset it measured looks comparable with one")
    print("   it is not -- ADR 0569, LESSONS L682 §1)")

    truth = y[test_mask]
    tiers = {}
    for tier, cache in (("fast", cache_fast), ("settled", cache_full)):
        data = np.load(os.path.join(os.path.dirname(__file__), cache))
        X = ((data["X"] - mean) / std)[test_mask]
        tiers[tier] = model.predict(X, batch_size=256, verbose=0)

    fast, settled = tiers["fast"], tiers["settled"]
    p_up_fast = direction_probs(fast)
    margin = np.abs(2 * p_up_fast - 1)
    # The no-strum gate is the FAST tier's decision: existence is settled at the live
    # deadline and the settled tier never revises it (ADR 0559 D2).
    suppressed = fast[:, NO_STRUM] > threshold

    def called_from(probs):
        return np.where(suppressed, -1, probs[:, :2].argmax(axis=1))

    print("%d strokes, %.0f%% up" % (len(truth), 100 * float((truth == UP).mean())))
    print("no-strum gate %.6f; a suppressed stroke is" % threshold)
    print("counted as an error either way, so the tiers are compared on equal terms.\n")

    fast_macro = score(called_from(fast), truth)
    settled_macro = score(called_from(settled), truth)
    print("  tier                       macro   downF1  upF1    neutral arrows  2nd fwd")
    print("  fast only (ships today)    %.4f  %.4f  %.4f       0.0%%          0.0%%"
          % fast_macro)
    print("  settled only              %.4f  %.4f  %.4f     100.0%%        100.0%%"
          % settled_macro)
    print("    (settled-only is NOT a shippable row: every arrow would wait ~238 ms,")
    print("     which ADR 0556 D1 rejects on measured revision cost.)\n")

    print("  ADR 0556 D3 hybrid: fast above the margin, settled below it")
    print("  margin t    macro   downF1  upF1    neutral arrows  2nd forwards  vs fast")
    for t in (0.0, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9, 0.99, 1.01):
        short = margin < t
        mixed = np.where(short[:, None], settled, fast)
        macro, down, up = score(called_from(mixed), truth)
        print("   %5.2f     %.4f  %.4f  %.4f      %5.1f%%        %5.1f%%     %+.4f"
              % (t, macro, down, up, 100 * short.mean(), 100 * short.mean(),
                 macro - fast_macro[0]))
    print("  t = 0 is fast-only, t > 1 is settled-only: the baseline and the ceiling are")
    print("  points on this curve, not separate code paths.")

    print("\n  where the gain actually sits")
    for t in (0.3, 0.9):
        short = margin < t
        if short.sum() == 0 or (~short).sum() == 0:
            continue
        for name, mask in (("short margin", short), ("adequate margin", ~short)):
            f_acc = float((called_from(fast)[mask] == truth[mask]).mean())
            s_acc = float((called_from(settled)[mask] == truth[mask]).mean())
            print("   t=%.2f  %-16s n=%4d   fast acc %.4f -> settled %.4f  (%+.4f)"
                  % (t, name, int(mask.sum()), f_acc, s_acc, s_acc - f_acc))
    print("  If the settled tier does not beat the fast one ON THE SHORT-MARGIN strokes,")
    print("  the hybrid cannot help however the threshold is set -- that subset is the")
    print("  only place it is consulted.")

    print("\n  the margin's own quality: does a low margin mean a likely error?")
    print("  (if not, the margin is the wrong thing to route on -- L672 section 2)")
    order = np.argsort(margin)
    correct = called_from(fast) == truth
    for lo, hi in ((0.0, 0.2), (0.2, 0.4), (0.4, 0.6), (0.6, 0.8), (0.8, 1.0)):
        band = (margin >= lo) & (margin < hi if hi < 1.0 else margin <= 1.0)
        if band.sum() == 0:
            continue
        print("    margin %.1f-%.1f  n=%4d  fast accuracy %.4f"
              % (lo, hi, int(band.sum()), float(correct[band].mean())))
    _ = order


if __name__ == "__main__":
    main()
