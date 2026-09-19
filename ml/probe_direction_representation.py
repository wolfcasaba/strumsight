"""E18-R30 - the remaining gap is the REPRESENTATION, and is it worth the parity work?

Where the gap stands after ADR 0552. At 238 ms of post-onset audio, on GuitarSet's
player- and tune-disjoint split:

    trained CRNN (Klangio + GuitarSet)                         macro 0.6446
    linear floor on the CRNN's OWN input (128 log-mel)         macro 0.6601
    linear floor on 16 geometric magnitude bands               macro 0.7326
    majority baseline ("always down")                          macro 0.4468
    Chapter 14  7.2 Alpha gate                                  macro 0.80

The CRNN is 0.0155 below the linear ceiling of its own input, which is nothing: more
capacity, more regularisation and more epochs have no room to work (and ADR 0551 D5 already
measured that shrinking it collapses it). So the model is not the remaining gap - the INPUT
is, and the candidate lever was frequency resolution.

On that one split, coarsening the bands improved the linear floor monotonically (128 -> 8
bands: 0.6601 -> 0.7160), and a tidy story came with it: 128 mels x 15 frames is 1920
features for ~1055 training sweeps, and direction is a broad spectral-balance cue, so fine
mel detail should be noise. **Both the trend and the story turned out to be wrong** - see
finding 1 below. They are written down here because the plausible explanation is exactly what
made the artefact believable.

Two things said "not yet" before acting: the 95 % bootstrap intervals on that split overlap
heavily ([0.61, 0.71] vs [0.67, 0.77]) because the test half holds only 102 upstrokes, and
changing the shipped representation means changing `ml/features.py` AND its Dart twin
`crnn_frontend.dart` under the r134 parity discipline.

So this file cross-validates over 18 candidate folds - every player held out in turn, crossed
with three rotations of the tune split, always disjoint in BOTH - and asks whether a
non-linear reader gets more out of the same features than a linear one.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_representation.py

## What it found, and it is mostly NEGATIVE

1. **The band-count effect did not replicate.** Monotone on one split (128 -> 8 bands:
   0.6601 -> 0.7160); across 14 usable folds it is not even ordered - 128: 0.6715,
   32: 0.7090, 16: 0.6731, 8: 0.6931 - and every value sits inside every other's spread
   (sd 0.08-0.11). The single-split monotonicity was an artefact. Had this not been
   cross-validated it would have bought a frontend change and a Dart parity round.
2. **The representation is a CEILING, not a floor.** Gradient boosting is WORSE than
   logistic regression on every representation (0.6492 vs 0.6715 on log-mel, 0.6822 vs
   0.7270 on geometric bands). A stronger reader extracts less, i.e. it overfits: there is
   no unexploited non-linear structure here.
3. **Geometric bands vs shipped log-mel is unproven.** Paired over 13 folds the difference
   is +0.0636 (sd 0.0981), and the two tests DISAGREE: the normal 95 % CI is
   [+0.0103, +0.1170], excluding zero, while the sign test gives p = 0.27 with 4 of 13
   folds negative. One fold contributes +0.3096. When a normal CI and a sign test disagree
   like that, the CI is being carried by the tail and the normality assumption is what is
   wrong - so this does NOT justify touching `ml/features.py` and `crnn_frontend.dart`.

Taken together: the model is at its input's ceiling, the input's ceiling is about 0.73 over
these folds, and nothing here reaches the 0.80 Alpha gate. The remaining gap is a DATA
problem - more players and more rigs - which is also the one lever that demonstrably
transferred (ADR 0552 D2).

numpy + scikit-learn. **The recordings are NOT committed.**
"""
from __future__ import annotations

import json
import os
import sys
from math import comb

import numpy as np

try:
    from sklearn.ensemble import HistGradientBoostingClassifier
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import f1_score
except ImportError:  # pragma: no cover - dev tool
    sys.exit("needs scikit-learn: pip install scikit-learn")

import features as F
import guitarset as G
from probe_direction_headroom import clean_sweeps, read_mono, resample_linear

