"""Smoke test for the strum-direction DATA pipeline (NumPy-only, no TF).
Run: `python3 ml/test_pipeline.py` — exits 0 on success, 1 on failure.

Proves the pipeline end-to-end on synthetic data so it's plug-and-play the
moment real (audio + Wear-OS-accel) recordings arrive: onset detection finds
the attack, the IMU auto-labeler recovers the stroke direction, and the log-mel
window has the model-input shape.
"""
from __future__ import annotations

import sys

import numpy as np

import features as F
import klangio
import synth


def _check(name, cond):
    print(f"  [{'ok' if cond else 'FAIL'}] {name}")
    return cond


def main() -> int:
    ok = True
    print("strum-direction data-pipeline smoke test")

    # 1. log-mel has the right shape + is finite.
    down = synth.strum("down")
    lm = F.log_mel(down)
    ok &= _check(f"log_mel shape (…,{F.N_MELS})", lm.shape[1] == F.N_MELS)
    ok &= _check("log_mel finite", np.all(np.isfinite(lm)))

    # 2. onset detection finds ~one attack near the lead (0.1 s).
    onsets = F.spectral_flux_onsets(down)
    ok &= _check(f"one onset found (got {len(onsets)})", len(onsets) >= 1)
    first = onsets[0] if onsets else -1
    ok &= _check(f"onset near 0.1 s (got {first:.3f})", 0.05 <= first <= 0.2)

    # 3. IMU auto-labeling recovers BOTH directions.
    for direction in ("down", "up"):
        sig = synth.strum(direction)
        ons = F.spectral_flux_onsets(sig)
        onset_s = ons[0] if ons else 0.1
        t, axis = synth.accel_axis(direction, onset_s)
        label = F.label_direction_from_accel(t, axis, onset_s)
        ok &= _check(f"auto-label {direction} → {label}", label == direction)

    # 4. model-input window has the fixed shape.
    win = F.window_at(lm, first if first > 0 else 0.1)
    ok &= _check(
        f"window shape ({F.PRE_FRAMES + F.POST_FRAMES},{F.N_MELS})",
        win.shape == (F.PRE_FRAMES + F.POST_FRAMES, F.N_MELS),
    )

    # 5. Klangio .strums parsing (round 140): exact fields, strict directions.
    events = klangio.parse_strums(
        "0.451\tD\tC-major\n\n1.612\tU\tF-major\n2.912\tD\tA-minor\n")
    ok &= _check("parse_strums 3 events", len(events) == 3)
    ok &= _check(
        "parse_strums fields",
        events[1] == (1.612, "up", "F-major") and events[0][1] == "down",
    )
    try:
        klangio.parse_strums("0.5\tX\tC-major\n")
        ok &= _check("unknown direction rejected", False)
    except ValueError:
        ok &= _check("unknown direction rejected", True)

    # 6. Klangio windows: labeled times → chunk-018-shaped (X, y), no
    #    detection in the loop (annotations are ground truth).
    sig = np.concatenate([synth.strum("down"), synth.strum("up")])
    lead = 0.1  # synth.strum lead silence
    evs = [(lead, "down", "C-major"),
           (lead + len(synth.strum("down")) / F.SR, "up", "C-major")]
    xs, ys, skipped = klangio.windows_for_recording(sig, evs)
    ok &= _check("klangio windows count",
                 len(xs) == 2 and ys == [0, 1] and skipped == 0)
    ok &= _check(
        "klangio window shape",
        xs[0].shape == (F.PRE_FRAMES + F.POST_FRAMES, F.N_MELS),
    )

    # 6b. A label past the audio end is SKIPPED, never a labeled zero window
    #     (r142 audit R4: truncated wav must not poison training).
    late = evs + [(len(sig) / F.SR + 5.0, "up", "C-major")]
    xs2, ys2, skipped2 = klangio.windows_for_recording(sig, late)
    ok &= _check("late label skipped", len(xs2) == 2 and skipped2 == 1)

    # 7. Split-by-recording (round 141): whole recordings stay on one side —
    #    a window-level split would leak recording identity (round-140 lesson:
    #    some takes are single-direction).
    rec = np.array(["a"] * 5 + ["b"] * 3 + ["c"] * 4 + ["d"] * 2)
    train, ev = klangio.split_by_recording(rec, eval_frac=0.25, seed=7)
    ok &= _check("split masks disjoint+complete",
                 bool(np.all(train ^ ev)) and int(ev.sum()) > 0)
    straddles = any(
        len({bool(m) for m, r2 in zip(ev.tolist(), rec.tolist()) if r2 == r})
        > 1 for r in set(rec.tolist()))
    ok &= _check("no recording straddles the split", not straddles)
    t2, e2 = klangio.split_by_recording(rec, eval_frac=0.25, seed=7)
    ok &= _check("split deterministic per seed", bool(np.all(ev == e2)))

    # 8. r142 audit: degenerate splits fail LOUDLY.
    try:
        klangio.split_by_recording(np.array(["only"] * 4))
        ok &= _check("single-recording split rejected", False)
    except ValueError:
        ok &= _check("single-recording split rejected", True)
    big = np.array(["a"] * 3 + ["b"] * 3)
    tb, eb = klangio.split_by_recording(big, eval_frac=0.9)
    ok &= _check("train side never empty", int(tb.sum()) > 0)
    y_bad = np.array([0, 0, 0, 1, 1, 1])  # a=all-down, b=all-up
    try:
        klangio.assert_folds_trainable(y_bad, tb, eb)
        ok &= _check("single-class fold rejected", False)
    except ValueError:
        ok &= _check("single-class fold rejected", True)
    y_good = np.array([0, 1, 0, 1, 0, 1])
    klangio.assert_folds_trainable(y_good, tb, eb)
    ok &= _check("mixed folds accepted", True)

    print("PASS" if ok else "FAILURES ABOVE")
    return 0 if ok else 1


