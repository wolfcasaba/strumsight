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


# ---------------------------------------------------------------------------
# E14-R19 (ADR 0525): seeded, manifested, switchable augmentation.
#
# Everything below is ADDITIVE — `augment_pcm` above and every transform it
# calls (pitch_shift/add_noise/gain/synth_rir/reverb/mic_sim) stay byte-for-
# byte unchanged (round §9 regression). The new pieces are:
#   1. a WHOLE-semitone, label-transposing pitch-shift path (D1/D2/D3) that
#      reuses the ALREADY-MERGED chord-class math from `chords.labels`
#      (D10) instead of reimplementing it;
#   2. the missing transforms named in the round brief (device response,
#      compression, traffic/ambient noise, fret/pick/tap transient bursts);
#   3. a config-driven composed augmentor where every transform has an
#      `enabled` switch, and switching all of them off reproduces the input
#      bit-for-bit (D4);
#   4. a class-balancing helper that only weights/resamples, never drops a
#      real row (D8); and
#   5. a manifest builder + validator for the contract in D5/D6.
# ---------------------------------------------------------------------------
try:  # imported as part of the `ml` tree -> plain sibling-package import
    from chords.labels import NO_CHORD, transpose_class
except ImportError:  # pragma: no cover - script-mode fallback, mirrors
    # chords/augment.py's own fallback for the same reason (run directly
    # from inside ml/ without ml/ itself on sys.path).
    import os
    import sys

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from chords.labels import NO_CHORD, transpose_class  # type: ignore

#: The PCM/varispeed pitch-shift range (ISMIR-2025 Murgul et al. ablation
#: optimum, arXiv:2508.07973 — same source `augment_pcm` above already
#: cites). This is a DIFFERENT constraint, in a DIFFERENT domain, from the
#: CQT/chord-track zero-fill limit `chords.augment.augment_windows`'s
#: `max_semi=5` default: that one exists so a zero-filled frequency-axis
#: shift never runs off both edges of the 144-bin CQT window. Conflating the
#: two limits is a MAJOR-lelet-class mistake (round brief R11) — the
#: manifest (see `PITCH_SHIFT_LIMITS` below) records both, explicitly
#: labelled by domain, so the two never get merged into one number.
LABEL_TRANSPOSE_SEMITONE_RANGE = 6

#: Recorded verbatim in every generated manifest (`build_manifest`) so a
#: reader never has to infer which limit governs which augmentation path.
PITCH_SHIFT_LIMITS = {
    "pcmVarispeedMaxSemitones": LABEL_TRANSPOSE_SEMITONE_RANGE,
    "pcmVarispeedSource": (
        "ISMIR-2025 Murgul et al. ablation optimum (arXiv:2508.07973)"
    ),
    "cqtChordTrackMaxSemitones": 5,
    "cqtChordTrackSource": (
        "ml/chords/augment.py::augment_windows default max_semi — the safe "
        "zero-fill range for the 144-bin CQT frequency axis, a different "
        "domain and a different constraint from the PCM/varispeed limit "
        "above (round brief R11)"
    ),
}


def _validate_whole_semitone(semitones, max_range=LABEL_TRANSPOSE_SEMITONE_RANGE):
    """Validate a chord-label-transposing semitone shift (ADR 0525 D2/D3).

    A fractional value is a TypeError — it is NEVER silently rounded, because
    rounding would make the manifest lie about what the audio actually did.
    A whole value outside `[-max_range, max_range]` is a ValueError; the
    boundary itself (`|semitones| == max_range`) is ACCEPTED (inclusive).
    """
    if isinstance(semitones, bool):
        raise TypeError(f"semitones must be a whole number, got bool {semitones!r}")
    if isinstance(semitones, (int, np.integer)):
        value = int(semitones)
    elif isinstance(semitones, (float, np.floating)) and float(semitones).is_integer():
        value = int(semitones)
    else:
        raise TypeError(
            f"semitones must be a whole number for the label-transposing "
            f"pitch-shift path — got {semitones!r} (a fractional shift has "
            f"no chord-class name and is never silently rounded, ADR 0525 D2)"
        )
    if abs(value) > max_range:
        raise ValueError(
            f"semitones={value} exceeds the inclusive range "
            f"[-{max_range}, {max_range}] (ADR 0525 D3)"
        )
    return value


