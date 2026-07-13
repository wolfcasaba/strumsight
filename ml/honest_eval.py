"""r172 HONEST MEASUREMENT — reprice every strum-direction accuracy number.

No new data, no architecture change. Produces:
  1. train/val/test three-way split accuracy (VAL early-stops, TEST touched once)
  2. leave-one-guitarist-out CV (batch + live-70ms configs; per-fold + mean±std)
  3. cluster-bootstrap 95% CI over RECORDINGS (not windows) for the headline test
  4. multi-seed standard-config sweep (mean±std) so future rounds see the noise
  5. calibration refit on VAL + ECE on TEST (live model)

Writes ml/honest_results.json (consumed by model_card + chunk 018). Trains for
real on this box (TF 2.21 aarch64). Runnable in sections via argv.

Usage:
  /home/ubuntu/tf-venv/bin/python honest_eval.py all
  /home/ubuntu/tf-venv/bin/python honest_eval.py threeway logo bootstrap seeds calib
"""
from __future__ import annotations

import json
import os
import sys
import time

import numpy as np

import features as F
from experiment_deadline import window_truncated
from klangio import (assert_folds_trainable, guitarist_of, logo_folds,
                     parse_strums, recording_ids, split_by_recording,
                     split_by_recording_3way)
from prepare_dataset import _read_wav
from train import build_model, set_seeds

DATA = os.path.join(os.path.dirname(__file__), "data", "klangio")
RESULTS = os.path.join(os.path.dirname(__file__), "honest_results.json")
LIVE_DEADLINE_S = 0.070
STD_SEEDS = [42, 1, 2]  # standard-config multi-seed sweep

# r173 augmentation + regularization treatment (applied to TRAIN folds only).
AUG_N = 2                       # augmented copies per training recording
AUG_REG = dict(dropout=0.25, rec_dropout=0.15, l2=1e-4)  # a-priori, NOT tuned
AUG_SEMITONES = 6.0             # Murgul ablation optimum (chunk 018)


# ---------------------------------------------------------------------------
# Datasets
# ---------------------------------------------------------------------------
def load_batch():
    """Full-window (PRE 3 + POST 12) log-mel dataset = train.py's shipping X."""
    d = np.load(os.path.join(os.path.dirname(__file__), "klangio.npz"))
    return d["X"], d["y"], d["rec"]


def build_live(deadline_s=LIVE_DEADLINE_S, cache="klangio_live70.npz"):
    """Audio-truncated (live-deadline) windows for ALL recordings, cached.

    Same geometry train==serve as experiment_deadline: audio zeroed past
    onset+deadline so the model only ever sees what the 70 ms live path has.
    """
    path = os.path.join(os.path.dirname(__file__), cache)
    if os.path.exists(path):
        d = np.load(path)
        return d["X"], d["y"], d["rec"]
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
    X = np.stack(xs).astype(np.float32)
    y = np.array(ys, dtype=np.int64)
    rec = np.array(recs)
    np.savez_compressed(path, X=X, y=y, rec=rec)
    print(f"built {cache}: {X.shape}")
    return X, y, rec


# ---------------------------------------------------------------------------
# One training run — normalisation + class weights from TRAIN only (r142).
# ---------------------------------------------------------------------------
def train_eval(X, y, tr, va, te, seed):
    """Train on `tr`, early-stop on `va`, evaluate ONCE on `te`.

    Returns dict with test/val accuracy + per-sample test probs (for the
    winning class) so the caller can cluster-bootstrap or calibrate.
    """
    import tensorflow as tf

    set_seeds(seed)
    assert_folds_trainable(y, tr, te)
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
    model.fit(Xn[tr], y[tr], epochs=40, batch_size=32, shuffle=True,
              class_weight=cw, verbose=0, callbacks=[stop],
              validation_data=(Xn[va], y[va]))

    def probs_on(mask):
        return model.predict(Xn[mask], verbose=0)

    ptest = probs_on(te)
    pval = probs_on(va)
    test_acc = float((ptest.argmax(1) == y[te]).mean())
    val_acc = float((pval.argmax(1) == y[va]).mean())
    return {
        "test_acc": test_acc,
        "val_acc": val_acc,
        "test_probs": ptest,
        "test_y": y[te],
        "test_rec": None,  # filled by caller when it has rec
        "val_probs": pval,
        "val_y": y[va],
    }