# ---------------------------------------------------------------------------
# r172 honest-measurement splitters (pytest — run: `python -m pytest`).
# The seed-42 two-way split above stays the legacy path; these guard the new
# guitarist-aware three-way split and leave-one-guitarist-out CV.
# ---------------------------------------------------------------------------

_LOGO_REC = np.array(
    ["1001"] * 4 + ["1002"] * 3 + ["1003"] * 2
    + ["2001"] * 5 + ["2002"] * 2
    + ["4001"] * 3 + ["4002"] * 4)


def _straddles(mask, rec):
    """True if any recording appears on BOTH sides of a boolean mask."""
    return any(
        len({bool(m) for m, r in zip(mask.tolist(), rec.tolist()) if r == rid})
        > 1 for rid in set(rec.tolist()))


def test_guitarist_of_is_leading_digit():
    assert klangio.guitarist_of("1001") == "1"
    assert klangio.guitarist_of("2028") == "2"
    assert klangio.guitarist_of("4015") == "4"


def test_three_way_split_partitions_all_windows():
    tr, va, te = klangio.split_by_recording_3way(
        _LOGO_REC, val_frac=0.2, test_frac=0.2, seed=1)
    # Every window lands in exactly one fold.
    assert np.all((tr.astype(int) + va.astype(int) + te.astype(int)) == 1)
    assert tr.sum() > 0 and va.sum() > 0 and te.sum() > 0


def test_three_way_split_no_recording_overlap():
    tr, va, te = klangio.split_by_recording_3way(
        _LOGO_REC, val_frac=0.2, test_frac=0.2, seed=3)
    for mask in (tr, va, te):
        assert not _straddles(mask, _LOGO_REC)
    # A recording in one fold is in no other fold.
    def ids(mask):
        return {r for m, r in zip(mask.tolist(), _LOGO_REC.tolist()) if m}
    assert ids(tr).isdisjoint(ids(va))
    assert ids(tr).isdisjoint(ids(te))
    assert ids(va).isdisjoint(ids(te))


