"""r175 — train + export the FINAL 3-class LIVE strum model (down/up/no-strum).

The r174 measurement (honest_eval.py `noreject`) proved a learned no-strum
reject class suppresses ~87-90 % of false onsets at >=95 % true-strum retention
(LOGO / new-player), ~13-27x the r170 confidence gate, at ZERO direction cost.
This script ships that capability in the LIVE path:

  1. Build the live-70 ms 3-class dataset (positives down/up + mined hard
     negatives), all recordings, same audio-truncated geometry as the shipped
     2-class live model (honest_eval.build_live / build_negatives).
  2. Split BY RECORDING (klangio.split_by_recording), train build_model(
     n_classes=3) on the TRAIN fold, early-stop on the eval fold, norm stats +
     inverse-frequency class weights from TRAIN only (r142 no-leak discipline).
  3. Calibrate the no-strum GATE the SAME way honest_eval._gate does: the
     threshold on P(no-strum) that KEEPS >=95 % of TRUE strums (eval fold), and
     report the false-onset rejection it buys — the value the Dart classifier
     hard-codes.
  4. Export assets/ml/strum_crnn_live_3c.bin (SSML v1, mirroring
     export_live_weights.py) + a 3-class parity fixture
     test/fixtures/crnn_live_3c_parity.json (windows incl. negatives + Keras
     3-col softmax, Dart must match <=1e-3). The existing 2-class asset is left
     untouched.

ONE training (~15-25 min on the TF 2.21 aarch64 box). Usage:
  /home/ubuntu/tf-venv/bin/python train_live_3c.py [--seed=42]
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

from export_dart_weights import NAMES, write_bin
from honest_eval import REJECT_RETENTION, load_noreject
from klangio import split_by_recording
from train import build_model, set_seeds

N_FIXTURE = 32
SEED = 42


def _gate(pos_pno, neg_pno, retention=REJECT_RETENTION):
    """honest_eval._gate, re-stated: threshold on P(no-strum) keeping
    `retention` of TRUE strums; returns (threshold, true_retention,
    neg_reject)."""
    thr = float(np.quantile(pos_pno, retention))
    true_retention = float((pos_pno < thr).mean())
    neg_reject = float((neg_pno >= thr).mean()) if len(neg_pno) else 0.0
    return thr, true_retention, neg_reject


def main(seed=SEED):
    import tensorflow as tf

    set_seeds(seed)
    X, y, rec = load_noreject("live70")
    n_pos = int((y < 2).sum())
    n_neg = int((y == 2).sum())
    print(f"3-class live dataset: {X.shape} — {int((y == 0).sum())} down / "
          f"{int((y == 1).sum())} up / {n_neg} no-strum")

    tr, ev = split_by_recording(rec)
    print(f"split by recording: {int(tr.sum())} train / {int(ev.sum())} eval")

    mean = X[tr].mean(axis=(0, 1))
    std = X[tr].std(axis=(0, 1)) + 1e-6
    Xn = (X - mean) / std

    model = build_model(X.shape[1], X.shape[2], n_classes=3)
    counts = np.bincount(y[tr], minlength=3).astype(float)
    counts[counts == 0] = 1.0
    n = float(counts.sum())
    cw = {c: n / (3 * counts[c]) for c in range(3)}
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=8, restore_best_weights=True)
    model.fit(Xn[tr], y[tr], epochs=40, batch_size=32, shuffle=True,
              class_weight=cw, verbose=2, callbacks=[stop],
              validation_data=(Xn[ev], y[ev]))

    ws = model.get_weights()
    np.savez("weights_live_3c.npz", *[w.astype(np.float32) for w in ws],
             mean=mean.astype(np.float32), std=std.astype(np.float32))
    print(f"wrote weights_live_3c.npz ({len(ws)} arrays)")

    # ---- Gate calibration on the EVAL fold (held out from training) --------
    ev_pos = ev & (y < 2)
    ev_neg = ev & (y == 2)
    p_pos = model.predict(Xn[ev_pos], verbose=0)
    p_neg = model.predict(Xn[ev_neg], verbose=0)
    # Direction accuracy on TRUE strums (argmax over the down/up columns).
    dir_acc = float((p_pos[:, :2].argmax(1) == y[ev_pos]).mean())
    nostrum_recall = float((p_neg.argmax(1) == 2).mean()) if len(p_neg) else 0.0
    thr, ret, rej = _gate(p_pos[:, 2], p_neg[:, 2])
    prov = {
        "note": "r175 shipped 3-class live model. Threshold = P(no-strum) "
                "quantile keeping >=95% of TRUE strums on the EVAL fold "
                "(same rule as honest_eval._gate). Dart hard-codes "
                "no_strum_threshold; retention/neg_reject document it.",
        "seed": seed, "retention_target": REJECT_RETENTION,
        "n_eval_pos": int(ev_pos.sum()), "n_eval_neg": int(ev_neg.sum()),
        "no_strum_threshold": thr, "true_strum_retention": ret,
        "false_onset_rejection": rej, "eval_dir_acc_true_strums": dir_acc,
        "eval_nostrum_recall": nostrum_recall,
    }
    with open("live_3c_threshold.json", "w") as fh:
        json.dump(prov, fh, indent=2)
    print(f"[gate] no_strum_threshold={thr:.6f} keeps {ret:.3f} of true "
          f"strums, rejects {rej:.3f} of false onsets")
    print(f"[gate] eval direction acc (true strums)={dir_acc:.3f} "
          f"no-strum recall={nostrum_recall:.3f}")

    # ---- Export bin (mirrors export_live_weights.py) -----------------------
    d = np.load("weights_live_3c.npz")
    arrays = list(zip(NAMES, [d[f"arr_{i}"] for i in range(len(NAMES))]))
    arrays += [("mean", d["mean"]), ("std", d["std"])]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_bin = os.path.join(root, "assets", "ml", "strum_crnn_live_3c.bin")
    write_bin(out_bin, arrays)
    print(f"wrote {out_bin} ({os.path.getsize(out_bin)} bytes)")

    # ---- Parity fixture: eval-fold windows incl. NEGATIVES -----------------
    # Balanced across the 3 classes so P(no-strum) is exercised on both sides.
    idx = []
    for cls in (0, 1, 2):
        cls_idx = np.flatnonzero(ev & (y == cls))
        take = min(len(cls_idx), N_FIXTURE // 3 + 1)
        step = max(1, len(cls_idx) // take)
        idx.extend(cls_idx[::step][:take].tolist())
    idx = sorted(idx)[:N_FIXTURE]
    Xr = X[idx].astype(float).round(5).astype(np.float32)
    probs = model.predict((Xr - d["mean"]) / d["std"], verbose=0)
    fixture = {
        "note": "r175 3-class LIVE (70 ms audio-truncated) log-mel windows + "
                "Keras 3-col softmax [P(down),P(up),P(no-strum)]; the Dart "
                "3-class net must match <=1e-3. Includes label-2 no-strum "
                "windows so suppression is exercised.",
        "no_strum_threshold": thr,
        "windows": [w.astype(float).tolist() for w in Xr],
        "labels": [int(v) for v in y[idx]],
        "probs": [[float(p[0]), float(p[1]), float(p[2])] for p in probs],
    }
    out_fix = os.path.join(root, "test", "fixtures", "crnn_live_3c_parity.json")
    with open(out_fix, "w") as fh:
        json.dump(fixture, fh)
    n_cls = {c: int((np.array(fixture["labels"]) == c).sum()) for c in (0, 1, 2)}
    print(f"wrote {out_fix} ({len(idx)} windows, by class {n_cls})")


if __name__ == "__main__":
    s = SEED
    for a in sys.argv[1:]:
        if a.startswith("--seed="):
            s = int(a.split("=", 1)[1])
    main(seed=s)
