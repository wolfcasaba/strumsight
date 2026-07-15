"""Tests for the GuitarSet REAL-audio TRAIN pool (`dataset.build_guitarset`, r203).

Pure NumPy — NO TensorFlow, NO network, NO real GuitarSet download. Runs on the
ARM dev box and as a fast CI TDD gate:

    python3 ml/chords/test_dataset_guitarset.py
    cd ml && python -m pytest chords/test_dataset_guitarset.py -q

The fixture tree is synthesised in a tmpdir from the trimmed real JAMS
(`testdata/00_BN1-129-Eb_comp.jams` — GuitarSet, Zenodo 3371780, CC-BY-4.0,
Xi et al. ISMIR 2018) copied under several canonical stems, paired with tiny
sine WAVs. That exercises the REAL parse/label path while staying tiny: the
labels come from the annotation, so they are checkable exactly; only the audio
is synthetic (the CQT of a sine is still a CQT).

What these tests protect (the LOGO contract):
  * `guitarists=` really excludes the hold-out — a leak here would turn the
    headline "new-player" number into a memorisation score, silently.
  * `modes=` defaults to comp only — solo takes are single-note leads whose
    annotation names a harmony the audio lacks.
  * the anti-aliased resample is actually used (not cqt's linear decimation).
"""
import os
import shutil
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords import cqt, dataset, guitarset  # noqa: E402

FIXTURE_JAMS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "testdata", "00_BN1-129-Eb_comp.jams")

#: Canonical GuitarSet stems: 3 guitarists x {comp, solo}. '05' mirrors
#: train_chord.GS_HOLDOUT_GUITARIST so the exclusion test bites on the real id.
STEMS = (
    "00_BN1-129-Eb_comp",
    "00_BN1-129-Eb_solo",
    "01_Funk1-114-Ab_comp",
    "01_Funk1-114-Ab_solo",
    "05_SS1-100-C_comp",
    "05_SS1-100-C_solo",
)

SR_IN = 44100          # GuitarSet's real mic rate (-> exercises the resample)
SECONDS = 1.5
WIN, STEP = 8, 4       # tiny windows: 1.5 s @ hop 2048 = ~17 frames


def _write_wav(path, sr=SR_IN, seconds=SECONDS, f=196.0):
    n = int(sr * seconds)
    x = 0.4 * np.sin(2 * np.pi * f * np.arange(n) / sr)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def _make_root(stems=STEMS):
    """A GuitarSet-shaped tmpdir: annotation/<stem>.jams + audio_mono-mic/<stem>_mic.wav."""
    root = tempfile.mkdtemp(prefix="gs_fixture_")
    ann = os.path.join(root, guitarset.ANNOTATION_DIR)
    aud = os.path.join(root, guitarset.AUDIO_MIC_DIR)
    os.makedirs(ann)
    os.makedirs(aud)
    for stem in stems:
        shutil.copyfile(FIXTURE_JAMS, os.path.join(ann, stem + ".jams"))
        _write_wav(os.path.join(aud, stem + guitarset.MIC_SUFFIX))
    return root


def _gids(rec):
    """`gs_<gid>_<stem>` -> the set of guitarist ids present."""
    return {r.split("_")[1] for r in set(rec.tolist())}


# --------------------------------------------------------------------------- #
# shapes / dtypes / rec tagging
# --------------------------------------------------------------------------- #
def test_build_guitarset_shapes_dtypes_and_recs():
    root = _make_root()
    try:
        X, Y, rec = dataset.build_guitarset(root, win=WIN, step=STEP)
        # Same contract as build / build_synth.
        assert X.ndim == 3 and X.shape[1] == WIN and X.shape[2] == cqt.N_BINS
        assert Y.ndim == 2 and Y.shape[1] == WIN
        assert X.shape[0] == Y.shape[0] == rec.shape[0] > 0
        assert X.dtype == np.float32
        assert Y.dtype == np.int32
        assert rec.dtype == object
        assert int(Y.min()) >= 0 and int(Y.max()) <= 24
        # rec = "gs_<gid>_<stem>": disjoint from Klangio ids and synth_*, gid
        # readable inside the tag (LOGO filtering leans on this).
        ids = set(rec.tolist())
        assert all(r.startswith("gs_") for r in ids)
        assert "gs_00_00_BN1-129-Eb_comp" in ids
        assert not any(r.startswith("synth_") for r in ids)
    finally:
        shutil.rmtree(root)


