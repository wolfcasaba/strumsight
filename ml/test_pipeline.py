"""Smoke test for the strum-direction DATA pipeline (NumPy-only, no TF).
Run: `python3 ml/test_pipeline.py` — exits 0 on success, 1 on failure.

Proves the pipeline end-to-end on synthetic data so it's plug-and-play the
moment real (audio + Wear-OS-accel) recordings arrive: onset detection finds
the attack, the IMU auto-labeler recovers the stroke direction, and the log-mel
window has the model-input shape.
"""
from __future__ import annotations

import sys

import numpy as np

import features as F
import klangio
import synth


def _check(name, cond):
    print(f"  [{'ok' if cond else 'FAIL'}] {name}")
    return cond


def main() -> int:
    ok = True
    print("strum-direction data-pipeline smoke test")

    # 1. log-mel has the right shape + is finite.
    down = synth.strum("down")
    lm = F.log_mel(down)
    ok &= _check(f"log_mel shape (…,{F.N_MELS})", lm.shape[1] == F.N_MELS)
    ok &= _check("log_mel finite", np.all(np.isfinite(lm)))

    # 2. onset detection finds ~one attack near the lead (0.1 s).
    onsets = F.spectral_flux_onsets(down)
    ok &= _check(f"one onset found (got {len(onsets)})", len(onsets) >= 1)
    first = onsets[0] if onsets else -1
    ok &= _check(f"onset near 0.1 s (got {first:.3f})", 0.05 <= first <= 0.2)

    # 3. IMU auto-labeling recovers BOTH directions.
    for direction in ("down", "up"):
        sig = synth.strum(direction)
        ons = F.spectral_flux_onsets(sig)
        onset_s = ons[0] if ons else 0.1
        t, axis = synth.accel_axis(direction, onset_s)
        label = F.label_direction_from_accel(t, axis, onset_s)
        ok &= _check(f"auto-label {direction} → {label}", label == direction)

    # 4. model-input window has the fixed shape.
    win = F.window_at(lm, first if first > 0 else 0.1)
    ok &= _check(
        f"window shape ({F.PRE_FRAMES + F.POST_FRAMES},{F.N_MELS})",
        win.shape == (F.PRE_FRAMES + F.POST_FRAMES, F.N_MELS),
    )

    # 5. Klangio .strums parsing (round 140): exact fields, strict directions.
    events = klangio.parse_strums(
        "0.451\tD\tC-major\n\n1.612\tU\tF-major\n2.912\tD\tA-minor\n")
    ok &= _check("parse_strums 3 events", len(events) == 3)
    ok &= _check(
        "parse_strums fields",
        events[1] == (1.612, "up", "F-major") and events[0][1] == "down",
    )
    try:
        klangio.parse_strums("0.5\tX\tC-major\n")
        ok &= _check("unknown direction rejected", False)
    except ValueError:
        ok &= _check("unknown direction rejected", True)

    # 6. Klangio windows: labeled times → chunk-018-shaped (X, y), no
    #    detection in the loop (annotations are ground truth).
    sig = np.concatenate([synth.strum("down"), synth.strum("up")])
    lead = 0.1  # synth.strum lead silence
    evs = [(lead, "down", "C-major"),
           (lead + len(synth.strum("down")) / F.SR, "up", "C-major")]
    xs, ys = klangio.windows_for_recording(sig, evs)
    ok &= _check("klangio windows count", len(xs) == 2 and ys == [0, 1])
    ok &= _check(
        "klangio window shape",
        xs[0].shape == (F.PRE_FRAMES + F.POST_FRAMES, F.N_MELS),
    )

    # 7. Split-by-recording (round 141): whole recordings stay on one side —
    #    a window-level split would leak recording identity (round-140 lesson:
    #    some takes are single-direction).
    rec = np.array(["a"] * 5 + ["b"] * 3 + ["c"] * 4 + ["d"] * 2)
    train, ev = klangio.split_by_recording(rec, eval_frac=0.25, seed=7)
    ok &= _check("split masks disjoint+complete",
                 bool(np.all(train ^ ev)) and int(ev.sum()) > 0)
    straddles = any(
        len({bool(m) for m, r2 in zip(ev.tolist(), rec.tolist()) if r2 == r})
        > 1 for r in set(rec.tolist()))
    ok &= _check("no recording straddles the split", not straddles)
    t2, e2 = klangio.split_by_recording(rec, eval_frac=0.25, seed=7)
    ok &= _check("split deterministic per seed", bool(np.all(ev == e2)))

    print("PASS" if ok else "FAILURES ABOVE")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
