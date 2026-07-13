"""Export the trained CRNN for the PURE-DART inference path (ml-track P1.3).

Reads weights.npz (written by train.py next to the tflite) and emits:

  assets/ml/strum_crnn.bin   little-endian binary the Dart loader parses:
                             magic 'SSML' | u32 version | u32 count |
                             per array: u32 nameLen | name utf8 | u32 ndim |
                             u32 dims[ndim] | f32 data[prod(dims)]
  test/fixtures/crnn_parity.json
                             N eval windows (RAW log-mel, un-normalised) +
                             the Keras float32 softmax probs for each — the
                             Dart forward pass must match <=1e-3 (the same
                             parity-contract pattern as the log-mel fixture).

Why pure Dart instead of tflite_flutter (plan P1.3 revision, 2026-07-13):
the model is ~350k params; a hand-written forward pass runs in ~1 ms, keeps
the ONE-win32-major rule untouchable, and is host-testable on this ARM64 box
where the plugin's libtensorflowlite_c is not. The .tflite still ships from
train.py for a future native path if profiling ever demands it.

Usage: python3 ml/export_dart_weights.py [klangio.npz]  (run from ml/)
"""
from __future__ import annotations

import json
import os
import struct
import sys

import numpy as np

NAMES = [
    "conv1_k", "conv1_b", "conv2_k", "conv2_b", "conv3_k", "conv3_b",
    "gru_k", "gru_rk", "gru_b", "dense_k", "dense_b",
]


def write_bin(path, arrays):
    with open(path, "wb") as fh:
        fh.write(b"SSML")
        fh.write(struct.pack("<II", 1, len(arrays)))
        for name, arr in arrays:
            arr = np.ascontiguousarray(arr, dtype="<f4")
            nb = name.encode()
            fh.write(struct.pack("<I", len(nb)))
            fh.write(nb)
            fh.write(struct.pack("<I", arr.ndim))
            fh.write(struct.pack(f"<{arr.ndim}I", *arr.shape))
            fh.write(arr.tobytes())


def main(npz="klangio.npz", n_fixture=8):
    d = np.load("weights.npz")
    ws = [d[f"arr_{i}"] for i in range(len(NAMES))]
    arrays = list(zip(NAMES, ws)) + [("mean", d["mean"]), ("std", d["std"])]

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_bin = os.path.join(root, "assets", "ml", "strum_crnn.bin")
    os.makedirs(os.path.dirname(out_bin), exist_ok=True)
    write_bin(out_bin, arrays)
    print(f"wrote {out_bin} ({os.path.getsize(out_bin)} bytes)")

    # Parity fixture: eval-fold windows (never train-fold — the fixture then
    # also documents honest eval-side behaviour) + Keras reference probs.
    import tensorflow as tf  # noqa: WPS433
    from klangio import split_by_recording
    from train import build_model

    data = np.load(npz)
    X, y = data["X"], data["y"]
    _, ev = split_by_recording(data["rec"])
    idx = np.flatnonzero(ev)[:: max(1, int(ev.sum()) // n_fixture)][:n_fixture]

    model = build_model(X.shape[1], X.shape[2])
    model.set_weights(ws)
    # r143 lesson: the reference is computed from the ROUNDED values the JSON
    # ships, so both sides consume literally identical input.
    Xr = X[idx].astype(float).round(5).astype(np.float32)
    Xn = (Xr - d["mean"]) / d["std"]
    probs = model.predict(Xn.astype(np.float32), verbose=0)

    fixture = {
        "note": "RAW (un-normalised) log-mel windows + Keras float32 softmax "
                "probs; Dart CrnnStrumClassifier must match <=1e-3.",
        "windows": [w.astype(float).tolist() for w in Xr],
        "labels": [int(v) for v in y[idx]],
        "probs": [[float(p[0]), float(p[1])] for p in probs],
    }
    out_fix = os.path.join(root, "test", "fixtures", "crnn_parity.json")
    with open(out_fix, "w") as fh:
        json.dump(fixture, fh)
    print(f"wrote {out_fix} ({len(idx)} windows)")
    acc = float((probs.argmax(1) == y[idx]).mean())
    print(f"fixture-window accuracy: {acc:.2f} (small-N, indicative only)")


if __name__ == "__main__":
    main(*sys.argv[1:])
