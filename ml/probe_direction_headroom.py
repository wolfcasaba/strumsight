"""E18-R27 - how much down/up information is in the input the LIVE model ALREADY gets?

## CORRECTED BY E18-R28 (ADR 0551) - this file's headline number is NOT the model's input

`centred_starts` below CENTRES each analysis window on its frame
(`onset - PRE_FRAMES*HOP - N_FFT//2`, i.e. onset-94 ms) and applies NO live-deadline
truncation. The shipped path (`experiment_deadline.window_truncated`) STARTS each window
at its frame (onset-30 ms) and zeroes everything past onset+70 ms. So this file hands the
classifier 64 ms of extra lead-in plus the audio past the deadline -- and section 3 below
measures that lead-in ALONE predicts direction at AUC 0.7128 by alternation, which the
same round's ADR said must not be counted.

    this file's headline, probe alignment, no truncation   macro 0.7723
    the same labels at the MODEL's alignment + 70 ms cut   macro 0.5885

Use `ml/probe_direction_budget.py` for numbers about the shipped input. This file is kept
as the record of how the error was found, and because sections 2 and 3 -- the controls and
the pre/post separation -- are unaffected by the alignment and are what caught it.


The shipped 3-class live CRNN scores direction macro-F1 0.3876 (up-F1 0.1905) on
GuitarSet (`docs/eval/guitarset-strum-baseline.md`). ADR 0549 raised the no-strum gate
and that helped; the round after it proved moving the decision boundary does NOT help -
it only fits the class prior (LESSONS L664). Both of those tuned a scalar. This asks a
different question, and it is the one that decides where the defect actually is:

    Is the direction cue PRESENT in the model's own input, and simply not extracted?

It is answered by fitting a plain logistic regression on band-pooled features taken with
the model's OWN transform geometry (ml/features.py: N_FFT 2048 @ 16 kHz = a 128 ms
window, HOP 160 = 10 ms, 15 frames) and comparing it against the shipped CRNN on the
same labels. A linear model is far weaker than a CRNN, so whatever it reaches is a FLOOR
on what is extractable from that input - not a ceiling.

Ground truth is GuitarSet's hexaphonic per-string onsets: the order in which the strings
enter IS the direction. The grouping and the `isClean` filter are the ones in
`test/tooling/guitarset_direction_boundary_test.dart`, so these numbers are comparable
to the shipped-path measurement rather than merely similar to it.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_headroom.py

numpy + scikit-learn only, no TF. **The recordings are NOT committed.**

## What it controls for, and why each control is here

Four consecutive measurement rounds failed on the instrument rather than the result
(LESSONS L660-L664), so every number below has to survive a control:

  * SPLIT. Every GuitarSet player plays the SAME 12 Rock/Funk tunes, so a
    player-disjoint split leaves the progression shared, and a classifier can memorise
    "this chord at this point in this tune" -> beat position -> direction. Hence three
    splits: player-disjoint, tune-disjoint, and BOTH.
  * SHUFFLED LABELS, 7 seeds. One seed is not a control: the first shuffle drew
    AUC 0.5776 and looked like leakage. Seven seeds put the null band at 0.35-0.59.
  * STRING COUNT. Upstrokes in comping often hit fewer strings, so "direction" could be
    a proxy for "how many strings sounded". Reported per note count, plus note count
    alone as a one-feature model.
  * STRICTLY PRE vs STRICTLY POST onset. A 128 ms window centred near the onset contains
    the attack in EVERY frame, so a frame-index ablation CANNOT separate "measuring this
    stroke" from "guessing from the last one". These two arms are cut so one sees only
    audio before the onset and the other only audio at or after it. That matters beyond
    tidiness: comping alternates down-up-down-up, so a model with pre-onset context can
    score well by predicting alternation - and the app's own patterns do not alternate
    (`D DU UDU` has two downs in a row), so here that cue would be a lie.
"""
from __future__ import annotations

import glob
import json
import os
import sys
import wave

import numpy as np

# --- ground truth, mirroring guitarset_direction_boundary_test.dart ------------------
LINK_MS = 45.0
STYLES = ("Rock", "Funk")