def test_build_guitarset_one_rec_id_per_take():
    root = _make_root()
    try:
        _, _, rec = dataset.build_guitarset(root, win=WIN, step=STEP,
                                            modes=("comp", "solo"))
        # 6 fixture takes -> exactly 6 distinct recording ids.
        assert len(set(rec.tolist())) == len(STEMS)
    finally:
        shutil.rmtree(root)


# --------------------------------------------------------------------------- #
# modes filter — comp only by default
# --------------------------------------------------------------------------- #
def test_build_guitarset_defaults_to_comp_only():
    root = _make_root()
    try:
        _, _, rec = dataset.build_guitarset(root, win=WIN, step=STEP)
        ids = set(rec.tolist())
        assert ids and all(r.endswith("_comp") for r in ids), ids
        assert dataset.GS_DEFAULT_MODES == ("comp",)
    finally:
        shutil.rmtree(root)


def test_build_guitarset_modes_filter():
    root = _make_root()
    try:
        _, _, solo = dataset.build_guitarset(root, win=WIN, step=STEP,
                                             modes=("solo",))
        assert set(solo.tolist()) and all(r.endswith("_solo")
                                          for r in set(solo.tolist()))
        _, _, both = dataset.build_guitarset(root, win=WIN, step=STEP,
                                             modes=("comp", "solo"))
        assert len(set(both.tolist())) == len(STEMS)
        # modes=None keeps everything too.
        _, _, allm = dataset.build_guitarset(root, win=WIN, step=STEP, modes=None)
        assert len(set(allm.tolist())) == len(STEMS)
    finally:
        shutil.rmtree(root)


# --------------------------------------------------------------------------- #
# guitarists filter — the LOGO knob
# --------------------------------------------------------------------------- #
def test_build_guitarset_guitarists_filter():
    root = _make_root()
    try:
        _, _, rec = dataset.build_guitarset(root, win=WIN, step=STEP,
                                            modes=("comp", "solo"),
                                            guitarists=["00"])
        assert _gids(rec) == {"00"}
        _, _, rec2 = dataset.build_guitarset(root, win=WIN, step=STEP,
                                             modes=("comp", "solo"),
                                             guitarists=["00", "05"])
        assert _gids(rec2) == {"00", "05"}
    finally:
        shutil.rmtree(root)


def test_build_guitarset_excludes_the_logo_holdout_guitarist():
    """The load-bearing one: the hold-out's audio must NOT reach the train pool.

    A leak here would not crash anything — it would just quietly turn
    `guitarset_logo_comp_wcsr` from a new-player score into a memorisation
    score, which is exactly the self-congratulation this round exists to avoid.
    """
    from chords import train_chord            # numpy-only at import (TF is lazy)

    root = _make_root()
    try:
        holdout = train_chord.GS_HOLDOUT_GUITARIST
        all_gids = sorted({gid for _, _, gid in guitarset.tracks(root)})
        assert holdout in all_gids, "fixture must contain the hold-out guitarist"
        train_gids = [g for g in all_gids if g != holdout]

        _, _, rec = dataset.build_guitarset(root, win=WIN, step=STEP,
                                            modes=train_chord.GS_MODES,
                                            guitarists=train_gids)
        assert holdout not in _gids(rec)
        assert _gids(rec) == set(train_gids)
        assert not any(r.startswith(f"gs_{holdout}_") for r in set(rec.tolist()))

        # ...and the hold-out alone is non-empty, i.e. the LOGO eval has data.
        _, _, held = dataset.build_guitarset(root, win=WIN, step=STEP,
                                             modes=train_chord.GS_MODES,
                                             guitarists=[holdout])
        assert _gids(held) == {holdout}
        assert held.shape[0] > 0
        # Train and hold-out pools share NO recording.
        assert not (set(rec.tolist()) & set(held.tolist()))
    finally:
        shutil.rmtree(root)


