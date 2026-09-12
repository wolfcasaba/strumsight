"""E18-R28 - how much AUDIO does the direction cue need, at the model's real alignment?

This file exists because the previous round's headline was wrong, and the error is worth
keeping visible.

ADR 0550 reported a linear floor of macro-F1 0.7723 and called it "the input the model
already gets". It was not. `probe_direction_headroom.centred_starts` CENTRES each
analysis window on its frame:

    start = onset - PRE_FRAMES * HOP - N_FFT // 2      ->  onset - 94 ms

while `experiment_deadline.window_truncated`, which is what actually feeds the shipped
model, STARTS each window at its frame and zeroes the tail past the live deadline:

    start = (center - PRE_FRAMES) * HOP               ->  onset - 30 ms
    seg[onset + 70 ms:] = 0

So the probe was handed 64 ms of extra lead-in AND the audio past the 70 ms deadline.
That matters specifically because ADR 0550 D3 had already measured that audio strictly
BEFORE the onset predicts direction at AUC 0.7128, and ruled that inadmissible. The probe
was scoring partly with the cue the same ADR forbade. Measured at the model's real
alignment the floor is 0.5885, not 0.7723 (`ml/probe_direction_headroom.py` is kept as the
record of how that was found; this file is the corrected measurement).

ADR 0550 D3 called that pre-onset cue "alternation". It is not: consecutive strokes share
a direction 61.4 % of the time in GuitarSet, so alternation cannot be what carries it. The
mechanism is worse, and `take_id_oracle` below measures it - 128 ms of room, guitar and
chord voicing identifies WHICH TAKE this is, and each take's own class prior does the rest.
Nothing about the stroke is involved. The decision not to count pre-onset context is
unchanged and better founded than when it was made.

    GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_budget.py

What the corrected sweep then shows is a real, and more useful, constraint: the cue needs
roughly 150-250 ms of POST-onset audio. Between 150 ms and no truncation the up-F1 nearly
doubles. Direction on a microphone is not an attack-transient feature -- it lives in the
DECAY, in which strings keep ringing and how the pick's travel shapes them. That is also
why higher time resolution measured worse (ADR 0550 D4) and why a 128 ms analysis window
was never the problem.

Two arms, so frame COUNT cannot be confused with audio DURATION: the shipped 15 frames
(spanning 238 ms) and a 28-frame extension (368 ms). More frames buy nothing; more audio
does.

numpy + scikit-learn only. **The recordings are NOT committed.**
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

try:
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import f1_score, roc_auc_score
except ImportError:  # pragma: no cover - dev tool
    sys.exit("needs scikit-learn: pip install scikit-learn")

import features as F
import guitarset as G
from probe_direction_headroom import clean_sweeps, read_mono, resample_linear

N_BANDS = 16
BAND_EDGES = np.geomspace(80.0, 8000.0, N_BANDS + 1)
FRAME_COUNTS = (15, 28)  # 15 = the shipped geometry
DEADLINES = (0.040, 0.070, 0.100, 0.150, 0.250, None)  # None = no truncation
_WINDOW = np.hanning(F.N_FFT)
_FREQS = np.fft.rfftfreq(F.N_FFT, 1.0 / F.SR)
_MASKS = [(_FREQS >= BAND_EDGES[b]) & (_FREQS < BAND_EDGES[b + 1])
          for b in range(N_BANDS)]


def represent(pcm, onset_s, deadline, n_frames):
    """`window_truncated`'s exact segment, read as 16 geometric magnitude bands.

    Band sums rather than the shipped 128 log-mels only so the feature count stays small
    enough for a linear model on ~1000 training sweeps; measured side by side the choice
    is worth about +0.03 macro, so it is not what this file is about.
    """
    center = int(round(onset_s * F.SR / F.HOP))
    lo = (center - F.PRE_FRAMES) * F.HOP
    hi = lo + (n_frames - 1) * F.HOP + F.N_FFT
    seg = np.zeros(hi - lo)
    a, b = max(0, lo), min(len(pcm), hi)
    if b > a:
        seg[a - lo:b - lo] = pcm[a:b]
    if deadline is not None:
        seg[max(0, int(round((onset_s + deadline) * F.SR)) - lo):] = 0.0
    out = np.empty((n_frames, N_BANDS))
    for i in range(n_frames):
        mag = np.abs(np.fft.rfft(seg[i * F.HOP:i * F.HOP + F.N_FFT] * _WINDOW))
        for j, mask in enumerate(_MASKS):
            out[i, j] = mag[mask].sum()
    return np.log(np.maximum(out, 1e-6)).ravel()


def take_id_oracle(take, y, test):
    """A baseline that knows NOTHING about the stroke: only which take it came from.

    It answers each take's own majority direction, fitted on the test takes themselves -
    deliberately generous, because the point is an upper bound on what "recognise the
    recording, apply its prior" can buy. 128 ms of room, guitar and chord voicing is
    plenty to identify a take, so any reader with pre-onset context can reach this for
    free (ADR 0550 D3 measured AUC 0.7128 from strictly pre-onset audio and called the
    mechanism alternation; the flip rate is only 38.6%, and THIS is the real mechanism).

    Two separate things come out of it.

    1. MACRO-F1 floor. Every test take is under 50 % up, so the oracle collapses to
       "always down" - it IS the majority-class baseline, and scores macro 0.4467 here
       (0.4468 over the full 530-sweep set; this file drops one sweep because every cell
       must have room for the longest window). The shipped 3-class CRNN scores 0.3876 end
       to end on this corpus, i.e. BELOW a system that ignores the audio. That is the
       number to quote when anyone asks how the direction head is doing.
    2. AUC is unreadable here. RANKING by each take's up-rate - still zero stroke
       information - reaches AUC 0.7399, because identifying the recording is enough to
       order the corpus. So an AUC below ~0.74 on this corpus is no evidence of direction
       discrimination at all: the shipped log-mel arm's 0.6523 is under it and the 16-band
       arms at 40-100 ms only scrape past it. Read macro-F1, where the oracle sits at
       0.4467 because it cannot emit a single upstroke.
    """
    rate = {t: y[test][take[test] == t].mean() for t in set(take[test].tolist())}
    score = np.array([rate[t] for t in take[test]])
    predicted = (score > 0.5).astype(int)
    down = f1_score(y[test], predicted, pos_label=0)
    up = f1_score(y[test], predicted, pos_label=1)
    return down, up, (down + up) / 2, roc_auc_score(y[test], score)


def span_ms(n_frames):
    """Audio after the onset that `n_frames` windows can reach."""
    return ((n_frames - 1) * F.HOP + F.N_FFT - F.PRE_FRAMES * F.HOP) / F.SR * 1000


def collect(root):
    cells = {(d, n): [] for d in DEADLINES for n in FRAME_COUNTS}
    meta = []
    takes = G.takes(root)
    if not takes:
        sys.exit(f"no Rock/Funk comping takes under {root}/audio_mono-mic")
    for index, (wav, jams, player, tune) in enumerate(takes, 1):
        with open(jams, encoding="utf-8") as handle:
            sweeps = clean_sweeps(json.load(handle))
        raw, sr = read_mono(wav)
        pcm = resample_linear(raw, sr, F.SR)
        for sweep in sweeps:
            # Every cell must describe the SAME sweeps, so require room for the longest.
            if (sweep["at"] + 0.35) * F.SR >= len(pcm):
                continue
            for deadline in DEADLINES:
                for n_frames in FRAME_COUNTS:
                    cells[(deadline, n_frames)].append(
                        represent(pcm, sweep["at"], deadline, n_frames))
            meta.append((player, tune, 1 if sweep["dir"] == "up" else 0))
        if index % 18 == 0:
            print(f"  {index}/{len(takes)} takes", flush=True)
    return (cells, np.array([m[0] for m in meta]), np.array([m[1] for m in meta]),
            np.array([m[2] for m in meta]),
            np.array([f"{m[0]}_{m[1]}" for m in meta]))


def main():
    root = os.environ.get("GUITARSET_DIR")
    if not root:
        sys.exit("set GUITARSET_DIR to the GuitarSet root")
    cells, player, tune, y, take = collect(root)
    train, test = G.split_masks(player, tune)
    print(f"\n{len(y)} clean sweeps, train {train.sum()} / test {test.sum()} "
          f"(disjoint in player AND tune), {100 * (1 - y[test].mean()):.0f}% down in test")
    oracle = take_id_oracle(take, y, test)
    print(f"\n  NO-INFORMATION BASELINE - the take-id oracle knows nothing about the "
          f"stroke:\n    down {oracle[0]:.4f}  up {oracle[1]:.4f}  "
          f"macro {oracle[2]:.4f}  AUC {oracle[3]:.4f}\n"
          f"    Read MACRO-F1, not AUC: zero stroke information already reaches "
          f"AUC {oracle[3]:.4f} here.")
    print("\n  frames  audio kept after onset     down      up    macro     AUC")
    for n_frames in FRAME_COUNTS:
        for deadline in DEADLINES:
            X = np.asarray(cells[(deadline, n_frames)])
            model = LogisticRegression(max_iter=6000, C=0.3, class_weight="balanced")
            model.fit(X[train], y[train])
            predicted = model.predict(X[test])
            down = f1_score(y[test], predicted, pos_label=0)
            up = f1_score(y[test], predicted, pos_label=1)
            auc = roc_auc_score(y[test], model.predict_proba(X[test])[:, 1])
            label = (f"all ({span_ms(n_frames):.0f} ms)" if deadline is None
                     else f"{deadline * 1000:.0f} ms"
                     + (" (SHIPPED)" if deadline == 0.070 else ""))
            print(f"  {n_frames:4d}    {label:<24} {down:.4f}  {up:.4f}  "
                  f"{(down + up) / 2:.4f}  {auc:.4f}")
    print("\n  shipped log-mel 128 at the SAME alignment and 70 ms cut: "
          "down 0.7857  up 0.3913  macro 0.5885")
    print(f"  shipped 3-class CRNN END TO END on this corpus:            "
          f"down 0.5848  up 0.1905  macro 0.3876  <- BELOW the oracle's "
          f"{oracle[2]:.4f}")
    print("  trained CRNN (Klangio+GuitarSet, 70 ms cut):              "
          "down 0.5835  up 0.4199  macro 0.5017")
    print("  ADR 0550's 0.7723 came from a 64 ms-earlier window start and no "
          "truncation -- see this file's docstring.")


if __name__ == "__main__":
    main()