# --- the model's own geometry (ml/features.py) and a high-resolution counterpart -----
MODEL_SR, MODEL_NFFT, MODEL_HOP = 16000, 2048, 160   # 128 ms window, 10 ms hop
HIRES_SR, HIRES_NFFT, HIRES_HOP = 44100, 256, 163    # 5.8 ms window, 3.7 ms hop
N_BANDS, N_FRAMES, PRE_FRAMES = 16, 15, 3            # 240 features - BOTH arms
BAND_EDGES = np.geomspace(80.0, 8000.0, N_BANDS + 1)

# Strictly-causal arms: 6 frames whose windows END at the onset, 9 that START at it.
N_STRICT_PRE, N_STRICT_POST = 6, 9

# GuitarSet's 12 Rock+Funk comping tunes, split so train and test share no progression.
TRAIN_TUNES = {
    "Funk1-114-Ab", "Funk1-97-C", "Funk2-108-Eb", "Funk2-119-G",
    "Rock1-130-A", "Rock1-90-C#", "Rock2-142-D", "Rock2-85-F",
}
TEST_TUNES = {"Funk3-112-C#", "Funk3-98-A", "Rock3-117-Bb", "Rock3-148-C"}
TRAIN_PLAYERS, TEST_PLAYERS = {"00", "01", "02"}, {"03", "04", "05"}

# The shipped path on the same clean labels - the only comparison that matters.
SHIPPED = "shipped CRNN, same clean labels: down 0.5848  up 0.1905  macro 0.3876"


# --------------------------------------------------------------------------- truth
def per_string_onsets(jams):
    """Every annotated note onset with the string that produced it (0 = low E)."""
    out = []
    for ann in jams["annotations"]:
        if ann.get("namespace") != "note_midi":
            continue
        source = (ann.get("annotation_metadata") or {}).get("data_source")
        try:
            string = int(source)
        except (TypeError, ValueError):
            continue
        out.extend((float(ob["time"]), string) for ob in ann["data"])
    out.sort()
    return out


def direction_of(group):
    """Pairwise concordance of time order with string order. Down sweeps low -> high."""
    score_ = 0
    for i in range(len(group)):
        for k in range(i + 1, len(group)):
            dt = group[k][0] - group[i][0]
            ds = group[k][1] - group[i][1]
            if dt and ds:
                score_ += 1 if ds > 0 else -1
    return "down" if score_ > 0 else ("up" if score_ < 0 else None)


def clean_sweeps(jams):
    """Groups of near-simultaneous notes that are unambiguously a directional sweep."""
    groups = []
    for onset in per_string_onsets(jams):
        if groups and (onset[0] - groups[-1][-1][0]) * 1000 <= LINK_MS:
            groups[-1].append(onset)
        else:
            groups.append([onset])
    out = []
    for group in groups:
        if len(group) < 3:
            continue
        strings = [s for _, s in group]
        if strings not in (sorted(strings), sorted(strings, reverse=True)):
            continue  # not monotone: arpeggiated or mis-annotated, not a sweep
        spread_ms = (group[-1][0] - group[0][0]) * 1000
        direction = direction_of(group)
        if direction is None or spread_ms < 5:
            continue
        out.append({"at": group[0][0], "dir": direction,
                    "n": len(group), "spread_ms": spread_ms})
    return out


# ------------------------------------------------------------------------- features
def read_mono(path):
    with wave.open(path, "rb") as handle:
        sr, frames, channels = (handle.getframerate(), handle.getnframes(),
                                handle.getnchannels())
        raw = handle.readframes(frames)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return (x.reshape(-1, channels).mean(axis=1) if channels > 1 else x), sr


def resample_linear(x, frm, to):
    """ml/features.py's contract: linear interpolation, both sides or neither."""
    n = int(round(len(x) * to / frm))
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def band_patch(x, sr, starts, nfft):
    """Loudness-invariant log band energies for the windows beginning at `starts`."""
    if starts[0] < 0 or starts[-1] + nfft > len(x):
        return None
    window = np.hanning(nfft)
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    masks = [(freqs >= BAND_EDGES[b]) & (freqs < BAND_EDGES[b + 1])
             for b in range(N_BANDS)]
    out = np.empty((len(starts), N_BANDS))
    for i, start in enumerate(starts):
        mag = np.abs(np.fft.rfft(x[start:start + nfft] * window))
        for b, mask in enumerate(masks):
            out[i, b] = mag[mask].sum() if mask.any() else 0.0
    total = out.sum()
    # Normalising by the patch total is what makes this a TIMBRE measurement and not a
    # loudness one: a hard downstroke is louder than a light upstroke, and a model
    # allowed to read that would be scoring dynamics while appearing to score direction.
    return None if total <= 0 else np.log1p(out / total * 1000.0).ravel()


