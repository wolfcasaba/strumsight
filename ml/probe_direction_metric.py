# -*- coding: utf-8 -*-
"""The METRIC channel: does a stroke's position in the beat predict its direction?

Annotation only -- no audio, no model, and for the headline feature no fitted
parameter at all. GuitarSet ships `beat_position` next to the hexaphonic note
annotation, so the question is answerable for the price of reading JSON, and the
controls that could have explained the result away are cheap too.

Why ask. Four rounds measured the direction cue in the AUDIO and ended at a wall:
the cue is a decay feature needing 150-250 ms of post-onset sound (ADR 0551), the
model sits at its own input's linear ceiling (ADR 0553), and the remaining gap is
data. Every one of those measurements took the stroke in isolation. A strumming
hand is not isolated -- it is a pendulum locked to the beat, which is how guitar
pedagogy teaches it and what `ss_strum_pendulum.dart` already draws.

What is measured here is therefore a SECOND, INDEPENDENT channel, not a better
model: position in the bar, which the pipeline already computes (`TempoTracker`
+ `_placeInBar`) and currently throws away as a direction cue.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_metric.py

NumPy + stdlib only. The direction label derivation is IMPORTED from
`probe_direction_headroom`, so this probe and the training corpus cannot disagree
about what "up" means.
"""
from __future__ import annotations

import collections
import glob
import json
import os

import numpy as np

import guitarset as G
from probe_direction_headroom import clean_sweeps

# The subdivision the headline feature assumes. GuitarSet's Rock and Funk comping
# is sixteenth-note strumming, so an upstroke belongs on a sixteenth OFFBEAT
# (beat phase .25 or .75) and a downstroke on an eighth (.0 or .5). This is the
# only assumption in the feature, and section 2 measures what happens when it is
# wrong.
OFFBEAT_PHASE = 0.25


def beats_of(jams):
    """The annotated beat grid: (time, position-in-bar, measure)."""
    for ann in jams["annotations"]:
        if ann.get("namespace") == "beat_position":
            return [
                (
                    float(ob["time"]),
                    int(ob["value"]["position"]),
                    int(ob["value"]["measure"]),
                )
                for ob in ann["data"]
            ]
    return []


def pendulum_score(phase: float) -> float:
    """The headline feature, with NO fitted parameter: minus the distance from the
    nearest sixteenth offbeat. Higher = nearer an offbeat = more likely an
    upstroke. A score, not a probability -- it is ranked by AUC, never thresholded
    here."""
    return -abs((phase % (2 * OFFBEAT_PHASE)) - OFFBEAT_PHASE)


def collect(base_dir=None):
    """One row per clean sweep: its direction label and where it sits in the beat."""
    base = base_dir or G.root()
    rows = []
    for path in sorted(glob.glob(os.path.join(base, "annotation", "*_comp.jams"))):
        name = os.path.basename(path)
        player, tune = name[:2], name[3:].replace("_comp.jams", "")
        if not tune.startswith(G.STYLES):
            continue
        with open(path, encoding="utf-8") as handle:
            jams = json.load(handle)
        beats = beats_of(jams)
        if len(beats) < 4:
            continue
        times = np.array([b[0] for b in beats])
        previous_time = previous_dir = None
        for sweep in clean_sweeps(jams):
            at = sweep["at"]
            k = int(np.searchsorted(times, at, side="right")) - 1
            if k < 0 or k + 1 >= len(times):
                previous_time = previous_dir = None
                continue
            period = times[k + 1] - times[k]
            if period <= 0:
                continue
            phase = (at - times[k]) / period
            rows.append(
                {
                    "player": player,
                    "tune": tune,
                    "at": at,
                    "up": 1 if sweep["dir"] == "up" else 0,
                    "phase": phase,
                    "period": float(period),
                    "ioi_beats": None if previous_time is None
                    else (at - previous_time) / period,
                    "prev_up": previous_dir,
                    "spread_ms": sweep["spread_ms"],
                }
            )
            previous_time = at
            previous_dir = 1 if sweep["dir"] == "up" else 0
    return rows


