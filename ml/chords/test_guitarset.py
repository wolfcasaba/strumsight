"""Tests for the GuitarSet loader (r202) — numpy-only, NO network, NO TensorFlow.

Runs on the ARM dev box (`python3 ml/chords/test_guitarset.py`) and in the CI
pytest gate. The JAMS fixture (`testdata/00_BN1-129-Eb_comp.jams`) is trimmed
from GuitarSet's file of the same name — Zenodo record 3371780, CC-BY-4.0,
Xi et al. ISMIR 2018 — keeping the chord/key_mode/tempo namespaces verbatim and
dropping the ~1.7 MB of per-string pitch_contour/note_midi data.
Crucially it retains BOTH chord annotations, so the "which annotation do we
evaluate against" decision is pinned by a test rather than by a comment.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords import guitarset  # noqa: E402
from chords.labels import NO_CHORD, to_majmin_class  # noqa: E402

# Keeps GuitarSet's canonical stem — `parse_jams` reads the guitarist/style/
# tempo/key/mode straight out of the filename, so a renamed fixture would not be
# a fixture of the real thing.
FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "testdata", "00_BN1-129-Eb_comp.jams")


# --------------------------------------------------------------------------- #
# harte_to_class
# --------------------------------------------------------------------------- #
def test_harte_maj_min():
    assert guitarset.harte_to_class("C:maj") == 1
    assert guitarset.harte_to_class("C#:maj") == 2
    assert guitarset.harte_to_class("B:maj") == 12
    assert guitarset.harte_to_class("C:min") == 13
    assert guitarset.harte_to_class("A:min") == 13 + 9
    assert guitarset.harte_to_class("F#:min") == 13 + 6


def test_harte_no_chord():
    for tok in ["N", "X", ""]:
        assert guitarset.harte_to_class(tok) == NO_CHORD


def test_harte_rich_qualities_reduce_to_the_triad():
    # Major third (or no third -> major by the MIREX majmin convention).
    for q in ["maj7", "7", "maj6", "sus4", "sus2", "aug", "maj9"]:
        assert guitarset.harte_to_class(f"G:{q}") == guitarset.harte_to_class("G:maj"), q
    # Minor third.
    for q in ["min7", "min9", "dim", "dim7", "hdim7", "minmaj7"]:
        assert guitarset.harte_to_class(f"G:{q}") == guitarset.harte_to_class("G:min"), q


def test_harte_hdim7_is_minor():
    # hdim7 (half-diminished) appears in GuitarSet's sheet vocabulary and has a
    # MINOR third — a naive 'starts with h' parser would drop it to N.C.
    assert guitarset.harte_to_class("B:hdim7") == to_majmin_class("Bm")
    assert guitarset.harte_to_class("A#:hdim7") == to_majmin_class("A#m")


def test_harte_dominant_seven_is_major():
    # ':7' is the dominant seventh — a MAJOR triad plus b7.
    assert guitarset.harte_to_class("A:7") == to_majmin_class("A")
    assert guitarset.harte_to_class("G#:7") == to_majmin_class("G#")


def test_harte_inversions_use_the_quality_not_the_bass():
    assert guitarset.harte_to_class("C:maj/3") == guitarset.harte_to_class("C:maj")
    assert guitarset.harte_to_class("F:maj/5") == guitarset.harte_to_class("F:maj")
    assert guitarset.harte_to_class("A:min/b3") == guitarset.harte_to_class("A:min")


def test_harte_performed_vocabulary_forms():
    # Shapes seen ONLY in the performed annotation (we do not evaluate against
    # it, but the mapper must not crash or mis-root them).
    assert guitarset.harte_to_class("D#:sus2(7)/1") == guitarset.harte_to_class("D#:maj")
    assert guitarset.harte_to_class("G#:maj6(2,b5,*5)/1") == guitarset.harte_to_class("G#:maj")
    # A power chord has NO third; documented fallback is major.
    assert guitarset.harte_to_class("G#:(1,5)/1") == guitarset.harte_to_class("G#:maj")


def test_harte_enharmonics():
    assert guitarset.harte_to_class("Db:maj") == guitarset.harte_to_class("C#:maj")
    assert guitarset.harte_to_class("Eb:maj") == guitarset.harte_to_class("D#:maj")
    assert guitarset.harte_to_class("Gb:min") == guitarset.harte_to_class("F#:min")


def test_harte_delegates_to_the_single_label_mapper():
    # Guards against a SECOND vocabulary drifting into existence.
    for lbl in ["C:maj", "A:min", "F#:7", "B:hdim7", "N", "G:sus4", "C:maj/3"]:
        assert guitarset.harte_to_class(lbl) == to_majmin_class(lbl)


# --------------------------------------------------------------------------- #
# parse_stem
# --------------------------------------------------------------------------- #
def test_parse_stem():
    m = guitarset.parse_stem("03_SS1-100-C#_comp")
    assert m == {"gid": "03", "style": "SS", "n": 1, "tempo": 100,
                 "key": "C#", "mode": "comp"}
    m = guitarset.parse_stem("00_BN1-129-Eb_solo")
    assert m["gid"] == "00" and m["style"] == "BN" and m["tempo"] == 129
    assert m["key"] == "Eb" and m["mode"] == "solo"
    # Multi-letter styles must not swallow the take index.
    assert guitarset.parse_stem("05_Funk2-119-G_comp")["style"] == "Funk"
    assert guitarset.parse_stem("05_Funk2-119-G_comp")["n"] == 2


def test_parse_stem_rejects_junk():
    for bad in ["nonsense", "00_BN1-129-Eb", "00_BN1-129-Eb_mic", "_-_-_"]:
        assert guitarset.parse_stem(bad) is None


# --------------------------------------------------------------------------- #
# parse_jams
# --------------------------------------------------------------------------- #
def test_parse_jams_fixture():
    gid, style, tempo, key, mode, segs = guitarset.parse_jams(FIXTURE)
    assert (gid, style, tempo, key, mode) == ("00", "BN", 129, "Eb", "comp")
    assert len(segs) == 6
    # Times are kept at full JAMS precision (no rounding in the loader).
    assert segs[0][0] == 0.0
    assert abs(segs[0][1] - 7.4419) < 1e-3
    assert segs[0][2] == "D#:maj"
    assert [s[2] for s in segs] == [
        "D#:maj", "G#:maj", "D#:maj", "A#:maj", "G#:maj", "D#:maj"]


def test_parse_jams_picks_the_sheet_annotation_not_the_performed_one():
    # THE decision this module rests on. The fixture holds both annotations;
    # the default must return the clean sheet labels.
    _, _, _, _, _, sheet = guitarset.parse_jams(FIXTURE)
    _, _, _, _, _, perf = guitarset.parse_jams(
        FIXTURE, data_source=guitarset.PERFORMED_DATA_SOURCE)
    assert [s[2] for s in sheet] == [
        "D#:maj", "G#:maj", "D#:maj", "A#:maj", "G#:maj", "D#:maj"]
    assert [s[2] for s in perf] == [
        "D#:sus2(7)/1", "G#:maj6(*5)/1", "D#:maj7/1", "A#:maj/1",
        "G#:maj6(2,b5,*5)/1", "D#:maj7/1"]
    assert sheet != perf                       # they genuinely differ
    # ...but the segmentation is identical, so annotation 1 buys no time detail.
    assert [(s[0], s[1]) for s in sheet] == [(s[0], s[1]) for s in perf]


def test_parse_jams_segments_are_sorted_and_gapless():
    _, _, _, _, _, segs = guitarset.parse_jams(FIXTURE)
    assert segs == sorted(segs, key=lambda s: s[0])
    for a, b in zip(segs, segs[1:]):
        assert abs((a[0] + a[1]) - b[0]) < 1e-6      # contiguous
    assert segs[0][0] == 0.0
    assert abs((segs[-1][0] + segs[-1][1]) - 22.3244) < 1e-3   # == duration


def test_parse_jams_unknown_data_source_raises():
    try:
        guitarset.parse_jams(FIXTURE, data_source="no such annotator")
    except ValueError as e:
        assert "data_source" in str(e)
    else:
        raise AssertionError("expected ValueError for an unknown data_source")


def test_parse_jams_bad_stem_raises():
    import shutil
    import tempfile
    d = tempfile.mkdtemp()
    try:
        bad = os.path.join(d, "not-a-guitarset-name.jams")
        shutil.copy(FIXTURE, bad)
        try:
            guitarset.parse_jams(bad)
        except ValueError as e:
            assert "stem" in str(e)
        else:
            raise AssertionError("expected ValueError for an unparseable stem")
    finally:
        shutil.rmtree(d)


# --------------------------------------------------------------------------- #
# frame_labels
# --------------------------------------------------------------------------- #
def test_frame_labels_basic_grid():
    # hop=sr -> frame i centres at i + 0.5 s. Segment [0,2) = C:maj, [2,4) = A:min.
    segs = [(0.0, 2.0, "C:maj"), (2.0, 2.0, "A:min")]
    y = guitarset.frame_labels(segs, 4, hop=1, sr=1)
    assert y.tolist() == [1, 1, 22, 22]          # A:min = 13+9 = 22
    assert y.dtype == np.int32


def test_frame_labels_honours_durations_and_gaps():
    # A GAP between 1s and 3s must be N.C. — frames.frame_labels would instead
    # sustain C:maj across it (onset model). This is the documented difference.
    segs = [(0.0, 1.0, "C:maj"), (3.0, 1.0, "G:maj")]
    y = guitarset.frame_labels(segs, 5, hop=1, sr=1)   # centres .5 1.5 2.5 3.5 4.5
    assert y.tolist() == [1, 0, 0, 8, 0]              # G:maj = 1+7 = 8


def test_frame_labels_before_first_segment_is_no_chord():
    segs = [(2.0, 1.0, "C:maj")]
    y = guitarset.frame_labels(segs, 4, hop=1, sr=1)   # centres .5 1.5 2.5 3.5
    assert y.tolist() == [0, 0, 1, 0]


def test_frame_labels_edges():
    assert guitarset.frame_labels([], 3, 1, 1).tolist() == [0, 0, 0]
    assert guitarset.frame_labels([(0.0, 1.0, "C:maj")], 0, 1, 1).tolist() == []


def test_frame_labels_unsorted_input():
    a = guitarset.frame_labels([(2.0, 2.0, "A:min"), (0.0, 2.0, "C:maj")], 4, 1, 1)
    b = guitarset.frame_labels([(0.0, 2.0, "C:maj"), (2.0, 2.0, "A:min")], 4, 1, 1)
    assert a.tolist() == b.tolist()


def test_frame_labels_uses_the_training_frame_centre_convention():
    # Must agree with frames.frame_center_time — one grid for truth + predictions.
    from chords import frames
    hop, sr = 2048, 22050
    segs = [(0.0, 1.0, "C:maj")]
    y = guitarset.frame_labels(segs, 20, hop, sr)
    for i in range(20):
        inside = frames.frame_center_time(i, hop, sr) < 1.0
        assert (y[i] == 1) == inside


def test_frame_labels_on_the_real_fixture_matches_the_annotation():
    _, _, _, _, _, segs = guitarset.parse_jams(FIXTURE)
    from chords import cqt, frames
    n = cqt.n_frames(int(22.3244 * cqt.SR))
    y = guitarset.frame_labels(segs, n, cqt.HOP, cqt.SR)
    # The sheet annotation is gapless, so every frame whose centre lands inside
    # the take is a real chord — N.C. may only appear in the trailing frame(s)
    # whose centre overruns the annotated end (here the final frame centres at
    # 22.342 s vs a 22.324 s annotation). That tail must be tiny and terminal.
    nc = np.flatnonzero(y == 0)
    assert nc.size <= 1
    assert nc.tolist() == list(range(n - nc.size, n))
    assert frames.frame_center_time(n - 1, cqt.HOP, cqt.SR) > 22.3244
    # Only the three roots in this take, all major: D#=4, G#=9, A#=11.
    assert sorted(set(y[y != 0].tolist())) == [4, 9, 11]
    # Spot-check a frame inside the first (D#:maj) and the 2nd (G#:maj) segment.
    i_first = 10
    assert frames.frame_center_time(i_first, cqt.HOP, cqt.SR) < 7.4419
    assert y[i_first] == 4
    i_second = int(8.0 * cqt.SR / cqt.HOP)
    assert 7.4419 < frames.frame_center_time(i_second, cqt.HOP, cqt.SR) < 11.1628
    assert y[i_second] == 9


# --------------------------------------------------------------------------- #
# tracks
# --------------------------------------------------------------------------- #
def test_tracks_pairs_wav_to_jams():
    import shutil
    import tempfile
    root = tempfile.mkdtemp()
    try:
        ann = os.path.join(root, "annotation")
        aud = os.path.join(root, "audio_mono-mic")
        os.makedirs(ann)
        os.makedirs(aud)
        for stem in ["00_BN1-129-Eb_comp", "03_SS1-100-C#_solo"]:
            shutil.copy(FIXTURE, os.path.join(ann, stem + ".jams"))
            open(os.path.join(aud, stem + "_mic.wav"), "wb").close()
        # Decoys: a JAMS with no audio, audio with no JAMS, and a pickup mix
        # (which must never be picked up as a mic track).
        shutil.copy(FIXTURE, os.path.join(ann, "01_Rock1-90-G_comp.jams"))
        open(os.path.join(aud, "02_Jazz1-90-A_comp_mic.wav"), "wb").close()
        open(os.path.join(aud, "00_BN1-129-Eb_comp_mix.wav"), "wb").close()

        ts = guitarset.tracks(root)
        assert len(ts) == 2
        stems = [os.path.basename(w)[: -len("_mic.wav")] for w, _, _ in ts]
        assert stems == ["00_BN1-129-Eb_comp", "03_SS1-100-C#_solo"]
        assert [g for _, _, g in ts] == ["00", "03"]
        for wav, jams, _ in ts:
            assert os.path.exists(wav) and os.path.exists(jams)
    finally:
        shutil.rmtree(root)


def test_tracks_empty_root():
    import shutil
    import tempfile
    d = tempfile.mkdtemp()
    try:
        assert guitarset.tracks(d) == []
    finally:
        shutil.rmtree(d)


# --------------------------------------------------------------------------- #
# eval_guitarset — the non-TensorFlow half (importable + testable on ARM;
# `load_model` is the only TF-touching function and it imports lazily).
# --------------------------------------------------------------------------- #
def _write_wav(path, x, sampwidth, sr=44100, channels=1):
    import wave
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(sampwidth)
        w.setframerate(sr)
        if sampwidth == 1:
            raw = ((x * 127) + 128).astype(np.uint8).tobytes()
        elif sampwidth == 2:
            raw = (x * 32767).astype("<i2").tobytes()
        elif sampwidth == 3:
            v = (x * 8388607).astype(np.int32)
            raw = np.stack([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF],
                           1).astype(np.uint8).tobytes()
        else:
            raw = (x * 2147483647).astype("<i4").tobytes()
        w.writeframes(raw)


def _sine(n=4410, sr=44100, f=440.0):
    return (0.5 * np.sin(2 * np.pi * f * np.arange(n) / sr)).astype(np.float32)


def test_eval_read_wav_sample_widths():
    import shutil
    import tempfile
    from chords import eval_guitarset as E
    d = tempfile.mkdtemp()
    try:
        sig = _sine()
        for sw in (1, 2, 3, 4):
            p = os.path.join(d, f"a{sw}.wav")
            _write_wav(p, sig, sw)
            y, sr = E.read_wav(p)
            assert sr == 44100 and y.shape == sig.shape and y.dtype == np.float32
            # 8-bit is coarse; the rest must be near-exact.
            tol = 0.02 if sw == 1 else 1e-4
            assert np.abs(y - sig).max() < tol, sw
    finally:
        shutil.rmtree(d)


def test_eval_read_wav_downmixes_stereo():
    import shutil
    import tempfile
    from chords import eval_guitarset as E
    d = tempfile.mkdtemp()
    try:
        sig = _sine()
        p = os.path.join(d, "st.wav")
        _write_wav(p, np.stack([sig, -sig], 1).reshape(-1), 2, channels=2)
        y, _ = E.read_wav(p)
        assert y.shape == sig.shape          # frames, not samples
        assert np.abs(y).max() < 1e-3        # L+R cancel -> silence
    finally:
        shutil.rmtree(d)


def test_eval_to_model_sr():
    from chords import cqt
    from chords import eval_guitarset as E
    sig = _sine(44100)
    out = E.to_model_sr(sig, 44100)
    assert abs(len(out) - cqt.SR) <= 10      # 44.1k -> 22.05k is exactly 2:1
    # Already at the model rate -> untouched (no needless resample).
    assert E.to_model_sr(sig, cqt.SR) is sig


class _StubModel:
    """Predicts class (global_frame_index % 25) — makes chunk order/trim visible."""

    def predict(self, batch, verbose=0):
        n, w, _ = batch.shape
        out = np.zeros((n, w, 25), dtype=np.float32)
        for i in range(n):
            for j in range(w):
                out[i, j, (i * w + j) % 25] = 1.0
        return out


def test_eval_predict_frames_windowing_is_exact():
    # The benchmark is only as trustworthy as this: every frame predicted once,
    # in order, tail padding trimmed back off. Covers F < WIN, F == WIN and
    # non-multiples of WIN.
    from chords import eval_guitarset as E
    for F in (1, 99, 100, 101, 250, 323):
        pred = E.predict_frames(_StubModel(), np.zeros((F, 144), np.float32))
        assert pred.shape == (F,), (F, pred.shape)
        assert pred.dtype == np.int32
        assert pred.tolist() == [i % 25 for i in range(F)], F


def test_eval_predict_frames_empty():
    from chords import eval_guitarset as E
    assert E.predict_frames(_StubModel(), np.zeros((0, 144), np.float32)).size == 0


def test_eval_win_matches_the_trained_model_input():
    # A WIN drift here would silently reshape the model's input.
    from chords import eval_guitarset as E
    assert E.WIN == 100


def test_eval_acc_counter():
    from chords import eval_guitarset as E
    a = E.Acc()
    assert a.acc == 0.0            # empty must not divide by zero
    a.add(3, 4)
    a.add(1, 4)
    assert a.ok == 4 and a.n == 8 and a.acc == 0.5


def test_eval_missing_dataset_exits_zero():
    # A GuitarSet outage must never fail the training job.
    import shutil
    import tempfile
    from chords import eval_guitarset as E
    d = tempfile.mkdtemp()
    argv = sys.argv[:]
    try:
        sys.argv = ["eval_guitarset.py", "--root", d]
        assert E.main() == 0
    finally:
        sys.argv = argv
        shutil.rmtree(d)


# --------------------------------------------------------------------------- #
# module constants
# --------------------------------------------------------------------------- #
def test_zenodo_constants():
    assert guitarset.ZENODO_RECORD == 3371780
    assert guitarset.LICENSE == "CC-BY-4.0"
    # The mic zip is what we evaluate; the pickup mix is deliberately not fetched.
    assert guitarset.REQUIRED_ZIPS == ("annotation.zip", "audio_mono-mic.zip")
    assert guitarset.AUDIO_PICKUP_ZIP not in guitarset.REQUIRED_ZIPS
    assert "zenodo.org" in guitarset.ZENODO_BASE and "3371780" in guitarset.ZENODO_BASE


if __name__ == "__main__":
    import inspect
    fns = [v for k, v in sorted(globals().items())
           if k.startswith("test_") and inspect.isfunction(v)]
    for fn in fns:
        fn()
    print(f"ALL {len(fns)} GUITARSET TESTS PASSED")
