"""Build a frame-wise CHORD dataset from real Klangio recordings (phase 0.4).

Each recording → CQT features (`cqt.cqt`) + per-frame majmin labels
(`frames.labels_for_recording`), chunked into fixed-length windows for the
sequence model. Real solo-guitar chord data — the first end-to-end shakedown of
the ML chord pipeline before the synthetic full-band corpus exists.

Pure NumPy (no TensorFlow) so it runs on the ARM box; training (`train_chord.py`)
consumes the npz on x86 CI.
"""
from __future__ import annotations

import glob
import os
import wave

import numpy as np

from chords import cqt, frames

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "data", "klangio")


def read_wav(path: str) -> tuple[np.ndarray, int]:
    """16-bit PCM WAV → (mono float32 in [-1,1], sample_rate)."""
    with wave.open(path, "rb") as w:
        ch, sr, n = w.getnchannels(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


def recording_ids(data_dir: str = DATA_DIR) -> list[str]:
    ids = []
    for p in sorted(glob.glob(os.path.join(data_dir, "recording_*_phone.wav"))):
        base = os.path.basename(p)
        rid = base[len("recording_"):-len("_phone.wav")]
        if os.path.exists(os.path.join(data_dir, f"recording_{rid}.strums")):
            ids.append(rid)
    return ids


def features_and_labels(rec_id: str, data_dir: str = DATA_DIR) -> tuple[np.ndarray, np.ndarray]:
    """(F,144) CQT features + (F,) majmin labels for one recording, aligned."""
    pcm, sr = read_wav(os.path.join(data_dir, f"recording_{rec_id}_phone.wav"))
    feat = cqt.cqt(pcm, sr)                       # (F, 144), framed at cqt.SR/HOP
    lab = frames.labels_for_recording(
        rec_id, feat.shape[0], cqt.HOP, cqt.SR, data_dir=data_dir)
    return feat.astype(np.float32), lab.astype(np.int32)


def _windows(feat: np.ndarray, lab: np.ndarray, win: int, step: int):
    """Slice a recording into (win, 144) / (win,) chunks with `step` overlap.
    A tail shorter than `win` is zero-padded (labels padded with N.C. = 0)."""
    F = feat.shape[0]
    if F == 0:
        return
    for s in range(0, max(1, F - win + 1), step):
        e = s + win
        if e <= F:
            yield feat[s:e], lab[s:e]
        else:
            fpad = np.zeros((win, feat.shape[1]), np.float32)
            lpad = np.zeros((win,), np.int32)
            fpad[: F - s] = feat[s:F]
            lpad[: F - s] = lab[s:F]
            yield fpad, lpad
            break


def build(data_dir: str = DATA_DIR, win: int = 100, step: int = 50,
          out: str | None = None):
    """Build X (N,win,144), Y (N,win), rec (N,) over all recordings and
    optionally save to `out` npz. Returns (X, Y, rec, ids)."""
    ids = recording_ids(data_dir)
    Xs, Ys, recs = [], [], []
    for rid in ids:
        feat, lab = features_and_labels(rid, data_dir)
        for fx, ly in _windows(feat, lab, win, step):
            Xs.append(fx)
            Ys.append(ly)
            recs.append(rid)
    if not Xs:
        return (np.zeros((0, win, cqt.N_BINS), np.float32),
                np.zeros((0, win), np.int32), np.array([], object), ids)
    X = np.stack(Xs).astype(np.float32)
    Y = np.stack(Ys).astype(np.int32)
    rec = np.array(recs, dtype=object)
    if out:
        np.savez_compressed(out, X=X, Y=Y, rec=rec.astype("U8"))
    return X, Y, rec, ids


def build_synth(n_songs: int, seed: int, win: int = 100, step: int = 50,
                seconds_per_chord: float = 1.0):
    """Build a SYNTHETIC full-band chord dataset (same convention as `build`).

    Renders `n_songs` full-band songs with `synth_songs.render_dataset` (pure
    NumPy, seedable — NO global randomness), then reuses the EXACT same feature
    (`cqt.cqt`) + label (`frames.frame_labels`) + window (`_windows`) pipeline as
    the Klangio `build`. Every window from song index `k` is tagged
    `rec = "synth_<k>"`, a namespace disjoint from Klangio recording ids so the
    two never collide in a split.

    Returns (X (N,win,144) float32, Y (N,win) int32, rec (N,) object) — the same
    dtypes/shapes as `build` (minus the Klangio-only `ids`). No TensorFlow.
    """
    from chords import synth_songs

    songs = synth_songs.render_dataset(
        n_songs, seed=seed, seconds_per_chord=seconds_per_chord)
    Xs, Ys, recs = [], [], []
    for k, (pcm, events) in enumerate(songs):
        feat = cqt.cqt(pcm, cqt.SR).astype(np.float32)          # (F, 144)
        lab = frames.frame_labels(
            events, feat.shape[0], cqt.HOP, cqt.SR).astype(np.int32)  # (F,)
        rid = f"synth_{k}"
        for fx, ly in _windows(feat, lab, win, step):
            Xs.append(fx)
            Ys.append(ly)
            recs.append(rid)
    if not Xs:
        return (np.zeros((0, win, cqt.N_BINS), np.float32),
                np.zeros((0, win), np.int32), np.array([], object))
    X = np.stack(Xs).astype(np.float32)
    Y = np.stack(Ys).astype(np.int32)
    rec = np.array(recs, dtype=object)
    return X, Y, rec


if __name__ == "__main__":
    if not os.path.isdir(DATA_DIR):
        print(f"[skip] no dataset at {DATA_DIR}")
    else:
        ids = recording_ids()
        print(f"[ok] {len(ids)} recordings with chord labels")
        # Smoke: one recording end-to-end.
        feat, lab = features_and_labels(ids[0])
        segs = frames.chord_segments(lab, cqt.HOP, cqt.SR)
        dist = frames.class_distribution(lab)
        print(f"[ok] rec {ids[0]}: feat {feat.shape}, labels {lab.shape}, "
              f"{len(segs)} segments, classes {sorted(np.nonzero(dist)[0].tolist())}")
        X, Y, rec, _ = build(win=100, step=50)
        print(f"[ok] dataset: X {X.shape}, Y {Y.shape}, "
              f"{len(set(rec.tolist()))} recordings, "
              f"class balance {np.bincount(Y.ravel(), minlength=25).tolist()}")
