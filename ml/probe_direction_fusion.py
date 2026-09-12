# -*- coding: utf-8 -*-
"""Does fusing the METRIC channel with the ACOUSTIC one actually help -- and what does
it COST on the strokes that break the pendulum?

ADR 0557 measured the two channels separately (metric held-out AUC 0.9797, acoustic
0.7484) and explicitly did NOT claim a combined number: two AUCs do not compose. This
probe supplies the combined number, and more importantly the one that decides whether
the idea is admissible at all.

The danger is not that fusion fails to help. It is that fusion helps ON AVERAGE by
being wrong exactly where it matters. A stroke that VIOLATES the pendulum -- an upstroke
away from the sixteenth offbeat -- is the learner mistake the app exists to catch, and on
those strokes the metric channel is wrong BY DEFINITION. If the fused arrow overrides a
correct acoustic call there, the app tells a learner they played the stroke they were
supposed to play. That is the forbidden false teaching (ADR 0557 D4), and a macro-F1
averaged over all strokes cannot see it, because the violations are 4 % of the corpus.
So every rule here is scored THREE times: all strokes, pendulum-obeying, pendulum-
violating. This is the L670 discipline -- instrument the axis the failure mode moves the
cost onto, not only the axis you meant to improve.

Three decision rules, all on the SAME held-out GuitarSet split (unseen player AND
unseen tune) and the same model:

  C  acoustic only                      the shipped behaviour, the baseline
  A  full fusion                        posterior proportional to P_ac * P_met
  B  metric breaks ties only            acoustic decides when its margin clears t,
                                        the metric call decides below t

The metric channel's probability is NOT fitted from the corpus (ADR 0557 D3: the map is
the lesson's notation, not a corpus table). It is one swept scalar, `lam` -- the
confidence the prescribed grid is given -- so the whole curve is reported rather than a
silently chosen operating point. lam = 0.5 IS rule C, which makes the baseline a point on
the same curve instead of a separate code path.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_fusion.py

Needs TensorFlow (it runs the trained model) and `ml/weights_live_3c_settled.npz`.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

import guitarset as G
import probe_direction_metric as M
from probe_direction_headroom import clean_sweeps
from train_live_3c_settled import DOWN, NO_STRUM, UP, f1

WEIGHTS = "weights_live_3c_settled.npz"
THRESHOLD_JSON = "live_3c_settled_threshold.json"

# A stroke counts as pendulum-OBEYING when the prescribed grid's call matches the truth.
# The tolerance is the half-width of the "this is a sixteenth offbeat" band, in beats;
# 0.09375 = 1.5/16 of a beat = 47 ms at 120 bpm, the middle row of ADR 0557 D5.
TOLERANCE = 0.09375


def aligned_onsets(cache: str = G.CACHE):
    """The onset time of every row in `guitarset.build`'s cache, in the same order.

    `build` is deterministic -- `takes()` order, then `clean_sweeps()` order -- so the
    times can be replayed from the annotation alone, with no audio read. Replaying is only
    safe if it demonstrably lands on the same rows, so BOTH the count and the full
    (player, tune) sequence are asserted against the cache. A future change to either
    loop then fails loudly here instead of silently pairing a stroke with another
    stroke's phase.
    """
    data = np.load(os.path.join(os.path.dirname(__file__), cache))
    times, players, tunes = [], [], []
    for _wav, jams_path, player, tune in G.takes(G.root()):
        with open(jams_path, encoding="utf-8") as handle:
            for sweep in clean_sweeps(json.load(handle)):
                times.append(sweep["at"])
                players.append(player)
                tunes.append(tune)
    replayed = list(zip(players, tunes))
    cached = list(zip(data["player"].tolist(), data["tune"].tolist()))
    if len(replayed) != len(cached) or replayed != cached:
        sys.exit("onset replay does not align with %s -- refusing to pair phases with "
                 "windows (replayed %d rows, cache has %d)"
                 % (cache, len(replayed), len(cached)))
    return (np.array(times), data["y"], data["player"], data["tune"])


def phase_of(base_dir: str):
    """(player, tune) -> (beat times array), for the beat grid of every strummed take."""
    grids = {}
    for _wav, jams_path, player, tune in G.takes(base_dir):
        with open(jams_path, encoding="utf-8") as handle:
            beats = M.beats_of(json.load(handle))
        if len(beats) >= 4:
            grids[(player, tune)] = np.array([b[0] for b in beats])
    return grids


def metric_call(times, players, tunes, grids):
    """The prescribed grid's direction call per row: UP, DOWN, or -1 when the metric
    channel is UNAVAILABLE (no beat grid, or the onset sits outside it). Unavailable is a
    real state, not a missing value to impute -- in free play without a metronome the app
    is in exactly this state for every stroke."""
    calls = np.full(len(times), -1, dtype=np.int64)
    offsets = np.full(len(times), np.nan)
    for i, (at, player, tune) in enumerate(zip(times, players, tunes)):
        grid = grids.get((player, tune))
        if grid is None:
            continue
        k = int(np.searchsorted(grid, at, side="right")) - 1
        if k < 0 or k + 1 >= len(grid):
            continue
        period = grid[k + 1] - grid[k]
        if period <= 0:
            continue
        phase = (at - grid[k]) / period
        distance = abs((phase % 0.5) - 0.25)
        offsets[i] = distance
        calls[i] = UP if distance <= TOLERANCE else DOWN
    return calls, offsets


def load_model():
    import tensorflow as tf  # noqa: F401  (imported for its side effect on Keras)
    from train import build_model

    path = os.path.join(os.path.dirname(__file__), WEIGHTS)
    loaded = np.load(path)
    arrays = [loaded[k] for k in sorted(
        (k for k in loaded.files if k.startswith("arr_")),
        key=lambda k: int(k.split("_")[1]))]
    model = build_model(15, 128, n_classes=3)
    model.set_weights(arrays)
    return model, loaded["mean"], loaded["std"]


def decide(probs, metric, lam, margin_gate, threshold):
    """One decision rule, as a vector of calls (DOWN / UP / -1 = suppressed).

    `lam` is the confidence given to the prescribed grid (0.5 = none, so the rule reduces
    to acoustic-only). `margin_gate` None means full fusion (rule A); a number means the
    metric call is consulted ONLY when the acoustic margin falls below it (rule B).

    A suppressed stroke stays suppressed either way: the metric channel says which
    direction a stroke would have, never whether a stroke happened. Letting it resurrect a
    suppressed onset would be the metric channel deciding EXISTENCE from the answer key.
    """
    suppressed = probs[:, NO_STRUM] > threshold
    total = probs[:, DOWN] + probs[:, UP]
    total = np.where(total > 0, total, 1.0)
    p_up = probs[:, UP] / total
    fused = p_up.copy()
    consult = metric >= 0
    if margin_gate is not None:
        consult = consult & (np.abs(2 * p_up - 1) < margin_gate)
    prior_up = np.where(metric == UP, lam, 1.0 - lam)
    # Naive-Bayes odds update against a flat prior; the acoustic channel's window is
    # onset-relative and never sees the grid, so the two channels are independent by
    # construction rather than by assumption (ADR 0557 D1).
    odds = (p_up / np.clip(1 - p_up, 1e-9, None)) * (prior_up / (1 - prior_up))
    fused = np.where(consult, odds / (1 + odds), p_up)
    called = np.where(fused > 0.5, UP, DOWN)
    return np.where(suppressed, -1, called)


def report(name, called, truth, obeying):
    down, up = f1(truth, called, DOWN), f1(truth, called, UP)
    macro = (down + up) / 2
    rows = [("all", np.ones(len(truth), dtype=bool)),
            ("obeying", obeying), ("violating", ~obeying)]
    accuracy = []
    for _, mask in rows:
        if mask.sum() == 0:
            accuracy.append(float("nan"))
            continue
        accuracy.append(float((called[mask] == truth[mask]).mean()))
    print("  %-34s %.4f  %.4f  %.4f   %.4f   %.4f   %.4f  (n viol %d)"
          % (name, macro, down, up, accuracy[0], accuracy[1], accuracy[2],
             int((~obeying).sum())))
    return macro, accuracy


def main():
    if not os.environ.get("GUITARSET_DIR"):
        sys.exit("set GUITARSET_DIR")
    times, y, player, tune = aligned_onsets()
    grids = phase_of(G.root())
    calls, _offsets = metric_call(times, player, tune, grids)
    _train_mask, test_mask = G.split_masks(player, tune)

    with open(os.path.join(os.path.dirname(__file__), THRESHOLD_JSON)) as handle:
        threshold = json.load(handle)["no_strum_threshold"]
    model, mean, std = load_model()

    print("held-out GuitarSet: unseen player AND unseen tune")
    print("rows %d of %d   metric channel available on %d (%.1f%%)"
          % (int(test_mask.sum()), len(y), int((calls[test_mask] >= 0).sum()),
             100.0 * (calls[test_mask] >= 0).mean()))
    print("no-strum gate %.6f (class-conditional, ADR 0555)\n" % threshold)

    for tier, cache in (("70 ms", "guitarset_live70.npz"),
                        ("238 ms", "guitarset_live_full.npz")):
        data = np.load(os.path.join(os.path.dirname(__file__), cache))
        X = ((data["X"] - mean) / std)[test_mask]
        truth = y[test_mask]
        metric = calls[test_mask]
        probs = model.predict(X, batch_size=256, verbose=0)
        obeying = (metric == truth) | (metric < 0)

        print("=== tier %s ===  (obeying %d / violating %d of %d)"
              % (tier, int(obeying.sum()), int((~obeying).sum()), len(truth)))
        print("  %-34s %-6s  %-6s  %-6s   %-6s   %-6s   %-6s"
              % ("rule", "macro", "downF1", "upF1", "accAll", "accObey", "accViol"))
        base_macro, base_acc = report("C  acoustic only", decide(
            probs, metric, 0.5, None, threshold), truth, obeying)

        for lam in (0.60, 0.70, 0.80, 0.90, 0.95, 0.99):
            report("A  full fusion       lam=%.2f" % lam, decide(
                probs, metric, lam, None, threshold), truth, obeying)

        for gate in (0.30, 0.60, 0.90):
            for lam in (0.90, 0.99):
                report("B  ties only  m<%.2f lam=%.2f" % (gate, lam), decide(
                    probs, metric, lam, gate, threshold), truth, obeying)

        print("  baseline macro %.4f, violating-subset accuracy %.4f -- every row above"
              % (base_macro, base_acc[2]))
        print("  must be read against BOTH, not the macro alone.")
        breakeven(probs, metric, truth, obeying, threshold, base_acc)
        print()


def breakeven(probs, metric, truth, obeying, threshold, base_acc):
    """The number that actually decides the product question.

    Every `accAll` above is inflated by THIS corpus's pendulum compliance: 98 % of the
    held-out strokes obey, so a rule that trusts the grid is largely being asked to predict
    the grid from the grid. A learner complies LESS. Their expected accuracy is

        acc(c) = c * accObey + (1 - c) * accViol

    which is a straight line in compliance c, so each rule crosses the acoustic-only
    baseline at one point. That crossing -- not the headline -- is what says whether the
    rule is safe to ship.

    Heavy caveat, and it is the ADR 0557 D5 finding turned on itself: the violating subset
    here is ELEVEN strokes, so every accViol is a multiple of 1/11 and the crossings carry
    wide uncertainty. The corpus cannot measure the harm because the corpus does not
    contain the error class. That is a reason to bound the decision, not to skip it.
    """
    print("\n  compliance break-even (acc = c*accObey + (1-c)*accViol, c = how often the")
    print("  learner obeys the pendulum). Baseline acoustic-only: obey %.4f viol %.4f."
          % (base_acc[1], base_acc[2]))
    print("  %-34s %-9s  %s" % ("rule", "break-even", "expected accuracy at compliance"))
    print("  %-34s %-9s  %s" % ("", "c*", "0.95    0.80    0.60    0.40"))
    base_slope = base_acc[1] - base_acc[2]
    for name, called in (
        ("A  full fusion       lam=0.99",
         decide(probs, metric, 0.99, None, threshold)),
        ("A  full fusion       lam=0.90",
         decide(probs, metric, 0.90, None, threshold)),
        ("B  ties only  m<0.30 lam=0.99",
         decide(probs, metric, 0.99, 0.30, threshold)),
    ):
        obey = float((called[obeying] == truth[obeying]).mean())
        viol = float((called[~obeying] == truth[~obeying]).mean())
        slope = obey - viol
        denominator = slope - base_slope
        star = ((base_acc[2] - viol) / denominator) if abs(denominator) > 1e-9 else np.nan
        cells = "  ".join("%.4f" % (c * obey + (1 - c) * viol)
                          for c in (0.95, 0.80, 0.60, 0.40))
        star_text = "never" if not (0.0 <= star <= 1.0) else "%.3f" % star
        print("  %-34s %-9s  %s" % (name, star_text, cells))
    print("  c* is where the rule stops beating acoustic-only. Below it, trusting the")
    print("  grid costs the learner more than the weak acoustic call does.")


if __name__ == "__main__":
    main()
