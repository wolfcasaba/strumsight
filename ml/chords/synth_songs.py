"""Pure-NumPy synthetic full-band chord-audio renderer (ML chord track, phase 0.2).

A fast, dependency-free way to generate labelled guitar+bass+drums training /
regression audio ON THE BOX. This is the *pipeline-shakedown + property-gate*
renderer; FluidSynth + real soundfonts (`docs/plans/ml-chord-track.md` P0.2) is a
later CI realism upgrade. The point here is: deterministic, seedable, in-memory
labelled audio so the CQT front-end, the frame-labeller and the training loop can
be wired end-to-end before the heavyweight synthesis corpus exists.

Style follows `test/support/synth.dart` / `ml/synth.py`: a note is a fundamental
plus a few decaying harmonics, chords are staggered strums, everything is driven
by a single `numpy.random.Generator` (NO global randomness — seed is an argument).

Voicing / class conventions come from `ml/chords/labels.py` (25-class majmin):
    0 = N.C., 1..12 = C..B major, 13..24 = C..B minor.

Public API:
    chord_pitches(cls) -> list[float]                 root-position triad in Hz
    render_song(progression, ...) -> (pcm, events)    labelled full-band mono audio
    render_dataset(n_songs, ...) -> list[(pcm, events)]
    write_wav(path, pcm, sr)                           tiny int16 WAV helper
    freq_to_pitch_class(f) -> int                      Hz -> 0..11 pitch class
"""
from __future__ import annotations

import math
import os
import struct
import wave
from typing import List, Sequence, Tuple, Union

import numpy as np

try:  # imported as a package (chords.synth_songs) -> relative
    from .labels import (
        NO_CHORD,
        class_to_label,
        to_majmin_class,
        transpose_class,
    )
except ImportError:  # run as a script from inside ml/chords/
    from labels import (  # type: ignore
        NO_CHORD,
        class_to_label,
        to_majmin_class,
        transpose_class,
    )

# ---------------------------------------------------------------------------
# Pitch helpers
# ---------------------------------------------------------------------------
_A4_HZ = 440.0
_A4_MIDI = 69

# Root octave: put the triad root at C3..B3 (MIDI 48..59) so the whole voicing
# (root .. fifth, +7 semitones) lands roughly in the guitar E2..E4 region.
_ROOT_BASE_MIDI = 48


def midi_to_freq(midi: float) -> float:
    """Equal-tempered MIDI note number -> frequency in Hz (A4 = 440)."""
    return _A4_HZ * (2.0 ** ((midi - _A4_MIDI) / 12.0))


def freq_to_pitch_class(freq: float) -> int:
    """Frequency (Hz) -> nearest equal-tempered pitch class 0..11 (C = 0)."""
    midi = round(12.0 * math.log2(freq / _A4_HZ) + _A4_MIDI)
    return int(midi) % 12


Event = Tuple[float, str, str]
ProgItem = Union[int, str, np.integer]


def _to_class(item: ProgItem) -> int:
    """Accept either a majmin class index or a chord label string."""
    if isinstance(item, str):
        return to_majmin_class(item)
    cls = int(item)
    if not 0 <= cls < 25:
        raise ValueError(f"class index out of range 0..24: {cls}")
    return cls


def chord_pitches(cls: ProgItem) -> List[float]:
    """Root-position triad (root, third, fifth) in Hz for a majmin class.

    Major class -> major third (+4 semitones); minor class -> minor third (+3).
    N.C. (0) -> [] (no tonal content — silence / noise only).
    """
    c = _to_class(cls)
    if c == NO_CHORD:
        return []
    if 1 <= c <= 12:  # major
        pc, third = c - 1, 4
    else:  # 13..24 minor
        pc, third = c - 13, 3
    root_midi = _ROOT_BASE_MIDI + pc
    return [
        midi_to_freq(root_midi),          # root
        midi_to_freq(root_midi + third),  # third (maj/min)
        midi_to_freq(root_midi + 7),      # perfect fifth
    ]


# ---------------------------------------------------------------------------
# Timbre primitives (pure NumPy; mirror synth.dart harmonicNote + release ramp)
# ---------------------------------------------------------------------------
def _harmonic_note(
    freq: float,
    seconds: float,
    sr: int,
    amp: float,
    harmonics: int = 6,
    decay: float = 3.0,
) -> np.ndarray:
    """A plucked-string-ish note: fundamental + decaying harmonic series."""
    n = int(seconds * sr)
    if n <= 0:
        return np.zeros(0, dtype=np.float64)
    t = np.arange(n) / sr
    env = np.exp(-decay * t)
    y = np.zeros(n, dtype=np.float64)
    for h in range(1, harmonics + 1):
        f = freq * h
        if f >= sr / 2:
            break
        y += (amp / h) * env * np.sin(2.0 * np.pi * f * t)
    # 10 ms cosine release so the tail doesn't END on a click (broadband onset).
    ramp = min(int(0.010 * sr), n)
    if ramp > 0:
        fade = 0.5 - 0.5 * np.cos(np.pi * np.arange(ramp) / ramp)  # 0 -> 1
        y[n - ramp:] *= fade[::-1]  # 1 -> 0 at the very end
    return y