def transpose_pcm_and_chord_labels(pcm, onsets_s, chord_classes, semitones,
                                   semitone_range=LABEL_TRANSPOSE_SEMITONE_RANGE):
    """Whole-semitone varispeed pitch-shift that also transposes chord labels.

    The additive, label-aware counterpart to `pitch_shift`/`augment_pcm`
    above (which stay direction-only and byte-for-byte unchanged, §9). Reuses
    `chords.labels.transpose_class` for the class arithmetic (ADR 0525 D10) —
    this module does not reimplement it. `chord_classes` is an array-like of
    majmin class indices (0..24) parallel to `onsets_s`; N.C. (0) is
    invariant, matching `transpose_class`'s own contract.

    Returns (aug_pcm, onsets_s, chord_classes) with the pitch-shift's varispeed
    factor already applied to the onset times (t -> t / f, same convention as
    `pitch_shift`).
    """
    st = _validate_whole_semitone(semitones, semitone_range)
    pcm = np.asarray(pcm, dtype=np.float32)
    onsets = np.asarray(onsets_s, dtype=np.float64).copy()
    classes = np.asarray(chord_classes)

    out, f = pitch_shift(pcm, float(st))
    onsets = onsets / f
    transposed = np.array(
        [transpose_class(int(c), st) for c in classes.ravel().tolist()],
        dtype=classes.dtype,
    ).reshape(classes.shape)
    return out.astype(np.float32), onsets, transposed


def random_label_transposing_shift(pcm, onsets_s, chord_classes, rng,
                                   semitone_range=LABEL_TRANSPOSE_SEMITONE_RANGE):
    """Stochastic wrapper: draw a whole semitone shift from `rng` and apply
    `transpose_pcm_and_chord_labels`. Deterministic for a given rng state."""
    st = int(rng.integers(-semitone_range, semitone_range + 1))
    return transpose_pcm_and_chord_labels(pcm, onsets_s, chord_classes, st,
                                          semitone_range=semitone_range)


# --- The missing transforms named in the round brief §1 --------------------

#: A small table of canonical device frequency-response curves, distinct from
#: `mic_sim`'s continuous random draw: these are named, reusable "devices" a
#: manifest can cite by name. Reuses `mic_sim` for the actual filtering (no
#: duplicated DSP) — "device response" is a curated PARAMETER SET, not a new
#: algorithm.
DEVICE_PROFILES = {
    "phone_a": {"tilt_db": -3.0, "hp_hz": 80.0, "lp_hz": 6500.0},
    "phone_b": {"tilt_db": 4.0, "hp_hz": 120.0, "lp_hz": 5800.0},
    "tablet_a": {"tilt_db": 1.0, "hp_hz": 60.0, "lp_hz": 7200.0},
}


def device_response(pcm, rng, sr=F.SR, profile=None):
    """Apply a named device frequency-response curve (see `DEVICE_PROFILES`).

    `profile=None` draws a random profile name from `rng` (deterministic for
    a given rng state); passing an explicit name is deterministic outright
    (used in tests). Returns (aug_pcm, profile_name)."""
    name = profile if profile is not None else rng.choice(list(DEVICE_PROFILES))
    params = DEVICE_PROFILES[str(name)]
    return mic_sim(pcm, rng, sr=sr, **params), str(name)


def compress(pcm, threshold_db=-18.0, ratio=3.0, makeup_db=0.0):
    """A simple feed-forward RMS-envelope compressor (deterministic — no rng;
    the composed augmentor draws `threshold_db`/`ratio` from its own rng).

    Samples above `threshold_db` (relative to a short RMS envelope) are
    attenuated by `ratio`:1; `makeup_db` restores overall level afterwards.
    """
    pcm = np.asarray(pcm, dtype=np.float32)
    if len(pcm) == 0:
        return pcm.copy()
    win = max(1, int(0.005 * F.SR))  # ~5 ms envelope
    kernel = np.ones(win, dtype=np.float32) / win
    env = np.sqrt(np.convolve(pcm ** 2, kernel, mode="same") + 1e-12).astype(np.float32)
    env_db = 20.0 * np.log10(env + 1e-12)
    over_db = np.clip(env_db - threshold_db, 0.0, None)
    gain_db = -over_db * (1.0 - 1.0 / ratio) + makeup_db
    gain_lin = (10.0 ** (gain_db / 20.0)).astype(np.float32)
    return (pcm * gain_lin).astype(np.float32)


