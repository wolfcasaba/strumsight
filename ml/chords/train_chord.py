"""Train the v0 CHORD-recognition model (phase 1) — frame-wise majmin over CQT.

Runs on x86 CI (TensorFlow). Reuses the strum pipeline's discipline: seed
control, split-by-recording (no leakage), best-val restore, train-only norm.
This v0 trains on REAL Klangio solo-guitar chord data to validate the whole
pipeline end-to-end; the full-band synthetic + GuitarSet corpus comes next.

Model: CQT (T,144) -> 3 conv blocks (pool freq only) -> Dense -> (Bi)GRU
return_sequences -> TimeDistributed Dense(25) softmax. Metric = frame-wise
majmin accuracy = WCSR (uniform hops), the MIREX-standard chord score.

Usage (CI):  python3 ml/chords/train_chord.py
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords import dataset  # noqa: E402
from chords.labels import N_CLASSES  # noqa: E402

WIN = 100
SEED = 42


def set_seeds(seed=SEED):
    import random
    import tensorflow as tf
    random.seed(seed)
    np.random.seed(seed)
    tf.random.set_seed(seed)


def build_chord_model(win=WIN, n_bins=144, n_classes=N_CLASSES,
                      bidirectional=True, gru=96, dropout=0.1):
    """CQT sequence -> per-frame chord posteriors."""
    from tensorflow.keras import layers, models
    m = models.Sequential(name="chord_crnn")
    m.add(layers.Input(shape=(win, n_bins)))
    m.add(layers.Reshape((win, n_bins, 1)))
    for f in (16, 32, 32):
        m.add(layers.Conv2D(f, 3, padding="same", activation="relu"))
        m.add(layers.BatchNormalization())
        m.add(layers.MaxPooling2D((1, 2)))  # pool FREQ only, keep time
        if dropout:
            m.add(layers.Dropout(dropout))
    # (win, n_bins/8, 32) -> per-frame feature vector
    m.add(layers.Reshape((win, (n_bins // 8) * 32)))
    m.add(layers.TimeDistributed(layers.Dense(128, activation="relu")))
    rnn = layers.GRU(gru, return_sequences=True)
    m.add(layers.Bidirectional(rnn) if bidirectional else rnn)
    m.add(layers.TimeDistributed(layers.Dense(n_classes, activation="softmax")))
    return m


def split_by_recording(rec, val_frac=0.25, seed=SEED):
    """Assign whole recordings to train/val (no window leakage across folds)."""
    ids = sorted(set(rec.tolist()))
    rng = np.random.default_rng(seed)
    rng.shuffle(ids)
    n_val = max(1, int(round(len(ids) * val_frac)))
    val_ids = set(ids[:n_val])
    val_mask = np.array([r in val_ids for r in rec])
    return ~val_mask, val_mask, sorted(val_ids)


def main():
    import tensorflow as tf
    set_seeds()

    print("Building Klangio chord dataset (CQT + frame labels)...", flush=True)
    X, Y, rec, ids = dataset.build(win=WIN, step=WIN // 2)
    if X.shape[0] == 0:
        print("No data (ml/data/klangio absent) — abort.")
        return
    print(f"X {X.shape}  Y {Y.shape}  recordings {len(ids)}", flush=True)
    dist = np.bincount(Y.ravel(), minlength=N_CLASSES)
    print("class balance:", dist.tolist(), flush=True)

    tr, va, val_ids = split_by_recording(rec)
    Xtr, Ytr, Xva, Yva = X[tr], Y[tr], X[va], Y[va]
    print(f"train {Xtr.shape[0]} win / val {Xva.shape[0]} win "
          f"(val recordings {val_ids})", flush=True)

    # Train-only normalization (per bin).
    mean = Xtr.reshape(-1, X.shape[-1]).mean(0)
    std = Xtr.reshape(-1, X.shape[-1]).std(0) + 1e-6
    Xtr = (Xtr - mean) / std
    Xva = (Xva - mean) / std

    model = build_chord_model()
    model.summary()
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy",
                  metrics=["accuracy"])
    es = tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=8, restore_best_weights=True)
    model.fit(Xtr, Ytr, validation_data=(Xva, Yva),
              epochs=40, batch_size=32, callbacks=[es], verbose=2)

    # WCSR = frame-wise majmin accuracy on the held-out recordings.
    pred = model.predict(Xva, verbose=0).argmax(-1)
    frame_acc = float((pred == Yva).mean())
    # Excluding N.C. frames (chord-only accuracy).
    nz = Yva != 0
    chord_acc = float((pred[nz] == Yva[nz]).mean()) if nz.any() else 0.0
    print(f"\n=== CHORD v0 (Klangio solo-guitar, held-out recordings) ===")
    print(f"frame majmin accuracy (WCSR) = {frame_acc:.3f}")
    print(f"chord-only accuracy (excl N.C.) = {chord_acc:.3f}")

    os.makedirs("ml/chords/out", exist_ok=True)
    np.savez("ml/chords/out/chord_weights.npz",
             *model.get_weights(), mean=mean, std=std)
    with open("ml/chords/out/chord_eval.txt", "w") as f:
        f.write(f"frame_wcsr={frame_acc:.4f}\nchord_only={chord_acc:.4f}\n"
                f"val_recordings={val_ids}\nclass_balance={dist.tolist()}\n")
    print("saved ml/chords/out/chord_weights.npz + chord_eval.txt")


if __name__ == "__main__":
    main()
