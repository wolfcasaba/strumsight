"""r173 audio augmentation for the strum-direction CRNN (RAG chunk 018).

Every transform operates on the raw PCM signal BEFORE log-mel, so the
augmentation is realistic (a pitch-shifted / reverberant / band-limited take
looks to the model like a genuinely different guitar+room+phone, not a
post-hoc spectrogram edit). Pure NumPy — runs on the ARM64 box, no scipy /
librosa (neither is in tf-venv).

Why these transforms (research chunk 018 / ml-research-2026-07-13):
  * pitch-shift ±6 semitones is the Murgul et al. (ISMIR-2025, arXiv:2508.07973)
    ablation OPTIMUM — ±3 st was weaker, ±12 st hurt. It is the single biggest
    lever for the new-player (leave-one-guitarist-out) gap.
  * additive noise + gain variation → phone-mic level / room-noise robustness.
  * RIR / reverb convolution → different rooms.
  * mic simulation (EQ tilt + band-limiting) → different phone microphones.

Direction labels are INVARIANT to all of these (pitch/EQ/noise/room do not turn
a down-stroke into an up-stroke). Pitch-shift is implemented as varispeed, which
changes duration, so it RESCALES onset times (t -> t / factor); the composed
`augment_pcm` returns the rescaled onsets. Augment TRAIN folds ONLY — never
val/test (leakage). See honest_eval.py::section_logo_aug.
"""
from __future__ import annotations

import numpy as np

import features as F


# ---------------------------------------------------------------------------
# Individual transforms
# ---------------------------------------------------------------------------
def pitch_shift(pcm, semitones, sr=F.SR):
    """Varispeed pitch-shift by `semitones`. Returns (aug_pcm, factor).

    factor f = 2**(semitones/12): the signal is resampled to length len/f, so a
    higher pitch (f>1) also compresses time. An onset at time t in the ORIGINAL
    maps to t / f in the output — the caller must rescale label times by f.
    (True time-preserving pitch-shift needs a phase vocoder; varispeed is the
    honest pure-NumPy option and keeps up/down direction intact.)
    """
    pcm = np.asarray(pcm, dtype=np.float32)
    f = 2.0 ** (float(semitones) / 12.0)
    n_out = max(1, int(round(len(pcm) / f)))
    if len(pcm) < 2 or n_out < 2:
        return pcm.copy(), f
    idx = np.linspace(0.0, len(pcm) - 1, n_out)
    out = np.interp(idx, np.arange(len(pcm)), pcm).astype(np.float32)
    return out, f


def add_noise(pcm, snr_db, rng):
    """Add white Gaussian noise at the given signal-to-noise ratio (dB)."""
    pcm = np.asarray(pcm, dtype=np.float32)
    sig_rms = float(np.sqrt(np.mean(pcm ** 2))) + 1e-12
    noise_rms = sig_rms / (10.0 ** (float(snr_db) / 20.0))
    noise = rng.standard_normal(len(pcm)).astype(np.float32) * noise_rms
    return (pcm + noise).astype(np.float32)


def gain(pcm, gain_db):
    """Scale amplitude by `gain_db` decibels (a global log-mel offset)."""
    return (np.asarray(pcm, dtype=np.float32)
            * np.float32(10.0 ** (float(gain_db) / 20.0)))


def synth_rir(sr=F.SR, decay_s=0.25, direct=1.0, wet=0.3, rng=None):
    """A tiny synthetic room impulse response: a unit direct path at index 0
    plus an exponentially-decaying noise tail scaled to `wet` RMS. Convolving
    with this adds room reflections WITHOUT pre-delaying the onset (the direct
    path stays at t=0)."""
    rng = np.random.default_rng(0) if rng is None else rng
    n = max(1, int(decay_s * sr))
    t = np.arange(n) / sr
    tail = (rng.standard_normal(n).astype(np.float32)
            * np.exp(-t / (decay_s / 3.0 + 1e-9)).astype(np.float32))
    tail[0] = 0.0  # the tail must not touch the direct path sample
    tail_rms = float(np.sqrt(np.mean(tail ** 2))) + 1e-12
    rir = tail * np.float32(wet / tail_rms)
    rir[0] = np.float32(direct)
    return rir.astype(np.float32)