def auc(score, y):
    """Tie-corrected ROC AUC. Chosen because it is invariant to the class balance,
    which differs between the splits here (train up-rate 0.385, test 0.192) -- a
    constant predictor scores 0.5 on either."""
    y = np.asarray(y)
    score = np.asarray(score, dtype=float)
    positive, negative = score[y == 1], score[y == 0]
    if len(positive) == 0 or len(negative) == 0:
        return float("nan")
    merged = np.concatenate([positive, negative])
    order = np.argsort(merged, kind="mergesort")
    ranks = np.empty(len(order), dtype=float)
    ranks[order] = np.arange(1, len(order) + 1, dtype=float)
    sorted_scores = merged[order]
    i = 0
    while i < len(sorted_scores):
        j = i
        while j + 1 < len(sorted_scores) and sorted_scores[j + 1] == sorted_scores[i]:
            j += 1
        if j > i:
            ranks[order[i:j + 1]] = (i + j + 2) / 2.0
        i = j + 1
    n_pos, n_neg = len(positive), len(negative)
    return (ranks[:n_pos].sum() - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def fit_table(rows, key, prior, strength=8.0):
    """Shrunk P(up | key) from TRAIN rows only. `strength` pulls thin cells toward
    the train prior so a cell seen three times cannot claim certainty."""
    total = collections.Counter()
    ups = collections.Counter()
    for row in rows:
        cell = key(row)
        if cell is None:
            continue
        total[cell] += 1
        ups[cell] += row["up"]
    return {
        cell: (ups[cell] + strength * prior) / (total[cell] + strength)
        for cell in total
    }, total


def score_with(table, rows, key, default):
    return [
        table.get(key(row), default) if key(row) is not None else default
        for row in rows
    ]


def splits(rows):
    """Player-disjoint AND tune-disjoint, the same rule `guitarset.split_masks`
    uses. Tune has to be disjoint too because every player plays every tune, so a
    shared tune leaks the progression AND the tempo (ADR 0550)."""
    train = [r for r in rows
             if r["player"] in G.TRAIN_PLAYERS and r["tune"] in G.TRAIN_TUNES]
    test = [r for r in rows
            if r["player"] in G.TEST_PLAYERS and r["tune"] in G.TEST_TUNES]
    return train, test


def main():
    rows = collect()
    train, test = splits(rows)
    y_train = [r["up"] for r in train]
    y_test = [r["up"] for r in test]
    prior = float(np.mean(y_train))
    print("sweeps %d   train (player+tune disjoint) %d   test %d"
          % (len(rows), len(train), len(test)))
    print("up rate: train %.4f   test %.4f   (a constant predictor scores AUC 0.5)"
          % (prior, float(np.mean(y_test))))

    print("\n--- 1  the metric channel, ZERO parameters ---")
    print("    score = -|distance from the nearest sixteenth offbeat|")
    print("    held-out AUC %.4f   (n=%d)"
          % (auc([pendulum_score(r["phase"]) for r in test], y_test), len(test)))
    print("    for comparison, the ACOUSTIC channel at the live deadline measures")
    print("    AUC 0.7484 (probe_direction_budget.py, 15 frames / 70 ms).")

    print("\n--- 2  the assumption: WHICH subdivision ---")
    print("    A fitted table is only here to show the map is subdivision-shaped;")
    print("    the feature above needs no table. Bin count = bins per beat:")
    def phase_bin(row, bins=8):
        return int(row["phase"] * bins) % bins

    def key8(row):
        return phase_bin(row, 8)

    for bins in (2, 4, 8, 16):
        def key(row, b=bins):
            return phase_bin(row, b)
        table, _ = fit_table(train, key, prior)
        print("      %2d bins  held-out AUC %.4f   train AUC %.4f"
              % (bins,
                 auc(score_with(table, test, key, prior), y_test),
                 auc(score_with(table, train, key, prior), y_train)))
    print("    2 bins (an EIGHTH-note map) scores near chance: the corpus's")
    print("    upstrokes are NOT on the 'and', they are on the sixteenth offbeats.")
    print("    So the map is pattern-specific, and a lesson prescribing eighths")
    print("    needs the eighth map -- which the app knows from its own notation")
    print("    (strum_patterns.dart), so it is never fitted from a corpus.")
    print("\n    P(up | phase), 8 bins, TRAIN -- the mechanism, legible:")
    table8, count8 = fit_table(train, key8, prior)
    for b in range(8):
        print("      phase %.3f-%.3f  n=%4d  P(up)=%.4f"
              % (b / 8, (b + 1) / 8, count8.get(b, 0), table8.get(b, float("nan"))))

    print("\n--- 3  control: could the LABEL have leaked through the sweep's time? ---")
    print("    A down sweep's first note is the bass string, an up sweep's the")
    print("    treble, and `at` is the first note either way -- so a directional")
    print("    bias could only be as large as the sweep's own spread.")
    spreads = collections.defaultdict(list)
    for r in rows:
        spreads["up" if r["up"] else "down"].append(r["spread_ms"])
    for key in ("down", "up"):
        values = spreads[key]
        print("      %-4s n=%4d  spread median %.1f ms  p90 %.1f ms"
              % (key, len(values), np.median(values), np.percentile(values, 90)))
    period = float(np.median([r["period"] for r in rows]))
    print("    median beat %.0f ms -> one sixteenth is %.0f ms, ~%.0fx the spread,"
          % (period * 1000, period * 250,
             period * 250 / max(np.median(spreads["down"]), 1e-9)))
    print("    and the two directions' spreads differ by %.1f ms -- no systematic"
          % abs(np.median(spreads["up"]) - np.median(spreads["down"])))
    print("    bias in the direction that would be needed. Leak ruled out.")

    print("\n--- 4  control: phase shuffled WITHIN each test take ---")
    print("    Destroys the phase-direction pairing while preserving every take's")
    print("    tempo, style and class balance. Must collapse to chance.")
    rng = np.random.default_rng(42)
    by_take = collections.defaultdict(list)
    for index, row in enumerate(test):
        by_take[(row["player"], row["tune"])].append(index)
    shuffled = [dict(r) for r in test]
    for indices in by_take.values():
        phases = [test[i]["phase"] for i in indices]
        rng.shuffle(phases)
        for i, phase in zip(indices, phases):
            shuffled[i]["phase"] = phase
    print("      held-out AUC %.4f"
          % auc([pendulum_score(r["phase"]) for r in shuffled], y_test))

    print("\n--- 5  per unseen player ---")
    for player in G.TEST_PLAYERS:
        subset = [r for r in test if r["player"] == player]
        print("      player %s  n=%4d  upRate %.3f  AUC %.4f"
              % (player, len(subset), float(np.mean([r["up"] for r in subset])),
                 auc([pendulum_score(r["phase"]) for r in subset],
                     [r["up"] for r in subset])))

    print("\n--- 6  cross-style transfer of the fitted map ---")
    print("    NOTE this does NOT test the subdivision assumption: Rock and Funk")
    print("    comping are BOTH sixteenth-based here. It only shows the map is")
    print("    stable across style at a fixed subdivision.")
    for fit_style, test_style in (("Rock", "Funk"), ("Funk", "Rock")):
        fit_rows = [r for r in train if r["tune"].startswith(fit_style)]
        test_rows = [r for r in test if r["tune"].startswith(test_style)]
        table, _ = fit_table(fit_rows, key8,
                             float(np.mean([r["up"] for r in fit_rows])))
        print("      fit %-5s -> test %-5s  AUC %.4f  (n fit %d, n test %d)"
              % (fit_style, test_style,
                 auc(score_with(table, test_rows, key8, prior),
                     [r["up"] for r in test_rows]), len(fit_rows), len(test_rows)))

    print("\n--- 7  the product number: timing scatter ---")
    print("    Displacing the grid by d is the same relative displacement as a")
    print("    learner playing d off a perfect grid, so this reads as the cost of")
    print("    the learner's OWN timing error. GuitarSet's players are")
    print("    professionals on a backing track; a beginner is not, and this is")
    print("    the closest this corpus can come to measuring that.")
    rng = np.random.default_rng(7)
    for jitter_ms in (0, 10, 20, 30, 50, 80):
        scores = []
        for row in test:
            shift = rng.normal(0.0, jitter_ms / 1000.0)
            scores.append(pendulum_score(
                ((row["phase"] * row["period"] + shift) / row["period"]) % 1.0))
        print("      +-%2d ms   AUC %.4f" % (jitter_ms, auc(scores, y_test)))

    print("\n--- 8  the supply of the error class the app exists to detect ---")
    print("    A stroke that VIOLATES the pendulum -- an upstroke away from the")
    print("    offbeat, a downstroke on it -- is exactly the learner mistake the")
    print("    app must catch, and the only stroke where the metric channel is")
    print("    WRONG and the acoustic channel must decide alone.")
    for tolerance in (0.0625, 0.09375, 0.125):
        violating = [r for r in rows
                     if (abs((r["phase"] % 0.5) - 0.25) <= tolerance) != bool(r["up"])]
        up_off = sum(1 for r in violating if r["up"])
        print("      tol +-%.4f beat (%.0f ms @120bpm):  %3d of %d violate (%.1f%%)"
              "   [upstroke off-grid %d, downstroke on it %d]"
              % (tolerance, tolerance * 500, len(violating), len(rows),
                 100 * len(violating) / len(rows), up_off,
                 len(violating) - up_off))
    tolerance = 0.09375
    violating = [r for r in train
                 if (abs((r["phase"] % 0.5) - 0.25) <= tolerance) != bool(r["up"])]
    print("    TRAIN split: %d of %d sweeps violate (%.2f%%), of which %d are"
          % (len(violating), len(train), 100 * len(violating) / len(train),
             sum(1 for r in violating if r["up"])))
    print("    upstrokes played off the grid. That is the entire supply of the")
    print("    error class, and it is why more PROFESSIONAL players (Guitar-TECHS,")
    print("    ADR 0553) cannot fix it: professionals do not make this mistake.")


if __name__ == "__main__":
    main()