# ---------------------------------------------------------------------------
# r173 augmentation — build augmented TRAIN windows from PCM (before log-mel).
# ---------------------------------------------------------------------------
def build_aug_windows(train_rids, config, seed, n_aug=AUG_N):
    """Augmented windows for the given TRAIN recordings only, config-matched.

    For each recording we draw `n_aug` stochastic augmented takes (augment.py:
    pitch ±6 st varispeed + reverb + mic-sim + gain/noise), recompute the
    log-mel, and cut windows at the RESCALED onset times. `batch` = full
    (PRE 3 / POST 12) window; `live70` = audio-truncated at onset+70 ms
    (train == serve geometry, same as build_live). Returns (X, y).
    """
    import augment as A

    rng = np.random.default_rng(seed)
    xs, ys = [], []
    for rid in sorted(train_rids):
        with open(f"{DATA}/recording_{rid}.strums") as fh:
            events = parse_strums(fh.read())
        pcm = _read_wav(f"{DATA}/recording_{rid}_phone.wav")
        onsets = np.array([t for t, _, _ in events], dtype=np.float64)
        dirs = [0 if d == "down" else 1 for _, d, _ in events]
        for _ in range(n_aug):
            aug_pcm, aug_onsets = A.augment_pcm(pcm, onsets, rng,
                                                semitone_range=AUG_SEMITONES)
            if config == "batch":
                lm = F.log_mel(aug_pcm)
                for t, dlab in zip(aug_onsets, dirs):
                    if t * F.SR >= len(aug_pcm):
                        continue
                    center = int(round(t * F.SR / F.HOP))
                    if center - F.PRE_FRAMES >= len(lm):
                        continue
                    xs.append(F.window_at(lm, t))
                    ys.append(dlab)
            else:  # live70
                for t, dlab in zip(aug_onsets, dirs):
                    if t * F.SR >= len(aug_pcm):
                        continue
                    xs.append(window_truncated(aug_pcm, t, LIVE_DEADLINE_S))
                    ys.append(dlab)
    if not xs:
        return (np.zeros((0, F.PRE_FRAMES + F.POST_FRAMES, F.N_MELS), np.float32),
                np.zeros((0,), np.int64))
    return np.stack(xs).astype(np.float32), np.array(ys, dtype=np.int64)


def train_eval_aug(X, y, rec, tr, va, te, seed, config, reg=AUG_REG):
    """train_eval, but the TRAIN fold is CLEAN windows + augmented copies of the
    same train recordings, and the model is regularized. Val/test stay CLEAN
    (identical to r172) so the number is directly comparable."""
    import tensorflow as tf

    set_seeds(seed)
    assert_folds_trainable(y, tr, te)
    train_rids = set(rec[tr].tolist())
    Xa, ya = build_aug_windows(train_rids, config, seed)
    Xtr = np.concatenate([X[tr], Xa], axis=0)
    ytr = np.concatenate([y[tr], ya], axis=0)
    # Normalisation stats from the (augmented) TRAIN fold only — no eval leak.
    mean = Xtr.mean(axis=(0, 1))
    std = Xtr.std(axis=(0, 1)) + 1e-6
    Xtr_n = (Xtr - mean) / std
    Xva_n = (X[va] - mean) / std
    Xte_n = (X[te] - mean) / std

    model = build_model(X.shape[1], X.shape[2], **reg)
    n_up = int((ytr == 1).sum()) or 1
    cw = {0: 1.0, 1: max(1.0, (ytr == 0).sum() / n_up)}
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=8, restore_best_weights=True)
    model.fit(Xtr_n, ytr, epochs=40, batch_size=32, shuffle=True,
              class_weight=cw, verbose=0, callbacks=[stop],
              validation_data=(Xva_n, y[va]))
    ptest = model.predict(Xte_n, verbose=0)
    pval = model.predict(Xva_n, verbose=0)
    return {
        "test_acc": float((ptest.argmax(1) == y[te]).mean()),
        "val_acc": float((pval.argmax(1) == y[va]).mean()),
        "n_aug_train": int(len(ya)), "n_clean_train": int(tr.sum()),
    }


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------
def section_threeway(results):
    """Standard config (full window) on a guitarist-mixed 3-way split, seed 42.
    This is the honest replacement for the old single-fold 0.867."""
    X, y, rec = load_batch()
    tr, va, te = split_by_recording_3way(rec, seed=42)
    print(f"[threeway] train {tr.sum()} / val {va.sum()} / test {te.sum()} "
          f"windows")
    r = train_eval(X, y, tr, va, te, seed=42)
    # Attach rec for the bootstrap section (reuse this exact test fold).
    results["threeway"] = {
        "split": "by-recording 3-way, seed 42, val_frac 0.15 test_frac 0.15",
        "n_train": int(tr.sum()), "n_val": int(va.sum()),
        "n_test": int(te.sum()),
        "test_ids": sorted(set(rec[te].tolist())),
        "val_ids": sorted(set(rec[va].tolist())),
        "val_acc": r["val_acc"], "test_acc": r["test_acc"],
    }
    # Cache probs for bootstrap.
    np.savez(os.path.join(os.path.dirname(__file__), "_threeway_test.npz"),
             probs=r["test_probs"], y=r["test_y"], rec=rec[te])
    print(f"[threeway] val_acc={r['val_acc']:.4f} test_acc={r['test_acc']:.4f}")
    return results


