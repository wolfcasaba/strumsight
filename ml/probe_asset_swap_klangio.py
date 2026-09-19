# -*- coding: utf-8 -*-
"""Does the settled asset REGRESS on Klangio? One instrument, both assets, bias named.

ADR 0567 measured the unwired settled asset through the shipped Dart path on GuitarSet and
found +0.186 direction macro-F1. ADR 0567 D4 listed what the wiring round still needs, and
the open item is the Klangio side: the shipped asset was trained on Klangio ALONE, the
settled one on Klangio + GuitarSet, so the GuitarSet win could be a trade rather than a gain.

The in-situ version of this measurement is not available here: the Klangio corpus is not on
this machine, and the Dart pipeline consumes audio, not cached windows. What IS available is
the question behind it -- regression or not -- because `ml/read_ssml.py` can now load BOTH
assets into the same Keras graph, so one instrument evaluates both on the same cached
windows. That satisfies the L682 §1 rule this probe would otherwise break.

## The two folds have OPPOSITE contamination, and that is the design

The shipped asset (`ml/train_live_3c.py`) held out a random 20 % of RECORDINGS
(`split_by_recording`, seed 42). The settled asset (`ml/train_live_3c_settled.py`) held out
guitarist "4" entirely. So:

  fold A  guitarist 4            settled = clean held-out, shipped = SEEN in training
                                 -> biased FOR the shipped asset
  fold B  shipped's eval fold    shipped = clean held-out, settled = SEEN in training
                                 -> biased FOR the settled asset
  fold C  A and B                neither trained on these WINDOWS

**There is no unbiased cell, and fold C is not one** -- stated because it is the trap this
probe walked into first. On fold C neither model memorised these samples, but the two splits
differ in KIND: the shipped asset saw guitarist 4's OTHER recordings, the settled asset saw
none of that guitarist. So fold C still favours the shipped asset, through same-guitarist
transfer rather than through memorisation. "Neither trained on these windows" is not
"equally unseen".

What survives is simpler and stronger, and it runs the other way: **on fold B the SETTLED
asset is the advantaged one -- it trained on those recordings -- so if it still loses there,
it is genuinely worse on Klangio.** That inference needs no unbiased cell, only a known bias
direction.

    python ml/probe_asset_swap_klangio.py

Needs TensorFlow, the Klangio caches, and both assets. No corpus audio.
"""
from __future__ import annotations

import os
import sys

import numpy as np

import klangio as K
from klangio import split_by_recording
from read_ssml import load_keras
from train_live_3c_settled import DOWN, NO_STRUM, UP, f1

SHIPPED = "assets/ml/strum_crnn_live_3c.bin"
SETTLED = "assets/ml/strum_crnn_live_3c_settled.bin"

#: What each asset would ship with: 0.85 is `LiveCrnnStrumClassifier.noStrumThreshold`
#: (ADR 0549); 0.439 is the fitted value ADR 0567 D3 proposes for the settled asset.
PROPOSED_GATE = {SHIPPED: 0.85, SETTLED: 0.439}
KLANGIO_TEST_GUITARIST = "4"


def root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def klangio_cells():
    """{name: (mask, description)} over the cached Klangio POSITIVES, plus (X, y, rec)."""
    cache = np.load(os.path.join(os.path.dirname(__file__), "klangio_live70.npz"))
    X, y, rec = cache["X"], cache["y"], cache["rec"]
    guitarist4 = np.array([K.guitarist_of(r) for r in rec]) == KLANGIO_TEST_GUITARIST
    _train, shipped_eval = split_by_recording(rec)
    cells = {
        "A guitarist 4      ": (guitarist4, "settled CLEAN, shipped SAW it"),
        "B shipped eval fold": (shipped_eval, "shipped CLEAN, settled SAW it"),
        # NOT an unbiased cell -- see the module docstring.
        "C neither saw these": (guitarist4 & shipped_eval, "still favours shipped"),
    }
    return X, y, rec, cells


def negatives():
    cache = np.load(os.path.join(os.path.dirname(__file__), "klangio_neg_live70.npz"))
    return cache["X"], cache["rec"]