def traffic_noise(pcm, snr_db, rng):
    """Add low-frequency-emphasized ("traffic"/ambient-hum-like) noise at a
    target SNR — distinct from `add_noise`'s flat white-noise spectrum.
    Deterministic given `rng`."""
    pcm = np.asarray(pcm, dtype=np.float32)
    n = len(pcm)
    if n < 2:
        return pcm.copy()
    white = rng.standard_normal(n).astype(np.float32)
    freqs = np.fft.rfftfreq(n, 1.0 / F.SR)
    shaping = 1.0 / np.sqrt(np.maximum(freqs, 1.0))  # 1/f-ish -> low-freq heavy
    colored = np.fft.irfft(np.fft.rfft(white) * shaping, n=n).astype(np.float32)
    colored_rms = float(np.sqrt(np.mean(colored ** 2))) + 1e-12
    sig_rms = float(np.sqrt(np.mean(pcm ** 2))) + 1e-12
    noise_rms = sig_rms / (10.0 ** (float(snr_db) / 20.0))
    return (pcm + colored * (noise_rms / colored_rms)).astype(np.float32)


def transient_burst(pcm, rng, sr=F.SR, n_bursts=2, dur_s=0.015,
                    amp_range=(0.05, 0.3)):
    """Add `n_bursts` short decaying noise bursts (fret-buzz / pick-click /
    tap-noise proxies) at random, non-overlapping times. Deterministic given
    `rng`; a burst is additive so it never shortens/lengthens the signal."""
    pcm = np.asarray(pcm, dtype=np.float32).copy()
    n = len(pcm)
    length = max(1, int(dur_s * sr))
    if n <= length or n_bursts <= 0:
        return pcm
    sig_rms = float(np.sqrt(np.mean(pcm ** 2))) + 1e-12
    env = np.exp(-np.arange(length) / (length / 6.0 + 1e-9)).astype(np.float32)
    for _ in range(n_bursts):
        start = int(rng.integers(0, n - length))
        burst = rng.standard_normal(length).astype(np.float32) * env
        burst_rms = float(np.sqrt(np.mean(burst ** 2))) + 1e-12
        amp = float(rng.uniform(*amp_range))
        pcm[start:start + length] += burst * (amp * sig_rms / burst_rms)
    return pcm.astype(np.float32)


# --- Config-driven, switchable composition (ADR 0525 D4) --------------------

#: Every transform has an `enabled` switch. With every switch False, the
#: composed functions below return the raw input bit-for-bit (D4) — no
#: transform is called, and no rng draw happens, when its switch is off.
DEFAULT_TRANSFORM_CONFIG = {
    "pitch_shift": {"enabled": True, "semitone_range": 6.0},
    "reverb": {"enabled": True, "prob": 0.6,
              "decay_s_range": (0.12, 0.40), "wet_range": (0.12, 0.40)},
    "device_response": {"enabled": False},
    "mic_sim": {"enabled": True, "prob": 0.7},
    "gain": {"enabled": True, "gain_db_range": (-6.0, 6.0)},
    "compression": {"enabled": False, "threshold_db_range": (-24.0, -12.0),
                    "ratio_range": (2.0, 4.0)},
    "add_noise": {"enabled": True, "prob": 0.6, "snr_db_range": (15.0, 35.0)},
    "traffic_noise": {"enabled": False, "prob": 0.5, "snr_db_range": (10.0, 25.0)},
    "transient_burst": {"enabled": False, "n_bursts": 2, "dur_s": 0.015,
                        "amp_range": (0.05, 0.3)},
}


def _merged_config(config):
    merged = {name: dict(cfg) for name, cfg in DEFAULT_TRANSFORM_CONFIG.items()}
    for name, overrides in (config or {}).items():
        if name not in merged:
            raise KeyError(f"unknown transform in config: {name!r}")
        merged[name].update(overrides)
    return merged