def test_three_way_split_deterministic_per_seed():
    a = klangio.split_by_recording_3way(_LOGO_REC, seed=9)
    b = klangio.split_by_recording_3way(_LOGO_REC, seed=9)
    for x, y in zip(a, b):
        assert np.all(x == y)
    # A different seed permutes the assignment (not a hard guarantee of
    # inequality, but with 7 recordings it must differ for these two seeds).
    c = klangio.split_by_recording_3way(_LOGO_REC, seed=10)
    assert not all(np.all(x == y) for x, y in zip(a, c))


def test_three_way_split_rejects_too_few_recordings():
    import pytest
    with pytest.raises(ValueError):
        klangio.split_by_recording_3way(np.array(["a", "a", "b"]))


def test_logo_folds_hold_out_each_guitarist_entirely():
    folds = list(klangio.logo_folds(_LOGO_REC))
    guitarists = sorted({klangio.guitarist_of(r) for r in _LOGO_REC.tolist()})
    assert [g for g, _, _ in folds] == guitarists  # one fold per guitarist
    for g, tr, te in folds:
        # The held-out guitarist is ENTIRELY in test, and in no training row.
        test_g = {klangio.guitarist_of(r)
                  for m, r in zip(te.tolist(), _LOGO_REC.tolist()) if m}
        train_g = {klangio.guitarist_of(r)
                   for m, r in zip(tr.tolist(), _LOGO_REC.tolist()) if m}
        assert test_g == {g}
        assert g not in train_g
        # Partition: train and test cover everything, disjoint.
        assert np.all(tr ^ te)
        assert not _straddles(te, _LOGO_REC)


def test_logo_folds_no_guitarist_overlap_between_train_and_test():
    for g, tr, te in klangio.logo_folds(_LOGO_REC):
        train_g = {klangio.guitarist_of(r)
                   for m, r in zip(tr.tolist(), _LOGO_REC.tolist()) if m}
        test_g = {klangio.guitarist_of(r)
                  for m, r in zip(te.tolist(), _LOGO_REC.tolist()) if m}
        assert train_g.isdisjoint(test_g)


def test_legacy_two_way_split_unchanged():
    # Backward-compat: the seed-42 two-way split still exists and behaves.
    tr, ev = klangio.split_by_recording(_LOGO_REC, eval_frac=0.2, seed=42)
    assert np.all(tr ^ ev)
    assert not _straddles(ev, _LOGO_REC)


# ---------------------------------------------------------------------------
# r173 AUDIO AUGMENTATION transforms (pytest). PCM-domain, pure NumPy — each
# operates on the raw signal BEFORE log-mel so the augmentation is realistic
# (chunk 018). Direction labels (down/up) are never touched by pitch/EQ/noise;
# pitch-shift is varispeed so it rescales onset TIMES, which the composed
# augmentor returns. Written test-first (TDD) — see ml/augment.py.
# ---------------------------------------------------------------------------

def _dominant_hz(sig, sr):
    mag = np.abs(np.fft.rfft(sig))
    freqs = np.fft.rfftfreq(len(sig), 1.0 / sr)
    return float(freqs[int(np.argmax(mag))])


def test_pitch_shift_up_raises_pitch_and_shortens():
    import augment as A
    sr = F.SR
    t = np.arange(sr) / sr
    x = np.sin(2 * np.pi * 440 * t).astype(np.float32)
    up, f = A.pitch_shift(x, 12.0)  # +1 octave -> ~880 Hz
    assert abs(_dominant_hz(up, sr) - 880.0) < 15.0
    assert f > 1.0 and len(up) < len(x)  # up-shift = time compression
    assert np.all(np.isfinite(up))


def test_pitch_shift_down_lowers_pitch_and_lengthens():
    import augment as A
    sr = F.SR
    t = np.arange(sr) / sr
    x = np.sin(2 * np.pi * 440 * t).astype(np.float32)
    down, f = A.pitch_shift(x, -12.0)  # -1 octave -> ~220 Hz
    assert abs(_dominant_hz(down, sr) - 220.0) < 8.0
    assert f < 1.0 and len(down) > len(x)