def _strum(
    freqs: Sequence[float],
    seconds: float,
    sr: int,
    amp: float,
    stagger_ms: float = 6.0,
    decay: float = 3.0,
) -> np.ndarray:
    """A down-strum of a triad: low strings first, each staggered slightly."""
    stag = int(stagger_ms / 1000.0 * sr)
    order = sorted(freqs)  # ascending == low-first == a down-strum
    note_n = int(seconds * sr)
    total = note_n + stag * max(len(order) - 1, 0)
    out = np.zeros(total, dtype=np.float64)
    for i, f in enumerate(order):
        note = _harmonic_note(f, seconds, sr, amp, decay=decay)
        off = i * stag
        out[off:off + len(note)] += note
    return out


def _kick(sr: int, rng: np.random.Generator, seconds: float = 0.18) -> np.ndarray:
    """Low-pass burst: a pitch-dropping sine thump + a touch of decaying noise."""
    n = int(seconds * sr)
    t = np.arange(n) / sr
    env = np.exp(-30.0 * t)
    f = 45.0 + 45.0 * np.exp(-40.0 * t)          # 90 Hz -> 45 Hz drop
    phase = 2.0 * np.pi * np.cumsum(f) / sr
    body = np.sin(phase)
    noise = rng.standard_normal(n) * np.exp(-80.0 * t)
    return (env * (0.9 * body + 0.1 * noise)).astype(np.float64)


def _snare(sr: int, rng: np.random.Generator, seconds: float = 0.15) -> np.ndarray:
    """Band noise: high-passed white noise (via first difference) + tonal body."""
    n = int(seconds * sr)
    t = np.arange(n) / sr
    env = np.exp(-35.0 * t)
    noise = rng.standard_normal(n)
    hp = np.diff(noise, prepend=0.0)             # crude high-pass -> band noise
    body = 0.3 * np.sin(2.0 * np.pi * 180.0 * t)
    return (env * (0.8 * hp + body)).astype(np.float64)


def _add(buf: np.ndarray, start: int, sig: np.ndarray) -> None:
    """Add `sig` into `buf` at sample `start`, clipping at the buffer end."""
    if start >= len(buf) or len(sig) == 0:
        return
    end = min(start + len(sig), len(buf))
    buf[start:end] += sig[: end - start]


# ---------------------------------------------------------------------------
# Song renderer
# ---------------------------------------------------------------------------
def render_song(
    progression: Sequence[ProgItem],
    seconds_per_chord: float = 1.0,
    bpm: float = 100.0,
    sr: int = 22050,
    seed: int = 0,
    with_drums: bool = True,
    with_bass: bool = True,
    gtr_gain: float = 0.6,
    bass_gain: float = 0.5,
    drum_gain: float = 0.45,
) -> Tuple[np.ndarray, List[Event]]:
    """Render a full-band chord progression to labelled mono PCM.

    Args:
        progression: majmin class indices OR chord-label strings (both accepted;
            strings go through `labels.to_majmin_class`).
        seconds_per_chord: duration each chord is held.
        bpm: drum / bass / strum-retrigger beat grid tempo.
        sr: sample rate.
        seed: seeds a private numpy Generator — NO global randomness.
        with_drums / with_bass: toggle the rhythm section.

    Returns:
        (pcm, events) where
          pcm    = float32 mono in [-1, 1], length ~= len(progression)*spc*sr,
                   peak-normalised to ~0.9.
          events = one (chord_onset_time_s, 'down', label) per chord change —
                   the ground truth the frame-labeller consumes.
    """
    rng = np.random.default_rng(seed)
    classes = [_to_class(p) for p in progression]
    n_chords = len(classes)
    spc = float(seconds_per_chord)
    total = int(round(n_chords * spc * sr))
    if total <= 0:
        return np.zeros(0, dtype=np.float32), []

    gtr = np.zeros(total, dtype=np.float64)
    bass = np.zeros(total, dtype=np.float64)
    drums = np.zeros(total, dtype=np.float64)

    beat_period = 60.0 / float(bpm)
    total_seconds = total / sr

    # Chord onsets (always) + beat grid (strum retrigger) -> guitar strum times.
    chord_onset_times = [i * spc for i in range(n_chords)]
    beat_times = []
    b = 0
    while b * beat_period < total_seconds:
        beat_times.append(b * beat_period)
        b += 1

    def _active_class(t: float) -> int:
        idx = int(t / spc)
        idx = max(0, min(idx, n_chords - 1))
        return classes[idx]

    # --- Guitar: strum on every chord onset AND every beat --------------------
    strum_secs = min(spc, beat_period) * 1.6  # let strums ring a little
    for t in sorted(set(chord_onset_times) | set(beat_times)):
        cls = _active_class(t)
        freqs = chord_pitches(cls)
        if not freqs:  # N.C. -> no tonal strum
            continue
        sig = _strum(freqs, strum_secs, sr, amp=0.15)
        _add(gtr, int(round(t * sr)), sig)

    # --- Bass: chord root one octave down, on each beat (downbeats) -----------
    if with_bass:
        for t in beat_times:
            cls = _active_class(t)
            freqs = chord_pitches(cls)
            if not freqs:  # N.C. -> no bass note
                continue
            root = freqs[0] / 2.0  # one octave down
            note = _harmonic_note(root, beat_period * 0.95, sr,
                                  amp=0.28, harmonics=3, decay=2.0)
            _add(bass, int(round(t * sr)), note)

    # --- Drums: kick on beats 1&3, snare on 2&4 (4/4) -------------------------
    if with_drums:
        for i, t in enumerate(beat_times):
            start = int(round(t * sr))
            if i % 4 in (0, 2):
                _add(drums, start, _kick(sr, rng) * 0.9)
            if i % 4 in (1, 3):
                _add(drums, start, _snare(sr, rng) * 0.7)

    # --- Mix + a faint broadband noise floor (also makes seeds differ) --------
    noise_floor = rng.standard_normal(total) * 5e-4
    mix = gtr_gain * gtr + bass_gain * bass + drum_gain * drums + noise_floor

    # Peak-normalise to ~0.9 — but a buffer with no real instruments (e.g. an
    # all-N.C. song: just the noise floor) is LEFT quiet rather than amplified,
    # so silence stays low-energy instead of being boosted to full scale.
    peak = float(np.max(np.abs(mix))) if total else 0.0
    if peak > 1e-2:
        mix *= 0.9 / peak
    mix = np.clip(mix, -1.0, 1.0).astype(np.float32)

    events: List[Event] = [
        (i * spc, "down", class_to_label(classes[i])) for i in range(n_chords)
    ]
    return mix, events


