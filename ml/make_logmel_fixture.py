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


def _round_pcm(pcm):
    """Round to the 8 sig-figs stored in JSON, so BOTH sides consume the
    IDENTICAL input (r142 audit N2 — the reference must not be computed from
    higher-precision samples than the fixture ships)."""
    return np.array([float(f"{v:.8g}") for v in pcm.tolist()], dtype=np.float32)


def _entry(pcm):
    pcm = _round_pcm(pcm)
    lm = features.log_mel(pcm)
    return pcm, lm


def make_adversarial_cases(sr: int):
    """The r142-audit adversarial input classes (short: 0.25 s each)."""
    n = 4000
    t = np.arange(n) / sr
    rng = np.random.default_rng(20260713)

    loud = 5.0 * np.sin(2 * np.pi * 220.0 * t) * np.exp(-t * 2.0)
    clipped = np.clip(loud, -1.0, 1.0).astype(np.float32)  # truly saturated

    dc = (0.15 + 0.3 * np.sin(2 * np.pi * 110.0 * t) * np.exp(-t * 3.0))
    dc = np.clip(dc, -1.0, 1.0).astype(np.float32)  # DC offset (cheap mic)

    quiet = (rng.normal(0.0, 0.004, n)
             + 0.02 * np.sin(2 * np.pi * 196.0 * t) * np.exp(-t * 4.0))
    quiet = np.clip(quiet, -1.0, 1.0).astype(np.float32)  # near the log floor

    return {"clipped": clipped, "dc_offset": dc, "near_floor": quiet}


def main() -> None:
    fixtures = pathlib.Path(__file__).resolve().parent.parent / "test" / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)

    n = 6000  # 0.375 s -> 25 log-mel frames: small fixture, full coverage
    pcm, lm = _entry(make_signal(features.SR, n))
    out = {
        "sr": features.SR,
        "n_fft": features.N_FFT,
        "hop": features.HOP,
        "n_mels": features.N_MELS,
        "fmin": features.FMIN,
        "pcm": pcm.tolist(),
        "logmel": [[float(f"{v:.6f}") for v in row] for row in lm.tolist()],
    }
    (fixtures / "logmel_parity.json").write_text(json.dumps(out))
    print(f"wrote logmel_parity.json — {lm.shape[0]} frames x {lm.shape[1]} mels")

    cases = []
    for name, sig in make_adversarial_cases(features.SR).items():
        pcm, lm = _entry(sig)
        cases.append({
            "name": name,
            "pcm": pcm.tolist(),
            "logmel": [[float(f"{v:.6f}") for v in row] for row in lm.tolist()],
        })
    (fixtures / "logmel_parity_cases.json").write_text(json.dumps({"cases": cases}))
    print(f"wrote logmel_parity_cases.json — {[c['name'] for c in cases]}")


if __name__ == "__main__":
    main()