def _apply_secondary_transforms(out, rng, cfg):
    """Reverb / device-or-mic / gain / compression / noise / bursts — the
    part of the recipe SHARED between the direction-only and the label-
    transposing composed augmentors below, so the two paths cannot silently
    drift apart (the bit-identical-when-disabled guarantee, D4, must hold
    identically for both)."""
    if cfg["reverb"]["enabled"] and rng.random() < cfg["reverb"]["prob"]:
        lo, hi = cfg["reverb"]["decay_s_range"]
        wlo, whi = cfg["reverb"]["wet_range"]
        out = reverb(out, synth_rir(decay_s=rng.uniform(lo, hi),
                                    wet=rng.uniform(wlo, whi), rng=rng))
    if cfg["device_response"]["enabled"]:
        out, _name = device_response(out, rng)
    elif cfg["mic_sim"]["enabled"] and rng.random() < cfg["mic_sim"]["prob"]:
        out = mic_sim(out, rng)
    if cfg["gain"]["enabled"]:
        lo, hi = cfg["gain"]["gain_db_range"]
        out = gain(out, rng.uniform(lo, hi))
    if cfg["compression"]["enabled"]:
        tlo, thi = cfg["compression"]["threshold_db_range"]
        rlo, rhi = cfg["compression"]["ratio_range"]
        out = compress(out, threshold_db=rng.uniform(tlo, thi),
                       ratio=rng.uniform(rlo, rhi))
    if cfg["traffic_noise"]["enabled"] and rng.random() < cfg["traffic_noise"]["prob"]:
        lo, hi = cfg["traffic_noise"]["snr_db_range"]
        out = traffic_noise(out, rng.uniform(lo, hi), rng)
    elif cfg["add_noise"]["enabled"] and rng.random() < cfg["add_noise"]["prob"]:
        lo, hi = cfg["add_noise"]["snr_db_range"]
        out = add_noise(out, rng.uniform(lo, hi), rng)
    if cfg["transient_burst"]["enabled"]:
        tb = cfg["transient_burst"]
        out = transient_burst(out, rng, n_bursts=tb["n_bursts"],
                              dur_s=tb["dur_s"], amp_range=tb["amp_range"])
    return out


def augment_pcm_configurable(pcm, onsets_s, rng, config=None):
    """Direction-only composed augmentor with per-transform `enabled`
    switches (ADR 0525 D4). Uses the CONTINUOUS pitch-shift (like
    `augment_pcm`) since direction labels are pitch-invariant. With every
    switch in `config` False, returns `(pcm, onsets_s)` bit-for-bit."""
    cfg = _merged_config(config)
    pcm = np.asarray(pcm, dtype=np.float32)
    onsets = np.asarray(onsets_s, dtype=np.float64).copy()
    out = pcm

    if cfg["pitch_shift"]["enabled"]:
        st = rng.uniform(-cfg["pitch_shift"]["semitone_range"],
                         cfg["pitch_shift"]["semitone_range"])
        out, f = pitch_shift(out, st)
        onsets = onsets / f

    out = _apply_secondary_transforms(out, rng, cfg)
    return out.astype(np.float32), onsets


def augment_pcm_with_chord_labels(pcm, onsets_s, chord_classes, rng, config=None):
    """Label-transposing composed augmentor (ADR 0525 D1): identical secondary
    recipe to `augment_pcm_configurable`, but the pitch-shift step is the
    WHOLE-semitone, chord-label-transposing path when `pitch_shift` is
    enabled. With every switch False, returns
    `(pcm, onsets_s, chord_classes)` bit-for-bit."""
    cfg = _merged_config(config)
    pcm = np.asarray(pcm, dtype=np.float32)
    onsets = np.asarray(onsets_s, dtype=np.float64).copy()
    classes = np.asarray(chord_classes)
    out = pcm

    if cfg["pitch_shift"]["enabled"]:
        semitone_range = int(cfg["pitch_shift"]["semitone_range"])
        out, onsets, classes = random_label_transposing_shift(
            out, onsets, classes, rng, semitone_range=semitone_range)

    out = _apply_secondary_transforms(out, rng, cfg)
    return out.astype(np.float32), onsets, classes


# --- Class balancing (ADR 0525 D8: weight/resample, never drop real data) --

def balance_indices(labels, rng):
    """Indices into `labels` that upsample every class to the size of the
    LARGEST class, without ever dropping an original index (ADR 0525 D8).

    Every index `0..len(labels)-1` appears at least once in the result;
    minority classes get additional, randomly-drawn-with-replacement repeats
    so every class reaches the majority class's count. Deterministic given
    `rng`."""
    labels = np.asarray(labels)
    n = len(labels)
    if n == 0:
        return np.zeros(0, dtype=int)
    classes, counts = np.unique(labels, return_counts=True)
    target = int(counts.max())
    parts = []
    for cls, count in zip(classes, counts):
        idx = np.flatnonzero(labels == cls)
        parts.append(idx)
        deficit = target - int(count)
        if deficit > 0:
            parts.append(rng.choice(idx, size=deficit, replace=True))
    result = np.concatenate(parts)
    rng.shuffle(result)
    return result


def class_ratios(labels):
    """{class -> fraction of rows} for an array-like of class labels."""
    labels = np.asarray(labels)
    n = len(labels)
    if n == 0:
        return {}
    classes, counts = np.unique(labels, return_counts=True)
    return {str(c): float(count) / n for c, count in zip(classes, counts)}


