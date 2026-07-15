"""HONEST real-audio chord benchmark: the trained model vs GuitarSet (r202).

GuitarSet (Xi, Bittner, Pauwels, Ye, Bello, ISMIR 2018; Zenodo record 3371780,
**CC-BY-4.0**) is real guitar audio with hand-verified chord annotations — the
first corpus we have that is BOTH real AND truly labelled. See `guitarset.py`
for the dataset/annotation details and the licence attribution.

Why: held-out SYNTH accuracy is ~0.99 while the same model manages ~36% on real
Lab-mode audio (the shipping DSP gets ~56%) — synth transfers nothing, and the
Lab-mode number leans on an imperfect librosa reference, not true labels. This
script removes both excuses: real audio, true labels, the model's own metric.

Metrics (all frame-wise on the CQT hop grid, i.e. uniformly time-weighted)
-------------------------------------------------------------------------
  WCSR (frame majmin accuracy)
      fraction of frames whose argmax class == the true class. With a uniform
      hop this IS the MIREX Weighted Chord Symbol Recall — every frame covers
      the same 92.9 ms, so frame-counting == duration-weighting. Same definition
      train_chord.py reports, so the numbers are directly comparable.
  chord-only
      WCSR restricted to frames whose TRUE class != N.C. On GuitarSet's sheet
      annotation this is ~identical to WCSR (the annotation is gapless), and is
      kept for comparability with the training report.
  per guitarist
      WCSR grouped by guitarist id 00..05 — the leave-one-guitarist-out view the
      ML plan asks for. The spread across players is the generalisation signal.
  per mode (comp / solo)
      READ THIS BEFORE QUOTING A NUMBER: GuitarSet's `solo` takes are single-note
      lead lines played over the changes. The chord annotation still names the
      underlying harmony, but the audio contains no chord to hear. `solo` WCSR is
      therefore a hard, partly-unfair floor; **`comp` is the number that reflects
      the app's strumming use case**. Overall is reported for completeness.
  per style
      BN / Funk / Jazz / Rock / SS — jazz-heavy vocabularies (7ths, hdim7)
      reduce to majmin more lossily, so a style split explains part of the gap.

Also reported: a majority-class baseline and the model's prediction entropy, so
a degenerate "always predicts C" model cannot look like a result.

Runs on x86 CI (needs TensorFlow + the trained npz + the downloaded audio); the
ARM dev box has no TF. Streams track-by-track — only one take's audio/features
are ever in memory, so 3 hours of audio costs ~a few hundred MB peak.

Usage (from repo root):
    python ml/chords/eval_guitarset.py [--root DIR] [--limit N] [--out FILE]
"""
from __future__ import annotations

import argparse
import collections
import os
import sys
import wave

import numpy as np

# Make `from chords import ...` importable when run as a script from repo root.
_ML_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ML_DIR not in sys.path:
    sys.path.insert(0, _ML_DIR)

from chords import cqt, guitarset  # noqa: E402
from chords.labels import N_CLASSES, class_to_label  # noqa: E402

WIN = 100  # must match train_chord.WIN (the model's fixed input length)


def _out_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


# --------------------------------------------------------------------------- #
# Audio
# --------------------------------------------------------------------------- #
def read_wav(path: str):
    """WAV -> (mono float32 in [-1,1], sample_rate).

    `dataset.read_wav` assumes 16-bit PCM; GuitarSet's provenance is not ours to
    assume, so handle the widths the `wave` module can hand back (8/16/24/32-bit
    int and 32-bit float) and fail loudly on anything else rather than silently
    decoding noise and reporting it as a low score.
    """
    with wave.open(path, "rb") as w:
        ch, sw, sr, n = (w.getnchannels(), w.getsampwidth(),
                         w.getframerate(), w.getnframes())
        raw = w.readframes(n)
    if sw == 1:                                    # unsigned 8-bit
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif sw == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif sw == 3:                                  # packed 24-bit little-endian
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v & 0x800000, v - 0x1000000, v)   # sign-extend
        x = v.astype(np.float32) / 8388608.0
    elif sw == 4:
        i = np.frombuffer(raw, dtype="<i4")
        x = i.astype(np.float32) / 2147483648.0
    else:
        raise ValueError(f"{path}: unsupported sample width {sw} bytes")
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x.astype(np.float32), sr


