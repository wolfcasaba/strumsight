"""Generate the log-mel PARITY fixture for the Dart front-end (plan: docs/plans/ml-track.md P0.1).

The Dart `LogMelExtractor` must reproduce ml/features.py `log_mel` on identical
PCM — a drifted front-end silently destroys any model trained on these features
(chunk 018 "MUST match on device"). This script is the single source of the
fixture; re-run it whenever features.py changes:

    python3 ml/make_logmel_fixture.py

Writes test/fixtures/logmel_parity.json — deterministic (seeded), no TF needed.
"""
from __future__ import annotations

import json
import pathlib

import numpy as np

import features


def make_signal(sr: int, n: int) -> np.ndarray:
    """A deterministic, guitar-ish test signal: two decaying plucks (E2 + A3
    partial stacks) over a low noise floor — exercises low/high mel bands,
    silence, attack transients and decay."""
    rng = np.random.default_rng(20260712)
    t = np.arange(n) / sr
    x = rng.normal(0.0, 0.002, n)

    def pluck(t0: float, f0: float, amp: float) -> np.ndarray:
        env = np.where(t >= t0, np.exp(-(t - t0) * 6.0), 0.0)
        s = np.zeros_like(t)
        for h in range(1, 6):
            s += (amp / h) * np.sin(2 * np.pi * f0 * h * (t - t0))
        return env * s

    x += pluck(0.020, 82.41, 0.5)   # E2
    x += pluck(0.180, 220.0, 0.35)  # A3
    return np.clip(x, -1.0, 1.0).astype(np.float32)


def main() -> None:
    n = 6000  # 0.375 s -> 25 log-mel frames: small fixture, full coverage
    pcm = make_signal(features.SR, n)
    lm = features.log_mel(pcm)
    out = {
        "sr": features.SR,
        "n_fft": features.N_FFT,
        "hop": features.HOP,
        "n_mels": features.N_MELS,
        "fmin": features.FMIN,
        "pcm": [float(f"{v:.8g}") for v in pcm.tolist()],
        "logmel": [[float(f"{v:.6f}") for v in row] for row in lm.tolist()],
    }
    dest = pathlib.Path(__file__).resolve().parent.parent / "test" / "fixtures" / "logmel_parity.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out))
    print(f"wrote {dest} — {lm.shape[0]} frames x {lm.shape[1]} mels")


if __name__ == "__main__":
    main()
