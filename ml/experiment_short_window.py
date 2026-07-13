"""r167 EXPERIMENT: how much eval accuracy does a SHORT window cost?

The live path needs a verdict ~70 ms after the onset; the shipped model sees
PRE 3 + POST 12 frames (~120 ms post-onset + FFT tail). A short variant
(PRE 3 + POST 7 = 10 frames) fits the live deadline — this measures what the
truncation costs on the SAME data/split/training recipe as train.py.

No dataset rebuild needed: window_at cuts rows center-3..center+11, so the
short window is exactly the first 10 rows of each stored 15-row window.

Writes NOTHING the app uses (weights_short.npz only). Compare against the
shipped 0.867 (r163).

Usage: /home/ubuntu/tf-venv/bin/python experiment_short_window.py [post_frames...]
"""
from __future__ import annotations

import sys

import numpy as np

from klangio import assert_folds_trainable, split_by_recording
from train import build_model

PRE = 3


def run(post: int):
    import tensorflow as tf

    d = np.load("klangio.npz")
    X, y = d["X"][:, : PRE + post, :], d["y"]
    tr, ev = split_by_recording(d["rec"])
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
              verbose=2, callbacks=[stop],
              validation_data=(Xn[ev], y[ev]))
    _, acc = model.evaluate(Xn[ev], y[ev], verbose=0)
    print(f"RESULT post={post} frames={PRE + post} eval_accuracy={acc:.4f} "
          f"(shipped post=12: 0.867)")
    np.savez(f"weights_short_p{post}.npz",
             *[w.astype(np.float32) for w in model.get_weights()],
             mean=mean.astype(np.float32), std=std.astype(np.float32))
    return acc


if __name__ == "__main__":
    posts = [int(a) for a in sys.argv[1:]] or [7]
    for p in posts:
        run(p)