# Three tune groups, one per Funk/Rock number, so each fold's test tunes are a whole
# rotation rather than an arbitrary pick.
TUNE_GROUPS = (
    ("Funk1-114-Ab", "Funk1-97-C", "Rock1-130-A", "Rock1-90-C#"),
    ("Funk2-108-Eb", "Funk2-119-G", "Rock2-142-D", "Rock2-85-F"),
    ("Funk3-112-C#", "Funk3-98-A", "Rock3-117-Bb", "Rock3-148-C"),
)
PLAYERS = ("00", "01", "02", "03", "04", "05")
GEOMETRIC_CACHE = "guitarset_geobands_full.npz"
N_GEO_BANDS = 16
MIN_TEST_UP = 15  # a fold with almost no upstrokes cannot measure up-F1


def geometric_bands(root):
    """16 geometric MAGNITUDE bands over the full (untruncated) shipped window.

    Cached, because it re-reads every take. Deliberately NOT log-mel: this is the
    representation that scored best, and the point is to find out whether that survives
    cross-validation.
    """
    path = os.path.join(os.path.dirname(__file__), GEOMETRIC_CACHE)
    if os.path.exists(path):
        d = np.load(path)
        return d["X"], d["y"], d["player"], d["tune"]
    edges = np.geomspace(80.0, 8000.0, N_GEO_BANDS + 1)
    window = np.hanning(F.N_FFT)
    freqs = np.fft.rfftfreq(F.N_FFT, 1.0 / F.SR)
    masks = [(freqs >= edges[b]) & (freqs < edges[b + 1]) for b in range(N_GEO_BANDS)]
    xs, ys, players, tunes = [], [], [], []
    takes = G.takes(root)
    for index, (wav, jams, player, tune) in enumerate(takes, 1):
        with open(jams, encoding="utf-8") as handle:
            sweeps = clean_sweeps(json.load(handle))
        raw, sr = read_mono(wav)
        pcm = resample_linear(raw, sr, F.SR)
        for sweep in sweeps:
            center = int(round(sweep["at"] * F.SR / F.HOP))
            lo = (center - F.PRE_FRAMES) * F.HOP
            hi = lo + 14 * F.HOP + F.N_FFT
            if lo < 0 or hi > len(pcm):
                continue
            seg = pcm[lo:hi]
            out = np.empty((15, N_GEO_BANDS))
            for i in range(15):
                mag = np.abs(np.fft.rfft(seg[i * F.HOP:i * F.HOP + F.N_FFT] * window))
                for j, mask in enumerate(masks):
                    out[i, j] = mag[mask].sum()
            xs.append(np.log(np.maximum(out, 1e-6)))
            ys.append(0 if sweep["dir"] == "down" else 1)
            players.append(player)
            tunes.append(tune)
        if index % 18 == 0:
            print(f"  geometric bands: {index}/{len(takes)} takes", flush=True)
    X = np.stack(xs).astype(np.float32)
    np.savez_compressed(path, X=X, y=np.array(ys, dtype=np.int64),
                        player=np.array(players), tune=np.array(tunes))
    print(f"built {GEOMETRIC_CACHE}: {X.shape}")
    d = np.load(path)
    return d["X"], d["y"], d["player"], d["tune"]


