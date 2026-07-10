"""Turn real recordings into a labeled training set for the strum CRNN.

Input: a folder of paired files, one pair per take:
    <take>.wav            mono guitar audio (any sr; resampled to 16 kHz)
    <take>.accel.csv      wrist-IMU: columns `t_seconds,axis` (the swing axis)

For each detected onset we auto-label the stroke from the IMU (chunk 015) and
cut a fixed log-mel window. Output: dataset.npz with X (N, frames, mels) and
y (N,) in {0=down, 1=up}. Pure NumPy + stdlib `wave` — no TF needed here.

Usage: python3 ml/prepare_dataset.py <data_dir> [out.npz]
"""
from __future__ import annotations

import glob
import os
import sys
import wave

import numpy as np

import features as F

LABELS = {"down": 0, "up": 1}


def _read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        raw = w.readframes(w.getnframes())
    x = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    if sr != F.SR:  # simple linear resample to 16 kHz
        n = int(round(len(x) * F.SR / sr))
        x = np.interp(np.linspace(0, len(x) - 1, n),
                      np.arange(len(x)), x).astype(np.float32)
    return x


def build(data_dir: str, out: str = "dataset.npz"):
    xs, ys, skipped = [], [], 0
    for wav_path in sorted(glob.glob(os.path.join(data_dir, "*.wav"))):
        base = wav_path[:-4]
        accel_path = base + ".accel.csv"
        if not os.path.exists(accel_path):
            print(f"  skip {os.path.basename(wav_path)} (no .accel.csv)")
            continue
        pcm = _read_wav(wav_path)
        logmel = F.log_mel(pcm)
        arr = np.loadtxt(accel_path, delimiter=",", ndmin=2)
        at, ax = arr[:, 0], arr[:, 1]
        for onset_s in F.spectral_flux_onsets(pcm):
            label = F.label_direction_from_accel(at, ax, onset_s)
            if label is None:
                skipped += 1
                continue
            xs.append(F.window_at(logmel, onset_s))
            ys.append(LABELS[label])
    if not xs:
        print("no labeled windows — check the data folder + IMU polarity")
        return
    X = np.stack(xs).astype(np.float32)
    y = np.array(ys, dtype=np.int64)
    np.savez_compressed(out, X=X, y=y)
    n_down = int((y == 0).sum())
    print(f"wrote {out}: {len(y)} windows "
          f"({n_down} down / {len(y) - n_down} up), {skipped} ambiguous skipped")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "dataset.npz")
