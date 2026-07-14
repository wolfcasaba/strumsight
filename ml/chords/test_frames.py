"""Tests for the frame-wise chord-label layer (phase 0.4).

pytest-style asserts + a manual `__main__` block (pytest is NOT installed on
this box -- verify with `python3 ml/chords/test_frames.py`).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords import frames  # noqa: E402
from chords.labels import to_majmin_class  # noqa: E402

# 10 fps grid: center(i) = (i*1 + 0.5)/10 = (i + 0.5)/10 seconds.
HOP, SR = 1, 10
FPS = SR / HOP  # 10

C = to_majmin_class("C")       # 1
AM = to_majmin_class("Am")     # 22
NC = 0

EVENTS = [(0.0, "down", "C"), (1.0, "down", "Am"), (2.0, "down", "N.C.")]


def test_frame_center_convention():
    # Documented convention: center(i) = (i*hop + hop/2)/sr.
    assert frames.frame_center_time(0, HOP, SR) == 0.05
    assert frames.frame_center_time(10, HOP, SR) == 1.05
    assert frames.frame_center_time(20, HOP, SR) == 2.05


def test_sustain_and_boundary_frames():
    fl = frames.frame_labels(EVENTS, n_frames=30, hop=HOP, sr=SR)
    assert fl.shape == (30,)
    assert fl.dtype == np.int32
    # ~0-1 s -> C (frames 0..9, centres 0.05..0.95).
    assert fl[0] == C and fl[9] == C
    # ~1-2 s -> Am (frames 10..19, centres 1.05..1.95).
    assert fl[10] == AM and fl[19] == AM
    # after 2 s -> N.C. (frames 20..29).
    assert fl[20] == NC and fl[29] == NC
    # The whole 0-1 s block is C, 1-2 s block is Am.
    assert list(fl[0:10]) == [C] * 10
    assert list(fl[10:20]) == [AM] * 10
    assert list(fl[20:30]) == [NC] * 10


def test_nc_before_first_event():
    # First event at 0.5 s -> frames whose centre < 0.5 s are N.C.
    ev = [(0.5, "down", "G")]
    fl = frames.frame_labels(ev, n_frames=10, hop=HOP, sr=SR)
    G = to_majmin_class("G")
    # centres 0.05..0.45 (frames 0..4) precede the onset -> N.C.
    assert list(fl[0:5]) == [NC] * 5
    # centres 0.55..0.95 (frames 5..9) -> G.
    assert list(fl[5:10]) == [G] * 5


def test_round_trip_segments():
    fl = frames.frame_labels(EVENTS, n_frames=30, hop=HOP, sr=SR)
    segs = frames.chord_segments(fl, hop=HOP, sr=SR)
    # Three segments: C, Am, N.C.
    labels_seq = [s[0] for s in segs]
    assert labels_seq == ["C", "Am", "N.C."]
    # Original onset times recovered within one frame (1/FPS = 0.1 s).
    tol = 1.0 / FPS
    original_starts = [0.0, 1.0, 2.0]
    for (lbl, start_s, end_s), want in zip(segs, original_starts):
        assert abs(start_s - want) <= tol + 1e-9, (lbl, start_s, want)
    # Segments are contiguous and cover the clip.
    assert segs[0][2] == segs[1][1]
    assert segs[1][2] == segs[2][1]
    assert abs(segs[-1][2] - (30 * HOP) / SR) <= 1e-9  # ends at clip end (3.0 s)


def test_empty_events_all_nc():
    fl = frames.frame_labels([], n_frames=8, hop=HOP, sr=SR)
    assert fl.shape == (8,)
    assert list(fl) == [NC] * 8
    # Segments of an all-N.C. track = a single N.C. segment.
    segs = frames.chord_segments(fl, hop=HOP, sr=SR)
    assert len(segs) == 1 and segs[0][0] == "N.C."


def test_n_frames_zero_is_empty():
    fl = frames.frame_labels(EVENTS, n_frames=0, hop=HOP, sr=SR)
    assert fl.shape == (0,)
    assert frames.chord_segments(fl, hop=HOP, sr=SR) == []


def test_unsorted_events_are_sorted():
    shuffled = [EVENTS[2], EVENTS[0], EVENTS[1]]
    a = frames.frame_labels(shuffled, n_frames=30, hop=HOP, sr=SR)
    b = frames.frame_labels(EVENTS, n_frames=30, hop=HOP, sr=SR)
    assert list(a) == list(b)


def test_class_distribution():
    fl = frames.frame_labels(EVENTS, n_frames=30, hop=HOP, sr=SR)
    dist = frames.class_distribution(fl)
    assert dist.shape == (25,)
    assert dist[C] == 10 and dist[AM] == 10 and dist[NC] == 10
    assert dist.sum() == 30
    # Empty input -> all-zero distribution.
    assert list(frames.class_distribution([])) == [0] * 25


def test_labels_for_recording_smoke():
    """Real Klangio recording, if the dataset is on the box (else skipped)."""
    data_dir = frames.DEFAULT_DATA_DIR
    if not os.path.isdir(data_dir):
        print("  [skip] no klangio dataset at", data_dir)
        return
    klangio = frames._load_klangio()
    ids = klangio.recording_ids(data_dir)
    if not ids:
        print("  [skip] no complete recording sets under", data_dir)
        return
    rid = ids[0]
    # Chord hop from the plan: 22.05 kHz, hop 2048 (~93 ms). n_frames chosen to
    # comfortably cover the recording (we do NOT read audio here).
    sr, hop = 22050, 2048
    events = klangio.parse_strums(
        open(os.path.join(data_dir, f"recording_{rid}.strums")).read()
    )
    last_t = max(t for t, _, _ in events)
    n_frames = int(last_t * sr / hop) + 200
    fl = frames.labels_for_recording(rid, n_frames, hop, sr, data_dir)
    assert fl.shape == (n_frames,)
    assert fl.dtype == np.int32
    assert int(fl.min()) >= 0 and int(fl.max()) <= 24
    print(
        f"  [ok] recording {rid}: {len(events)} strums -> {n_frames} frames, "
        f"{len(frames.chord_segments(fl, hop, sr))} chord segments, "
        f"classes present: {sorted(set(fl.tolist()))}"
    )


def _run_all():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\nALL {len(tests)} TESTS PASSED")


if __name__ == "__main__":
    _run_all()