def _mean_std(xs):
    a = np.array(xs, dtype=float)
    return float(a.mean()), float(a.std())


def section_logo(results):
    """Leave-one-guitarist-out CV for BOTH configs — the *new player* number."""
    out = {}
    for cfg, loader in (("batch", load_batch), ("live70", build_live)):
        X, y, rec = loader()
        folds = []
        for g, trall, te in logo_folds(rec):
            # Carve a VAL slice (by recording) from the training guitarists so
            # EarlyStopping never sees the held-out guitarist.
            tr_rec = rec[trall]
            tr_only, va_only = split_by_recording(tr_rec, eval_frac=0.2,
                                                  seed=42)
            # Lift the sub-masks back onto the full index space.
            tr = np.zeros(len(rec), dtype=bool)
            va = np.zeros(len(rec), dtype=bool)
            idx = np.where(trall)[0]
            tr[idx[tr_only]] = True
            va[idx[va_only]] = True
            r = train_eval(X, y, tr, va, te, seed=42)
            folds.append({"held_out_guitarist": g,
                          "n_test": int(te.sum()),
                          "test_acc": r["test_acc"],
                          "val_acc": r["val_acc"]})
            print(f"[logo/{cfg}] hold-out guitarist {g}: "
                  f"test_acc={r['test_acc']:.4f} (n={int(te.sum())})")
        m, s = _mean_std([f["test_acc"] for f in folds])
        out[cfg] = {"folds": folds, "mean_test_acc": m, "std_test_acc": s}
        print(f"[logo/{cfg}] mean±std test_acc = {m:.4f} ± {s:.4f}")
    results["logo"] = out
    return results


def section_logo_aug(results):
    """r173: leave-one-guitarist-out CV WITH augmentation + regularization on
    the TRAIN folds — the same logo_folds splits as section_logo so the
    new-player number is directly comparable to the r172 baseline."""
    out = {"settings": {"n_aug": AUG_N, "semitone_range": AUG_SEMITONES,
                        "reg": AUG_REG,
                        "augment": "pitch±6 varispeed + reverb + mic-sim + "
                                   "gain/noise (augment.py), TRAIN fold only"}}
    for cfg, loader in (("batch", load_batch), ("live70", build_live)):
        X, y, rec = loader()
        folds = []
        for g, trall, te in logo_folds(rec):
            tr_rec = rec[trall]
            tr_only, va_only = split_by_recording(tr_rec, eval_frac=0.2,
                                                  seed=42)
            tr = np.zeros(len(rec), dtype=bool)
            va = np.zeros(len(rec), dtype=bool)
            idx = np.where(trall)[0]
            tr[idx[tr_only]] = True
            va[idx[va_only]] = True
            r = train_eval_aug(X, y, rec, tr, va, te, seed=42, config=cfg)
            folds.append({"held_out_guitarist": g, "n_test": int(te.sum()),
                          "test_acc": r["test_acc"], "val_acc": r["val_acc"],
                          "n_aug_train": r["n_aug_train"]})
            print(f"[logo_aug/{cfg}] hold-out {g}: test_acc={r['test_acc']:.4f} "
                  f"(clean_tr={r['n_clean_train']} +aug={r['n_aug_train']})")
        m, s = _mean_std([f["test_acc"] for f in folds])
        out[cfg] = {"folds": folds, "mean_test_acc": m, "std_test_acc": s}
        print(f"[logo_aug/{cfg}] mean±std test_acc = {m:.4f} ± {s:.4f}")
    results["logo_aug"] = out
    return results


