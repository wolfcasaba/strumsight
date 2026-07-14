"""±semitone CQT-transposition data augmentation (ML chord track, phase 1).

Key-invariance is the single biggest robustness lever for a chord model
(`docs/plans/ml-chord-track.md` "Augmentation"): a C-major shape and a D-major
shape are the SAME pattern shifted along the log-frequency axis, so transposing
the CQT ± a few semitones (and its labels along with it) multiplies the training
data while teaching the net to ignore absolute key.

CQT layout (`chords/cqt.py`): BINS_PER_OCTAVE=24 → **1 semitone = 2 bins**;
144 bins total (6 octaves). A window is `X (WIN, 144)` float, `Y (WIN,)` int in
the 25-class majmin space (0 = N.C., 1..12 = C..B major, 13..24 = C..B minor).

Transpose by `k` semitones =
  * shift `X`'s frequency axis (last axis) by `2*k` bins, and
  * transpose every non-N.C. label in `Y` by `k` (via `labels.transpose_class`).

The frequency shift is **zero-fill**, NOT `np.roll`: rolling would wrap octave
energy around the edge (phantom energy from the opposite end of the spectrum).
Zero-fill leaves the vacated bins empty, which is the physically-honest thing for
a ± few-semitone shift where the true energy simply moved off one edge.

Pure NumPy, seedable, NO TensorFlow — runs anywhere.
"""
from __future__ import annotations

import numpy as np

try:  # imported as a package (chords.augment) -> relative
    from .labels import transpose_class
except ImportError:  # run as a script from inside ml/chords/
    from labels import transpose_class  # type: ignore

BINS_PER_SEMITONE = 2  # BINS_PER_OCTAVE(24) / 12 semitones


def _transpose_labels(Y: np.ndarray, k: int) -> np.ndarray:
    """Transpose a label array by `k` semitones (per-element majmin roll).

    Reuses `labels.transpose_class` (do NOT reinvent the class math): N.C. (0)
    is invariant; major/minor groups roll within themselves, mod 12."""
    Y = np.asarray(Y)
    flat = [transpose_class(int(c), int(k)) for c in Y.ravel().tolist()]
    return np.array(flat, dtype=Y.dtype).reshape(Y.shape)


def transpose_window(X: np.ndarray, Y: np.ndarray, k: int):
    """Transpose one window (X freq axis + Y labels) by `k` semitones.

    Args:
        X: (WIN, 144) CQT window (float); the LAST axis is log-frequency.
        Y: (WIN,) int labels in the 25-class majmin space.
        k: semitone shift (positive = up in pitch = towards higher bin indices).

    Returns:
        (X2, Y2): X frequency-shifted by `2*k` bins with zero-fill (no wrap),
        Y transposed by `k` semitones. Shapes/dtypes preserved.
    """
    X = np.asarray(X)
    shift = BINS_PER_SEMITONE * int(k)
    n_bins = X.shape[-1]
    X2 = np.zeros_like(X)
    if shift == 0:
        X2 = X.copy()
    elif shift > 0:                       # energy moves UP: low bins vacated -> 0
        if shift < n_bins:
            X2[..., shift:] = X[..., : n_bins - shift]
    else:                                 # energy moves DOWN: high bins vacated -> 0
        s = -shift
        if s < n_bins:
            X2[..., : n_bins - s] = X[..., s:]
    Y2 = _transpose_labels(Y, int(k))
    return X2, Y2


def augment_windows(X: np.ndarray, Y: np.ndarray, rng: np.random.Generator,
                    copies: int = 2, max_semi: int = 5):
    """Expand a window set with random ±semitone transpositions.

    For EACH base window keep the original, then append `copies` random DISTINCT
    non-zero transpositions drawn from [-max_semi, max_semi] \\ {0}. Deterministic
    given `rng`.

    Args:
        X: (N, WIN, 144) train windows.
        Y: (N, WIN) labels.
        rng: numpy Generator (seed it upstream for reproducibility).
        copies: transposed copies per base window (row count -> N*(1+copies)).
        max_semi: max |semitone| shift (±5 => ±10 bins, safe zero-fill range).

    Returns:
        (Xa, Ya): originals first (rows 0..N-1) then the transposed copies.
    """
    X = np.asarray(X)
    Y = np.asarray(Y)
    N = X.shape[0]
    choices = [k for k in range(-max_semi, max_semi + 1) if k != 0]
    if copies < 0:
        raise ValueError(f"copies must be >= 0, got {copies}")
    if copies > len(choices):
        raise ValueError(
            f"copies={copies} exceeds the {len(choices)} distinct non-zero "
            f"shifts available in [-{max_semi},{max_semi}]")
    if N == 0 or copies == 0:
        return X.copy(), Y.copy()

    Xs = [X]  # originals kept
    Ys = [Y]
    for i in range(N):
        ks = rng.choice(choices, size=copies, replace=False)
        for k in ks:
            X2, Y2 = transpose_window(X[i], Y[i], int(k))
            Xs.append(X2[None])
            Ys.append(Y2[None])
    Xa = np.concatenate(Xs, axis=0).astype(X.dtype)
    Ya = np.concatenate(Ys, axis=0).astype(Y.dtype)
    return Xa, Ya