# --- Manifest contract (ADR 0525 D5/D6) -------------------------------------

_REQUIRED_TRANSFORM_FIELDS = {
    "name", "enabled", "params", "status", "measured", "reproCommand",
    "measuredCostSeconds",
}
_VALID_STATUSES = {"accepted", "candidate", "rejected"}
_NOT_MEASURED = "nem mért"


def _splits_of(measured):
    if not isinstance(measured, dict):
        return []
    splits = []
    for key in ("unseenPlayerSplits", "unseenDeviceSplits"):
        value = measured.get(key)
        if isinstance(value, list):
            splits.extend(value)
    return splits


def _validate_ratio_group(manifest, group_name):
    class_ratios_field = manifest.get("classRatios")
    if not isinstance(class_ratios_field, dict) or group_name not in class_ratios_field:
        raise TypeError(f"manifest.classRatios missing required group: {group_name!r}")
    group = class_ratios_field[group_name]
    if not isinstance(group, dict):
        raise TypeError(f"manifest.classRatios.{group_name} must be an object")
    for phase in ("baseline", "balanced"):
        if phase not in group:
            raise TypeError(
                f"manifest.classRatios.{group_name} missing required phase: {phase!r}")
        ratios = group[phase]
        if not isinstance(ratios, dict) or not ratios:
            raise TypeError(
                f"manifest.classRatios.{group_name}.{phase} must be a non-empty object")
        total = sum(float(v) for v in ratios.values())
        if abs(total - 1.0) > 1e-6:
            raise ValueError(
                f"manifest.classRatios.{group_name}.{phase} ratios must sum to "
                f"1.0, got {total}")


