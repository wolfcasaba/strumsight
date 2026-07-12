"""Adapter for the PUBLIC Klangio strumming dataset (ml-track P2 step 1).

`github.com/Klangio/guitar-strumming-transcription` (Apache-2.0, ISMIR 2025,
arXiv:2508.07973) ships 56 recording sets under `dataset/klangio-gst-mm-2025/`:

    recording_<id>.strums       TAB-separated: time_s \t D|U \t chord-label
    recording_<id>_phone.wav    phone-mic take (our deployment condition)
    recording_<id>_line.wav     pickup take
    recording_<id>.csv          wrist-IMU (their labeling rig; unused here —
                                the .strums file IS the ground truth)

Fetch sets into `ml/data/klangio/` (gitignored — third-party data stays out of
the repo) with:

    curl -sL -o ml/data/klangio/recording_1001.strums \
      https://raw.githubusercontent.com/Klangio/guitar-strumming-transcription/main/dataset/klangio-gst-mm-2025/recording_1001.strums
    # same URL pattern for recording_<id>_phone.wav

Then build the training set (windows cut at the LABELED strum times — no onset
detection in the loop, the annotations are the truth):

    python3 ml/klangio.py            # stats over ml/data/klangio
    python3 ml/klangio.py build      # -> klangio.npz (X, y as in chunk 018)

Pure NumPy + stdlib — runs on this ARM64 box (TF only needed for train.py).
"""
from __future__ import annotations

import glob
import os
import sys

import numpy as np

import features as F
from prepare_dataset import _read_wav

#: .strums direction letters -> our label names (chunk 018 LABELS order).
DIRECTIONS = {"D": "down", "U": "up"}
LABELS = {"down": 0, "up": 1}


def parse_strums(text: str):
    """Parse .strums content -> list of (time_s, 'down'|'up', chord_label).

    Strict on directions (an unknown letter means we misread the format —
    fail loudly, never mislabel training data); blank lines are skipped.
    """
    events = []
    for ln, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise ValueError(f".strums line {ln}: expected 3 TAB fields, got {parts!r}")
        t, d, chord = parts
        if d not in DIRECTIONS:
            raise ValueError(f".strums line {ln}: unknown direction {d!r}")
        events.append((float(t), DIRECTIONS[d], chord))
    return events


def recording_ids(data_dir: str):
    """Sorted ids that have BOTH a .strums and a _phone.wav present."""
    ids = []
    for p in sorted(glob.glob(os.path.join(data_dir, "recording_*.strums"))):
        rid = os.path.basename(p)[len("recording_"):-len(".strums")]
        if os.path.exists(os.path.join(data_dir, f"recording_{rid}_phone.wav")):
            ids.append(rid)
    return ids


def windows_for_recording(pcm, events):
    """(X, y) for one 16 kHz recording: a log-mel window cut at each LABELED
    strum time (the dataset's annotations are ground truth — detection is not
    in the training loop)."""
    logmel = F.log_mel(pcm)
    xs, ys = [], []
    for t, direction, _chord in events:
        xs.append(F.window_at(logmel, t))
        ys.append(LABELS[direction])
    return xs, ys


def build(data_dir: str, out: str = "klangio.npz", variant: str = "phone"):
    """All recordings in [data_dir] -> a chunk-018-shaped dataset.npz.

    Besides X/y the npz carries `rec` (the recording id per window) so the
    train/eval split can be drawn BY RECORDING: some takes are single-
    direction and all share a room/guitar per take, so a window-level random
    split leaks recording identity into the direction task (round-140 lesson).
    """
    xs, ys, recs, per_rec = [], [], [], []
    for rid in recording_ids(data_dir):
        with open(os.path.join(data_dir, f"recording_{rid}.strums")) as fh:
            events = parse_strums(fh.read())
        pcm = _read_wav(
            os.path.join(data_dir, f"recording_{rid}_{variant}.wav"))
        x, y = windows_for_recording(pcm, events)
        xs.extend(x)
        ys.extend(y)
        recs.extend([rid] * len(y))
        per_rec.append((rid, len(y), sum(1 for v in y if v == 1)))
    if not xs:
        print(f"no complete recording sets under {data_dir} — see the fetch "
              "recipe in this file's docstring")
        return None
    X = np.stack(xs).astype(np.float32)
    y = np.array(ys, dtype=np.int64)
    rec = np.array(recs)
    np.savez_compressed(out, X=X, y=y, rec=rec)
    stats(per_rec, y)
    print(f"wrote {out}")
    return X, y, rec


def split_by_recording(rec, eval_frac: float = 0.2, seed: int = 42):
    """(train_mask, eval_mask) with WHOLE recordings on one side only.

    Never splits a recording across train/eval (identity leak); at least one
    recording always lands in eval. Deterministic per seed.
    """
    ids = sorted(set(rec.tolist()))
    rng = np.random.default_rng(seed)
    rng.shuffle(ids)
    n_eval = max(1, int(round(len(ids) * eval_frac)))
    eval_ids = set(ids[:n_eval])
    eval_mask = np.array([r in eval_ids for r in rec.tolist()])
    return ~eval_mask, eval_mask


def stats(per_rec, y):
    n_up = int((y == 1).sum())
    print(f"{len(per_rec)} recordings, {len(y)} strums: "
          f"{len(y) - n_up} down / {n_up} up "
          f"({0 if len(y) == 0 else 100 * n_up // len(y)}% up)")
    for rid, n, up in per_rec:
        print(f"  {rid}: {n} strums ({n - up} D / {up} U)")


def main():
    data_dir = os.path.join(os.path.dirname(__file__), "data", "klangio")
    if len(sys.argv) > 1 and sys.argv[1] == "build":
        build(data_dir)
        return
    per_rec, all_y = [], []
    for rid in recording_ids(data_dir):
        with open(os.path.join(data_dir, f"recording_{rid}.strums")) as fh:
            events = parse_strums(fh.read())
        y = [LABELS[d] for _, d, _ in events]
        per_rec.append((rid, len(y), sum(y)))
        all_y.extend(y)
    if not per_rec:
        print(f"no recording sets under {data_dir} — see the fetch recipe "
              "in this file's docstring")
        return
    stats(per_rec, np.array(all_y))


if __name__ == "__main__":
    main()
