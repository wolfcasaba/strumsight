"""Tests for ±semitone CQT-transposition augmentation (`chords/augment.py`).

Pure NumPy — NO TensorFlow import (runs on the ARM box + as a fast CI gate).
pytest-collectable AND runnable as a plain script:

    python3 ml/chords/test_augment.py
    cd ml && python -m pytest chords/test_augment.py -q
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords.augment import augment_windows, transpose_window  # noqa: E402

WIN = 8
N_BINS = 144


def _onehot_window(bin_idx: int, cls: int):
    """A synthetic 'one-hot-ish' CQT: energy=1.0 at one bin, plus label `cls`."""
    X = np.zeros((WIN, N_BINS), dtype=np.float32)
    X[:, bin_idx] = 1.0
    Y = np.full((WIN,), cls, dtype=np.int32)
    return X, Y


def test_plus_two_semitones_shifts_up_four_bins_and_maps_C_to_D():
    # C-major (class 1), energy at bin 40. +2 semitones = +4 bins -> bin 44,
    # and C-major(1) -> D-major(3).
    X, Y = _onehot_window(40, 1)
    X2, Y2 = transpose_window(X, Y, 2)
    assert np.all(X2[:, 44] == 1.0)              # energy moved up 4 bins
    assert X2[:, 40].sum() == 0.0                # original bin now empty
    assert float(X2.sum()) == float(X[:, 40].sum())  # energy conserved, none lost
    assert np.all(Y2 == 3)                       # C major -> D major


def test_minus_one_semitone_maps_A_minor_to_Gsharp_minor():
    # A-minor (class 22), energy at bin 50. -1 semitone = -2 bins -> bin 48,
    # and A-minor(22) -> G#-minor(21).
    X, Y = _onehot_window(50, 22)
    X2, Y2 = transpose_window(X, Y, -1)
    assert np.all(X2[:, 48] == 1.0)
    assert X2[:, 50].sum() == 0.0
    assert np.all(Y2 == 21)                      # A minor -> G# minor


def test_no_chord_label_is_invariant():
    X, Y = _onehot_window(60, 0)                 # N.C.
    for k in (-5, -1, 3, 5):
        _, Y2 = transpose_window(X, Y, k)
        assert np.all(Y2 == 0)                   # N.C. never transposes


def test_zero_fill_leaves_no_wrapped_energy():
    # Energy near the LOW edge; a +5-semitone up-shift must NOT wrap it to the
    # high end (that would be np.roll behaviour — phantom energy).
    X, Y = _onehot_window(1, 1)                  # bin 1, near bottom
    X2, _ = transpose_window(X, Y, 5)            # +10 bins -> bin 11
    assert np.all(X2[:, 11] == 1.0)
    assert X2[:, -10:].sum() == 0.0              # nothing wrapped to the top
    # Energy near the HIGH edge; a shift-up drops it off the top entirely.
    Xh, Yh = _onehot_window(N_BINS - 2, 1)       # bin 142
    Xh2, _ = transpose_window(Xh, Yh, 5)         # +10 -> bin 152 (off the edge)
    assert float(Xh2.sum()) == 0.0               # shifted off top, none wraps low


def test_augment_windows_triples_rows_and_labels_in_range():
    rng = np.random.default_rng(0)
    N = 5
    X = rng.standard_normal((N, WIN, N_BINS)).astype(np.float32)
    Y = rng.integers(0, 25, size=(N, WIN)).astype(np.int32)
    Xa, Ya = augment_windows(X, Y, rng, copies=2, max_semi=5)
    assert Xa.shape[0] == Ya.shape[0] == N * 3   # copies=2 -> triple the rows
    assert Xa.shape[1:] == (WIN, N_BINS)
    assert Ya.shape[1:] == (WIN,)
    assert int(Ya.min()) >= 0 and int(Ya.max()) <= 24
    # Originals preserved as the first N rows.
    assert np.array_equal(Xa[:N], X)
    assert np.array_equal(Ya[:N], Y)


def test_augment_windows_is_deterministic_given_rng():
    N = 4
    base = np.random.default_rng(7)
    X = base.standard_normal((N, WIN, N_BINS)).astype(np.float32)
    Y = base.integers(0, 25, size=(N, WIN)).astype(np.int32)
    a = augment_windows(X, Y, np.random.default_rng(1), copies=2)[0]
    b = augment_windows(X, Y, np.random.default_rng(1), copies=2)[0]
    assert np.array_equal(a, b)                  # same seed -> identical
    c = augment_windows(X, Y, np.random.default_rng(2), copies=2)[0]
    assert not np.array_equal(a, c)              # different seed -> different


def _run_all():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
        print(f"  ok  {t.__name__}")
    print(f"\nALL {len(tests)} AUGMENT TESTS PASSED")


if __name__ == "__main__":
    _run_all()