def validate_manifest(manifest):
    """Validate the augmentation manifest contract (ADR 0525 D5/D6/D8).

    Raises TypeError/ValueError (never returns a boolean a caller could
    silently ignore, fail-closed) on: a missing required field, an unknown
    `status`, a numeric `0` standing in for a missing measurement, an
    `"accepted"` status paired with `measured == "nem mért"`, an `"accepted"`
    status whose measured splits do not actually show an improvement, or
    `balancing.dropsRealData` not being `False`.
    """
    if not isinstance(manifest, dict):
        raise TypeError("manifest must be an object")

    if "seed" not in manifest:
        raise TypeError("manifest missing required field: seed")
    if isinstance(manifest["seed"], bool) or not isinstance(manifest["seed"], int):
        raise TypeError("manifest.seed must be an int")

    transforms = manifest.get("transforms")
    if not isinstance(transforms, list) or not transforms:
        raise TypeError("manifest missing required non-empty field: transforms")

    for i, t in enumerate(transforms):
        if not isinstance(t, dict):
            raise TypeError(f"transforms[{i}] must be an object")
        missing = _REQUIRED_TRANSFORM_FIELDS - set(t)
        if missing:
            raise TypeError(
                f"transforms[{i}] ({t.get('name')!r}) missing required "
                f"field(s): {sorted(missing)}")
        if not isinstance(t["name"], str) or not t["name"]:
            raise TypeError(f"transforms[{i}].name must be a non-empty string")
        if not isinstance(t["enabled"], bool):
            raise TypeError(f"transforms[{i}].name={t['name']!r}.enabled must be a bool")
        if not isinstance(t["params"], dict):
            raise TypeError(f"transforms[{i}].name={t['name']!r}.params must be an object")
        status = t["status"]
        if status not in _VALID_STATUSES:
            raise ValueError(
                f"transforms[{i}].name={t['name']!r}.status must be one of "
                f"{sorted(_VALID_STATUSES)}, got {status!r}")

        measured = t["measured"]
        if isinstance(measured, (int, float)) and not isinstance(measured, bool):
            raise TypeError(
                f"transforms[{i}].name={t['name']!r}.measured must never be a "
                f"bare number (a missing measurement is the literal "
                f"{_NOT_MEASURED!r}, never numeric 0, ADR 0525 D6) — got "
                f"{measured!r}")

        cost = t["measuredCostSeconds"]
        if not isinstance(cost, (int, float)) or isinstance(cost, bool):
            raise TypeError(
                f"transforms[{i}].name={t['name']!r}.measuredCostSeconds must "
                f"be a number (ADR 0525 D6: a 'nem mért' row still carries its "
                f"measured cost)")
        if not isinstance(t["reproCommand"], str) or not t["reproCommand"]:
            raise TypeError(
                f"transforms[{i}].name={t['name']!r}.reproCommand must be a "
                f"non-empty string")

        if measured == _NOT_MEASURED:
            if status == "accepted":
                raise ValueError(
                    f"transforms[{i}].name={t['name']!r} status='accepted' "
                    f"but measured=={_NOT_MEASURED!r} — ADR 0525 D6 forbids "
                    f"accepting an unmeasured transform")
        elif isinstance(measured, dict):
            splits = _splits_of(measured)
            if not splits:
                raise TypeError(
                    f"transforms[{i}].name={t['name']!r} has a measured "
                    f"object but no unseenPlayerSplits/unseenDeviceSplits")
            for split in splits:
                baseline = split.get("baseline")
                treated = split.get("treated")
                delta = split.get("delta")
                if not all(isinstance(v, (int, float)) and not isinstance(v, bool)
                          for v in (baseline, treated, delta)):
                    raise TypeError(
                        f"transforms[{i}].name={t['name']!r} every split needs "
                        f"numeric baseline/treated/delta")
                if abs((treated - baseline) - delta) > 1e-6:
                    raise ValueError(
                        f"transforms[{i}].name={t['name']!r} split "
                        f"{split.get('split')!r}: delta must equal "
                        f"treated - baseline ({treated - baseline}), got {delta}")
            improves = any(s["delta"] > 0 for s in splits)
            degrades_beyond_error = any(
                s["delta"] < 0 and abs(s["delta"]) >
                (s.get("baselineStdDev", 0.0) + s.get("treatedStdDev", 0.0))
                for s in splits
            )
            if status == "accepted" and (not improves or degrades_beyond_error):
                raise ValueError(
                    f"transforms[{i}].name={t['name']!r} status='accepted' "
                    f"requires at least one improving split and no split "
                    f"degrading beyond its reported error bar (ADR 0525 D6)")
            if status == "rejected" and improves and not degrades_beyond_error:
                raise ValueError(
                    f"transforms[{i}].name={t['name']!r} status='rejected' "
                    f"but the measured splits show a clean improvement — "
                    f"should not be 'rejected' (ADR 0525 D6)")
        else:
            raise TypeError(
                f"transforms[{i}].name={t['name']!r}.measured must be either "
                f"the literal {_NOT_MEASURED!r} or an object of measured "
                f"splits — got {measured!r}")

    _validate_ratio_group(manifest, "direction")
    _validate_ratio_group(manifest, "chord")

    limits = manifest.get("pitchShiftLimits")
    if not isinstance(limits, dict):
        raise TypeError("manifest missing required field: pitchShiftLimits")
    if limits.get("pcmVarispeedMaxSemitones") != 6:
        raise ValueError("manifest.pitchShiftLimits.pcmVarispeedMaxSemitones must be 6 "
                        "(ADR 0525 D3 ISMIR optimum)")
    if limits.get("cqtChordTrackMaxSemitones") != 5:
        raise ValueError("manifest.pitchShiftLimits.cqtChordTrackMaxSemitones must be 5 "
                        "(ml/chords/augment.py::augment_windows default max_semi — a "
                        "DIFFERENT constraint from the PCM/varispeed limit, R11)")

    balancing = manifest.get("balancing")
    if not isinstance(balancing, dict):
        raise TypeError("manifest missing required field: balancing")
    if balancing.get("dropsRealData") is not False:
        raise ValueError(
            "manifest.balancing.dropsRealData must be exactly False — "
            "balancing may only weight/resample, never drop real data "
            "(ADR 0525 D8)")
    if not isinstance(balancing.get("method"), str) or not balancing["method"]:
        raise TypeError("manifest.balancing.method must be a non-empty string")


def build_manifest(seed, transforms, direction_ratios, chord_ratios,
                   balancing_method="resample_with_replacement"):
    """Assemble + validate a manifest dict from already-computed pieces
    (ADR 0525 D5). `direction_ratios`/`chord_ratios` are each
    `{"baseline": {...}, "balanced": {...}}`. Raises on any contract
    violation (see `validate_manifest`) — never returns an invalid manifest."""
    manifest = {
        "schemaVersion": "1.0",
        "seed": int(seed),
        "transforms": transforms,
        "classRatios": {"direction": direction_ratios, "chord": chord_ratios},
        "pitchShiftLimits": dict(PITCH_SHIFT_LIMITS),
        "balancing": {"method": balancing_method, "dropsRealData": False},
    }
    validate_manifest(manifest)
    return manifest
