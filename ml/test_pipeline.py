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

    print("PASS" if ok else "FAILURES ABOVE")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