def centred_starts(onset_sample, hop, nfft):
    """The model's own alignment: PRE_FRAMES hops back, each window centred on a frame."""
    first = onset_sample - PRE_FRAMES * hop - nfft // 2
    return [first + f * hop for f in range(N_FRAMES)]


def extract(root):
    """Every clean sweep in GuitarSet's Rock+Funk comping, as four feature views."""
    audio_dir, ann_dir = f"{root}/audio_mono-mic", f"{root}/annotation"
    wavs = sorted(f for f in glob.glob(f"{audio_dir}/*_comp_mic.wav")
                  if any(s in os.path.basename(f) for s in STYLES))
    if not wavs:
        sys.exit(f"no Rock/Funk comping WAVs under {audio_dir}")
    rows = {"lo": [], "hi": [], "pre": [], "post": []}
    meta = []
    for index, wav in enumerate(wavs, 1):
        base = os.path.basename(wav)
        jams_path = os.path.join(ann_dir, base.replace("_mic.wav", ".jams"))
        if not os.path.exists(jams_path):
            continue
        with open(jams_path, encoding="utf-8") as handle:
            sweeps = clean_sweeps(json.load(handle))
        x44, sr = read_mono(wav)
        x16 = resample_linear(x44, sr, MODEL_SR)
        for sweep in sweeps:
            o16 = int(round(sweep["at"] * MODEL_SR))
            o44 = int(round(sweep["at"] * HIRES_SR))
            views = {
                "lo": band_patch(x16, MODEL_SR,
                                 centred_starts(o16, MODEL_HOP, MODEL_NFFT),
                                 MODEL_NFFT),
                "hi": band_patch(x44, HIRES_SR,
                                 centred_starts(o44, HIRES_HOP, HIRES_NFFT),
                                 HIRES_NFFT),
                # Strictly before: the LAST window ends exactly at the onset.
                "pre": band_patch(x16, MODEL_SR,
                                  [o16 - MODEL_NFFT - f * MODEL_HOP
                                   for f in range(N_STRICT_PRE - 1, -1, -1)],
                                  MODEL_NFFT),
                # Strictly at or after: the FIRST window starts exactly at the onset.
                "post": band_patch(x16, MODEL_SR,
                                   [o16 + f * MODEL_HOP
                                    for f in range(N_STRICT_POST)],
                                   MODEL_NFFT),
            }
            if any(v is None for v in views.values()):
                continue  # too close to a file edge for one of the views
            for key, value in views.items():
                rows[key].append(value)
            meta.append((base[:2], base[3:].replace("_comp_mic.wav", ""),
                         1 if sweep["dir"] == "up" else 0,
                         sweep["n"], sweep["spread_ms"]))
        if index % 18 == 0:
            print(f"  {index}/{len(wavs)} files", flush=True)
    return ({k: np.asarray(v) for k, v in rows.items()},
            np.array([m[0] for m in meta]), np.array([m[1] for m in meta]),
            np.array([m[2] for m in meta]), np.array([m[3] for m in meta]),
            np.array([m[4] for m in meta]))


# --------------------------------------------------------------------------- scoring
def score(X, y, train, test, shuffle_seed=None):
    # Imported here, not at module scope: `ml/guitarset.py` imports this module only for
    # the LABEL derivation, and a training-corpus loader must not need scikit-learn.
    try:
        from sklearn.linear_model import LogisticRegression
        from sklearn.metrics import f1_score, roc_auc_score
    except ImportError:  # pragma: no cover - dev tool
        sys.exit("needs scikit-learn: pip install scikit-learn")
    y_train = y[train]
    if shuffle_seed is not None:
        y_train = np.random.default_rng(shuffle_seed).permutation(y_train)
    model = LogisticRegression(max_iter=4000, C=0.3, class_weight="balanced")
    model.fit(X[train], y_train)
    predicted = model.predict(X[test])
    down = f1_score(y[test], predicted, pos_label=0)
    up = f1_score(y[test], predicted, pos_label=1)
    auc = roc_auc_score(y[test], model.predict_proba(X[test])[:, 1])
    return down, up, (down + up) / 2, auc, predicted