def test_pitch_shift_rescales_onset_time():
    import augment as A
    sr = F.SR
    x = np.zeros(sr, dtype=np.float32)
    x[sr // 2] = 1.0  # impulse at 0.5 s
    up, f = A.pitch_shift(x, 7.0)
    peak_s = float(np.argmax(np.abs(up))) / sr
    assert abs(peak_s - 0.5 / f) < 0.01  # onset maps t -> t / f


def test_add_noise_hits_target_snr_and_keeps_shape():
    import augment as A
    rng = np.random.default_rng(0)
    sr = F.SR
    x = np.sin(2 * np.pi * 440 * np.arange(sr) / sr).astype(np.float32)
    y = A.add_noise(x, 20.0, rng)
    assert y.shape == x.shape and np.all(np.isfinite(y))
    resid = y - x
    snr = 20.0 * np.log10(np.sqrt(np.mean(x ** 2))
                          / (np.sqrt(np.mean(resid ** 2)) + 1e-12))
    assert abs(snr - 20.0) < 1.5


def test_gain_scales_amplitude_exactly():
    import augment as A
    x = np.ones(100, dtype=np.float32)
    assert np.allclose(A.gain(x, 6.0), 10 ** (6 / 20), atol=1e-4)
    assert np.allclose(A.gain(x, -6.0), 10 ** (-6 / 20), atol=1e-4)
    assert A.gain(x, 0.0).shape == x.shape


def test_reverb_preserves_length_and_onset_adds_tail():
    import augment as A
    x = np.zeros(2000, dtype=np.float32)
    x[500] = 1.0
    rir = A.synth_rir(decay_s=0.05, direct=1.0, wet=0.5,
                      rng=np.random.default_rng(1))
    y = A.reverb(x, rir)
    assert len(y) == len(x) and np.all(np.isfinite(y))
    # No pre-delay: the direct path keeps the onset at its original index.
    assert np.allclose(y[:500], 0.0, atol=1e-6)
    assert abs(y[500] - 1.0) < 1e-5
    # A decaying tail follows the direct path.
    assert np.sum(np.abs(y[501:700])) > 0.0


def test_mic_sim_bandlimits_and_keeps_shape():
    import augment as A
    rng = np.random.default_rng(3)
    sr, n = F.SR, F.SR
    hi = np.sin(2 * np.pi * 7800 * np.arange(n) / sr).astype(np.float32)
    y_hi = A.mic_sim(hi, rng, lp_hz=6000.0, hp_hz=80.0, tilt_db=0.0)
    assert y_hi.shape == hi.shape and np.all(np.isfinite(y_hi))
    # A tone above the low-pass cutoff is attenuated.
    assert np.sqrt(np.mean(y_hi ** 2)) < 0.6 * np.sqrt(np.mean(hi ** 2))
    lo = np.sin(2 * np.pi * 1000 * np.arange(n) / sr).astype(np.float32)
    y_lo = A.mic_sim(lo, rng, lp_hz=6000.0, hp_hz=80.0, tilt_db=0.0)
    # An in-band tone passes largely intact.
    assert np.sqrt(np.mean(y_lo ** 2)) > 0.5 * np.sqrt(np.mean(lo ** 2))


def test_augment_pcm_rescales_onsets_stays_ordered_and_finite():
    import augment as A
    rng = np.random.default_rng(5)
    sr = F.SR
    pcm = np.sin(2 * np.pi * 220 * np.arange(sr) / sr).astype(np.float32)
    onsets = np.array([0.1, 0.5, 0.9])
    aug, ao = A.augment_pcm(pcm, onsets, rng)
    assert np.all(np.isfinite(aug))
    assert len(ao) == len(onsets)
    assert np.all(ao[:-1] <= ao[1:])  # monotonic (order preserved)
    dur = len(aug) / sr
    assert np.all((ao >= 0.0) & (ao <= dur + 1e-6))


def test_augment_pcm_is_stochastic_but_deterministic_per_seed():
    import augment as A
    sr = F.SR
    pcm = np.sin(2 * np.pi * 220 * np.arange(sr) / sr).astype(np.float32)
    onsets = np.array([0.25, 0.75])
    a1, o1 = A.augment_pcm(pcm, onsets.copy(), np.random.default_rng(7))
    a2, o2 = A.augment_pcm(pcm, onsets.copy(), np.random.default_rng(7))
    assert np.array_equal(a1, a2) and np.array_equal(o1, o2)
    a3, _ = A.augment_pcm(pcm, onsets.copy(), np.random.default_rng(8))
    assert not (a1.shape == a3.shape and np.array_equal(a1, a3))


# ---------------------------------------------------------------------------
# r174 HARD-NEGATIVE mining for the no-strum reject head (pytest). Written
# test-first (TDD) — see ml/negatives.py. A no-strum window must NEVER overlap
# a labeled strum, must stay inside the audio, and the mining must be
# deterministic per rng so the reject-head dataset is reproducible.
# ---------------------------------------------------------------------------

def _clicky(duration_s, click_times, sr=F.SR):
    """Synthetic recording: a decaying 300 Hz tone-burst at each click time
    over a low noise floor — each burst is a spectral-flux onset."""
    n = int(duration_s * sr)
    x = (0.001 * np.random.default_rng(0).standard_normal(n)).astype(np.float32)
    L = sr // 4
    env = np.exp(-np.arange(L) / (0.03 * sr)).astype(np.float32)
    tone = np.sin(2 * np.pi * 300 * np.arange(L) / sr).astype(np.float32)
    burst = env * tone
    for t in click_times:
        i = int(t * sr)
        end = min(n, i + L)
        x[i:end] += burst[: end - i]
    return x


def test_negatives_never_overlap_a_labeled_strum():
    import negatives as NEG
    strums = np.array([0.5, 1.2, 2.0])
    # extra transients at 0.85 / 1.6 are NOT strums -> candidate hard negatives
    pcm = _clicky(3.0, [0.5, 0.85, 1.2, 1.6, 2.0])
    times, kinds = NEG.negative_times(
        pcm, strums, rng=np.random.default_rng(1), n_per_strum=2.0)
    assert len(times) > 0
    for t in times:
        assert np.min(np.abs(strums - t)) > NEG.MARGIN_S


def test_negatives_stay_inside_the_audio_with_window_room():
    import negatives as NEG
    strums = np.array([0.5, 1.2, 2.0])
    pcm = _clicky(3.0, [0.5, 0.85, 1.2, 1.6, 2.0])
    dur = len(pcm) / F.SR
    times, _ = NEG.negative_times(pcm, strums, rng=np.random.default_rng(2))
    assert np.all(times >= NEG.EDGE_LO_S)
    assert np.all(times <= dur - NEG.EDGE_HI_PAD_S)


def test_negatives_are_deterministic_per_seed():
    import negatives as NEG
    strums = np.array([0.5, 1.2, 2.0])
    pcm = _clicky(3.0, [0.5, 0.85, 1.2, 1.6, 2.0])
    t1, k1 = NEG.negative_times(pcm, strums, rng=np.random.default_rng(7),
                                n_per_strum=2.0)
    t2, k2 = NEG.negative_times(pcm, strums, rng=np.random.default_rng(7),
                                n_per_strum=2.0)
    assert np.array_equal(t1, t2) and np.array_equal(k1, k2)
    t3, _ = NEG.negative_times(pcm, strums, rng=np.random.default_rng(8),
                               n_per_strum=2.0)
    # A different seed permutes the EASY draws (the recording has >1 valid gap).
    assert not (len(t1) == len(t3) and np.array_equal(t1, t3))


def test_hard_negatives_are_flux_peaks_far_from_strums():
    import negatives as NEG
    strums = np.array([0.5, 1.2, 2.0])
    pcm = _clicky(3.0, [0.5, 0.85, 1.2, 1.6, 2.0])
    peaks = np.array(F.spectral_flux_onsets(pcm))
    times, kinds = NEG.negative_times(
        pcm, strums, rng=np.random.default_rng(3), n_per_strum=3.0)
    hard = times[kinds == "hard"]
    assert len(hard) > 0
    for t in hard:
        # a hard negative coincides with a real flux peak ...
        assert np.min(np.abs(peaks - t)) <= 0.06
        # ... and is far from every labeled strum (it's a FALSE onset).
        assert np.min(np.abs(strums - t)) > NEG.MARGIN_S


def test_negatives_handle_no_strums_and_tiny_audio_gracefully():
    import negatives as NEG
    # No labeled strums: still returns interior no-strum windows.
    pcm = _clicky(2.0, [0.9])
    times, _ = NEG.negative_times(pcm, np.array([]), rng=np.random.default_rng(4),
                                  n_per_strum=1.0)
    assert np.all((times >= NEG.EDGE_LO_S) & (times <= 2.0 - NEG.EDGE_HI_PAD_S))
    # Audio too short for any interior window -> empty, no crash.
    tiny = np.zeros(int(0.15 * F.SR), dtype=np.float32)
    t0, k0 = NEG.negative_times(tiny, np.array([0.05]))
    assert len(t0) == 0 and len(k0) == 0


# ---------------------------------------------------------------------------
# r175 — the 3-class LIVE model export (down/up/no-strum). Parity between the
# SHIPPED asset and the parity fixture, TF-free so it runs anywhere: the bin's
# Dense layer must be 3-wide, and the fixture must carry 3-column softmax rows
# that sum to 1 and actually exercise the no-strum class. (The <=1e-3 Dart<->
# Keras numeric match is owned by the Dart parity test; here we lock that the
# export shipped a 3-class model consistent with its own fixture.)
# ---------------------------------------------------------------------------
import json  # noqa: E402
import os  # noqa: E402
import struct  # noqa: E402

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_BIN_3C = os.path.join(_ROOT, "assets", "ml", "strum_crnn_live_3c.bin")
_FIX_3C = os.path.join(_ROOT, "test", "fixtures", "crnn_live_3c_parity.json")


def _read_ssml(path):
    """Parse the SSML v1 binary (export_dart_weights.write_bin) → {name: dims}.
    Pure struct — no NumPy/TF needed."""
    with open(path, "rb") as fh:
        buf = fh.read()
    off = 0

    def u32():
        nonlocal off
        (v,) = struct.unpack_from("<I", buf, off)
        off += 4
        return v

    assert buf[:4] == b"SSML", "bad magic"
    off = 4
    version, count = u32(), u32()
    assert version == 1
    dims = {}
    for _ in range(count):
        nlen = u32()
        name = buf[off:off + nlen].decode()
        off += nlen
        ndim = u32()
        shp = [u32() for _ in range(ndim)]
        dims[name] = shp
        off += 4 * int(np.prod(shp)) if shp else 0
    return dims


def test_live_3c_asset_is_a_three_class_model():
    if not os.path.exists(_BIN_3C):
        import pytest
        pytest.skip("3-class live asset not built (run train_live_3c.py)")
    dims = _read_ssml(_BIN_3C)
    # Dense kernel (units, n_classes) and bias (n_classes) must be 3-wide.
    assert dims["dense_k"][-1] == 3, dims["dense_k"]
    assert dims["dense_b"] == [3], dims["dense_b"]
    assert dims["mean"] == [F.N_MELS] and dims["std"] == [F.N_MELS]


def test_live_3c_fixture_exercises_the_reject_class():
    if not os.path.exists(_FIX_3C):
        import pytest
        pytest.skip("3-class live fixture not built (run train_live_3c.py)")
    with open(_FIX_3C) as fh:
        fix = json.load(fh)
    probs = fix["probs"]
    labels = fix["labels"]
    assert len(probs) == len(labels) and len(probs) > 0
    assert all(len(p) == 3 for p in probs), "3-column softmax"
    assert all(abs(sum(p) - 1.0) < 1e-3 for p in probs), "rows sum to 1"
    assert 0.0 < fix["no_strum_threshold"] < 1.0
    negs = [p for p, y in zip(probs, labels) if y == 2]
    assert len(negs) > 0, "fixture must include no-strum windows"
    rejected = sum(1 for p in negs if p[2] >= p[0] and p[2] >= p[1])
    assert rejected / len(negs) >= 0.6, "reject weights must be the trained ones"


if __name__ == "__main__":
    sys.exit(main())
