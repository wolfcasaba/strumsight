"""E18-R44 - WHICH PART of the settled window breaks the shipped asset.

ADR 0572 D3 established that feeding the shipped asset an untruncated window is an
out-of-distribution input and that an OOD input is unpredictable rather than worse - two
corpora, opposite signs. It explicitly declined to explain the mechanism (L681).

This probe does not explain the mechanism either. It answers a strictly smaller question
that IS measurable: **which frames of the tensor carry the damage.** That is input geometry,
not model behaviour, and it turns "out of distribution" from a label into a measurement.

## The geometry, measured from the caches

The live window is 15 frames (PRE 3 + POST 12) at hop 256. In the `live70` cache the audio is
truncated at onset + 70 ms, so the tail frames are the log-mel of silence:

```
  klangio live70     row std per frame (mean over mels)
    f0..f9   1.51 .. 2.08      <- real signal
    f10      1.736             <- the truncation boundary falls inside this frame
    f11..f14 0.00153           <- a CONSTANT. mean -13.81, over all 11767 windows.
  klangio live_full
    f0..f14  1.655 .. 2.069    <- every frame carries signal
```

So 4 of 15 frames - 26.7 % of the tensor - switch from a dead constant to live signal when
the settled tier hands the shipped asset an untruncated window.

## The experiment

Two complementary edits on the SAME strums, so sufficiency and necessity can be separated:

  RESTORE  start from the untruncated window, put the `live70` values back from frame k on
           -> how much of the collapse does putting that region back REPAIR
  INJECT   start from the 70 ms window, take frames k.. from the untruncated one
           -> how much of the collapse does that region alone REPRODUCE

Swept over every k, so k=0 reproduces the opposite baseline exactly - a built-in control that
caught nothing here but would have caught an off-by-one (all four blocks pass).

Run on BOTH assets. The settled asset (ADR 0554) trained at both truncations, so for it the
same edit should help rather than hurt - the control that makes the shipped asset's number
interpretable rather than merely bad.

## MEASURED, and it refutes the hypothesis this probe was built to test

The hypothesis was that the damage lives in the 4 dead frames, because that is where the
input visibly changes. It does not:

```
  shipped asset, fold A (n=3721), gate 0.85      fold B (n=2013), gate 0.85
  70 ms                   0.9490                 0.7950
  untruncated             0.5712  (-0.3777)      0.5578  (-0.2372)
  RESTORE frames 11..14   0.7826  repairs 56 %   0.6554  repairs 41 %
  RESTORE frames  9..14   0.8900          84 %   0.7521          82 %
  RESTORE frames  7..14   0.9339          96 %   0.7828          95 %
  INJECT  frames 11..14   0.7964  repro'd 40 %   0.7372  repro'd 24 %
  INJECT  frames  7..14   0.5860          96 %   0.6035          81 %
```

The constant region accounts for only 40-56 % of the collapse on either fold. What accounts
for ~95 % is frames **7..14** - the truncation's whole footprint, including the DECAY RAMP
where the 1024-sample analysis window straddles the cut (|d| 2.6 at f7, 4.2 at f8, 7.4 at f9,
14.0 at f10). So the damage is localised to 8 of 15 frames, not 4, and it is carried mostly by
the frames that merely FADE rather than the ones that go flat.

And the settled asset is the mirror image in the same frames: fold A 0.5055 -> 0.6363 (+0.1309)
untruncated, and restoring frames 7..14 takes it back down to 0.6399. **The same input region
carries the loss for the asset that trained at one truncation and the gain for the asset that
trained at both** - ADR 0572 D3's statement, now local and measured.

### The probe's own limit, stated

Every edit builds an input neither training distribution contains, so single-frame edits are
not clean counterfactuals and they produce artefacts. The clearest: for the SETTLED asset,
restoring ONLY frame 14 to the constant is catastrophic (fold A macro 0.3325, down-F1 0.1368)
while restoring frames 13..14 is fine (0.6351) - a one-frame cliff at the end of a live
signal. That is not interpreted here. It bounds the probe's resolution: read the 8-frame
conclusion, which holds on both folds and in both directions, not the per-frame wiggles.

What this probe still does NOT claim: why the model responds to that region as it does. Which
frames carry the damage is input geometry; why is model behaviour, and remains unmeasured
(L681).

Note what this probe does NOT propose: "use a 70 ms-shaped window taken later instead".
`ml/probe_gate_window_jitter.py` already measured that the shipped asset is steeply
asymmetric in window centring (+15 ms -> 0.802, +30 ms -> 0.454 at gate 0.439), so moving the
window is not a free alternative to lengthening it.

    python ml/probe_settled_window_frames.py
"""
from __future__ import annotations

import os

import numpy as np

import honest_eval as H
import klangio as K
from read_ssml import load_keras
from train_live_3c_settled import KLANGIO_TEST_GUITARIST, score_direction

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = (
    ("shipped (live70 only)", "strum_crnn_live_3c.bin", 0.85),
    ("settled (both truncations)", "strum_crnn_live_3c_settled.bin", 0.2929),
)
CONSTANT_TOLERANCE = 0.01  # row std below this = the frame carries no information at all


def frame_profile(X, label):
    std = X.std(axis=0).mean(axis=1)
    mean = X.mean(axis=(0, 2))
    dead = [int(f) for f in np.flatnonzero(std < CONSTANT_TOLERANCE)]
    print(f"  {label:<10} row std  " + " ".join(f"{v:6.3f}" for v in std))
    print(f"  {'':<10} mean     " + " ".join(f"{v:6.2f}" for v in mean))
    print(f"  {'':<10} -> frames with row std < {CONSTANT_TOLERANCE}: "
          f"{dead or 'none'}")
    return dead


