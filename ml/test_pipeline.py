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


if __name__ == "__main__":
    sys.exit(main())
