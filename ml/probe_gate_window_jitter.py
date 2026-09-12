# -*- coding: utf-8 -*-
"""Does moving the window's CENTRE explain the gate's 30-point in-situ retention gap?

`probe_gate_cost_frame.py` section 3b measures a gap it does not explain: at every gate,
the no-strum gate keeps ~0.95 of held-out true strums when the window is built at the
ANNOTATED onset, and ~0.65 of the ones the detector finds when production builds it at
the DETECTED onset. +0.30, stable across three gates.

Elimination left one candidate -- the window is centred on a different instant -- but
elimination is not a measurement, and a mechanism claim is its own claim (LESSONS L679,
L681). So this probe moves the centre ON PURPOSE, by a known offset, and reads the
retention off the same model, the same gate, the same corpus split.

The prediction being tested, stated before the run: if centring explains the gap, then an
offset on the order of the detector's own jitter (a spectral-flux peak lags the physical
attack, typically 5-20 ms) should cost retention on the order of tens of points. If the
curve is flat out to 30 ms, the hypothesis is WRONG and the gap has another cause.

Signed offsets are reported separately rather than averaged: a flux peak lags, so LATE is
the direction production actually suffers, and a symmetric summary would hide it.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_gate_window_jitter.py

Reads GuitarSet in place. Needs TensorFlow and `ml/weights_live_3c_settled.npz`.
"""
from __future__ import annotations

import json
import os

import numpy as np

import features as F
import guitarset as G
from train_live_3c_settled import DOWN, NO_STRUM, UP

OFFSETS_MS = (-30, -20, -15, -10, -5, 0, 5, 10, 15, 20, 30)
GATES = (0.439, 0.650, 0.850)


def held_out_takes():
    """The test split only: players 03-05 x the 4 unseen tunes (ADR 0550's both-ways)."""
    return [
        (wav, jams, player, tune)
        for wav, jams, player, tune in G.takes(G.root())
        if player in G.TEST_PLAYERS and tune in G.TEST_TUNES
    ]


def windows_at_offsets(takes, offsets_ms, deadline_s=G.LIVE_DEADLINE_S):
    """{offset_ms: (X, y)} -- the same sweeps, windowed at onset + offset."""
    out = {ms: ([], []) for ms in offsets_ms}
    for index, (wav, jams, _player, _tune) in enumerate(takes, 1):
        with open(jams, encoding="utf-8") as handle:
            sweeps = G.clean_sweeps(json.load(handle))
        raw, sr = G.read_mono(wav)
        pcm = G.resample_linear(raw, sr, F.SR).astype(np.float32)
        limit = len(pcm) / F.SR
        for sweep in sweeps:
            at = sweep["at"]
            label = DOWN if sweep["dir"] == "down" else UP
            for ms in offsets_ms:
                shifted = at + ms / 1000.0
                # Skip a sweep whose SHIFTED window would leave the recording, and skip
                # it at EVERY offset, so each column grades the identical sweep set.
                if shifted <= 0.05 or shifted >= limit - 0.05:
                    break
            else:
                for ms in offsets_ms:
                    xs, ys = out[ms]
                    xs.append(G.window_truncated(pcm, at + ms / 1000.0, deadline_s))
                    ys.append(label)
        print(f"  {index}/{len(takes)} takes", flush=True)
    return {ms: (np.stack(xs).astype(np.float32), np.array(ys))
            for ms, (xs, ys) in out.items() if xs}


def main():
    takes = held_out_takes()
    if not takes:
        raise SystemExit("no held-out takes found -- is GUITARSET_DIR right?")
    print(f"held-out split: {len(takes)} takes "
          f"(players {sorted(G.TEST_PLAYERS)} x tunes {sorted(G.TEST_TUNES)})")

    from probe_direction_fusion import load_model

    model, mean, std = load_model()
    grids = windows_at_offsets(takes, OFFSETS_MS)
    n = len(next(iter(grids.values()))[1])
    print(f"\n{n} clean sweeps, windowed at {len(OFFSETS_MS)} offsets each")

    print("\nRETENTION (share of true strums the gate KEEPS), by window offset")
    print("offset is how much LATER than the true attack the window is centred;")
    print("a spectral-flux peak lags, so positive is the direction production suffers.\n")
    print("  offset    " + "  ".join(f"gate {g:.3f}" for g in GATES)
          + "    P(no-strum) median   dir-acc on kept")
    rows = {}
    for ms in OFFSETS_MS:
        x, y = grids[ms]
        probs = model.predict(((x - mean) / std)[..., None], verbose=0)
        p_no = probs[:, NO_STRUM]
        cells, keeps = [], {}
        for gate in GATES:
            keep = p_no <= gate
            keeps[gate] = keep
            cells.append(f"   {keep.mean():.3f}  ")
        shipped = keeps[0.850]
        if shipped.any():
            sub, truth = probs[shipped], y[shipped]
            called = np.where(sub[:, UP] > sub[:, DOWN], UP, DOWN)
            dir_acc = float((called == truth).mean())
        else:
            dir_acc = float("nan")
        rows[ms] = (keeps, float(np.median(p_no)), dir_acc)
        print(f"  {ms:+4d} ms  " + "".join(cells)
              + f"        {np.median(p_no):.4f}            {dir_acc:.3f}")

    print("\nWhat this says about the +0.30 gap:")
    base = rows[0][0]
    for gate in GATES:
        at0 = base[gate].mean()
        worst = min(rows[ms][0][gate].mean() for ms in OFFSETS_MS)
        worst_ms = min(OFFSETS_MS, key=lambda ms: rows[ms][0][gate].mean())
        print(f"  gate {gate:.3f}: centred {at0:.3f} -> worst {worst:.3f}"
              f" at {worst_ms:+d} ms  (drop {at0 - worst:.3f})")
    print("\n  Compare the measured in-situ retentions: 0.633 / 0.659 / 0.690.")
    print("  If the drops above do not reach that far, centring is only PART of the gap")
    print("  and the rest is still unexplained -- which is what gets written down.")


if __name__ == "__main__":
    main()
