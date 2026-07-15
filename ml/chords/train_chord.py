"""Train the v0 CHORD-recognition model (phase 1) — frame-wise majmin over CQT.

Runs on x86 CI (TensorFlow). Reuses the strum pipeline's discipline: seed
control, split-by-recording (no leakage), best-val restore, train-only norm.

TRAIN pool = Klangio solo-guitar + synthetic full-band + (r203) **GuitarSet REAL
guitar audio**, minus one guitarist held out entirely. The headline metric is
therefore `guitarset_logo_comp_wcsr`: real audio, true labels, a player the model
has never heard. Held-out SYNTH accuracy (~0.99) is reported too but proves only
learnability — it transfers nothing (see the "adversarial synth testing" lesson).

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
from chords import cqt, dataset, guitarset  # noqa: E402
from chords.augment import augment_windows  # noqa: E402
from chords.labels import N_CLASSES  # noqa: E402

WIN = 100
SEED = 42

# --- GuitarSet REAL-audio TRAIN pool + LOGO hold-out (r203) ----------------
# THE decisive experiment: synth held-out is 0.99 while the same model scores
# 0.5176 on real GuitarSet comp — synth transfers nothing, so train on real
# audio. To keep that claim honest we hold ONE guitarist out completely.
#
# GS_HOLDOUT_GUITARIST: this guitarist's audio is **NEVER trained on** — not in
# the train pool, not augmented, not in val. Their comp takes are scored after
# training as `guitarset_logo_comp_wcsr`. That number is a NEW-PLAYER score: it
# says how the model does on a human it has never heard, on a guitar/room it has
# never heard. It is the only GuitarSet number here that is not self-
# congratulation — a train-pool guitarist's score would mostly measure
# memorisation. Guitarist 05 is an arbitrary but FIXED choice (fixed so the
# metric is comparable run-to-run; arbitrary because we have no reason to think
# any guitarist is special — a full 6-fold LOGO sweep is 6x the compute and can
# come later if this single fold shows promise).
GS_HOLDOUT_GUITARIST = "05"
# comp only: `solo` takes are single-note leads whose annotation names a harmony
# the audio does not contain — training on them teaches hallucination, scoring on
# them is an unfair floor (see guitarset.py / eval_guitarset.py).
GS_MODES = ("comp",)

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


def guitarset_guitarists(root=None):
    """Sorted guitarist ids present under the GuitarSet root ([] if absent)."""
    try:
        return sorted({gid for _, _, gid in guitarset.tracks(root)})
    except Exception as e:                    # a broken/missing root must not
        print(f"[warn] guitarset.tracks failed: {e}")   # abort the training run
        return []


def guitarset_logo_eval(model, mean, std, root=None,
                        guitarist=GS_HOLDOUT_GUITARIST, modes=GS_MODES):
    """Frame-WCSR on the HELD-OUT guitarist's takes — the NEW-PLAYER score.

    Streams the hold-out's takes exactly as `eval_guitarset.py` does (same audio
    decode, same anti-aliased resample, same CQT, same `predict_frames`, same
    train-only mean/std) and scores frame-wise majmin accuracy against the sheet
    annotation. Uniform hop => frame accuracy IS the MIREX WCSR, so this is
    directly comparable to every other WCSR in this report and to the standalone
    GuitarSet benchmark.

    Honest reading: `guitarist` was excluded from the train pool, so this
    measures generalisation to an UNHEARD player — not "how well did we fit
    GuitarSet". Expect it to be the lowest GuitarSet number produced anywhere in
    the pipeline; that is the point, not a bug.

    Returns `(wcsr, n_frames, n_tracks)`; `(0.0, 0, 0)` if the dataset is absent.
    """
    from chords.eval_guitarset import predict_frames

    keep = set(modes) if modes is not None else None
    ok = n = n_tracks = 0
    for wav_path, jams_path, gid in guitarset.tracks(root):
        if gid != guitarist:
            continue
        stem = os.path.basename(wav_path)[: -len(guitarset.MIC_SUFFIX)]
        meta = guitarset.parse_stem(stem)
        if meta is None or (keep is not None and meta["mode"] not in keep):
            continue
        try:
            pcm, sr = guitarset.read_wav(wav_path)
            feat = cqt.cqt(guitarset.to_model_sr(pcm, sr), cqt.SR)
            if feat.shape[0] == 0:
                continue
            y_true = guitarset.labels_for_jams(
                jams_path, feat.shape[0], cqt.HOP, cqt.SR)
            y_pred, _ = predict_frames(model, (feat - mean) / std)
        except Exception as e:
            print(f"[warn] LOGO {stem}: {e}")
            continue
        ok += int((y_pred == y_true).sum())
        n += int(y_true.size)
        n_tracks += 1
    return (ok / n if n else 0.0), n, n_tracks


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
    del Xsyn, Ysyn

    # --- GuitarSet REAL-audio TRAIN pool, LOGO hold-out (r203) ---------------
    # The decisive experiment: real guitar audio with TRUE labels in TRAINING.
    # Every guitarist EXCEPT GS_HOLDOUT_GUITARIST, comp takes only. The hold-out
    # never enters train / augment / val — their comp takes are scored at the end
    # as the NEW-PLAYER number (guitarset_logo_comp_wcsr). GuitarSet goes 100%
    # into TRAIN, none into val, so the Klangio held-out split above stays
    # exactly the metric it was.
    gs_all = guitarset_guitarists()
    gs_train_gids = [g for g in gs_all if g != GS_HOLDOUT_GUITARIST]
    n_gs_tr = 0
    if not gs_all:
        print("[skip] no GuitarSet under "
              f"{guitarset.default_root()} — training WITHOUT the real-audio "
              "pool and reporting no LOGO score.", flush=True)
    elif not gs_train_gids:
        print(f"[skip] GuitarSet holds only the hold-out guitarist "
              f"{GS_HOLDOUT_GUITARIST!r} — no real-audio train pool.", flush=True)
    else:
        print(f"Building GuitarSet TRAIN pool (modes={GS_MODES}, guitarists="
              f"{gs_train_gids}, hold-out={GS_HOLDOUT_GUITARIST} NEVER "
              f"trained on)...", flush=True)
        Xgs, Ygs, gs_rec = dataset.build_guitarset(
            win=WIN, step=WIN // 2, modes=GS_MODES, guitarists=gs_train_gids)
        n_gs_tr = Xgs.shape[0]
        if n_gs_tr:
            Xtr = np.concatenate([Xtr, Xgs], axis=0)
            Ytr = np.concatenate([Ytr, Ygs], axis=0)
            print(f"  GuitarSet: {n_gs_tr} windows from "
                  f"{len(set(gs_rec.tolist()))} takes", flush=True)
            # Tripwire: the hold-out must not have leaked in via the filter.
            leaked = [r for r in set(gs_rec.tolist())
                      if r.startswith(f"gs_{GS_HOLDOUT_GUITARIST}_")]
            assert not leaked, f"LOGO leak — hold-out takes in TRAIN: {leaked}"
        del Xgs, Ygs

    n_base_tr = Xtr.shape[0]
    print(f"TRAIN windows: klangio={n_klangio_tr} + synth={n_synth_tr} "
          f"+ guitarset={n_gs_tr} = {n_base_tr} total "
          f"(synth songs {len(set(syn_rec.tolist()))})", flush=True)

    # --- ±semitone CQT-transposition augmentation (r193) ---------------------
    # Key-invariance: shift the CQT freq axis ±k semitones (2 bins each) + roll
    # the labels by k. Applied to the TRAIN windows ONLY (after the Klangio +
    # synth + GuitarSet concat, BEFORE mean/std) — val and ALL held-out evals
    # (incl. the LOGO guitarist) stay untouched so their metrics remain honest.
    # Fixed seed = reproducible.
    Xtr, Ytr = augment_windows(
        Xtr, Ytr, np.random.default_rng(AUG_SEED),
        copies=AUG_COPIES, max_semi=AUG_MAX_SEMI)
    n_aug_tr = Xtr.shape[0]
    print(f"AUGMENT (±{AUG_MAX_SEMI} semi, copies={AUG_COPIES}): "
          f"{n_base_tr} base -> {n_aug_tr} augmented TRAIN windows", flush=True)

    # Train-only normalization (per bin), recomputed on the AUGMENTED (Klangio +
    # synth + GuitarSet + transpositions) train set and applied to model input
    # and all evals.
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

    # --- GuitarSet LOGO eval (r203) — THE honest number ----------------------
    # The held-out guitarist's comp takes: real audio, true labels, a player the
    # model has NEVER heard. Everything above is either synthetic or a split of
    # data whose players are in the train pool; this is the only line that
    # answers "does it work for a NEW person with a NEW guitar in a NEW room".
    logo_wcsr = logo_frames = logo_tracks = 0
    if gs_all:
        print(f"\nEvaluating LOGO hold-out guitarist {GS_HOLDOUT_GUITARIST} "
              f"(modes={GS_MODES}, never trained on)...", flush=True)
        logo_wcsr, logo_frames, logo_tracks = guitarset_logo_eval(
            model, mean, std)
    if logo_frames:
        print(f"=== GuitarSet LOGO — REAL audio, NEW player "
              f"(guitarist {GS_HOLDOUT_GUITARIST}, {GS_MODES[0]} takes) ===")
        print(f"guitarset_logo_comp_wcsr = {logo_wcsr:.4f}")
        print(f"guitarset_logo_comp_frames = {logo_frames} "
              f"(tracks {logo_tracks})")
        print("# This is a NEW-PLAYER score: guitarist "
              f"{GS_HOLDOUT_GUITARIST}'s audio never entered train/augment/val. "
              "It is the honest generalisation number — the Klangio val and the "
              "synth tripwire above are not.", flush=True)
    else:
        print("=== GuitarSet LOGO: SKIPPED (no hold-out audio available) ===",
              flush=True)

    with open("ml/chords/out/chord_eval.txt", "w") as f:
        f.write(f"frame_wcsr={frame_acc:.4f}\nchord_only={chord_acc:.4f}\n"
                f"val_recordings={val_ids}\nclass_balance={dist.tolist()}\n")
        f.write(f"train_windows_klangio={n_klangio_tr}\n"
                f"train_windows_synth={n_synth_tr}\n"
                f"train_windows_guitarset={n_gs_tr}\n"
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
        # --- GuitarSet REAL-audio pool + LOGO (r203) -------------------------
        f.write(f"# GuitarSet REAL-audio TRAIN pool mixed in "
                f"(modes={list(GS_MODES)}, guitarists={gs_train_gids}); "
                f"guitarist {GS_HOLDOUT_GUITARIST} is HELD OUT — their audio "
                f"never entered train/augment/val\n")
        f.write(f"guitarset_train_guitarists={gs_train_gids}\n"
                f"guitarset_logo_holdout_guitarist={GS_HOLDOUT_GUITARIST}\n"
                f"guitarset_logo_modes={list(GS_MODES)}\n")
        if logo_frames:
            f.write("# guitarset_logo_comp_wcsr = frame-wise majmin accuracy "
                    "(== MIREX WCSR, uniform hop) on the HELD-OUT guitarist's "
                    "comp takes. A NEW-PLAYER score on REAL audio: the only "
                    "number here that measures generalisation to an unheard "
                    "player/guitar/room rather than fit. Quote THIS one.\n")
            f.write(f"guitarset_logo_comp_wcsr={logo_wcsr:.4f}\n"
                    f"guitarset_logo_comp_frames={logo_frames}\n"
                    f"guitarset_logo_comp_tracks={logo_tracks}\n")
        else:
            f.write("# guitarset_logo_comp_wcsr=n/a — GuitarSet absent (no "
                    "download); the real-audio pool and the LOGO eval were "
                    "both skipped.\n")
    print("saved ml/chords/out/chord_weights.npz + chord_eval.txt")


if __name__ == "__main__":
    main()