def test_logo_constants_are_fixed_and_wired_into_the_eval():
    """Pin the LOGO design: a drifting hold-out id would make the headline
    new-player number incomparable between runs."""
    import inspect

    from chords import train_chord
    assert train_chord.GS_HOLDOUT_GUITARIST == "05"      # fixed => comparable
    assert train_chord.GS_MODES == ("comp",)             # solo is an unfair floor
    # The eval defaults ARE the constants — not a second, drifting copy.
    sig = inspect.signature(train_chord.guitarset_logo_eval)
    assert sig.parameters["guitarist"].default == train_chord.GS_HOLDOUT_GUITARIST
    assert sig.parameters["modes"].default == train_chord.GS_MODES


# --------------------------------------------------------------------------- #
# labels + audio path
# --------------------------------------------------------------------------- #
def test_build_guitarset_labels_come_from_the_annotation():
    root = _make_root(stems=("00_BN1-129-Eb_comp",))
    try:
        X, Y, _ = dataset.build_guitarset(root, win=WIN, step=STEP)
        # Recompute the truth independently and compare the FIRST window, which
        # covers frames 0..WIN-1 -> the fixture's opening D#:maj segment.
        n_f = X.shape[0] and cqt.n_frames(int(cqt.SR * SECONDS))
        truth = guitarset.labels_for_jams(
            os.path.join(root, guitarset.ANNOTATION_DIR,
                         "00_BN1-129-Eb_comp.jams"), n_f, cqt.HOP, cqt.SR)
        assert np.array_equal(Y[0], truth[:WIN])
        # The fixture opens on D#:maj for 7.4 s, so every frame of a 1.5 s take.
        assert set(Y.ravel().tolist()) == {guitarset.harte_to_class("D#:maj")}
    finally:
        shutil.rmtree(root)


def test_build_guitarset_uses_the_antialiased_resample():
    """cqt.cqt must never see the raw 44.1 kHz — that path decimates linearly
    and aliases everything above 11 kHz into the CQT's band (r202 finding)."""
    root = _make_root(stems=("00_BN1-129-Eb_comp",))
    seen = []
    real = guitarset.to_model_sr
    try:
        def spy(pcm, sr):
            seen.append(int(sr))
            return real(pcm, sr)

        guitarset.to_model_sr = spy
        X, _, _ = dataset.build_guitarset(root, win=WIN, step=STEP)
        assert seen == [SR_IN], seen           # called once, with the file's rate
        assert X.shape[0] > 0
    finally:
        guitarset.to_model_sr = real
        shutil.rmtree(root)


# --------------------------------------------------------------------------- #
# graceful absence — a missing download must not break training
# --------------------------------------------------------------------------- #
def test_build_guitarset_missing_root_is_empty_not_an_error():
    X, Y, rec = dataset.build_guitarset("/nonexistent/guitarset", win=WIN,
                                        step=STEP)
    assert X.shape == (0, WIN, cqt.N_BINS) and X.dtype == np.float32
    assert Y.shape == (0, WIN) and Y.dtype == np.int32
    assert rec.shape == (0,)


def test_build_guitarset_filtered_to_nothing_is_empty():
    root = _make_root()
    try:
        X, Y, rec = dataset.build_guitarset(root, win=WIN, step=STEP,
                                            guitarists=["99"])
        assert X.shape[0] == Y.shape[0] == rec.shape[0] == 0
        assert X.shape[1:] == (WIN, cqt.N_BINS)
    finally:
        shutil.rmtree(root)


def test_build_guitarset_skips_a_bad_take_without_sinking_the_build():
    root = _make_root()
    try:
        # Truncate one WAV to a header-only file -> read_wav raises for it only.
        bad = os.path.join(root, guitarset.AUDIO_MIC_DIR,
                           "00_BN1-129-Eb_comp" + guitarset.MIC_SUFFIX)
        with open(bad, "wb") as fh:
            fh.write(b"not a wav")
        _, _, rec = dataset.build_guitarset(root, win=WIN, step=STEP,
                                            modes=("comp", "solo"))
        ids = set(rec.tolist())
        assert "gs_00_00_BN1-129-Eb_comp" not in ids   # the bad take is dropped
        assert len(ids) == len(STEMS) - 1              # ...the rest survive
    finally:
        shutil.rmtree(root)


if __name__ == "__main__":
    import inspect
    fns = [v for k, v in sorted(globals().items())
           if k.startswith("test_") and inspect.isfunction(v)]
    for fn in fns:
        fn()
        print(f"  ok  {fn.__name__}")
    print(f"\nALL {len(fns)} GUITARSET-DATASET TESTS PASSED")
