"""Tests for the SYNTHETIC full-band chord dataset builder (`dataset.build_synth`).

Pure NumPy — NO TensorFlow import (so it runs on the ARM box and as a fast CI
TDD gate). pytest-collectable AND runnable as a plain script:

    python3 ml/chords/test_dataset_synth.py
    cd ml && python -m pytest chords/test_dataset_synth.py -q
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords import cqt, frames  # noqa: E402
from chords.dataset import build_synth  # noqa: E402
from chords.labels import to_majmin_class  # noqa: E402
from chords.synth_songs import render_song  # noqa: E402

WIN = 100


def test_build_synth_shapes_dtypes_and_recs():
    X, Y, rec = build_synth(2, seed=0, win=WIN, step=WIN // 2)
    # X (N,100,144) float, Y (N,100) int in 0..24, N>0.
    assert X.ndim == 3 and X.shape[1] == WIN and X.shape[2] == cqt.N_BINS
    assert Y.ndim == 2 and Y.shape[1] == WIN
    assert X.shape[0] == Y.shape[0] == rec.shape[0]
    assert X.shape[0] > 0
    assert np.issubdtype(X.dtype, np.floating)
    assert np.issubdtype(Y.dtype, np.integer)
    assert int(Y.min()) >= 0 and int(Y.max()) <= 24
    # >=2 distinct synth_* rec ids, all in the synth_ namespace (disjoint from
    # Klangio ids), one per song index.
    ids = set(rec.tolist())
    assert len(ids) >= 2
    assert all(isinstance(r, str) and r.startswith("synth_") for r in ids)


def test_build_synth_is_seedable_deterministic():
    a = build_synth(2, seed=0)[0]
    b = build_synth(2, seed=0)[0]
    assert np.array_equal(a, b)          # same seed -> identical features
    c = build_synth(2, seed=1)[0]
    assert not np.array_equal(a, c)      # different seed -> different data


def test_label_feature_alignment_single_chord():
    # A known single-chord render pushed through the SAME cqt + frame_labels
    # path build_synth uses: the dominant per-frame label must be that chord's
    # class (labels are aligned to the features, not shifted).
    cls = to_majmin_class("G")           # 8
    pcm, events = render_song(["G"], seconds_per_chord=2.0, sr=cqt.SR, seed=0,
                              with_drums=False, with_bass=False)
    feat = cqt.cqt(pcm, cqt.SR)
    lab = frames.frame_labels(events, feat.shape[0], cqt.HOP, cqt.SR)
    assert feat.shape[0] == lab.shape[0]
    dominant = int(np.bincount(lab, minlength=25).argmax())
    assert dominant == cls


def _run_all():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
        print(f"  ok  {t.__name__}")
    print(f"\nALL {len(tests)} SYNTH-DATASET TESTS PASSED")


if __name__ == "__main__":
    _run_all()