def section_threeway_aug(results):
    """r173: the guitarist-mixed 3-way split (regression check) with the SAME
    aug+reg treatment — comparable to the r172 batch 0.852."""
    X, y, rec = load_batch()
    tr, va, te = split_by_recording_3way(rec, seed=42)
    r = train_eval_aug(X, y, rec, tr, va, te, seed=42, config="batch")
    results["threeway_aug"] = {
        "split": "by-recording 3-way, seed 42 (same fold as threeway)",
        "settings": {"n_aug": AUG_N, "reg": AUG_REG},
        "val_acc": r["val_acc"], "test_acc": r["test_acc"],
        "n_aug_train": r["n_aug_train"],
    }
    print(f"[threeway_aug] val_acc={r['val_acc']:.4f} "
          f"test_acc={r['test_acc']:.4f} (vs r172 batch 0.852)")
    return results


def section_bootstrap(results, n_boot=2000, seed=42):
    """Cluster-bootstrap 95% CI over RECORDINGS for the 3-way test accuracy.
    Windows cluster within a recording, so resample recordings, not windows."""
    p = os.path.join(os.path.dirname(__file__), "_threeway_test.npz")
    if not os.path.exists(p):
        print("[bootstrap] run threeway first"); return results
    d = np.load(p, allow_pickle=True)
    probs, y, rec = d["probs"], d["y"], d["rec"]
    correct = (probs.argmax(1) == y).astype(float)
    ids = sorted(set(rec.tolist()))
    by_id = {i: correct[rec == i] for i in ids}
    rng = np.random.default_rng(seed)
    accs = []
    for _ in range(n_boot):
        pick = rng.choice(len(ids), size=len(ids), replace=True)
        pooled = np.concatenate([by_id[ids[k]] for k in pick])
        accs.append(pooled.mean())
    lo, hi = np.percentile(accs, [2.5, 97.5])
    point = float(correct.mean())
    results["bootstrap"] = {
        "metric": "3-way test accuracy (standard/batch config, seed 42)",
        "point": point, "ci95_lo": float(lo), "ci95_hi": float(hi),
        "n_boot": n_boot, "n_recordings": len(ids),
    }
    print(f"[bootstrap] test_acc={point:.4f} 95% CI "
          f"[{lo:.4f}, {hi:.4f}] over {len(ids)} recordings")
    return results


def section_seeds(results):
    """Standard config, 3 seeds, mean±std — separate signal from noise."""
    X, y, rec = load_batch()
    tr, va, te = split_by_recording_3way(rec, seed=42)
    accs, vals = [], []
    for s in STD_SEEDS:
        r = train_eval(X, y, tr, va, te, seed=s)
        accs.append(r["test_acc"]); vals.append(r["val_acc"])
        print(f"[seeds] seed {s}: test_acc={r['test_acc']:.4f}")
    m, sd = _mean_std(accs)
    results["multiseed"] = {
        "config": "standard/batch, fixed 3-way split (seed 42), "
                  f"train seeds {STD_SEEDS}",
        "per_seed_test_acc": {str(s): a for s, a in zip(STD_SEEDS, accs)},
        "mean_test_acc": m, "std_test_acc": sd,
    }
    print(f"[seeds] mean±std test_acc = {m:.4f} ± {sd:.4f}")
    return results


def _fit_piecewise(conf, correct, edges):
    """Bucketed empirical P(correct) at each interior edge → knot list.
    Returns [(x, y)] with x = bucket mean-conf, y = bucket accuracy."""
    knots = []
    lo = 0.5
    bounds = list(edges) + [1.0001]
    prev = lo
    for b in bounds:
        m = (conf >= prev) & (conf < b)
        if m.sum() >= 10:
            knots.append((float(conf[m].mean()), float(correct[m].mean())))
        prev = b
    return knots


