"""Tests for the pure-NumPy synthetic full-band chord renderer (phase 0.2).

pytest is NOT installed on the box -> a plain `if __name__ == '__main__'` block
runs every test and prints a pass line. Verify with:

    python3 ml/chords/test_synth_songs.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords.labels import to_majmin_class  # noqa: E402
from chords.synth_songs import (  # noqa: E402
    chord_pitches,
    freq_to_pitch_class,
    render_dataset,
    render_song,
)

SR = 22050
C_MAJ = to_majmin_class("C")   # 1
G_MAJ = to_majmin_class("G")   # 8
A_MIN = to_majmin_class("Am")  # 22
F_MAJ = to_majmin_class("F")   # 6


def _pcs(freqs):
    return {freq_to_pitch_class(f) for f in freqs}


def test_chord_pitches_major_and_minor_triads():
    # C major -> {C, E, G} = {0, 4, 7}
    cmaj = chord_pitches(C_MAJ)
    assert len(cmaj) == 3
    assert _pcs(cmaj) == {0, 4, 7}
    # A minor -> {A, C, E} = {9, 0, 4}
    amin = chord_pitches(A_MIN)
    assert len(amin) == 3
    assert _pcs(amin) == {9, 0, 4}
    # Accept a label string too, and check the minor third differs from major.
    assert _pcs(chord_pitches("Cm")) == {0, 3, 7}  # C Eb G
    # N.C. -> no tonal content.
    assert chord_pitches(0) == []
    assert chord_pitches("N.C.") == []
    # Triad ordered ascending and within a sensible guitar octave (~E2..F#4).
    assert cmaj == sorted(cmaj)
    assert 80.0 < cmaj[0] < 400.0 and cmaj[-1] < 420.0


def test_render_song_shape_and_events():
    prog = [C_MAJ, G_MAJ, A_MIN, F_MAJ]
    spc = 1.0
    pcm, events = render_song(prog, seconds_per_chord=spc, sr=SR, seed=3)
    # mono float32 in [-1, 1]
    assert pcm.dtype == np.float32
    assert pcm.ndim == 1
    assert float(np.max(np.abs(pcm))) <= 1.0
    # length ~= 4 * spc * sr
    assert abs(len(pcm) - int(4 * spc * SR)) <= 1
    # peak normalised to ~0.9
    assert abs(float(np.max(np.abs(pcm))) - 0.9) < 0.05
    # 4 events, right labels, right onset times, all 'down'
    assert len(events) == 4
    times = [e[0] for e in events]
    dirs = [e[1] for e in events]
    labels = [e[2] for e in events]
    assert dirs == ["down"] * 4
    assert labels == ["C", "G", "Am", "F"]
    assert np.allclose(times, [0.0, 1.0, 2.0, 3.0])


def test_determinism_same_seed_identical_diff_seed_differs():
    prog = [C_MAJ, G_MAJ, A_MIN, F_MAJ]
    a, _ = render_song(prog, sr=SR, seed=7)
    b, _ = render_song(prog, sr=SR, seed=7)
    c, _ = render_song(prog, sr=SR, seed=8)
    assert np.array_equal(a, b)          # same seed -> bit-identical
    assert not np.array_equal(a, c)      # different seed -> different audio
    assert a.shape == c.shape


def test_nc_segment_is_low_energy():
    # A chord then N.C.: the N.C. half should carry far less energy (no tonal
    # guitar/bass — only drums + noise), even after global normalisation.
    pcm, events = render_song(["C", "N.C."], seconds_per_chord=1.0, sr=SR, seed=2)
    assert [e[2] for e in events] == ["C", "N.C."]
    half = len(pcm) // 2
    rms_chord = float(np.sqrt(np.mean(pcm[:half] ** 2)))
    rms_nc = float(np.sqrt(np.mean(pcm[half:] ** 2)))
    assert rms_nc < 0.7 * rms_chord

    # And with the rhythm section OFF, N.C. is essentially silent vs a chord.
    tonal, _ = render_song(["C"], sr=SR, seed=2,
                           with_drums=False, with_bass=False)
    silent, _ = render_song(["N.C."], sr=SR, seed=2,
                            with_drums=False, with_bass=False)
    rms_tonal = float(np.sqrt(np.mean(tonal ** 2)))
    rms_silent = float(np.sqrt(np.mean(silent ** 2)))
    assert rms_silent < 0.2 * rms_tonal


def test_spectral_peaks_of_c_major_land_on_c_e_g():
    # One clean C-major chord (rhythm section off) -> its dominant spectral
    # peaks must fall on the C / E / G pitch classes.
    pcm, _ = render_song([C_MAJ], seconds_per_chord=1.0, sr=SR, seed=0,
                         with_drums=False, with_bass=False)
    spec = np.abs(np.fft.rfft(pcm.astype(np.float64)))
    freqs = np.fft.rfftfreq(len(pcm), 1.0 / SR)
    band = (freqs > 60.0) & (freqs < 1000.0)
    idx_sorted = np.argsort(spec)[::-1]
    peaks = []  # greedily take the 3 strongest peaks >10 Hz apart
    for i in idx_sorted:
        if not band[i]:
            continue
        f = float(freqs[i])
        if all(abs(f - p) > 10.0 for p in peaks):
            peaks.append(f)
        if len(peaks) == 3:
            break
    assert len(peaks) == 3
    assert {freq_to_pitch_class(p) for p in peaks} == {0, 4, 7}


def test_render_dataset_in_memory():
    songs = render_dataset(4, seed=11, seconds_per_chord=0.5, sr=SR)
    assert len(songs) == 4
    for pcm, events in songs:
        assert pcm.dtype == np.float32
        assert pcm.ndim == 1 and len(pcm) > 0
        assert len(events) >= 3
        assert all(d == "down" for _, d, _ in events)
    # Reproducible: same dataset seed -> identical first song.
    again = render_dataset(4, seed=11, seconds_per_chord=0.5, sr=SR)
    assert np.array_equal(songs[0][0], again[0][0])


def _run_all():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
        print(f"  ok  {t.__name__}")
    print(f"\nALL {len(tests)} SYNTH-SONG TESTS PASSED")


if __name__ == "__main__":
    _run_all()