def pool_bands(A, k):
    """Average adjacent mel bands down to k, in the log domain."""
    return A.reshape(A.shape[0], A.shape[1], k, A.shape[2] // k).mean(axis=3)


def macro_f1(true, predicted):
    return (f1_score(true, predicted, pos_label=0)
            + f1_score(true, predicted, pos_label=1)) / 2


def folds(player, tune):
    """Every (player, tune-group) pair: test is that cell, train shares neither."""
    for held_player in PLAYERS:
        for group in TUNE_GROUPS:
            test = (player == held_player) & np.isin(tune, group)
            train = (player != held_player) & ~np.isin(tune, group)
            yield held_player, group[0].split("-")[0], train, test


def evaluate(name, X, y, player, tune, model_factory):
    flat = X.reshape(len(y), -1)
    scores, skipped = [], 0
    for _, _, train, test in folds(player, tune):
        if test.sum() < 30 or y[test].sum() < MIN_TEST_UP or y[train].sum() < 50:
            skipped += 1
            continue
        model = model_factory().fit(flat[train], y[train])
        scores.append(macro_f1(y[test], model.predict(flat[test])))
    s = np.asarray(scores)
    print(f"  {name:<42} {s.mean():.4f} +/- {s.std():.4f}   "
          f"[{s.min():.4f}, {s.max():.4f}]  {len(s)} folds ({skipped} skipped)")
    return s


def paired_compare(mel, y, player, tune, geo, gy, gplayer, gtune):
    """Per-fold DIFFERENCE between the two representations, with a distribution-free test.

    Two independent means with overlapping spreads look inconclusive, but the design is
    paired - same folds, same sweeps - so the deciding statistic is the difference per fold.
    Both a normal CI and a sign test are printed ON PURPOSE: when they disagree, the CI is
    being carried by a few extreme folds and the normal assumption is the thing that is
    wrong, not the test. That disagreement is the actual result here.
    """
    groups = {g[0].split("-")[0]: g for g in TUNE_GROUPS}
    diffs, rows = [], []
    for held_player, group_name, _, _ in folds(player, tune):
        group = groups[group_name]
        m_tr = (player != held_player) & ~np.isin(tune, group)
        m_te = (player == held_player) & np.isin(tune, group)
        g_tr = (gplayer != held_player) & ~np.isin(gtune, group)
        g_te = (gplayer == held_player) & np.isin(gtune, group)
        usable = (m_te.sum() >= 30 and y[m_te].sum() >= MIN_TEST_UP
                  and y[m_tr].sum() >= 50 and g_te.sum() >= 30
                  and gy[g_te].sum() >= MIN_TEST_UP and gy[g_tr].sum() >= 50)
        if not usable:
            continue
        flat_mel, flat_geo = mel.reshape(len(y), -1), geo.reshape(len(gy), -1)
        a = macro_f1(y[m_te], linear().fit(flat_mel[m_tr], y[m_tr]).predict(flat_mel[m_te]))
        b = macro_f1(gy[g_te],
                     linear().fit(flat_geo[g_tr], gy[g_tr]).predict(flat_geo[g_te]))
        rows.append((held_player, group_name, int(m_te.sum()), a, b))
        diffs.append(b - a)

    print("\n=== 3. PAIRED: geometric bands minus shipped log-mel, fold by fold ===")
    print("  fold                      n    log-mel  geometric     diff")
    for held_player, group_name, n, a, b in rows:
        print(f"  player {held_player} x {group_name:<6}        {n:4d}   "
              f"{a:.4f}    {b:.4f}   {b - a:+.4f}")
    d = np.asarray(diffs)
    se = d.std(ddof=1) / np.sqrt(len(d))
    wins = int((d > 0).sum())
    p = min(1.0, 2 * sum(comb(len(d), i) for i in range(wins, len(d) + 1)) / 2 ** len(d))
    print(f"\n  mean {d.mean():+.4f}  sd {d.std(ddof=1):.4f}  SE {se:.4f}  "
          f"(n={len(d)} folds)")
    print(f"  95% CI assuming normality: [{d.mean() - 1.96 * se:+.4f}, "
          f"{d.mean() + 1.96 * se:+.4f}]")
    print(f"  geometric wins {wins}/{len(d)} folds; sign test (two-sided) p = {p:.4f}")
    print(f"  largest single fold contributes {d.max():+.4f}")
    return d


def report_fold_sizes(y, player, tune):
    """Why the single ADR 0552 split is a LOWER bound, and why its leftovers are unusable.

    The single split trains on players 00-02 x 8 tunes and tests on players 03-05 x 4
    tunes, leaving 1471 of 3056 sweeps in neither set. Those leftovers cannot be recovered
    for training: each one shares a player or a tune with the test set. What IS recoverable
    is the split itself - withholding ONE player and ONE tune group instead of three players
    and eight tunes gives every fold substantially more training data, so the single split's
    0.6446 describes what the configuration manages from 1055 sweeps rather than what it can
    do.
    """
    train, test = G.split_masks(player, tune)
    crossed = ~(train | test)
    shares_player = np.isin(player, list(set(player[test].tolist()))) & crossed
    shares_tune = np.isin(tune, list(set(tune[test].tolist()))) & crossed
    print("\n=== 4. the single split starves training ===")
    print(f"  single split: train {train.sum()}  test {test.sum()}  "
          f"crossed (in neither) {crossed.sum()}")
    print(f"    crossed sharing a PLAYER with the test set: {shares_player.sum()}")
    print(f"    crossed sharing a TUNE   with the test set: {shares_tune.sum()}")
    print(f"    crossed sharing NEITHER (i.e. recoverable): "
          f"{(crossed & ~shares_player & ~shares_tune).sum()}")
    sizes = [int(tr.sum()) for _, _, tr, te in folds(player, tune)
             if te.sum() >= 30 and y[te].sum() >= MIN_TEST_UP and y[tr].sum() >= 50]
    print(f"  CV fold training size: min {min(sizes)}  median "
          f"{int(np.median(sizes))}  max {max(sizes)}   vs {train.sum()} in the single split")


def linear():
    return LogisticRegression(max_iter=6000, C=0.3, class_weight="balanced")


def boosted():
    return HistGradientBoostingClassifier(max_iter=300, learning_rate=0.06,
                                          max_leaf_nodes=15, l2_regularization=1.0,
                                          class_weight="balanced", random_state=42)


def main():
    root = os.environ.get("GUITARSET_DIR")
    if not root:
        sys.exit("set GUITARSET_DIR to the GuitarSet root")

    mel, y, player, tune = G.build(deadline_s=10.0, cache="guitarset_live_full.npz")
    geo, gy, gplayer, gtune = geometric_bands(root)

    print(f"\nlog-mel set {mel.shape}, geometric set {geo.shape}; "
          f"{18} candidate folds (every player x every tune group), "
          f"disjoint in BOTH")
    print("\n=== 1. does coarser frequency resolution really help? (logistic, 18 folds) ===")
    print("  representation                             mean +/- sd        "
          "[min, max]   folds")
    results = {}
    for k, label in ((128, "shipped 128 log-mel  <- the CRNN input"),
                     (32, "32 bands pooled from log-mel"),
                     (16, "16 bands pooled from log-mel"),
                     (8, "8 bands pooled from log-mel")):
        A = mel if k == 128 else pool_bands(mel, k)
        results[label] = evaluate(label, A, y, player, tune, linear)
    results["16 geometric magnitude bands"] = evaluate(
        "16 geometric magnitude bands", geo, gy, gplayer, gtune, linear)

    print("\n=== 2. is that a FLOOR or a CEILING? (gradient boosting, same folds) ===")
    print("  representation                             mean +/- sd        "
          "[min, max]   folds")
    evaluate("shipped 128 log-mel, boosted", mel, y, player, tune, boosted)
    evaluate("16 bands pooled from log-mel, boosted", pool_bands(mel, 16), y, player,
             tune, boosted)
    evaluate("16 geometric magnitude bands, boosted", geo, gy, gplayer, gtune, boosted)

    paired_compare(mel, y, player, tune, geo, gy, gplayer, gtune)
    report_fold_sizes(y, player, tune)

    shipped = results["shipped 128 log-mel  <- the CRNN input"]
    best = max(results.values(), key=lambda s: s.mean())
    print(f"\n  coarse-vs-shipped difference: {best.mean() - shipped.mean():+.4f} "
          f"mean macro-F1 over the same folds")
    print("  majority baseline on the single held-out split: macro 0.4468")
    print("  trained CRNN (B @238 ms) on that split:         macro 0.6446")
    print("  Chapter 14 7.2 Alpha gate:                      macro 0.80")


if __name__ == "__main__":
    main()
