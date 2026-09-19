"""Adapter for GuitarSet as a TRAINING corpus for the live strum-direction head.

GuitarSet (https://zenodo.org/records/3371780, CC-BY 4.0) has no direction
annotation. It has something better: a **hexaphonic** pickup, annotated per string
(`note_midi` with `data_source` 0-5, 0 = low E). The order in which the strings enter
IS the direction, so the label is derived, not guessed.

Why it is here at all: the shipped live model trained on Klangio GST-MM-2025
(`ml/klangio.py`) -- real, labelled, phone-mic data, but `guitarist_of(rid)` is the
leading digit and the blocks are `1xxx / 2xxx / 4xxx`: **three guitarists**, one room,
one guitar, one microphone. A model never asked to generalise past three players has no
reason to have learned a player-invariant cue, and on GuitarSet it scores direction
macro-F1 0.3876 (up-F1 0.1905). GuitarSet adds six more players.

Measured payoff (`ml/experiment_cross_corpus.py`, ADR 0551 D2): adding this corpus to the
training pool improves BOTH held-out corpora -- GuitarSet macro 0.3552 -> 0.5017 and, in
the ORIGINAL Klangio domain, 0.4080 -> 0.5979. So the derived labels are qualified for
training rather than assumed to be; a corpus whose labels were noise could not lift the
other corpus's held-out player.

(ADR 0550 first justified this with a linear probe scoring 0.7723. That figure was
inflated by a window-alignment error -- 64 ms of extra lead-in and no live-deadline
truncation -- and is corrected to 0.5885 in ADR 0551 D1. The cross-corpus result above is
NOT affected: it uses `window_truncated` throughout.)

The label derivation is IMPORTED from `probe_direction_headroom` rather than restated,
so the corpus that trains the model and the measurement that justified it cannot drift
apart. Those functions in turn mirror
`test/tooling/guitarset_direction_boundary_test.dart`, which is what the shipped-path
numbers are measured with.

Point GUITARSET_DIR at a root holding `audio_mono-mic/` and `annotation/`. The
recordings are third-party and **never enter the repo** (`ml/data/` is gitignored, and
GuitarSet is not copied in at all -- only read in place).

    GUITARSET_DIR=/path/to/guitarset python ml/guitarset.py          # stats
    GUITARSET_DIR=/path/to/guitarset python ml/guitarset.py build    # -> cache npz

NumPy + stdlib only. It imports `probe_direction_headroom` for the label
derivation, whose scikit-learn use is lazy for exactly this reason; TF is needed
only by the trainer.
"""
from __future__ import annotations

import glob
import json
import os
import sys

import numpy as np

import features as F
from experiment_deadline import window_truncated
from probe_direction_headroom import (clean_sweeps, per_string_onsets, read_mono,
                                      resample_linear)

# Only the comping takes, and only the two styles that are actually strummed. GuitarSet's
# `solo` takes are single-note lines and its Jazz/BN/SS comping is largely arpeggiated or
# chord-melody, neither of which is a directional sweep.
STYLES = ("Rock", "Funk")

LIVE_DEADLINE_S = 0.070  # honest_eval.LIVE_DEADLINE_S -- train==serve geometry
CACHE = "guitarset_live70.npz"

# The 12 Rock+Funk comping tunes. EVERY player plays ALL of them, so a player-disjoint
# split leaves the progression shared and a model can reach direction through "which
# chord, how far into this tune" instead of through the stroke. Splitting both ways is
# the only honest option here (ADR 0550).
TRAIN_TUNES = (
    "Funk1-114-Ab", "Funk1-97-C", "Funk2-108-Eb", "Funk2-119-G",
    "Rock1-130-A", "Rock1-90-C#", "Rock2-142-D", "Rock2-85-F",
)
TEST_TUNES = ("Funk3-112-C#", "Funk3-98-A", "Rock3-117-Bb", "Rock3-148-C")
TRAIN_PLAYERS = ("00", "01", "02")
TEST_PLAYERS = ("03", "04", "05")


def root() -> str:
    value = os.environ.get("GUITARSET_DIR")
    if not value:
        sys.exit("set GUITARSET_DIR to the GuitarSet root (audio_mono-mic + annotation)")
    return value


def takes(base_dir: str):
    """(wav path, jams path, player, tune) for every strummed comping take."""
    out = []
    for wav in sorted(glob.glob(f"{base_dir}/audio_mono-mic/*_comp_mic.wav")):
        name = os.path.basename(wav)
        if not any(style in name for style in STYLES):
            continue
        jams = f"{base_dir}/annotation/" + name.replace("_mic.wav", ".jams")
        if os.path.exists(jams):
            out.append((wav, jams, name[:2], name[3:].replace("_comp_mic.wav", "")))
    return out