def main():
    x70, y70, rec70 = H.build_live(deadline_s=H.LIVE_DEADLINE_S,
                                   cache="klangio_live70.npz")
    xfu, yfu, recfu = H.build_live(deadline_s=10.0, cache="klangio_live_full.npz")
    assert (y70 == yfu).all() and (rec70 == recfu).all(), "caches are not row-aligned"

    # Fold B of ADR 0569: the shipped asset's own eval fold - RECORDING-disjoint for it, but
    # not player-disjoint (`split_by_recording` leaves all three guitarists on both sides;
    # ADR 0573 measured that the shipped asset trained on 22 of guitarist 4's 27 recordings).
    # Both folds are therefore same-player for the shipped asset, and neither is a new-player
    # number. That does not matter HERE: this probe reads a WITHIN-ROW comparison - the same
    # windows, the same model, only the tail edited - so the fold's difficulty and the
    # training exposure cancel. It matters for the LEVELS, which is why both folds are shown.
    _, eval_fold = K.split_by_recording(rec70)
    guitarist4 = np.array([K.guitarist_of(r) for r in rec70]) == KLANGIO_TEST_GUITARIST
    folds = (("fold B (shipped's eval fold: recording-disjoint for SHIPPED, NOT "
              "player-disjoint)", eval_fold),
             ("fold A (guitarist 4: player-disjoint for SETTLED; SHIPPED trained on 22/27 "
              "of it)", guitarist4))

    print("=== the window geometry, measured from the caches (all 11767 rows) ===")
    frame_profile(x70, "live70")
    dead = frame_profile(xfu, "live_full")
    delta = np.abs(x70 - xfu).mean(axis=(0, 2))
    print(f"  {'|d| 70-full':<10} per frame " + " ".join(f"{v:6.2f}" for v in delta))
    print(f"  {'':<10} -> the truncation's footprint is a RAMP, not a cliff: it is already "
          f"{delta[7]:.1f} log-mel units at frame 7,")
    print(f"  {'':<10}    {delta[9]:.1f} at frame 9, and only then {delta[11]:.1f} in the "
          f"constant region. 8 of 15 frames are affected, not 4.")
    if dead:
        raise SystemExit("live_full has dead frames too - the caches are suspect")
    dead70 = [int(f) for f in np.flatnonzero(x70.std(axis=0).mean(axis=1)
                                             < CONSTANT_TOLERANCE)]
    if not dead70:
        raise SystemExit("live70 has no constant tail - the geometry assumption is wrong")
    tail = min(dead70)
    print(f"\n  the constant region starts at frame {tail}: "
          f"{len(dead70)} of {x70.shape[1]} frames "
          f"({100 * len(dead70) / x70.shape[1]:.1f} % of the tensor) carry NO information "
          f"in the 70 ms window.")

    for asset_label, filename, gate in ASSETS:
        path = os.path.join(ROOT, "assets", "ml", filename)
        if not os.path.exists(path):
            print(f"\n=== {asset_label}: {filename} MISSING - skipped ===")
            continue
        model, mean, std = load_keras(path)
        print(f"\n=== {asset_label}  (gate {gate}) ===")
        for fold_label, fold in folds:
            rows = fold & (y70 < 2)
            truth = y70[rows]
            # Slice the fold FIRST: the edits are then on a few thousand rows, not on the
            # whole 11767-row cache.
            a70, afu = x70[rows].copy(), xfu[rows].copy()
            print(f"\n  {fold_label}, n={len(truth)}")
            print("    edit                                      macro    down     up")

            def row(label, X):
                probs = model.predict((X - mean) / std, verbose=0)
                d, u, m, _ = score_direction(probs, truth, gate)
                print(f"    {label:<40} {m:.4f}  {d:.4f}  {u:.4f}", flush=True)
                return m

            base70 = row("the 70 ms window (in distribution)", a70)
            basefu = row("the untruncated window (OOD)", afu)

            # RESTORE: from untruncated, put the live70 tail back, frame by frame. Swept all
            # the way to frame 0, where the edit IS the 70 ms window - a built-in control: if
            # that row does not equal `base70` exactly, the probe is wrong.
            print("    --- RESTORE: untruncated, with the live70 tail put back ---")
            last = a70.shape[1] - 1
            for first in range(last, -1, -1):
                edit = afu.copy()
                edit[:, first:, :] = a70[:, first:, :]
                flag = "  <- control: must equal the 70 ms row" if first == 0 else ""
                row(f"frames {first}..{last} restored to live70{flag}", edit)

            # INJECT: from live70, take the untruncated tail. At frame 0 the edit IS the
            # untruncated window - the mirror control.
            print("    --- INJECT: the 70 ms window, with the untruncated tail ---")
            for first in range(last, -1, -1):
                edit = a70.copy()
                edit[:, first:, :] = afu[:, first:, :]
                flag = "  <- control: must equal the untruncated row" if first == 0 else ""
                row(f"frames {first}..{last} taken from live_full{flag}", edit)

            print(f"    (70 ms {base70:.4f} -> untruncated {basefu:.4f}: "
                  f"{basefu - base70:+.4f})")
        del model


if __name__ == "__main__":
    main()
