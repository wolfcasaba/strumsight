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
from chords.augment import augment_windows  # noqa: E402
from chords.labels import N_CLASSES  # noqa: E402

WIN = 100
SEED = 42

# --- Synth full-band TRAIN pool params (r192) — single source of truth so the
# eval-file comment can't drift from the actual run. ------------------------
SYN_TRAIN_N = 256        # songs mixed into TRAIN
SYN_TRAIN_SEED = 7       # != held-out eval seed (no leakage)
SYN_TRAIN_SPC = 2.0      # seconds_per_chord (>= 2 windows of real chord content)
# --- Held-out SYNTH full-band eval (CI tripwire) ---------------------------
SYN_EVAL_N = 16
SYN_EVAL_SEED = 1234
# --- ±semitone CQT-transposition augmentation (r193) — key-invariance ------
AUG_COPIES = 2           # transposed copies per base window (-> ~3x train data)
AUG_MAX_SEMI = 5         # max |semitone| shift (±10 CQT bins, safe zero-fill)
AUG_SEED = 4243          # fixed aug RNG seed (distinct from SEED / eval seeds)


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
    n_klangio_tr = Xtr.shape[0]
    print(f"train {Xtr.shape[0]} win / val {Xva.shape[0]} win "
          f"(val recordings {val_ids})", flush=True)

    # --- Synth full-band TRAIN pool (r192) -----------------------------------
    # Mix synthetic full-band windows into the TRAINING data ONLY so the model
    # learns full-band chords. Seed 7 is DIFFERENT from the held-out eval's 1234
    # (below) so the seed=1234 tripwire stays a clean, non-leaked comparison
    # baseline. Synth goes 100% into train, NONE into val — the Klangio held-out
    # split above stays the pure REAL WCSR metric.
    # seconds_per_chord=2.0 makes each song span ~2+ windows of REAL chord
    # content (short 1s-per-chord songs were < WIN frames → one half-padding
    # window each, a weak/N.C.-heavy signal — r192 second-eye fix). The held-out
    # eval below keeps the DEFAULT 1.0 so it stays the r191-comparable baseline.
    print(f"Building synth full-band TRAIN pool (n_songs={SYN_TRAIN_N}, "
          f"seed={SYN_TRAIN_SEED}, seconds_per_chord={SYN_TRAIN_SPC})...",
          flush=True)
    Xsyn, Ysyn, syn_rec = dataset.build_synth(
        n_songs=SYN_TRAIN_N, seed=SYN_TRAIN_SEED, win=WIN, step=WIN // 2,
        seconds_per_chord=SYN_TRAIN_SPC)
    n_synth_tr = Xsyn.shape[0]
    Xtr = np.concatenate([Xtr, Xsyn], axis=0)
    Ytr = np.concatenate([Ytr, Ysyn], axis=0)
    n_base_tr = Xtr.shape[0]
    print(f"TRAIN windows: klangio={n_klangio_tr} + synth={n_synth_tr} "
          f"= {n_base_tr} total "
          f"(synth songs {len(set(syn_rec.tolist()))})", flush=True)

    # --- ±semitone CQT-transposition augmentation (r193) ---------------------
    # Key-invariance: shift the CQT freq axis ±k semitones (2 bins each) + roll
    # the labels by k. Applied to the TRAIN windows ONLY (after the Klangio +
    # synth concat, BEFORE mean/std) — val and both held-out evals stay
    # untouched so their metrics remain honest. Fixed seed = reproducible.
    Xtr, Ytr = augment_windows(
        Xtr, Ytr, np.random.default_rng(AUG_SEED),
        copies=AUG_COPIES, max_semi=AUG_MAX_SEMI)
    n_aug_tr = Xtr.shape[0]
    print(f"AUGMENT (±{AUG_MAX_SEMI} semi, copies={AUG_COPIES}): "
          f"{n_base_tr} base -> {n_aug_tr} augmented TRAIN windows", flush=True)

    # Train-only normalization (per bin), recomputed on the AUGMENTED (Klangio +
    # synth + transpositions) train set and applied to model input and all evals.
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

    # --- Held-out SYNTH full-band eval (CI tripwire, NOT real audio) ----------
    # A FIXED synthetic full-band set (guitar+bass+drums) NEVER mixed into
    # training — the honest baseline drop for the solo-trained model on full
    # band. Same train-only mean/std norm + same WCSR/chord-only metric as the
    # Klangio eval above. This is a synthetic regression tripwire only; the real
    # acceptance gate stays the real-guitar/full-mix APK test (HORIZON).
    print(f"\nBuilding held-out SYNTH full-band eval set "
          f"(n_songs={SYN_EVAL_N}, seed={SYN_EVAL_SEED})...", flush=True)
    Xsy, Ysy, _ = dataset.build_synth(
        n_songs=SYN_EVAL_N, seed=SYN_EVAL_SEED, win=WIN, step=WIN // 2)
    Xsy = (Xsy - mean) / std
    psy = model.predict(Xsy, verbose=0).argmax(-1)
    synth_wcsr = float((psy == Ysy).mean())
    nzsy = Ysy != 0
    synth_chord = float((psy[nzsy] == Ysy[nzsy]).mean()) if nzsy.any() else 0.0
    print("=== SYNTH full-band (held-out) — CI tripwire, NOT real audio ===")
    print(f"synth_fullband_wcsr = {synth_wcsr:.3f}")
    print(f"synth_fullband_chord_only = {synth_chord:.3f}")
    print("# NOTE: a synth_fullband jump proves the model CAN learn full-band "
          "chords from synth (tripwire); it is NOT real-world full-band proof "
          "— GuitarSet/real full-band eval is a later increment.", flush=True)

    with open("ml/chords/out/chord_eval.txt", "w") as f:
        f.write(f"frame_wcsr={frame_acc:.4f}\nchord_only={chord_acc:.4f}\n"
                f"val_recordings={val_ids}\nclass_balance={dist.tolist()}\n")
        f.write(f"train_windows_klangio={n_klangio_tr}\n"
                f"train_windows_synth={n_synth_tr}\n"
                f"train_windows_base={n_base_tr}\n"
                f"aug_copies={AUG_COPIES}\naug_max_semi={AUG_MAX_SEMI}\n"
                f"train_windows_augmented={n_aug_tr}\n")
        f.write(f"# SYNTH full-band TRAIN pool mixed in (n_songs={SYN_TRAIN_N} "
                f"seed={SYN_TRAIN_SEED} seconds_per_chord={SYN_TRAIN_SPC}); "
                f"held-out eval below is a DIFFERENT set "
                f"(seed={SYN_EVAL_SEED}, no leakage)\n")
        f.write(f"# TRAIN windows augmented ±{AUG_MAX_SEMI} semitones "
                f"(copies={AUG_COPIES}): {n_base_tr} -> {n_aug_tr}; "
                f"val + both held-out evals are NOT augmented\n")
        f.write(f"# SYNTH full-band (held-out, n_songs={SYN_EVAL_N} "
                f"seed={SYN_EVAL_SEED}) — CI tripwire, NOT real audio "
                f"(a jump proves learnability, not real-world full-band "
                f"accuracy)\n")
        f.write(f"synth_fullband_wcsr={synth_wcsr:.4f}\n"
                f"synth_fullband_chord_only={synth_chord:.4f}\n")
    print("saved ml/chords/out/chord_weights.npz + chord_eval.txt")


if __name__ == "__main__":
    main()
