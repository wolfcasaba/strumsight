"""Synthetic strum audio + matching wrist-IMU traces, so the data pipeline can
be smoke-tested with no real recordings (mirrors test/support/synth.dart)."""
from __future__ import annotations

import numpy as np

from features import SR

OPEN_STRINGS = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63]  # E2..E4


def strum(direction: str, sr: int = SR, stagger_ms: float = 8.0,
          seconds: float = 0.6, lead_s: float = 0.1) -> np.ndarray:
    """A staggered 6-string strum. down = low strings first, up = high first."""
    order = OPEN_STRINGS if direction == "down" else OPEN_STRINGS[::-1]
    n = int((lead_s + seconds) * sr)
    out = np.zeros(n, dtype=np.float32)
    stagger = int(stagger_ms / 1000 * sr)
    lead = int(lead_s * sr)
    for i, f in enumerate(order):
        off = lead + i * stagger
        t = np.arange(n - off) / sr
        env = np.exp(-1.5 * t)
        note = np.zeros(n, dtype=np.float32)
        for h in range(1, 6):
            if f * h < sr / 2:
                note[off:] += (0.12 / h) * env * np.sin(2 * np.pi * f * h * t)
        out += note
    return out


def accel_axis(direction: str, onset_s: float, sr: int = SR,
               seconds: float = 0.7) -> tuple[np.ndarray, np.ndarray]:
    """A wrist-accel axis whose mean over the attack window has the sign that
    encodes the stroke (down → +, up → −). Returns (t, axis) at 200 Hz."""
    fs = 200
    t = np.arange(int(seconds * fs)) / fs
    sign = 1.0 if direction == "down" else -1.0
    # A single swing centred just after the onset (a ~6 Hz gesture).
    axis = sign * np.exp(-((t - (onset_s + 0.03)) ** 2) / (2 * 0.04 ** 2))
    axis += 0.02 * np.random.default_rng(0).standard_normal(len(t))
    return t, axis.astype(np.float64)
