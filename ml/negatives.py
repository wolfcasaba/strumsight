"""r174 HARD-NEGATIVE mining for the no-strum reject head (pure NumPy).

The r170 finding: the heuristic onset detector fires ~1-in-6 FALSE onsets and
the direction CRNN is EQUALLY confident on them (median raw 0.94) as on real
strums (0.97), so confidence cannot gate noise. The fix (r172 roadmap / Klangio
recipe): give the model a way to SAY "no strum here" — a learned no-strum class
trained with HARD NEGATIVES.

This module mines "no-strum" windows from the SAME recordings as the positive
strum windows: times NOT near any labeled strum. Two kinds are produced:

  - HARD negatives: spectral-flux onset PEAKS that are far from every labeled
    strum. These approximate the heuristic detector's actual false positives
    (transients / string noise / palm hits that look like onsets but aren't a
    strum) — the exact events the reject head must learn to suppress.
  - EASY negatives: random interior times far from every strum (sustain / decay
    / near-silence between strums) — the background the head must NOT confuse.

Windowing (log-mel at each time) is done by the caller so the negatives get the
IDENTICAL geometry as the positive windows (batch full-window or live-70 ms
truncated). This file only chooses TIMES — pure NumPy + features.py, no TF.
"""
from __future__ import annotations

import numpy as np

import features as F

#: A candidate no-strum time must be at least this far from EVERY labeled strum.
#: 120 ms > the 70 ms live deadline + the ±30 ms window pre-roll, so a negative
#: window never overlaps a real strum's attack. (Task r174: guard >120 ms.)
MARGIN_S = 0.12

#: Keep a full window clear of the recording edges (PRE/POST frames + FFT tail).
EDGE_LO_S = 0.10
EDGE_HI_PAD_S = 0.20


def _min_dist_to_strum(t, strum_times):
    if len(strum_times) == 0:
        return np.inf
    return float(np.min(np.abs(strum_times - t)))


def negative_times(pcm, strum_times, sr=F.SR, margin_s=MARGIN_S,
                   n_per_strum=1.0, hard_frac=0.5, rng=None,
                   max_draws=4000):
    """Times (s) of no-strum windows mined from one recording.

    Returns (times, kinds): a sorted float array of times and a matching array
    of {"hard","easy"} labels. Every returned time is > `margin_s` from every
    entry of `strum_times` and leaves room for a full window at both edges.

    - HARD times come from `features.spectral_flux_onsets` (flux peaks) that are
      far from every strum — the detector's would-be false positives.
    - EASY times are random interior draws far from every strum AND from each
      other (>= margin apart, so windows don't overlap-duplicate).

    Count target ~ round(n_per_strum * n_strums), split hard_frac / rest. Fewer
    hard candidates than requested just shifts the balance toward easy (there is
    no way to fabricate a flux peak that isn't there). Deterministic per `rng`.
    """
    if rng is None:
        rng = np.random.default_rng(0)
    pcm = np.asarray(pcm, dtype=np.float32)
    strum_times = np.asarray(strum_times, dtype=np.float64)
    dur = len(pcm) / sr
    lo, hi = EDGE_LO_S, dur - EDGE_HI_PAD_S
    if hi <= lo:
        return np.zeros(0, dtype=np.float64), np.zeros(0, dtype="<U4")

    n_strums = len(strum_times)
    n_target = int(round(n_per_strum * max(n_strums, 1)))
    n_hard_want = int(round(hard_frac * n_target))

    def ok(t, chosen):
        if not (lo <= t <= hi):
            return False
        if _min_dist_to_strum(t, strum_times) <= margin_s:
            return False
        if chosen and np.min(np.abs(np.asarray(chosen) - t)) <= margin_s:
            return False
        return True

    # HARD: flux peaks far from every strum. Deterministic (no rng), then we
    # subsample deterministically if there are more than we want.
    flux_peaks = np.asarray(F.spectral_flux_onsets(pcm), dtype=np.float64)
    hard_all = [float(t) for t in flux_peaks
                if lo <= t <= hi and _min_dist_to_strum(t, strum_times) > margin_s]
    hard = []
    for t in hard_all:
        if ok(t, hard):
            hard.append(t)
    if len(hard) > n_hard_want:
        pick = rng.choice(len(hard), size=n_hard_want, replace=False)
        hard = [hard[i] for i in sorted(pick.tolist())]

    # EASY: random interior draws to fill the rest of the target.
    n_easy_want = max(0, n_target - len(hard))
    easy = []
    chosen = list(hard)
    draws = 0
    while len(easy) < n_easy_want and draws < max_draws:
        t = float(rng.uniform(lo, hi))
        draws += 1
        if ok(t, chosen):
            easy.append(t)
            chosen.append(t)

    times = np.array(hard + easy, dtype=np.float64)
    kinds = np.array(["hard"] * len(hard) + ["easy"] * len(easy), dtype="<U4")
    order = np.argsort(times)
    return times[order], kinds[order]
