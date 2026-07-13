"""r167 EXPERIMENT 2: TRUE deadline-limited models (audio-truncated).

experiment_short_window.py truncated FRAMES, but a log-mel frame at +60 ms
still integrates 2048 samples (128 ms) of FUTURE audio — the honest live
model must see ZEROS past its verdict deadline. Here each training window is
cut from audio that is zeroed past (onset + deadline), so train == serve.

Windows are rebuilt from the wavs (klangio.npz stores finished log-mel), on a
local slice per event for speed. Same split/recipe as train.py; eval accuracy
answers: what does a verdict at onset+D cost?

Usage: /home/ubuntu/tf-venv/bin/python experiment_deadline.py 0.070 0.188
"""
from __future__ import annotations

import sys

import numpy as np

import features as F
from klangio import (assert_folds_trainable, parse_strums, recording_ids,
                     split_by_recording)
from prepare_dataset import _read_wav
from train import build_model

DATA = "data/klangio"
FRAMES = F.PRE_FRAMES + F.POST_FRAMES  # keep the 15-frame geometry


def window_truncated(pcm, onset_s, deadline_s):
    """The (15, 128) log-mel window with audio ZEROED past onset+deadline."""
    center = int(round(onset_s * F.SR / F.HOP))
    lo_f = center - F.PRE_FRAMES
    lo_s = lo_f * F.HOP
    hi_s = (center + F.POST_FRAMES - 1) * F.HOP + F.N_FFT
    seg = np.zeros(hi_s - lo_s, dtype=np.float32)
    a, b = max(0, lo_s), min(len(pcm), hi_s)
    if b > a:
        seg[a - lo_s: b - lo_s] = pcm[a:b]
    cut = int(round((onset_s + deadline_s) * F.SR)) - lo_s
    seg[max(0, cut):] = 0.0
    lm = F.log_mel(seg)
    out = np.full((FRAMES, F.N_MELS), np.log(1e-6), dtype=np.float32)
    out[: min(FRAMES, len(lm))] = lm[:FRAMES]
    return out


def build_dataset(deadline_s):
    xs, ys, recs = [], [], []
    for rid in recording_ids(DATA):
        with open(f"{DATA}/recording_{rid}.strums") as fh:
            events = parse_strums(fh.read())
        pcm = _read_wav(f"{DATA}/recording_{rid}_phone.wav")
        for t, direction, _ in events:
            if t * F.SR >= len(pcm):
                continue
            xs.append(window_truncated(pcm, t, deadline_s))
            ys.append(0 if direction == "down" else 1)
            recs.append(rid)
    return np.stack(xs), np.array(ys), np.array(recs)


def run(deadline_s):
    import tensorflow as tf

    X, y, rec = build_dataset(deadline_s)
    tr, ev = split_by_recording(rec)
    assert_folds_trainable(y, tr, ev)
    mean = X[tr].mean(axis=(0, 1))
    std = X[tr].std(axis=(0, 1)) + 1e-6
    Xn = (X - mean) / std

    model = build_model(X.shape[1], X.shape[2])
    n_up = int((y[tr] == 1).sum()) or 1
    cw = {0: 1.0, 1: max(1.0, (y[tr] == 0).sum() / n_up)}
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=8, restore_best_weights=True)
    model.fit(Xn[tr], y[tr], epochs=40, batch_size=32, class_weight=cw,
              verbose=2, callbacks=[stop], validation_data=(Xn[ev], y[ev]))
    _, acc = model.evaluate(Xn[ev], y[ev], verbose=0)
    print(f"RESULT deadline={deadline_s * 1000:.0f}ms "
          f"eval_accuracy={acc:.4f} (full window: 0.867)")
    return acc


if __name__ == "__main__":
    for d in [float(a) for a in sys.argv[1:]] or [0.070]:
        run(d)