def line(label, result):
    down, up, macro, auc = result[:4]
    print(f"  {label:<44} down {down:.4f}  up {up:.4f}  "
          f"macro {macro:.4f}  AUC {auc:.4f}")


def main():
    root = os.environ.get("GUITARSET_DIR")
    if not root:
        sys.exit("set GUITARSET_DIR to the GuitarSet root (audio_mono-mic + annotation)")
    views, player, tune, y, n_strings, spread = extract(root)
    print(f"\n{len(y)} clean sweeps, {100 * (1 - y.mean()):.1f}% down")
    print(f"  sweep spread ms: median {np.median(spread):.1f}, "
          f"p95 {np.percentile(spread, 95):.1f}; "
          f"{100 * (spread < 20).mean():.1f}% span under two 10 ms model frames")

    in_player = np.isin(player, list(TRAIN_PLAYERS))
    out_player = np.isin(player, list(TEST_PLAYERS))
    in_tune, out_tune = np.isin(tune, list(TRAIN_TUNES)), np.isin(tune, list(TEST_TUNES))
    splits = {
        "A player-disjoint (tunes SHARED)": (in_player, out_player),
        "B tune-disjoint (players SHARED)": (in_tune, out_tune),
        "C BOTH disjoint": (in_player & in_tune, out_player & out_tune),
    }

    print("\n=== 1. is the cue in the model's own input? "
          "(resolution is the only variable; 240 features in BOTH arms) ===")
    for label, (train, test) in splits.items():
        print(f"  {label}  train {train.sum()} / test {test.sum()}, "
              f"test {100 * (1 - y[test].mean()):.0f}% down")
        line("    lo = model geometry (128 ms, 10 ms hop)",
             score(views["lo"], y, train, test))
        line("    hi = 5.8 ms window, 3.7 ms hop",
             score(views["hi"], y, train, test))

    train, test = splits["C BOTH disjoint"]
    print("\n=== 2. controls, all on split C ===")
    aucs = [score(views["lo"], y, train, test, shuffle_seed=s)[3] for s in range(7)]
    print(f"  shuffled labels, 7 seeds: AUC {min(aucs):.4f}..{max(aucs):.4f} "
          f"(mean {np.mean(aucs):.4f})")
    predicted = score(views["lo"], y, train, test)[4]
    for count in sorted(set(n_strings[test])):
        mask = n_strings[test] == count
        print(f"  note count {count}: {(y[test][mask] == 0).sum():4d} down / "
              f"{(y[test][mask] == 1).sum():4d} up, "
              f"accuracy {(predicted[mask] == y[test][mask]).mean():.4f}")
    from sklearn.metrics import f1_score  # lazy, see score()

    balanced = [c for c in set(n_strings[test])
                if (y[test][n_strings[test] == c] == 0).sum() >= 20
                and (y[test][n_strings[test] == c] == 1).sum() >= 20]
    mask = np.isin(n_strings[test], balanced)
    down = f1_score(y[test][mask], predicted[mask], pos_label=0)
    up = f1_score(y[test][mask], predicted[mask], pos_label=1)
    print(f"  note counts with >=20 of BOTH classes {sorted(balanced)}: "
          f"down {down:.4f}  up {up:.4f}  macro {(down + up) / 2:.4f} (n={mask.sum()})")
    counts = n_strings.reshape(-1, 1).astype(float)
    print("  note count ALONE as the only feature: "
          f"AUC {score(counts, y, train, test)[3]:.4f}")

    print("\n=== 3. measuring the stroke, or guessing from the last one? (split C) ===")
    line("pre  = audio STRICTLY BEFORE the onset", score(views["pre"], y, train, test))
    line("post = audio STRICTLY AT/AFTER the onset", score(views["post"], y, train, test))
    line("both", score(np.hstack([views["pre"], views["post"]]), y, train, test))
    print(f"\n  {SHIPPED}")


if __name__ == "__main__":
    main()
