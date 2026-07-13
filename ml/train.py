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

import os
import random
import sys

import numpy as np


def set_seeds(seed: int) -> None:
    """Make a training run reproducible (r171 honest-measurement).

    Seeds Python, NumPy and TensorFlow RNGs and pins PYTHONHASHSEED so weight
    init, the class-weighted shuffle and dropout (if any) repeat run-to-run.
    Point estimates from a single unseeded run were noise (r171); with this,
    `--seed` sweeps tell signal from variance.
    """
    os.environ["PYTHONHASHSEED"] = str(seed)
    random.seed(seed)
    np.random.seed(seed)
    import tensorflow as tf  # noqa: WPS433
    tf.random.set_seed(seed)
    tf.keras.utils.set_random_seed(seed)


def build_model(frames, mels, dropout=0.0, rec_dropout=0.0, l2=0.0,
                n_classes=2):
    """The streaming CRNN. With all regularization args at 0 AND n_classes=2
    (the defaults) this is BYTE-IDENTICAL to the shipped architecture — no extra
    layers, no weight reordering — so every existing fixture / exported-weight
    parity test still holds. r173 adds optional regularization (dropout after
    each conv pool, GRU dropout / recurrent_dropout, L2 weight decay) to attack
    the documented train-0.99 / val-0.84 overfit on ~364k params; Dropout layers
    carry no weights, so even the regularized graph keeps the same get_weights()
    order. r174 adds `n_classes` for the no-strum reject head: n_classes=3 makes
    the final Dense (down / up / no-strum) softmax; class order is preserved
    (0=down, 1=up, 2=no-strum) so a 3-class model's [:, :2] is the same direction
    logit space as the 2-class model. Only the final Dense changes width — the
    trunk (conv + GRU) is identical, so 3-class weights back-port cleanly.
    """
    import tensorflow as tf  # noqa: WPS433 (lazy — keeps NumPy tools TF-free)
    L = tf.keras.layers
    reg = tf.keras.regularizers.l2(l2) if l2 else None

    def conv(filters):
        return L.Conv2D(filters, 3, padding="same", activation="relu",
                        kernel_regularizer=reg)

    layers = [L.Input(shape=(frames, mels)), L.Reshape((frames, mels, 1))]
    for filt in (16, 32, 48):
        layers.append(conv(filt))
        layers.append(L.MaxPool2D((1, 2)))
        if dropout:
            layers.append(L.Dropout(dropout))
    layers.append(L.Reshape((frames, -1)))
    layers.append(L.GRU(128, dropout=dropout, recurrent_dropout=rec_dropout,
                        kernel_regularizer=reg))
    layers.append(L.Dense(n_classes, activation="softmax",
                          kernel_regularizer=reg))
    return tf.keras.Sequential(layers)


def main(npz_path, out="strum_direction.tflite", seed=42):
    import tensorflow as tf

    set_seeds(seed)
    print(f"seed={seed}")
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
    # The net overfits the ~10k-window set fast (observed 2026-07-13: train
    # 0.99 vs val ~0.84 by epoch 8, val loss rising) — keep the BEST-val
    # weights, never the last epoch's.
    stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=8, restore_best_weights=True)
    model.fit(Xn, y, epochs=40, batch_size=32, shuffle=True,
              class_weight=cw, verbose=2, callbacks=[stop], **fit_kw)

    # Raw float32 weights FIRST — this is the shipping path (ml-track P1.3,
    # revised 2026-07-13: pure-Dart inference; the model is tiny enough to run
    # in hand-written Dart, which keeps the win32 rule safe and makes
    # inference host-testable). Order = model.get_weights() (documented in
    # the Dart loader). Never let the optional tflite step destroy a finished
    # training run (2026-07-13: the converter crashed on the GRU's TensorList
    # lowering in TF 2.21 and took the un-exported weights with it).
    ws = model.get_weights()
    np.savez("weights.npz", *[w.astype(np.float32) for w in ws],
             mean=mean.astype(np.float32), std=std.astype(np.float32))
    print(f"wrote weights.npz ({len(ws)} arrays) for the Dart inference port")
    model.save("strum_model.keras")  # re-exports never need a retrain

    try:
        conv = tf.lite.TFLiteConverter.from_keras_model(model)
        conv.optimizations = [tf.lite.Optimize.DEFAULT]  # int8-ish size cut
        open(out, "wb").write(conv.convert())
        print(f"wrote {out} (optional native path)")
    except Exception as e:  # noqa: BLE001 — best-effort side artifact
        print(f"tflite export failed (non-fatal, Dart path unaffected): "
              f"{type(e).__name__}: {str(e)[:300]}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--seed")]
    seed = 42
    for a in sys.argv[1:]:
        if a.startswith("--seed="):
            seed = int(a.split("=", 1)[1])
    if not args:
        print(__doc__)
        sys.exit(1)
    main(args[0], args[1] if len(args) > 1 else "strum_direction.tflite",
         seed=seed)
