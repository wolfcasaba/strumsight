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


def direction_probs(probs):
    """P(up) renormalised over the down/up mass, as the shipped Dart path does."""
    total = probs[:, DOWN] + probs[:, UP]
    total = np.where(total > 0, total, 1.0)
    return probs[:, UP] / total


def score(called, truth):
    down, up = f1(truth, called, DOWN), f1(truth, called, UP)
    return (down + up) / 2, down, up


def main():
    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")

    _times, y, player, tune = aligned_onsets()
    _train_mask, test_mask = G.split_masks(player, tune)
    with open(os.path.join(os.path.dirname(__file__), THRESHOLD_JSON)) as handle:
        threshold = json.load(handle)["no_strum_threshold"]
    model, mean, std = load_model()

    truth = y[test_mask]
    tiers = {}
    for tier, cache in (("fast", "guitarset_live70.npz"),
                        ("settled", "guitarset_live_full.npz")):
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

    print("held-out GuitarSet: unseen player AND unseen tune, %d strokes" % len(truth))
    print("no-strum gate %.6f (class-conditional, ADR 0555); a suppressed stroke is"
          % threshold)
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
