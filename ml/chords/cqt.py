"""Constant-Q transform (CQT) feature front-end for the ML CHORD track (P0.3).

The chord model (plan: docs/plans/ml-chord-track.md) consumes a CQT, NOT the
log-mel the strum model uses: chord identity is harmonic pitch content, and a
constant-Q spacing puts every octave the same number of bins apart so a chord
looks the same shape at any root (the ±semitone augmentation is then a plain
integer bin-roll). Parameters follow BTC (arXiv 1907.02698) / Korzeniowski &
Widmer 2016:

    SR = 22050 Hz, 24 bins/octave, 6 octaves from C1 (~32.703 Hz) = 144 bins,
    hop 2048 (~93 ms, = the existing chord hop).

Implementation = the standard **precomputed sparse spectral kernel** method
(Brown & Puckette 1992):

  1. For each CQT bin k build a complex temporal kernel — a Hann-windowed
     complex exponential of length N_k = ceil(Q * SR / f_k), centred in an
     FFT frame of length FFT_LEN (the next power of two >= the LONGEST kernel,
     i.e. the lowest bin). Q = 1 / (2^(1/bins_per_octave) - 1).
  2. FFT each temporal kernel ONCE into a spectral kernel row; conjugate,
     divide by FFT_LEN (Parseval), and zero entries below SPARSITY_THRESH of
     the peak magnitude -> a sparse (N_BINS, FFT_LEN) matrix.
  3. Per audio hop: take the FFT of the (zero-padded, centred) frame and
     matrix-multiply by the kernel; |result| is the CQT magnitude.

Post: **log-amplitude = log(1 + GAMMA*|CQT|)** (`np.log1p`). This maps silence
to exactly 0 (not a large negative floor), keeps everything >= 0, and needs no
eps. Per-bin normalization is intentionally left to the caller (train-only mean
/ std, exactly like the log-mel path in features.py + train.py).

Pure NumPy, deterministic. Matches the NumPy style of ml/features.py; the
`_resample` idiom matches prepare_dataset.py::_read_wav. A Dart `CqtExtractor`
must reproduce `cqt()` bit-for-parity against ml/chords/cqt_fixture.json — so
every constant that changes the numbers lives here as a named module constant.
"""
from __future__ import annotations

import numpy as np

# --- public constants (the Dart port and the exported model depend on these) --
SR = 22050
BINS_PER_OCTAVE = 24
N_OCTAVES = 6
N_BINS = BINS_PER_OCTAVE * N_OCTAVES          # 144
HOP = 2048                                    # ~93 ms @ 22.05 kHz
FMIN = 32.70319566257483                      # C1 (A4 = 440 Hz reference)

#: log-amplitude compression: out = log(1 + GAMMA*|CQT|).
GAMMA = 1.0
#: spectral-kernel sparsification: entries below this fraction of the global
#: peak |kernel| are set to 0. Documented so a Dart port matches exactly.
SPARSITY_THRESH = 0.01


def _q() -> float:
    """Constant-Q quality factor Q = 1 / (2^(1/bins_per_octave) - 1)."""
    return 1.0 / (2.0 ** (1.0 / BINS_PER_OCTAVE) - 1.0)


def _next_pow2(x: int) -> int:
    p = 1
    while p < x:
        p <<= 1
    return p


# The kernel is large (144 x FFT_LEN complex64) so build it lazily + cache it.
_KERNEL = None   # type: ignore  # (N_BINS, FFT_LEN) complex64, conjugated/scaled
_FFT_LEN = 0


def _build_kernel():
    """Precompute (and cache) the sparse spectral kernel + its FFT length."""
    global _KERNEL, _FFT_LEN
    if _KERNEL is not None:
        return _KERNEL, _FFT_LEN
    q = _q()
    n_lo = int(np.ceil(q * SR / FMIN))        # longest kernel = lowest bin
    fft_len = _next_pow2(n_lo)
    kernel = np.zeros((N_BINS, fft_len), dtype=np.complex128)
    for k in range(N_BINS):
        f_k = FMIN * 2.0 ** (k / BINS_PER_OCTAVE)
        n_k = int(np.ceil(q * SR / f_k))
        win = np.hanning(n_k)
        n = np.arange(n_k)
        temporal = (win / n_k) * np.exp(2j * np.pi * q * n / n_k)
        start = (fft_len - n_k) // 2          # centre the kernel in the frame
        tk = np.zeros(fft_len, dtype=np.complex128)
        tk[start:start + n_k] = temporal
        kernel[k] = np.fft.fft(tk)
    # sparsify (Brown-Puckette): drop the numerically negligible spectral tail
    kernel[np.abs(kernel) < SPARSITY_THRESH * np.abs(kernel).max()] = 0.0
    # conjugate + Parseval 1/N so cq[k] = <frame, temporal_k> exactly
    _KERNEL = (np.conj(kernel) / fft_len).astype(np.complex64)
    _FFT_LEN = fft_len
    return _KERNEL, _FFT_LEN


def _resample(pcm: np.ndarray, sr: int) -> np.ndarray:
    """Linear resample to SR (same simple idiom as prepare_dataset._read_wav).

    Linear interpolation is adequate for a feature front-end; the app captures
    at the model rate so this path is only hit for imported/off-rate files.
    """
    if sr == SR or len(pcm) == 0:
        return pcm
    n = int(round(len(pcm) * SR / sr))
    if n <= 0:
        return pcm[:0]
    return np.interp(
        np.linspace(0.0, len(pcm) - 1, n),
        np.arange(len(pcm)),
        pcm,
    ).astype(np.float32)


def n_frames(n_samples: int) -> int:
    """Number of CQT frames for `n_samples` input samples (centred hops).

    Frame i is centred at sample i*HOP; frames run while the centre is inside
    the signal -> ceil(n_samples / HOP). Any non-empty signal yields >= 1 frame
    (short input is zero-padded), and the count grows monotonically with length.
    """
    if n_samples <= 0:
        return 0
    return 1 + (n_samples - 1) // HOP


def cqt(pcm: np.ndarray, sr: int) -> np.ndarray:
    """Log-amplitude CQT of a mono [-1, 1] signal -> (n_frames, 144) float32.

    Frames are centred (zero-padded by FFT_LEN//2 each side), so a note near an
    onset is not truncated and even a short clip produces a frame. Empty input
    returns shape (0, 144). Resamples internally if `sr != SR`.
    """
    kernel, fft_len = _build_kernel()
    pcm = np.asarray(pcm, dtype=np.float32).ravel()
    pcm = _resample(pcm, sr)
    ns = len(pcm)
    if ns == 0:
        return np.zeros((0, N_BINS), dtype=np.float32)

    nf = n_frames(ns)
    pad = fft_len // 2
    padded = np.zeros(ns + 2 * pad, dtype=np.float32)
    padded[pad:pad + ns] = pcm

    frames = np.empty((nf, fft_len), dtype=np.float32)
    for i in range(nf):
        s = i * HOP
        frames[i] = padded[s:s + fft_len]

    spec = np.fft.fft(frames, axis=1)             # (nf, fft_len) complex
    cq = spec @ kernel.T                           # (nf, N_BINS) complex
    mag = np.abs(cq).astype(np.float32)
    return np.log1p(GAMMA * mag).astype(np.float32)
