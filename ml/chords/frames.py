"""Frame-wise chord-label layer for the ML CHORD track (phase 0.4).

This is the LABEL side of the chord training dataset. It turns a recording's
strum events -- each of which carries a chord label -- into a PER-FRAME
chord-class array aligned to the feature hop. The feature side (CQT) is a
separate module: this file takes ``n_frames``, ``hop`` and ``sr`` as inputs and
NEVER touches audio/features itself.

Model of a chord track
----------------------
A chord SUSTAINS from its strum onset until the next strum's onset (or the clip
end). So the per-frame label at frame ``i`` is the chord of the LATEST event
whose onset time is at or before that frame's centre; before the first event the
label is N.C. (class 0).

Frame-centre-time convention
----------------------------
Frame ``i`` (0-based) represents the audio hop starting at sample ``i*hop``. We
sample the label at the frame's CENTRE::

    center_time(i) = (i * hop + hop / 2) / sr      # seconds

i.e. the midpoint of the hop, in seconds. This matches the usual "a frame stands
for the audio around its centre" convention and makes the label robust to the
exact placement of an onset within a hop.

Classes are the 25-way MIREX majmin space of ``chords.labels`` (0 = N.C.,
1..12 = major, 13..24 = minor). Pure Python + NumPy, no audio deps.
"""
from __future__ import annotations

import os
import sys
from typing import List, Sequence, Tuple

import numpy as np

# ``chords.labels`` is a sibling module (pure Python, no heavy deps). Support
# both `python3 ml/chords/test_frames.py` (this dir on the path) and
# `import chords.frames` from the ml/ root.
try:  # pragma: no cover - import shim
    from chords import labels
except Exception:  # pragma: no cover - import shim
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import labels  # type: ignore


DEFAULT_DATA_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "klangio"
)

# An event is (onset_time_seconds, direction, chord_label). The direction is
# unused here (it is the strum-track target); we only need onset + chord.
Event = Tuple[float, str, str]
Segment = Tuple[str, float, float]


def frame_center_time(i: int, hop: int, sr: int) -> float:
    """Centre time (seconds) of frame ``i`` -- see module docstring convention."""
    return (i * hop + hop / 2.0) / sr


def frame_labels(
    events: Sequence[Event], n_frames: int, hop: int, sr: int
) -> np.ndarray:
    """Per-frame chord-class array (int32, shape ``(n_frames,)``).

    For each frame ``i`` the active chord is the LATEST event whose ``time_s`` is
    at or before the frame's centre ``(i*hop + hop/2)/sr``; frames before the
    first event are N.C. (0), and frames after the last event keep the last
    chord until the clip end. Chord labels are mapped through
    ``labels.to_majmin_class`` (0..24). Events need not be pre-sorted.
    """
    n = max(0, int(n_frames))
    out = np.zeros(n, dtype=np.int32)  # default everywhere = N.C. (0)
    if n == 0 or not events:
        return out

    ev = sorted(events, key=lambda e: e[0])
    times = np.asarray([float(e[0]) for e in ev], dtype=np.float64)
    classes = np.asarray([labels.to_majmin_class(e[2]) for e in ev], dtype=np.int32)

    centers = (np.arange(n, dtype=np.float64) * hop + hop / 2.0) / sr
    # Index of the latest event with time <= center: searchsorted(right) - 1.
    idx = np.searchsorted(times, centers, side="right") - 1
    active = idx >= 0  # False where the frame precedes the first event -> N.C.
    out[active] = classes[idx[active]]
    return out


def chord_segments(frame_cls: Sequence[int], hop: int, sr: int) -> List[Segment]:
    """Merge consecutive equal frames into ``(label, start_s, end_s)`` segments.

    Inverse of :func:`frame_labels`: adjacent frames of the same class collapse
    into one segment. ``start_s`` is the centre time of the run's first frame;
    ``end_s`` is the centre time of the next run's first frame (so segments are
    contiguous: ``seg[k].end == seg[k+1].start``), and the final segment ends at
    the clip end ``n_frames*hop/sr``. Labels via ``labels.class_to_label``.
    Useful for eval/inspection and round-trip checks.
    """
    frame_cls = np.asarray(frame_cls)
    n = int(frame_cls.shape[0])
    segs: List[Segment] = []
    i = 0
    while i < n:
        j = i + 1
        while j < n and frame_cls[j] == frame_cls[i]:
            j += 1
        start_s = frame_center_time(i, hop, sr)
        end_s = frame_center_time(j, hop, sr) if j < n else (n * hop) / sr
        segs.append((labels.class_to_label(int(frame_cls[i])), start_s, end_s))
        i = j
    return segs


def class_distribution(frame_cls: Sequence[int], n_classes: int = None) -> np.ndarray:
    """Count of frames per class (shape ``(n_classes,)``, default 25).

    Handy for spotting label imbalance before training / setting class weights.
    Index c holds the number of frames labelled class ``c``.
    """
    if n_classes is None:
        n_classes = labels.N_CLASSES
    arr = np.asarray(frame_cls, dtype=np.int64).reshape(-1)
    if arr.size == 0:
        return np.zeros(n_classes, dtype=np.int64)
    return np.bincount(arr, minlength=n_classes).astype(np.int64)


# --------------------------------------------------------------------------- #
# Klangio real-data adapter (guarded: klangio.py pulls audio/feature deps, so
# it is imported lazily -- this module must import even where the dataset or
# those deps are absent).
# --------------------------------------------------------------------------- #
def _load_klangio():
    """Import the sibling ``klangio`` module lazily (has audio/feature deps)."""
    ml_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if ml_root not in sys.path:
        sys.path.insert(0, ml_root)
    import klangio  # type: ignore

    return klangio


def labels_for_recording(
    rec_id, n_frames: int, hop: int, sr: int, data_dir: str = DEFAULT_DATA_DIR
) -> np.ndarray:
    """Per-frame chord-class array for one Klangio recording.

    Reads ``recording_<rec_id>.strums`` (via ``klangio.parse_strums``) from
    ``data_dir`` and sustains each strum's chord to the next onset over
    ``n_frames`` at the given ``hop``/``sr``. The caller supplies ``n_frames``
    (typically the CQT frame count of the paired ``_phone.wav``) so this stays
    feature-agnostic. Returns int32 values in 0..24.
    """
    klangio = _load_klangio()
    path = os.path.join(data_dir, f"recording_{rec_id}.strums")
    with open(path) as fh:
        events = klangio.parse_strums(fh.read())
    return frame_labels(events, n_frames, hop, sr)


def build_klangio_chord_labels(
    n_frames_for, hop: int, sr: int, data_dir: str = DEFAULT_DATA_DIR
) -> dict:
    """Per-frame chord labels for EVERY complete recording under ``data_dir``.

    ``n_frames_for`` is a callable ``rec_id -> n_frames`` (kept a callback so
    this module never opens audio / computes features itself -- the CQT agent
    owns frame counts). Returns ``{rec_id: frame_cls_array}``. Guarded so an
    absent dataset yields an empty dict rather than raising.
    """
    if not os.path.isdir(data_dir):
        return {}
    klangio = _load_klangio()
    out = {}
    for rid in klangio.recording_ids(data_dir):
        out[rid] = labels_for_recording(rid, n_frames_for(rid), hop, sr, data_dir)
    return out
