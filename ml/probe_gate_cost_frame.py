# -*- coding: utf-8 -*-
"""ADR 0555 D4: derive the no-strum gate from COSTS instead of a retention quantile.

D4 left the frame open and proposed the textbook fix: state `C_FS / C_FP` and invert
Chow. This probe measures the inputs that fix actually needs, and the measurement says
the proposed frame CANNOT express either cost, for two reasons that are in our own code:

  1. A suppressed stroke does NOT cost a deduction. `rhythm_grading.dart` decision 3 --
     "a missed slot subtracts nothing" -- leaves `directionAccuracy` untouched and moves
     only `coverage`. What it costs is a CLIFF: below `minimumRhythmCoverage` (0.5)
     `rhythmAttemptEvidence` returns NO evidence at all, so the attempt yields no
     progress. A step function has no cost-per-error to put in a ratio.
  2. A phantom stroke costs a false claim only if it lands within the grader's tolerance
     of a slot that holds no confirmed stroke. `gradeRhythm` matches with
     maximum cardinality, so a phantom next to a stroke the learner DID play becomes an
     `extraConfirmedStrokes` count -- "reported, never subtracted". The damage is
     CONDITIONAL on a slot being open, and open slots are what suppression creates.

(2) means the two errors are not independent: suppressing more strokes opens more slots
for phantoms to fill. So there may be no trade-off at all in the region we ship in --
both costs can move the same way. That is the hypothesis this probe tests.

## What kind each number is (ADR 0474's discipline, applied to an analysis)

  MEASURED end-to-end   the gate sweep in `docs/eval/guitarset-strum-baseline.md`:
                        72 real GuitarSet files through the SHIPPED Dart path, 10286
                        SuperFlux onsets, 3035 clean sweeps. Gives phantom counts and
                        true-strum retention per gate with no calibration assumption.
  MEASURED here         P(no-strum) distributions on HELD-OUT groups (player AND tune
                        disjoint), per class, plus the direction assigned to surviving
                        phantoms, plus the calibration of P(no-strum) itself.
  ANALYTIC              the grader's own arithmetic: binomial coverage, and the share of
                        an attempt's timeline covered by open slot windows.
  SWEPT                 tempo / slot density, pattern length, and a multiplier on the
                        phantom rate (a beginner's lesson is not GuitarSet comping).

Nothing here is a `target`. The one thing deliberately NOT estimated is the phantom rate
of a beginner's own room; it is swept, and the output says over what range the decision
holds.

    python ml/probe_gate_cost_frame.py

Needs TensorFlow and `ml/weights_live_3c_settled.npz` for sections 1-3; sections 4-6 are
pure arithmetic over the measured table and run regardless.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

import guitarset as G
from train_live_3c_settled import DOWN, NO_STRUM, UP

# ---------------------------------------------------------------------------------------
# MEASURED end-to-end, `docs/eval/guitarset-strum-baseline.md` (E18-R24/R25, ADR 0549).
# 72 files, 10286 SuperFlux onsets, 8089 annotated events, 3035 clean sweeps.
# Rows are the `margin on` rows, because that is what production does.
#   gate, onsets kept, onset precision, true-strum recall
SWEEP = (
    (0.439, 3789, 0.913, 0.596),
    (0.650, 4015, 0.906, 0.620),
    (0.850, 4279, 0.899, 0.649),   # <- SHIPPED (`noStrumThreshold`)
    (None,  10106, 0.701, 0.941),  # no gate at all
)
TRUE_SWEEPS = 3035

#: `rhythmToleranceUs` / `onsetToleranceMsPrimary` -- the grader's window, half-width.
TOLERANCE_S = 0.050
#: `minimumRhythmCoverage`.
COVERAGE_FLOOR = 0.5

THRESHOLD_JSON = "live_3c_settled_threshold.json"


def here(name):
    return os.path.join(os.path.dirname(__file__), name)


# =======================================================================================
# 1. Is P(no-strum) calibrated? If it is not, a threshold CANNOT be read as a cost ratio.
# =======================================================================================

def calibration(p_no_strum, is_no_strum, bins=10):
    """Reliability of P(no-strum) as a probability. Returns (rows, ece)."""
    edges = np.linspace(0.0, 1.0, bins + 1)
    rows, ece, n = [], 0.0, len(p_no_strum)
    for lo, hi in zip(edges[:-1], edges[1:]):
        sel = (p_no_strum >= lo) & (p_no_strum < hi if hi < 1.0 else p_no_strum <= hi)
        if not sel.any():
            continue
        conf = float(p_no_strum[sel].mean())
        freq = float(is_no_strum[sel].mean())
        rows.append((lo, hi, int(sel.sum()), conf, freq))
        ece += sel.sum() / n * abs(conf - freq)
    return rows, ece


# =======================================================================================
# 2/3. The gate curves on held-out groups, and what the surviving phantoms CLAIM.
# =======================================================================================

def model_probs():
    """Held-out P(no-strum) for true strums (by class) and for mined false onsets."""
    from probe_direction_fusion import load_model

    model, mean, std = load_model()
    px, py, pplayer, ptune = G.build(cache="guitarset_live70.npz")
    nx, nplayer, ntune = G.build_negatives(tag="live70")
    _ptrain, ptest = G.split_masks(pplayer, ptune)
    _ntrain, ntest = G.split_masks(nplayer, ntune)

    def run(x):
        return model.predict(((x - mean) / std)[..., None], verbose=0)

    pos = run(px[ptest])
    neg = run(nx[ntest])
    return pos, py[ptest], neg


# =======================================================================================
# 4. The coverage CLIFF -- exact binomial, not an approximation.
# =======================================================================================

def p_non_reportable(p_heard, slots, floor=COVERAGE_FLOOR):
    """P(an attempt where the learner played EVERY slot yields no evidence at all).

    Coverage = heard / notated, and `rhythmAttemptEvidence` returns nothing below
    `floor`. Heard strokes are modelled as independent Bernoulli(p_heard), which is the
    assumption this function makes and the only one: the grader's own arithmetic does the
    rest. Independence is optimistic if suppression is bursty (a dull-sounding player
    suppresses in runs), so this is a LOWER bound on how often the app refuses to judge.

    There is no second gate to fold in: production builds every `DetectedStroke` with
    `isConfirmed: true` (the pipeline publishes a strum only once its direction is
    confirmed), so `coverage` equals the gate's retention exactly -- and
    `RhythmSlotOutcome.unclear`, which exists for the stroke the engine half-heard, can
    never occur.
    """
    need = math.ceil(floor * slots)
    # P(X < need) where X ~ Binomial(slots, p_heard).
    total = 0.0
    for k in range(need):
        total += math.comb(slots, k) * p_heard ** k * (1 - p_heard) ** (slots - k)
    return total


# =======================================================================================
# 5. What a phantom costs the GRADER, and what it costs the ARROW. Not the same number.
# =======================================================================================

def grader_false_claims(phantoms_per_slot, p_heard, slots, bpm, beats_per_bar=4.0):
    """Expected FALSE CLAIMS per attempt, through `gradeRhythm`'s matcher.

    A phantom only makes a claim if it lands within +-TOLERANCE of a slot with no
    confirmed stroke. Open slots = slots * (1 - p_heard); their windows cover
    `open * 2 * TOLERANCE` of an attempt lasting `duration`. Uniform phantom arrival is
    ANALYTIC, and it is the right population to use here: `negatives.MARGIN_S` mines
    no-strum windows at least 120 ms from every annotated onset, so the corpus measures
    exactly the phantoms that fall in the GAPS -- which is where an open slot is.
    """
    bars = slots / beats_per_bar if slots >= beats_per_bar else 1.0
    duration = bars * beats_per_bar * 60.0 / bpm
    phantoms = phantoms_per_slot * slots
    open_slots = slots * (1.0 - p_heard)
    covered = min(1.0, open_slots * 2.0 * TOLERANCE_S / duration)
    return phantoms * covered, phantoms, duration


def arrow_false_claims(phantoms_per_slot, slots):
    """Expected false ARROWS per attempt. No matcher, no tolerance, no protection.

    Every onset the gate admits draws an arrow at the learner in real time (ADR 0556), so
    a phantom is a false claim unconditionally -- the grader's `extraConfirmedStrokes`
    escape hatch does not exist on the display path.
    """
    return phantoms_per_slot * slots


def main():
    print(__doc__.split("## What kind")[0].strip()[:0] or "", end="")
    print("=" * 88)
    print("ADR 0555 D4 -- the gate's cost frame, measured")
    print("=" * 88)

    # ---- 0. The measured table, turned into the two rates the cost model needs --------
    print("\n0. MEASURED end-to-end (72 GuitarSet files, shipped Dart path)")
    print("   phantom = kept onset matching NO annotated event; slot = notated stroke\n")
    print("   gate     kept   onsetP   strum-recall   phantoms   strums   phantoms/slot")
    rates = []
    for gate, kept, precision, recall in SWEEP:
        phantoms = kept * (1.0 - precision)
        strums = recall * TRUE_SWEEPS
        per_slot = phantoms / TRUE_SWEEPS
        rates.append((gate, recall, per_slot, phantoms, strums))
        label = "none " if gate is None else f"{gate:.3f}"
        print(f"   {label}  {kept:7d}   {precision:.3f}        {recall:.3f}"
              f"      {phantoms:7.0f}  {strums:7.0f}      {per_slot:.3f}")

    print("\n   marginal exchange rate (true strums gained per extra phantom admitted):")
    for (g0, r0, _p0, f0, s0), (g1, r1, _p1, f1, s1) in zip(rates, rates[1:]):
        l0 = "none" if g0 is None else f"{g0:.3f}"
        l1 = "none" if g1 is None else f"{g1:.3f}"
        print(f"     {l0} -> {l1}:  {(s1 - s0):+7.0f} strums / {(f1 - f0):+6.0f}"
              f" phantoms = {(s1 - s0) / (f1 - f0):5.2f}")
    print("   A gate is only worth stopping at if C_FS/C_FP exceeds 1/(rate) there.")
    print("   This is REVEALED preference: it needs no assumption about what the")
    print("   threshold MEANS, only what moves when it moves.")

    # ---- 1-3. Model-side measurements (need TF) --------------------------------------
    try:
        pos, truth, neg = model_probs()
    except Exception as exc:                                    # pragma: no cover
        print(f"\n[sections 1-3 skipped: {type(exc).__name__}: {exc}]")
        pos = truth = neg = None

    if pos is not None:
        p_pos, p_neg = pos[:, NO_STRUM], neg[:, NO_STRUM]
        print(f"\n1. Is P(no-strum) CALIBRATED? held-out: {len(p_pos)} strums,"
              f" {len(p_neg)} false onsets")
        allp = np.concatenate([p_pos, p_neg])
        flag = np.concatenate([np.zeros(len(p_pos)), np.ones(len(p_neg))])
        rows, ece = calibration(allp, flag)
        print("   bin          n    mean P(no-strum)   actual no-strum rate")
        for lo, hi, n, conf, freq in rows:
            print(f"   {lo:.1f}-{hi:.1f}  {n:6d}        {conf:.3f}              {freq:.3f}")
        print(f"   ECE = {ece:.4f}")
        print("   NOTE the held-out MIX is not the app's prior, so this is calibration")
        print("   under THIS mixture; it answers 'may a threshold be read as a cost")
        print("   ratio', which needs the conditional frequency, and nothing more.")

        print("\n2. Per-class retention and phantom survival vs gate (held-out)")
        print("   gate    retain-DOWN  retain-UP   phantom-survival   of survivors: "
              "called DOWN")
        with open(here(THRESHOLD_JSON)) as handle:
            fitted = json.load(handle)
        gates = sorted({0.1245, fitted["no_strum_threshold"], 0.439, 0.65, 0.85, 0.95,
                        0.99, 1.01})
        for gate in gates:
            keep_pos = p_pos <= gate
            keep_neg = p_neg <= gate
            rd = float(keep_pos[truth == DOWN].mean())
            ru = float(keep_pos[truth == UP].mean())
            surv = float(keep_neg.mean())
            if keep_neg.any():
                sub = neg[keep_neg]
                called_down = float((sub[:, DOWN] >= sub[:, UP]).mean())
            else:
                called_down = float("nan")
            label = "none " if gate > 1.0 else f"{gate:.3f}"
            print(f"   {label}     {rd:.3f}        {ru:.3f}         {surv:.3f}"
                  f"              {called_down:.3f}")
        print("   A surviving phantom claims a DIRECTION. Against a down-up grid it")
        print("   becomes `credited` or `wrongDirection` -- both false, the second one")
        print("   being the claim only this app makes, so a phantom poisons exactly the")
        print("   differentiator.")

    # ---- 3b. Oracle-centred retention vs IN-SITU retention --------------------------
    # The single most consequential number in this probe, and it is pure arithmetic over
    # two measurements that were never divided by each other.
    if pos is not None:
        print()
        print("3b. The gate was CALIBRATED on oracle-centred windows and SHIPS on")
        print("    detector-centred ones. Same corpus, same model, same gate:")
        none_recall = [r for r in rates if r[0] is None][0][1]
        balance = float((truth == DOWN).mean())
        print()
        print(f"    held-out class balance: {balance:.3f} down / {1 - balance:.3f} up")
        print("    gate    oracle-window retention   in-situ retention   gap")
        for gate, recall, _per_slot, _f, _s in rates:
            if gate is None:
                continue
            keep_pos = p_pos <= gate
            rd = float(keep_pos[truth == DOWN].mean())
            ru = float(keep_pos[truth == UP].mean())
            oracle = balance * rd + (1 - balance) * ru
            in_situ = recall / none_recall
            print(f"    {gate:.3f}           {oracle:.3f}                 {in_situ:.3f}"
                  f"          {oracle - in_situ:+.3f}")
        print()
        print("    in-situ retention = strum-recall(gate) / strum-recall(none): of")
        print("    real strums the detector DOES find, the share the gate then keeps.")
        print("    The oracle column builds its window at the ANNOTATED onset; production")
        print("    builds it at the DETECTED onset, with that detector's jitter, and the")
        print("    window is 15 frames wide -- so a few ms of jitter is a different input.")
        print("    This is NOT a corpus difference: the end-to-end sweep covers all 72")
        print("    files, INCLUDING the model's own training players, so if anything it")
        print("    flatters the in-situ column. ADR 0549/0555 both calibrated the gate to")
        print("    a 95% retention TARGET on the oracle column.")

    # ---- 3c. The curves ADR 0555 D4 asked for by name --------------------------------
    if pos is not None:
        print()
        print("3c. PRECISION / RECALL REJECT CURVES (Fischer & Wollstadt 2023), per class")
        print("    D4 named these because accuracy-reject curves mislead on imbalanced")
        print("    classes, and ours are 81/19. The reject rate is over the MIXED stream")
        print("    (strums + false onsets), which is what a gate actually sees.")
        print()
        print("    gate    reject%   DOWN prec/rec      UP prec/rec       macro-F1")
        pos_dir = np.where(pos[:, UP] > pos[:, DOWN], UP, DOWN)
        neg_dir = np.where(neg[:, UP] > neg[:, DOWN], UP, DOWN)
        for gate in (0.1245, 0.293, 0.439, 0.650, 0.850, 0.950, 1.01):
            kp, kn = p_pos <= gate, p_neg <= gate
            reject = 1.0 - (kp.sum() + kn.sum()) / (len(kp) + len(kn))
            cells, f1s = [], []
            for cls in (DOWN, UP):
                # A kept false onset called `cls` is a false positive FOR cls: the grader
                # cannot tell it from a real stroke, which is the whole point.
                tp = int((kp & (pos_dir == cls) & (truth == cls)).sum())
                fp = int((kp & (pos_dir == cls) & (truth != cls)).sum())                     + int((kn & (neg_dir == cls)).sum())
                fn = int(((truth == cls) & ~(kp & (pos_dir == cls))).sum())
                prec = tp / (tp + fp) if tp + fp else 0.0
                rec = tp / (tp + fn) if tp + fn else 0.0
                f1s.append(2 * prec * rec / (prec + rec) if prec + rec else 0.0)
                cells.append(f"{prec:.3f}/{rec:.3f}")
            label = "none " if gate > 1.0 else f"{gate:.3f}"
            print(f"    {label}    {100 * reject:5.1f}    {cells[0]:16s}  {cells[1]:16s}"
                  f"  {sum(f1s) / 2:.4f}")
        print()
        print("    RECALL is what the coverage floor spends and PRECISION is what a false")
        print("    claim spends, so the two curves are the two costs -- read as curves,")
        print("    there is no single quantile that is 'the' right operating point.")

    # ---- 4. The cliff ---------------------------------------------------------------
    print("\n4. The COVERAGE CLIFF: P(a perfectly played attempt yields NO evidence)")
    print("   p_heard IS the measured end-to-end retention, with nothing else in the")
    print("   way: `rhythm_practice_screen.dart` builds every stroke with")
    print("   `isConfirmed: true`, so coverage equals retention EXACTLY and")
    print("   `RhythmSlotOutcome.unclear` is unreachable in production. Still a LOWER")
    print("   bound, for a different reason -- independent Bernoulli suppression. Real")
    print("   suppression is bursty (a dull guitar, a quiet room, one muted string")
    print("   suppresses in RUNS), and bursts push more attempts below the floor.\n")
    print("   gate    p_heard    4 slots   8 slots   16 slots")
    for gate, recall, _per_slot, _f, _s in rates:
        label = "none " if gate is None else f"{gate:.3f}"
        cells = "  ".join(f"{p_non_reportable(recall, n):8.3f}" for n in (4, 8, 16))
        print(f"   {label}    {recall:.3f}   {cells}")

    # ---- 5. The two consumers ------------------------------------------------------
    print("\n5. The same phantom costs the GRADER and the ARROW different amounts")
    for bpm, slots, name in ((80, 8, "80 bpm eighths, one bar"),
                             (80, 16, "80 bpm sixteenths, one bar"),
                             (120, 8, "120 bpm eighths, one bar")):
        print(f"\n   {name}")
        print("   gate    phantoms/attempt   open-slot cover   GRADER false claims"
              "   ARROW false arrows   P(no evidence)")
        for gate, recall, per_slot, _f, _s in rates:
            claims, phantoms, duration = grader_false_claims(per_slot, recall, slots, bpm)
            arrows = arrow_false_claims(per_slot, slots)
            cover = claims / phantoms if phantoms else 0.0
            cliff = p_non_reportable(recall, slots)
            label = "none " if gate is None else f"{gate:.3f}"
            print(f"   {label}        {phantoms:6.2f}            {cover:.4f}"
                  f"             {claims:.3f}               {arrows:6.2f}"
                  f"            {cliff:.3f}")
        print(f"   (attempt duration {duration:.2f} s)")

    # ---- 6. The decision under each frame -------------------------------------------
    print("\n6. What each frame CHOOSES, for an 8-slot attempt at 80 bpm")
    print("   frame                                      chosen gate")
    print("   retention quantile (ADR 0549/0555)         0.293-0.439  (a coverage target)")
    for delta in (0.20, 0.10, 0.05, 0.02):
        best = None
        for gate, recall, per_slot, _f, _s in rates:
            cliff = p_non_reportable(recall, 8)
            if cliff > delta:
                continue
            claims, _p, _d = grader_false_claims(per_slot, recall, 8, 80)
            if best is None or claims < best[1]:
                best = (gate, claims, cliff)
        label = "unattainable" if best is None else (
            "none " if best[0] is None else f"{best[0]:.3f}")
        extra = "" if best is None else f"  (false claims {best[1]:.3f}, cliff {best[2]:.3f})"
        print(f"   GRADER, min false claims s.t. P(no evidence)<={delta:.2f}   {label}"
              f"{extra}")
    print("   READ THIS BEFORE BELIEVING THE `none` ROWS: the GRADER objective above")
    print("   counts SLOT-VERDICT false claims only, because that is all the matcher")
    print("   exposes. It is NOT the whole cost of a loose gate. Section 3c measures the")
    print("   other consumer -- anything reading detections directly, such as the share")
    print("   card's arrow row -- and there `none` is the WORST row in the table: UP")
    print("   precision collapses 0.206 -> 0.043, because 93.8% of the phantoms a loose")
    print("   gate admits are called UP. Two consumers, two objectives, one constant.")
    best_arrow = min(rates, key=lambda r: arrow_false_claims(r[2], 8))
    print(f"   ARROW, min false arrows (no constraint)   "
          f"{'none ' if best_arrow[0] is None else f'{best_arrow[0]:.3f}'}"
          f"  (false arrows {arrow_false_claims(best_arrow[2], 8):.2f})")

    # ---- 7. Sensitivity: a beginner's room is not GuitarSet comping -------------------
    print("\n7. SWEPT: the phantom rate of a beginner's own room is NOT measured.")
    print("   Multiplier on phantoms/slot, 8 slots at 80 bpm:\n")
    print("   mult    gate 0.439        gate 0.850        none")
    for mult in (0.5, 1.0, 2.0, 4.0):
        cells = []
        for gate, recall, per_slot, _f, _s in rates:
            if gate == 0.650:
                continue
            claims, _p, _d = grader_false_claims(per_slot * mult, recall, 8, 80)
            arrows = arrow_false_claims(per_slot * mult, 8)
            cells.append(f"{claims:.3f}/{arrows:5.2f}")
        print(f"   {mult:4.1f}x   " + "   ".join(f"{c:16s}" for c in cells))
    print("   (grader false claims / arrow false arrows)")
    print("\n   The ARROW column is linear in the rate and the GRADER column is not,")
    print("   so no multiplier makes them agree: they are different optimisations.")


if __name__ == "__main__":
    main()