# ---------------------------------------------------------------------------
# Dataset generation
# ---------------------------------------------------------------------------
# A small pool of common progressions (as chord-label strings, in C / A-minor
# tonal centres). render_dataset transposes each to a random key.
_PROGRESSION_POOL: List[List[str]] = [
    ["C", "G", "Am", "F"],                 # I  V  vi IV (pop axis)
    ["Am", "F", "C", "G"],                 # vi IV I  V  (pop loop)
    ["Dm", "G", "C"],                      # ii V  I  (jazz cadence)
    ["C", "F", "G"],                       # I  IV V
    ["C", "Am", "F", "G"],                 # 50s doo-wop
    ["C", "C", "C", "C", "F", "F", "C", "C", "G", "F", "C", "G"],  # 12-bar blues
    ["C", "G", "Am", "Em", "F", "C", "F", "G"],  # Pachelbel-ish
]


def render_dataset(
    n_songs: int,
    out_dir: str = None,
    seed: int = 0,
    seconds_per_chord: float = 1.0,
    bpm_range: Tuple[int, int] = (80, 140),
    sr: int = 22050,
    with_drums: bool = True,
    with_bass: bool = True,
    transpose: bool = True,
) -> List[Tuple[np.ndarray, List[Event]]]:
    """Generate `n_songs` random full-band songs (in memory).

    Progressions are drawn from a small pool of common ones and transposed to a
    random key; tempo is randomised per song. Returns a list of (pcm, events).
    Writing files is OPTIONAL: pass `out_dir` to also dump `song_###.wav`.
    """
    rng = np.random.default_rng(seed)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    songs: List[Tuple[np.ndarray, List[Event]]] = []
    for k in range(n_songs):
        prog_labels = _PROGRESSION_POOL[int(rng.integers(len(_PROGRESSION_POOL)))]
        classes = [to_majmin_class(x) for x in prog_labels]
        if transpose:
            shift = int(rng.integers(0, 12))
            classes = [transpose_class(c, shift) for c in classes]
        bpm = int(rng.integers(bpm_range[0], bpm_range[1] + 1))
        song_seed = int(rng.integers(0, 2 ** 31 - 1))
        pcm, events = render_song(
            classes,
            seconds_per_chord=seconds_per_chord,
            bpm=bpm,
            sr=sr,
            seed=song_seed,
            with_drums=with_drums,
            with_bass=with_bass,
        )
        if out_dir:
            write_wav(os.path.join(out_dir, f"song_{k:03d}.wav"), pcm, sr)
        songs.append((pcm, events))
    return songs


def write_wav(path: str, pcm: np.ndarray, sr: int = 22050) -> None:
    """Tiny 16-bit mono WAV writer (optional; keeps the renderer file-free)."""
    x = np.clip(np.asarray(pcm, dtype=np.float64), -1.0, 1.0)
    ints = (x * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sr))
        w.writeframes(struct.pack("<%dh" % len(ints), *ints.tolist()))


if __name__ == "__main__":  # tiny manual smoke
    pcm, ev = render_song(["C", "G", "Am", "F"], seed=1)
    print(f"rendered {len(pcm)} samples, {len(ev)} events: {ev}")