def evaluate(model, mean, std, X, y, gate):
    """(macro, down_f1, up_f1, retention) on TRUE strums at `gate`."""
    if len(y) == 0:
        return (float("nan"),) * 4
    probs = model.predict(((X - mean) / std), verbose=0, batch_size=256)
    kept = probs[:, NO_STRUM] <= gate
    called = np.where(probs[:, UP] > probs[:, DOWN], UP, DOWN)
    # A suppressed strum is not a direction error; it is absent evidence. Scoring it as a
    # wrong call would mix the gate's behaviour into the direction metric, which is the
    # confusion ADR 0566 D2's reject curves exist to avoid.
    calls = np.where(kept, called, -1)
    down, up = f1(y, calls, DOWN), f1(y, calls, UP)
    return (down + up) / 2, down, up, float(kept.mean())


def main():
    os.chdir(root())
    models = {}
    for path in (SHIPPED, SETTLED):
        model, mean, std = load_keras(path)
        models[path] = (model, mean, std)
        print(f"loaded {path}")

    X, y, rec, cells = klangio_cells()
    print(f"\nKlangio cache: {len(y)} true strums over "
          f"{len(set(rec.tolist()))} recordings\n")

    print("KLANGIO — direction macro-F1 on true strums, each asset at its PROPOSED gate")
    print("  (suppressed strums count as no call, never as a wrong call)\n")
    print("  fold                   n   bias                      shipped@0.85   "
          "settled@0.439   delta")
    for name, (mask, bias) in cells.items():
        row = {}
        for path in (SHIPPED, SETTLED):
            model, mean, std = models[path]
            row[path] = evaluate(model, mean, std, X[mask], y[mask], PROPOSED_GATE[path])
        delta = row[SETTLED][0] - row[SHIPPED][0]
        print(f"  {name} {int(mask.sum()):5d}   {bias:<24s}  {row[SHIPPED][0]:.4f}"
              f"         {row[SETTLED][0]:.4f}        {delta:+.4f}")

    print("\n  the same, broken out, and at a COMMON gate so model and gate separate:")
    print("  fold                   asset     gate    macro    down     up     retention")
    for name, (mask, _bias) in cells.items():
        for path in (SHIPPED, SETTLED):
            model, mean, std = models[path]
            for gate in sorted({PROPOSED_GATE[path], 0.85, 0.439}):
                macro, down, up, keep = evaluate(model, mean, std, X[mask], y[mask], gate)
                tag = "shipped" if path == SHIPPED else "settled"
                star = " *" if gate == PROPOSED_GATE[path] else "  "
                print(f"  {name} {tag}   {gate:.3f}{star} {macro:.4f}  {down:.4f}  "
                      f"{up:.4f}   {keep:.4f}")
    print("  (* = the gate that asset would ship with)")

    nx, nrec = negatives()
    n_g4 = np.array([K.guitarist_of(r) for r in nrec]) == KLANGIO_TEST_GUITARIST
    print("\nKLANGIO false onsets — the share each asset SUPPRESSES (higher is better)\n")
    print("  fold                   n   shipped@0.85   settled@0.439")
    for label, mask in (("A guitarist 4      ", n_g4), ("all negatives      ",
                                                        np.ones(len(nrec), bool))):
        cols = []
        for path in (SHIPPED, SETTLED):
            model, mean, std = models[path]
            probs = model.predict(((nx[mask] - mean) / std), verbose=0, batch_size=256)
            cols.append(float((probs[:, NO_STRUM] > PROPOSED_GATE[path]).mean()))
        print(f"  {label} {int(mask.sum()):5d}   {cols[0]:.4f}         {cols[1]:.4f}")

    print()
    print("Read fold B first, and read it the other way round: there the SETTLED asset")
    print("trained on these recordings and is the ADVANTAGED one, so a loss there settles")
    print("the question. There is NO unbiased cell -- fold C is not one, because the two")
    print("splits differ in kind (recording-disjoint vs guitarist-disjoint) and the")
    print("shipped asset saw guitarist 4's OTHER recordings.")
    print("NOT claimed: an in-situ Klangio number. These are ORACLE windows built at the")
    print("annotated onset by the Python path, not windows the Dart detector produced, so")
    print("they answer 'which model is better on this audio' and not 'what would the app")
    print("do'. ADR 0567 has the in-situ answer for GuitarSet; Klangio has no local audio.")


if __name__ == "__main__":
    sys.exit(main())
