"""Train the streaming strum-direction CRNN and export TFLite (chunk 015/018).

Needs TensorFlow (see requirements.txt); NOT runnable on the ARM64 dev box —
run in CI or Colab. The data pipeline (features.py / prepare_dataset.py) and its
smoke test are pure-NumPy and DO run locally; this is only the model step.

Architecture (arXiv 2508.07973-class, shrunk for on-device streaming):
  log-mel window (frames, mels) → 3 conv blocks → GRU(128) → Dense(2 softmax).
For deployment the GRU runs stateful, one 10 ms hop at a time, so the conv
receptive field is kept tiny (<30 ms lookahead). This trainer uses whole
windows; the exported graph is re-wired to single-step in export_streaming().

Usage: python3 ml/train.py dataset.npz [strum_direction.tflite]
"""
from __future__ import annotations

import sys

import numpy as np


def build_model(frames, mels):
    import tensorflow as tf  # noqa: WPS433 (lazy — keeps NumPy tools TF-free)
    L = tf.keras.layers
    return tf.keras.Sequential([
        L.Input(shape=(frames, mels)),
        L.Reshape((frames, mels, 1)),
        L.Conv2D(16, 3, padding="same", activation="relu"),
        L.MaxPool2D((1, 2)),
        L.Conv2D(32, 3, padding="same", activation="relu"),
        L.MaxPool2D((1, 2)),
        L.Conv2D(48, 3, padding="same", activation="relu"),
        L.MaxPool2D((1, 2)),
        L.Reshape((frames, -1)),
        L.GRU(128),
        L.Dense(2, activation="softmax"),
    ])


def main(npz_path, out="strum_direction.tflite"):
    import tensorflow as tf

    d = np.load(npz_path)
    X, y = d["X"], d["y"]
    print(f"dataset: {X.shape} windows, {int((y == 0).sum())} down / "
          f"{int((y == 1).sum())} up")

    # Eval split BY RECORDING when the npz carries ids (klangio.py) — some
    # takes are single-direction and share a room/guitar, so a window-level
    # split leaks recording identity into the eval score (round-140 lesson).
    # Normalisation stats come from the TRAIN fold only (r142 audit: full-X
    # stats leak eval data into the eval score).
    if "rec" in d:
        from klangio import assert_folds_trainable, split_by_recording

        tr, ev = split_by_recording(d["rec"])
        assert_folds_trainable(y, tr, ev)  # loud failure beats a fake model
        mean = X[tr].mean(axis=(0, 1))
        std = X[tr].std(axis=(0, 1)) + 1e-6
        Xn = (X - mean) / std
        fit_kw = {"validation_data": (Xn[ev], y[ev])}
        Xn, y = Xn[tr], y[tr]
        print(f"split by recording: {int(tr.sum())} train / "
              f"{int(ev.sum())} eval windows")
    else:
        mean, std = X.mean(axis=(0, 1)), X.std(axis=(0, 1)) + 1e-6
        Xn = (X - mean) / std
        fit_kw = {"validation_split": 0.2}  # legacy dataset.npz (no ids)

    # Store these; the Dart side must apply the same standardisation.
    np.savez("norm.npz", mean=mean, std=std)

    model = build_model(X.shape[1], X.shape[2])
    # Up-strums are the minority + harder class → weight them up (chunk 015).
    n_up = int((y == 1).sum()) or 1
    cw = {0: 1.0, 1: max(1.0, (y == 0).sum() / n_up)}
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    model.fit(Xn, y, epochs=30, batch_size=32,
              class_weight=cw, verbose=2, **fit_kw)

    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]  # int8-ish size cut
    open(out, "wb").write(conv.convert())
    print(f"wrote {out} — copy to assets/ and wire via tflite_flutter "
          f"(keep ONE win32 major; see chunk 018)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "strum_direction.tflite")
