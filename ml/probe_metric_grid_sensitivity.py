# -*- coding: utf-8 -*-
"""What does the metric channel need from the GRID, and what happens when it is wrong?

ADR 0557 measured the channel against GuitarSet's ANNOTATED beat grid: the right tempo
and, crucially, the right PHASE ORIGIN. The app does not have that in free play. What
`LivePipeline` has is

  * `TempoTracker.bpm` -- a median-IOI estimate, EMA-smoothed, and folded into 60-200
    by repeated doubling/halving, so its OCTAVE is explicitly ambiguous; and
  * `_barStartSec` -- anchored to `event.timeSec` of whichever strum happened to
    overflow the previous bar, i.e. an ARBITRARY stroke, re-picked about once a bar.

Neither is a beat grid. A phase origin taken from an arbitrary stroke is off by whatever
that stroke's own position was, and the channel's whole claim is that position decides
direction -- so the error does not degrade the answer, it INVERTS it. That is the worst
possible failure shape: confident and wrong.

This probe measures the three ways the grid can be wrong, before anything is wired:

  1. ORIGIN from an arbitrary stroke (the pipeline's actual behaviour), with the right
     tempo.
  2. TEMPO off by an octave (x2 / /2), with the right origin.
  3. Both, which is the honest free-play case.

Annotation only -- no audio, no model.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_metric_grid_sensitivity.py
"""
from __future__ import annotations

import collections

import numpy as np

import probe_direction_metric as M

# How the pipeline re-anchors: `_placeInBar` resets `_barStartSec` to the overflowing
# stroke's own time once a bar has elapsed, with a bar being 8 eighths.
BEATS_PER_BAR = 4.0


def phase_against(at, origin, period):
    return ((at - origin) / period) % 1.0


def call_from(phase):
    return M.slot_call(phase)


def accuracy(rows, calls):
    truth = np.array([r["up"] for r in rows])
    return float((np.asarray(calls) == truth).mean())


def by_take(rows):
    groups = collections.defaultdict(list)
    for row in rows:
        groups[(row["player"], row["tune"])].append(row)
    return groups


def annotated(rows):
    """The ADR 0557 baseline: the annotated grid, restated through `slot_call`."""
    return [call_from(r["phase"]) for r in rows]


def single_anchor(groups, seed=0):
    """Origin = ONE arbitrary stroke per take, right tempo. The kindest version of
    self-anchoring: the pipeline re-picks far more often."""
    rng = np.random.default_rng(seed)
    rows, calls = [], []
    for take_rows in groups.values():
        anchor = take_rows[int(rng.integers(len(take_rows)))]
        period = anchor["period"]
        for row in take_rows:
            rows.append(row)
            calls.append(call_from(phase_against(row["at"], anchor["at"], period)))
    return rows, calls


def rolling_anchor(groups, seed=0):
    """Origin re-picked about once a bar from the stroke that crosses the boundary --
    what `_placeInBar` actually does."""
    rng = np.random.default_rng(seed)
    rows, calls = [], []
    for take_rows in groups.values():
        ordered = sorted(take_rows, key=lambda r: r["at"])
        origin = None
        for row in ordered:
            period = row["period"]
            bar = BEATS_PER_BAR * period
            if origin is None or row["at"] - origin >= bar:
                origin = row["at"]
            rows.append(row)
            calls.append(call_from(phase_against(row["at"], origin, period)))
    _ = rng  # kept for signature symmetry; this arm is deterministic
    return rows, calls


def wrong_octave(rows, factor):
    """Right origin, tempo off by an octave -- the fold `TempoTracker` performs."""
    calls = []
    for row in rows:
        # The annotated phase came from the true period; rebuild a time offset from it
        # and re-measure against a period that is `factor` times wrong.
        offset = row["phase"] * row["period"]
        calls.append(call_from((offset / (row["period"] * factor)) % 1.0))
    return calls


def main():
    rows = M.collect()
    _train, test = M.splits(rows)
    groups = by_take(test)
    base = accuracy(test, annotated(test))

    print("held-out GuitarSet (unseen player AND tune): %d strokes, %d takes"
          % (len(test), len(groups)))
    print("up rate %.4f -- so ALWAYS-DOWN scores %.4f, the number to beat\n"
          % (float(np.mean([r["up"] for r in test])),
             1 - float(np.mean([r["up"] for r in test]))))
    print("  grid                                            accuracy   vs annotated")
    print("  annotated (ADR 0557, right tempo AND origin)      %.4f        --" % base)

    print("\n  --- 1  ORIGIN from an arbitrary stroke, right tempo ---")
    for seed in range(5):
        sub, calls = single_anchor(groups, seed)
        print("      one anchor per take, seed %d                  %.4f      %+.4f"
              % (seed, accuracy(sub, calls), accuracy(sub, calls) - base))
    sub, calls = rolling_anchor(groups)
    print("      re-anchored every bar (what _placeInBar does)       %.4f      %+.4f"
          % (accuracy(sub, calls), accuracy(sub, calls) - base))

    print("\n  --- 2  TEMPO off by an octave, right origin ---")
    for factor, label in ((2.0, "x2 (half-time read)"), (0.5, "/2 (double-time read)")):
        calls = wrong_octave(test, factor)
        print("      %-28s              %.4f      %+.4f"
              % (label, accuracy(test, calls), accuracy(test, calls) - base))

    print("\n  --- 3  the honest free-play case: both wrong ---")
    for factor in (2.0, 0.5):
        rows_out, calls = [], []
        for take_rows in groups.values():
            ordered = sorted(take_rows, key=lambda r: r["at"])
            origin = None
            for row in ordered:
                period = row["period"] * factor
                if origin is None or row["at"] - origin >= BEATS_PER_BAR * period:
                    origin = row["at"]
                rows_out.append(row)
                calls.append(call_from(phase_against(row["at"], origin, period)))
        print("      re-anchored + tempo x%.1f                      %.4f      %+.4f"
              % (factor, accuracy(rows_out, calls),
                 accuracy(rows_out, calls) - base))

    print("\n  --- what an arbitrary anchor costs, mechanically ---")
    print("  The channel's claim is that POSITION decides direction, so an origin")
    print("  error of half a slot does not blur the answer, it INVERTS it. Measured")
    print("  offset distribution of the stroke a self-anchored grid would pick:")
    offsets = collections.Counter()
    for row in test:
        offsets[M.slot_call(row["phase"])] += 1
    total = sum(offsets.values())
    for slot_dir, count in sorted(offsets.items()):
        print("      anchor stroke would be %-4s  %5.1f%% of the time"
              % ('UP' if slot_dir == M.UP_SLOT else 'DOWN', 100.0 * count / total))
    print("  An UP anchor shifts the grid by one slot, which flips every call on a")
    print("  strict alternation -- so the self-anchored arms above are a MIXTURE of")
    print("  near-perfect and near-inverted takes, not a uniformly degraded signal.")


if __name__ == "__main__":
    main()
