"""Feature extraction + IMU auto-labeling for the StrumSight strum-direction
CRNN (RAG chunk 015/018). Pure NumPy so the data pipeline is verifiable without
TensorFlow (the model/export step lives in train.py and needs TF).

The log-mel parameters MATCH the on-device intent (16 kHz, 2048 win / 160 hop =
10 ms frames, mel from 30 Hz) so features computed here are the same class the
Dart inference path will feed the model. Keep this file and chunk 018 in sync.
"""
from __future__ import annotations

import numpy as np

SR = 16000
N_FFT = 2048
HOP = 160          # 10 ms @ 16 kHz
N_MELS = 128
FMIN = 30.0
FMAX = SR / 2


def _hz_to_mel(f):
    return 2595.0 * np.log10(1.0 + f / 700.0)


def _mel_to_hz(m):
    return 700.0 * (10.0 ** (m / 2595.0) - 1.0)


def mel_filterbank(sr=SR, n_fft=N_FFT, n_mels=N_MELS, fmin=FMIN, fmax=FMAX):
    """A (n_mels, n_fft//2+1) triangular HTK-mel filterbank."""
    n_bins = n_fft // 2 + 1
    fft_freqs = np.linspace(0, sr / 2, n_bins)
    mel_pts = np.linspace(_hz_to_mel(fmin), _hz_to_mel(fmax), n_mels + 2)
    hz_pts = _mel_to_hz(mel_pts)
    fb = np.zeros((n_mels, n_bins), dtype=np.float32)
    for m in range(1, n_mels + 1):
        lo, ce, hi = hz_pts[m - 1], hz_pts[m], hz_pts[m + 1]
        for k in range(n_bins):
            f = fft_freqs[k]
            if lo <= f <= ce and ce > lo:
                fb[m - 1, k] = (f - lo) / (ce - lo)
            elif ce < f <= hi and hi > ce:
                fb[m - 1, k] = (hi - f) / (hi - ce)
    return fb


_FB = mel_filterbank()
_WIN = np.hanning(N_FFT).astype(np.float32)


def log_mel(pcm, sr=SR):
    """(n_frames, N_MELS) log-mel spectrogram of a mono [-1,1] signal."""
    pcm = np.asarray(pcm, dtype=np.float32)
    if sr != SR:
        raise ValueError(f"expected {SR} Hz, got {sr} — resample first")
    n = 1 + max(0, (len(pcm) - N_FFT) // HOP)
    out = np.empty((n, N_MELS), dtype=np.float32)
    for i in range(n):
        frame = pcm[i * HOP: i * HOP + N_FFT] * _WIN
        mag = np.abs(np.fft.rfft(frame))
        mel = _FB @ (mag * mag)
        out[i] = np.log(mel + 1e-6)
    return out


def spectral_flux_onsets(pcm, sr=SR, delta=0.15, min_gap_s=0.06):
    """Rough onset times (s) via half-wave-rectified spectral flux + threshold.
    Used only to align labels to attacks; the on-device detector is authoritative.
    """
    pcm = np.asarray(pcm, dtype=np.float32)
    n = 1 + max(0, (len(pcm) - N_FFT) // HOP)
    prev = None
    flux = np.zeros(n, dtype=np.float32)
    for i in range(n):
        frame = pcm[i * HOP: i * HOP + N_FFT] * _WIN
        mag = np.abs(np.fft.rfft(frame))
        if prev is not None:
            flux[i] = np.sum(np.maximum(0.0, mag - prev))
        prev = mag
    if flux.max() > 0:
        flux = flux / flux.max()
    onsets = []
    min_gap = int(min_gap_s * sr / HOP)
    last = -min_gap
    for i in range(1, n - 1):
        if (flux[i] > delta and flux[i] >= flux[i - 1] and flux[i] >= flux[i + 1]
                and i - last >= min_gap):
            onsets.append(i * HOP / sr)
            last = i
    return onsets


def label_direction_from_accel(accel_t, accel_axis, onset_s, win_s=0.12):
    """Auto-label ONE onset as down/up from a wrist-IMU axis (chunk 015).

    The strumming hand's dominant axis swings one way for a down-stroke and the
    opposite for an up-stroke. We take the mean of the axis over a short window
    starting at the onset: sign > 0 → 'down', < 0 → 'up' (the physical polarity
    is fixed per rig at collection time — flip `accel_axis` if your mounting is
    reversed). Returns 'down' | 'up' | None (ambiguous / no motion).
    """
    accel_t = np.asarray(accel_t, dtype=np.float64)
    accel_axis = np.asarray(accel_axis, dtype=np.float64)
    m = (accel_t >= onset_s) & (accel_t < onset_s + win_s)
    if not np.any(m):
        return None
    v = float(np.mean(accel_axis[m]))
    if abs(v) < 1e-3:
        return None
    return "down" if v > 0 else "up"


# Fixed-length model input window around an onset (frames of log-mel).
PRE_FRAMES = 3    # 30 ms before the attack
POST_FRAMES = 12  # 120 ms after — the attack + early decay


def window_at(logmel, onset_s, sr=SR):
    """The (PRE+POST, N_MELS) log-mel window centred on an onset, zero-padded."""
    center = int(round(onset_s * sr / HOP))
    lo, hi = center - PRE_FRAMES, center + POST_FRAMES
    out = np.zeros((PRE_FRAMES + POST_FRAMES, N_MELS), dtype=np.float32)
    src_lo, src_hi = max(0, lo), min(len(logmel), hi)
    if src_hi > src_lo:
        out[src_lo - lo: src_hi - lo] = logmel[src_lo:src_hi]
    return out