def to_model_sr(pcm: np.ndarray, sr: int) -> np.ndarray:
    """Resample to cqt.SR (22050). GuitarSet mic audio is 44.1 kHz -> exactly 2:1.

    Prefers `scipy.signal.resample_poly` (polyphase FIR = proper anti-aliasing).
    `cqt.cqt` would otherwise resample internally by LINEAR interpolation, which
    for a 2:1 decimation aliases everything above 11 kHz back down into the band
    the CQT reads — that would penalise the model for our own front-end. Falls
    back to cqt's linear path (with a loud warning) if scipy is unavailable, so
    a missing dep degrades transparently instead of crashing.
    """
    if sr == cqt.SR or len(pcm) == 0:
        return pcm
    try:
        from math import gcd

        from scipy.signal import resample_poly
        g = gcd(int(sr), int(cqt.SR))
        return resample_poly(pcm, cqt.SR // g, sr // g).astype(np.float32)
    except ImportError:
        print(f"[warn] scipy missing — falling back to cqt's LINEAR resample "
              f"({sr} -> {cqt.SR} Hz); expect aliasing to depress the score.",
              file=sys.stderr)
        return cqt._resample(pcm, sr)


# --------------------------------------------------------------------------- #
# Model
# --------------------------------------------------------------------------- #
def load_model(npz_path: str):
    """Rebuild build_chord_model() + load the trained weights -> (model, mean, std).

    Reuses export_chord_dart's npz reader/loader so the weight->layer mapping has
    exactly ONE definition (it validates the array count and every shape via
    Keras set_weights).
    """
    from chords.export_chord_dart import build_loaded_model, load_npz
    weights, mean, std = load_npz(npz_path)
    return build_loaded_model(weights), mean, std


def predict_frames(model, feat_norm: np.ndarray) -> np.ndarray:
    """Per-frame argmax classes for a whole take -> (F,) int32.

    The model's Input is a fixed (WIN,144), so a take is cut into NON-OVERLAPPING
    WIN-frame chunks (every frame predicted exactly once — no averaging that
    could flatter the score), the tail zero-padded and trimmed back off. Weights
    are length-independent, so this is the same function the app's windowed path
    would compute.
    """
    F = feat_norm.shape[0]
    if F == 0:
        return np.zeros((0,), dtype=np.int32)
    n_chunks = -(-F // WIN)                       # ceil
    buf = np.zeros((n_chunks * WIN, feat_norm.shape[1]), dtype=np.float32)
    buf[:F] = feat_norm
    batch = buf.reshape(n_chunks, WIN, feat_norm.shape[1])
    probs = model.predict(batch, verbose=0)       # (n_chunks, WIN, 25)
    return probs.reshape(-1, probs.shape[-1]).argmax(-1)[:F].astype(np.int32)


# --------------------------------------------------------------------------- #
# Accumulators
# --------------------------------------------------------------------------- #
class Acc:
    """Streaming (correct, total) counter — keeps memory flat over 360 takes."""

    def __init__(self):
        self.ok = 0
        self.n = 0

    def add(self, ok: int, n: int):
        self.ok += int(ok)
        self.n += int(n)

    @property
    def acc(self) -> float:
        return self.ok / self.n if self.n else 0.0


def _fmt(name: str, a: Acc) -> str:
    return f"{name:<22s} {a.acc:.4f}  ({a.ok}/{a.n} frames)"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=None,
                    help="GuitarSet root (default $GUITARSET_ROOT or ml/data/guitarset)")
    ap.add_argument("--npz", default=None,
                    help="trained weights (default ml/chords/out/chord_weights.npz)")
    ap.add_argument("--limit", type=int, default=0,
                    help="evaluate only the first N tracks (smoke test)")
    ap.add_argument("--out", default=None,
                    help="report path (default ml/chords/out/guitarset_eval.txt)")
    args = ap.parse_args()

    root = args.root or guitarset.default_root()
    npz = args.npz or os.path.join(_out_dir(), "chord_weights.npz")
    out_path = args.out or os.path.join(_out_dir(), "guitarset_eval.txt")

    ts = guitarset.tracks(root)
    if not ts:
        print(f"[skip] no GuitarSet tracks under {root} — download() first.",
              file=sys.stderr)
        return 0            # a missing dataset must NOT fail the training job
    if not os.path.exists(npz):
        print(f"[skip] no trained weights at {npz} — run train_chord.py first.",
              file=sys.stderr)
        return 0
    if args.limit:
        ts = ts[: args.limit]

    print(f"[guitarset] {len(ts)} tracks under {root}", flush=True)
    model, mean, std = load_model(npz)

    overall, chord_only = Acc(), Acc()
    by_guitarist = collections.defaultdict(Acc)
    by_mode = collections.defaultdict(Acc)
    by_style = collections.defaultdict(Acc)
    true_hist = np.zeros(N_CLASSES, dtype=np.int64)
    pred_hist = np.zeros(N_CLASSES, dtype=np.int64)
    n_done = 0

    for wav_path, jams_path, gid in ts:
        try:
            _, style, _, _, mode, segs = guitarset.parse_jams(jams_path)
            pcm, sr = read_wav(wav_path)
            pcm = to_model_sr(pcm, sr)
            feat = cqt.cqt(pcm, cqt.SR)                       # (F,144) raw log1p
            if feat.shape[0] == 0:
                continue
            y_true = guitarset.frame_labels(segs, feat.shape[0], cqt.HOP, cqt.SR)
            y_pred = predict_frames(model, (feat - mean) / std)
        except Exception as e:  # one bad take must not sink a 360-track run
            print(f"[warn] {os.path.basename(wav_path)}: {e}", file=sys.stderr)
            continue

        hit = (y_pred == y_true)
        n = hit.size
        overall.add(hit.sum(), n)
        by_guitarist[gid].add(hit.sum(), n)
        by_mode[mode].add(hit.sum(), n)
        by_style[style].add(hit.sum(), n)
        nz = y_true != 0
        chord_only.add(hit[nz].sum(), nz.sum())
        true_hist += np.bincount(y_true, minlength=N_CLASSES)
        pred_hist += np.bincount(y_pred, minlength=N_CLASSES)

        n_done += 1
        if n_done % 20 == 0:
            print(f"  [{n_done}/{len(ts)}] running WCSR = {overall.acc:.4f}",
                  flush=True)

    if overall.n == 0:
        print("[skip] no track produced frames", file=sys.stderr)
        return 0

    # Degenerate-model tripwires: a constant predictor scores the majority class
    # share, and a collapsed model uses very few classes.
    majority = float(true_hist.max() / true_hist.sum())
    pred_classes = int((pred_hist > 0).sum())
    top_pred = int(pred_hist.argmax())
    top_pred_share = float(pred_hist.max() / pred_hist.sum())

    lines = []
    lines.append("=== GuitarSet REAL-audio chord eval (r202) ===")
    lines.append(f"# {guitarset.CITATION}")
    lines.append(f"# licence={guitarset.LICENSE}  audio={guitarset.AUDIO_MIC_DIR} "
                 f"(mono room mic — closest to the app's phone-mic path)")
    lines.append("# ground truth = the SHEET-derived chord annotation "
                 f"(data_source={guitarset.SHEET_DATA_SOURCE!r}); the performed "
                 "voicing annotation contains third-less power chords that "
                 "cannot be reduced to majmin honestly — see guitarset.py")
    lines.append(f"# metric = frame-wise majmin accuracy on the CQT hop grid "
                 f"(hop={cqt.HOP} @ {cqt.SR} Hz = {cqt.HOP/cqt.SR*1000:.1f} ms); "
                 f"uniform hop => frame accuracy == MIREX WCSR")
    lines.append(f"tracks_evaluated={n_done}")
    lines.append("")
    lines.append(_fmt("frame_wcsr", overall))
    lines.append(_fmt("chord_only(excl N.C.)", chord_only))
    lines.append("")
    lines.append("--- per guitarist (leave-one-guitarist-out view) ---")
    for g in sorted(by_guitarist):
        lines.append(_fmt(f"guitarist_{g}", by_guitarist[g]))
    lines.append("")
    lines.append("--- per mode ---")
    lines.append("# comp = strummed accompaniment -> the app's use case, QUOTE THIS.")
    lines.append("# solo = single-note lead over the changes: the annotation names")
    lines.append("#        the harmony but the audio has no chord to hear, so this")
    lines.append("#        is a partly-unfair floor, not a fair chord score.")
    for m in sorted(by_mode):
        lines.append(_fmt(f"mode_{m}", by_mode[m]))
    lines.append("")
    lines.append("--- per style ---")
    for s in sorted(by_style):
        lines.append(_fmt(f"style_{s}", by_style[s]))
    lines.append("")
    lines.append("--- sanity / degeneracy tripwires ---")
    lines.append(f"majority_class_baseline={majority:.4f}   "
                 f"# constant-predictor score; frame_wcsr must beat this")
    lines.append(f"pred_distinct_classes={pred_classes}/{N_CLASSES}")
    lines.append(f"pred_top_class={class_to_label(top_pred)} "
                 f"share={top_pred_share:.4f}")
    lines.append(f"true_class_hist={true_hist.tolist()}")
    lines.append(f"pred_class_hist={pred_hist.tolist()}")

    report = "\n".join(lines)
    print("\n" + report)
    os.makedirs(_out_dir(), exist_ok=True)
    with open(out_path, "w") as fh:
        fh.write(report + "\n")
    print(f"\nsaved {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
