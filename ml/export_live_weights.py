"""Export the TRUE-70ms live strum model for Dart (ml-track r168).

Same SSML v1 binary as export_dart_weights.py, but from weights_live_d70.npz
into assets/ml/strum_crnn_live.bin, plus a net-level parity fixture whose
windows are AUDIO-TRUNCATED (experiment_deadline.window_truncated) — the
exact distribution the live serve path must reproduce.

Usage: /home/ubuntu/tf-venv/bin/python export_live_weights.py
"""
from __future__ import annotations

import json
import os

import numpy as np

from experiment_deadline import DATA, window_truncated
from export_dart_weights import NAMES, write_bin
from klangio import parse_strums, split_by_recording
from prepare_dataset import _read_wav
from train import build_model

DEADLINE_S = 0.070
N_FIXTURE = 32


def main():
    d = np.load("weights_live_d70.npz")
    ws = [d[f"arr_{i}"] for i in range(len(NAMES))]
    arrays = list(zip(NAMES, ws)) + [("mean", d["mean"]), ("std", d["std"])]

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_bin = os.path.join(root, "assets", "ml", "strum_crnn_live.bin")
    write_bin(out_bin, arrays)
    print(f"wrote {out_bin} ({os.path.getsize(out_bin)} bytes)")

    # Fixture windows: eval-fold recordings, audio-truncated at the deadline.
    full = np.load("klangio.npz")
    _, ev = split_by_recording(full["rec"])
    eval_ids = sorted(set(full["rec"][ev].tolist()))

    xs, ys = [], []
    for rid in eval_ids:
        with open(f"{DATA}/recording_{rid}.strums") as fh:
            events = parse_strums(fh.read())
        pcm = _read_wav(f"{DATA}/recording_{rid}_phone.wav")
        for t, direction, _ in events[:2]:  # 2 per take -> 32 windows
            if t * 16000 >= len(pcm):
                continue
            xs.append(window_truncated(pcm, t, DEADLINE_S))
            ys.append(0 if direction == "down" else 1)
        if len(xs) >= N_FIXTURE:
            break
    X = np.stack(xs[:N_FIXTURE])
    y = ys[:N_FIXTURE]

    model = build_model(X.shape[1], X.shape[2])
    model.set_weights(ws)
    Xr = X.astype(float).round(5).astype(np.float32)  # r143: ref from ROUNDED
    probs = model.predict((Xr - d["mean"]) / d["std"], verbose=0)

    fixture = {
        "note": "audio-truncated (70 ms) log-mel windows + Keras softmax; "
                "the Dart live net must match <=1e-3.",
        "windows": [w.astype(float).tolist() for w in Xr],
        "labels": [int(v) for v in y],
        "probs": [[float(p[0]), float(p[1])] for p in probs],
    }
    out_fix = os.path.join(root, "test", "fixtures", "crnn_live_parity.json")
    with open(out_fix, "w") as fh:
        json.dump(fixture, fh)
    acc = float((probs.argmax(1) == np.array(y)).mean())
    print(f"wrote {out_fix} ({len(y)} windows), fixture accuracy {acc:.2f}")


if __name__ == "__main__":
    main()