def reverb(pcm, rir):
    """Convolve `pcm` with `rir`, truncated to the input length. The RIR's
    direct path at index 0 keeps the onset aligned (no pre-delay)."""
    pcm = np.asarray(pcm, dtype=np.float32)
    wet = np.convolve(pcm, np.asarray(rir, dtype=np.float32))[: len(pcm)]
    return wet.astype(np.float32)


def mic_sim(pcm, rng, sr=F.SR, tilt_db=None, hp_hz=None, lp_hz=None):
    """Simulate a different phone microphone: a random spectral tilt plus a
    soft high-pass + low-pass band-limit, applied in the frequency domain.

    tilt_db: dB change per octave relative to 1 kHz (+ = brighter).
    hp_hz / lp_hz: first-order-style corner frequencies of the band-limit.
    All default to random draws (the training use); pass explicit values in
    tests for a deterministic response.
    """
    pcm = np.asarray(pcm, dtype=np.float32)
    n = len(pcm)
    if n < 2:
        return pcm.copy()
    tilt_db = rng.uniform(-6.0, 6.0) if tilt_db is None else float(tilt_db)
    hp_hz = rng.uniform(40.0, 120.0) if hp_hz is None else float(hp_hz)
    lp_hz = rng.uniform(5500.0, 7500.0) if lp_hz is None else float(lp_hz)

    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    spec = np.fft.rfft(pcm)
    # EQ tilt: linear in dB across log-frequency, clamped so extreme octaves
    # (DC, near-Nyquist) cannot explode.
    octaves = np.log2((freqs + 1e-6) / 1000.0)
    octaves = np.clip(octaves, -4.0, 3.5)
    tilt = 10.0 ** ((tilt_db * octaves) / 20.0)
    # Second-order high-pass and low-pass magnitude responses (steeper, more
    # like a real phone mic's band-limit than a first-order slope).
    hp = (freqs ** 2) / (freqs ** 2 + hp_hz ** 2)
    lp = (lp_hz ** 2) / (freqs ** 2 + lp_hz ** 2)
    resp = np.clip(tilt * hp * lp, 0.0, 8.0).astype(np.float32)
    out = np.fft.irfft(spec * resp, n=n).astype(np.float32)
    return out


# ---------------------------------------------------------------------------
# Composed augmentor — one stochastic take per call
# ---------------------------------------------------------------------------
def augment_pcm(pcm, onsets_s, rng, semitone_range=6.0):
    """One randomly-augmented copy of a recording. Returns (aug_pcm, onsets_s).

    Composition (per the chunk-018 recipe): always pitch-shift within
    ±`semitone_range` (the Murgul optimum) and apply a small gain; probabilistic
    reverb / mic-sim / additive-noise. Only pitch-shift moves the onset times,
    which are returned rescaled. Deterministic for a given rng state.
    """
    pcm = np.asarray(pcm, dtype=np.float32)
    onsets = np.asarray(onsets_s, dtype=np.float64).copy()

    st = rng.uniform(-semitone_range, semitone_range)
    out, f = pitch_shift(pcm, st)
    onsets = onsets / f

    if rng.random() < 0.6:
        out = reverb(out, synth_rir(decay_s=rng.uniform(0.12, 0.40),
                                    wet=rng.uniform(0.12, 0.40), rng=rng))
    if rng.random() < 0.7:
        out = mic_sim(out, rng)
    out = gain(out, rng.uniform(-6.0, 6.0))
    if rng.random() < 0.6:
        out = add_noise(out, rng.uniform(15.0, 35.0), rng)
    return out.astype(np.float32), onsets
