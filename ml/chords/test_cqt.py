"""Tests for the CQT feature front-end (ML chord track, phase 0.3).

pytest-style, but also runnable directly (pytest is NOT installed on the box):

    python3 ml/chords/test_cqt.py     # prints an all-pass line

Covers: correct peak bin for a bin-centred sine (octaves weaker), output shape
/ dtype / frame-count growth, silence -> ~0 (the log1p floor), determinism, and
a parity check against the shipped golden fixture cqt_fixture.json.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords.cqt import (  # noqa: E402
    BINS_PER_OCTAVE,
    FMIN,
    GAMMA,
    HOP,
    N_BINS,
    SR,
    cqt,
    n_frames,
)

_HERE = os.path.dirname(os.path.abspath(__file__))


def _bin_of_hz(hz: float) -> int:
    """CQT bin index whose centre frequency is `hz` (rounded)."""
    return int(round(BINS_PER_OCTAVE * np.log2(hz / FMIN)))


def _sine(hz: float, n: int, sr: int = SR, amp: float = 0.5) -> np.ndarray:
    t = np.arange(n) / sr
    return (amp * np.sin(2 * np.pi * hz * t)).astype(np.float32)


def test_constants():
    assert SR == 22050
    assert BINS_PER_OCTAVE == 24
    assert N_BINS == 144
    assert HOP == 2048
    assert abs(FMIN - 32.70319566257483) < 1e-9
    # A4 = 440 Hz must land exactly on a bin centre (45 semitones above C1).
    assert _bin_of_hz(440.0) == 90


def test_shape_and_dtype():
    out = cqt(_sine(440.0, 8192), SR)
    assert out.shape == (n_frames(8192), N_BINS)
    assert out.shape[1] == 144
    assert out.dtype == np.float32


def test_peak_at_correct_bin():
    # A4 = 440 Hz -> bin 90. Averaged over frames, the argmax must be there.
    out = cqt(_sine(440.0, 16384), SR)
    prof = out.mean(axis=0)
    peak = int(np.argmax(prof))
    assert abs(peak - 90) <= 2, f"peak {peak} not near bin 90"


def test_neighbouring_octaves_weaker():
    # A pure 440 Hz tone: the octave-below (220, bin 66) and octave-above
    # (880, bin 114) bins must be clearly weaker than the true bin 90.
    out = cqt(_sine(440.0, 16384), SR)
    prof = out.mean(axis=0)
    assert prof[90] > 3 * prof[66]
    assert prof[90] > 3 * prof[114]


def test_frame_count_grows_with_length():
    counts = [cqt(_sine(440.0, n), SR).shape[0]
              for n in (2000, 6000, 12000, 24000)]
    assert counts == sorted(counts)
    assert counts[0] >= 1                 # short input still yields a frame
    assert counts[-1] > counts[0]


def test_empty_input():
    out = cqt(np.zeros(0, dtype=np.float32), SR)
    assert out.shape == (0, N_BINS)


def test_silence_near_zero():
    # log1p(GAMMA*|CQT|) of silence is exactly 0 (no eps floor).
    out = cqt(np.zeros(8192, dtype=np.float32), SR)
    assert out.shape[0] >= 1
    assert np.max(np.abs(out)) < 1e-6


def test_determinism():
    x = _sine(329.63, 10000)              # E4
    a = cqt(x, SR)
    b = cqt(x, SR)
    assert np.array_equal(a, b)


def test_resample_path_runs():
    # A 44.1 kHz 440 Hz tone resampled to SR must still peak at bin 90.
    sr2 = 44100
    t = np.arange(16384) / sr2
    x = (0.5 * np.sin(2 * np.pi * 440.0 * t)).astype(np.float32)
    out = cqt(x, sr2)
    assert out.shape[1] == N_BINS
    assert abs(int(np.argmax(out.mean(axis=0))) - 90) <= 3


def test_log_amplitude_nonnegative():
    out = cqt(_sine(261.63, 8192), SR)    # C4
    assert np.all(out >= 0.0)             # log(1 + GAMMA*|CQT|) >= 0


def test_golden_fixture_parity():
    path = os.path.join(_HERE, "cqt_fixture.json")
    with open(path) as f:
        fx = json.load(f)
    pcm = np.array(fx["pcm"], dtype=np.float32)
    got = cqt(pcm, fx["sr"])
    exp = np.array(fx["cqt"], dtype=np.float32)
    assert got.shape == exp.shape, f"{got.shape} vs {exp.shape}"
    # fixture stores 6-decimal rounded values -> compare at that tolerance.
    assert np.max(np.abs(got - exp)) < 2e-6, np.max(np.abs(got - exp))


def _run():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"  FAIL {t.__name__}: {e}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"  ERROR {t.__name__}: {type(e).__name__}: {e}")
    print("-" * 48)
    if failed:
        print(f"CQT TESTS: {failed}/{len(tests)} FAILED")
        return 1
    print(f"CQT TESTS: all {len(tests)} passed")
    return 0


if __name__ == "__main__":
    _ = GAMMA  # referenced for the log-amplitude doc contract
    sys.exit(_run())