def build(deadline_s: float = LIVE_DEADLINE_S, cache: str = CACHE):
    """Live-deadline windows for every CLEAN derived sweep, cached.

    Geometry is `window_truncated` -- the SAME train==serve window the Klangio live
    dataset uses, audio zeroed past onset+deadline so the model only ever sees what the
    70 ms live path has. Using anything else here would train a model that cannot be
    compared to the shipped one (LESSONS L662: a configuration that differs from
    production measures a different system).
    """
    path = os.path.join(os.path.dirname(__file__), cache)
    if os.path.exists(path):
        data = np.load(path)
        return data["X"], data["y"], data["player"], data["tune"]
    base_dir = root()
    found = takes(base_dir)
    if not found:
        sys.exit(f"no Rock/Funk comping takes under {base_dir}/audio_mono-mic")
    xs, ys, players, tunes = [], [], [], []
    for index, (wav, jams, player, tune) in enumerate(found, 1):
        with open(jams, encoding="utf-8") as handle:
            sweeps = clean_sweeps(json.load(handle))
        raw, sr = read_mono(wav)
        pcm = resample_linear(raw, sr, F.SR).astype(np.float32)
        for sweep in sweeps:
            if sweep["at"] * F.SR >= len(pcm):
                continue
            xs.append(window_truncated(pcm, sweep["at"], deadline_s))
            ys.append(0 if sweep["dir"] == "down" else 1)
            players.append(player)
            tunes.append(tune)
        if index % 18 == 0:
            print(f"  {index}/{len(found)} takes", flush=True)
    X = np.stack(xs).astype(np.float32)
    np.savez_compressed(path, X=X, y=np.array(ys, dtype=np.int64),
                        player=np.array(players), tune=np.array(tunes))
    print(f"built {cache}: {X.shape}")
    data = np.load(path)
    return data["X"], data["y"], data["player"], data["tune"]


NEG_CACHE = "guitarset_neg_{}.npz"


def build_negatives(deadline_s: float = LIVE_DEADLINE_S, tag: str = "live70", seed: int = 42):
    """No-strum windows (label 2) mined from GuitarSet, geometry-matched to [build].

    `negatives.negative_times` is corpus-agnostic, so the only real decision is WHAT counts
    as "near a strum" and must therefore be excluded. It is **every annotated note onset**,
    not the clean sweeps the positives come from.

    That distinction is the whole correctness of this function. GuitarSet's non-clean groups
    are arpeggios, two-note stabs and mis-annotated sweeps - all of them REAL guitar attacks.
    Mining one as a no-strum negative would teach the model that a genuine attack is not a
    strum, and the no-strum head's entire job is to reject things that are NOT the player
    playing. The positives filter is about label quality; the negatives filter is about
    physical truth, and they are not the same set.

    ## Known limit of that exclusion set, stated because it is not visible in the numbers

    GuitarSet's annotation is PITCH-based (hexaphonic `note_midi`), so an attack that
    produces no pitched note produces no annotation - a palm-muted scratch or a dead
    percussive stroke, which Rock and especially Funk comping are full of. Those can
    therefore be mined here as no-strum negatives even though the player did strike the
    strings.

    It is arguably the behaviour we want: the curriculum already models a non-sounding
    stroke as a ghost crossing that earns no credit (`StrokeSound.ghost`), so a head that
    rejects a dead scratch agrees with the lesson. But it is an assumption, not a
    measurement, and a learner who palm-mutes heavily would be the one to find out. Any
    future round that teaches the app to CREDIT muted strokes must revisit this set first.
    """
    path = os.path.join(os.path.dirname(__file__), NEG_CACHE.format(tag))
    if os.path.exists(path):
        data = np.load(path)
        return data["X"], data["player"], data["tune"]
    import negatives as NEG

    rng = np.random.default_rng(seed)
    xs, players, tunes = [], [], []
    found = takes(root())
    for index, (wav, jams, player, tune) in enumerate(found, 1):
        with open(jams, encoding="utf-8") as handle:
            parsed = json.load(handle)
        # EVERY annotated onset, clean or not - see the docstring.
        excluded = np.array(sorted(t for t, _ in per_string_onsets(parsed)))
        raw, sr = read_mono(wav)
        pcm = resample_linear(raw, sr, F.SR).astype(np.float32)
        times, _kinds = NEG.negative_times(pcm, excluded, rng=rng)
        for t in times:
            xs.append(window_truncated(pcm, t, deadline_s))
            players.append(player)
            tunes.append(tune)
        if index % 18 == 0:
            print(f"  negatives {tag}: {index}/{len(found)} takes, {len(xs)} so far",
                  flush=True)
    X = np.stack(xs).astype(np.float32)
    np.savez_compressed(path, X=X, player=np.array(players), tune=np.array(tunes))
    print(f"built {NEG_CACHE.format(tag)}: {X.shape} negatives")
    data = np.load(path)
    return data["X"], data["player"], data["tune"]


def split_masks(player, tune):
    """Train / test masks that are disjoint in BOTH player and tune."""
    train = np.isin(player, TRAIN_PLAYERS) & np.isin(tune, TRAIN_TUNES)
    test = np.isin(player, TEST_PLAYERS) & np.isin(tune, TEST_TUNES)
    return train, test


def stats():
    X, y, player, tune = build()
    down, up = int((y == 0).sum()), int((y == 1).sum())
    print(f"{len(y)} clean sweeps over {len(set(zip(player, tune)))} takes: "
          f"{down} down / {up} up ({100 * up / len(y):.0f}% up)")
    print(f"  windows {X.shape}, players {sorted(set(player.tolist()))}, "
          f"{len(set(tune.tolist()))} tunes")
    train, test = split_masks(player, tune)
    for label, mask in (("train (players 00-02 x 8 tunes)", train),
                        ("test  (players 03-05 x 4 tunes)", test),
                        ("unused (crossed combinations)", ~(train | test))):
        if mask.sum():
            print(f"  {label}: {mask.sum():5d} sweeps, "
                  f"{100 * (y[mask] == 0).mean():.0f}% down")
        else:
            print(f"  {label}: 0")
    for p in sorted(set(player.tolist())):
        mask = player == p
        print(f"    player {p}: {mask.sum():4d} sweeps, "
              f"{100 * (y[mask] == 0).mean():.0f}% down")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "build":
        build()
    else:
        stats()