def _ece(conf, correct, n_bins=10):
    """Expected calibration error over equal-width confidence bins."""
    edges = np.linspace(0.5, 1.0, n_bins + 1)
    n = len(conf)
    e = 0.0
    for i in range(n_bins):
        m = (conf >= edges[i]) & (conf < edges[i + 1] if i < n_bins - 1
                                  else conf <= edges[i + 1])
        if m.sum() == 0:
            continue
        e += m.sum() / n * abs(correct[m].mean() - conf[m].mean())
    return float(e)


def section_calib(results):
    """Refit the live-model confidence calibration on VAL, report ECE on TEST.

    The shipped Dart knots (live_crnn_classifier.dart) were fit on the same
    eval fold used to report accuracy — in-sample. Here VAL fits, TEST scores.
    """
    X, y, rec = build_live()
    tr, va, te = split_by_recording_3way(rec, seed=42)
    r = train_eval(X, y, tr, va, te, seed=42)
    for split, probs, yy in (("val", r["val_probs"], r["val_y"]),
                             ("test", r["test_probs"], r["test_y"])):
        conf = probs.max(1)
        corr = (probs.argmax(1) == yy).astype(float)
        r[f"{split}_conf"] = conf
        r[f"{split}_corr"] = corr

    # Fit on VAL at the SHIPPED knot edges so the comparison is apples-to-apples.
    ship_edges = [0.7, 0.9, 0.97]
    fitted = _fit_piecewise(r["val_conf"], r["val_corr"], ship_edges)

    # ECE on TEST: raw softmax confidence vs empirical correctness.
    ece_raw = _ece(r["test_conf"], r["test_corr"])
    # Calibrated: map test conf through the VAL-fitted piecewise-linear knots.
    def apply_knots(p, knots):
        if not knots:
            return p
        if p <= knots[0][0]:
            return knots[0][1]
        for i in range(1, len(knots)):
            if p <= knots[i][0]:
                x0, y0 = knots[i - 1]; x1, y1 = knots[i]
                return y0 + (y1 - y0) * (p - x0) / (x1 - x0)
        return knots[-1][1]
    cal_conf = np.array([apply_knots(p, fitted) for p in r["test_conf"]])
    # ECE of calibrated confidence: bin by the CALIBRATED value.
    ece_cal = _ece(cal_conf, r["test_corr"])

    results["calibration"] = {
        "note": "live-70ms model; VAL-fitted piecewise-linear, ECE on TEST. "
                "Confidence = max softmax; correctness = argmax==label at "
                "LABELED onsets (reproducible proxy for the Dart detected-"
                "onset probe).",
        "val_fitted_knots": [[round(x, 4), round(yv, 4)] for x, yv in fitted],
        "shipped_dart_knots": [[0.50, 0.55], [0.60, 0.58], [0.80, 0.63],
                               [0.935, 0.74], [0.9825, 0.86], [1.00, 0.87]],
        "ece_test_raw_softmax": round(ece_raw, 4),
        "ece_test_calibrated": round(ece_cal, 4),
        "live_test_acc": r["test_acc"],
        "n_val": int(va.sum()), "n_test": int(te.sum()),
    }
    print(f"[calib] VAL-fitted knots: {fitted}")
    print(f"[calib] ECE test raw={ece_raw:.4f} calibrated={ece_cal:.4f}")
    return results


SECTIONS = {
    "threeway": section_threeway,
    "logo": section_logo,
    "logo_aug": section_logo_aug,
    "threeway_aug": section_threeway_aug,
    "bootstrap": section_bootstrap,
    "seeds": section_seeds,
    "calib": section_calib,
}


def main(which):
    results = {}
    if os.path.exists(RESULTS):
        with open(RESULTS) as fh:
            results = json.load(fh)
    order = ["threeway", "logo", "logo_aug", "threeway_aug",
             "bootstrap", "seeds", "calib"]
    todo = order if "all" in which else [s for s in order if s in which]
    for name in todo:
        t0 = time.time()
        print(f"\n=== {name} ===")
        results = SECTIONS[name](results)
        results.setdefault("_timing", {})[name] = round(time.time() - t0, 1)
        with open(RESULTS, "w") as fh:
            json.dump(results, fh, indent=2, default=str)
        print(f"=== {name} done in {time.time() - t0:.1f}s ===")
    print(f"\nwrote {RESULTS}")


if __name__ == "__main__":
    main(sys.argv[1:] or ["all"])
