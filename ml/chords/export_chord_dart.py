"""Export the trained CHORD CRNN for the PURE-DART inference path (ship-path 2).

Mirrors `ml/export_dart_weights.py` (the strum-CRNN exporter): same
self-describing little-endian, name-keyed, float32 container — only the MAGIC
and the array set differ (chord model adds BatchNorm + is Bidirectional). This
module is the r196 CONTRACT: the Dart chord loader/forward-pass must consume
exactly this layout and match the fixture below to <=1e-3.

It emits TWO artifacts into ml/chords/out/ (CI uploads both):

  chord_crnn.bin            the weights blob (byte layout documented below)
  chord_infer_fixture.json  a deterministic (100,144) CQT input + the Keras
                            float32 per-frame softmax + argmax = the golden
                            for the r196 Dart forward-pass parity test.

Run on x86 CI (needs TensorFlow + the trained npz); the ARM dev box has no TF.
Usage (from repo root): python3 ml/chords/export_chord_dart.py


================================ BYTE LAYOUT ================================
(THIS is the r196 contract — a Dart loader parses it byte-for-byte.)

All integers uint32 LITTLE-ENDIAN, all weights float32 LITTLE-ENDIAN, C-order
(row-major) exactly as the numpy shape. The container is self-describing AND
order-stable: a reader may key arrays by name (like Dart CrnnStrumNet.parse) or
read them in the fixed documented order — both are valid.

  HEADER
    bytes[0:4]    ASCII magic  'CCRN'
    u32           version      = 1
    u32           count        = number of arrays (= 30)

  then `count` arrays, each:
    u32           nameLen
    nameLen bytes UTF-8 name
    u32           ndim
    ndim * u32    dims[]  (numpy shape, row-major)
    prod(dims)*4  float32 data[]  (C-contiguous)

  ARRAY ORDER + SHAPES (win=100, n_bins=144, 25 classes, gru units=96):

    idx name          shape          meaning
    --- ------------- -------------- ------------------------------------------
     0  conv1_k       (3,3,1,16)     Conv2D#1 kernel (kh,kw,inC,outC)
     1  conv1_b       (16,)          Conv2D#1 bias
     2  bn1_gamma     (16,)          BatchNorm#1 scale (gamma)
     3  bn1_beta      (16,)          BatchNorm#1 shift (beta)
     4  bn1_mean      (16,)          BatchNorm#1 moving_mean
     5  bn1_var       (16,)          BatchNorm#1 moving_variance
     6  conv2_k       (3,3,16,32)    Conv2D#2 kernel
     7  conv2_b       (32,)          Conv2D#2 bias
     8  bn2_gamma     (32,)
     9  bn2_beta      (32,)
    10  bn2_mean      (32,)
    11  bn2_var       (32,)
    12  conv3_k       (3,3,32,32)    Conv2D#3 kernel
    13  conv3_b       (32,)          Conv2D#3 bias
    14  bn3_gamma     (32,)
    15  bn3_beta      (32,)
    16  bn3_mean      (32,)
    17  bn3_var       (32,)
    18  dense1_k      (576,128)      TimeDistributed Dense(128) kernel; 576 =
                                     (n_bins//8)*32 = 18*32 (freq pooled 3x /2)
    19  dense1_b      (128,)         Dense(128) bias
    20  gru_fwd_k     (128,288)      fwd GRU input kernel; 288 = 3*96 gates
    21  gru_fwd_rk    (96,288)       fwd GRU recurrent_kernel
    22  gru_fwd_b     (2,288)        fwd GRU bias; row0 = input bias, row1 =
                                     recurrent bias (reset_after=True → 2 rows)
    23  gru_bwd_k     (128,288)      bwd GRU input kernel
    24  gru_bwd_rk    (96,288)       bwd GRU recurrent_kernel
    25  gru_bwd_b     (2,288)        bwd GRU bias (2 rows)
    26  dense2_k      (192,25)       output Dense(25) kernel; 192 = 2*96 (BiGRU
                                     concat: forward ++ backward)
    27  dense2_b      (25,)          output Dense(25) bias
    28  mean          (144,)         train-only per-bin CQT mean (normalize IN)
    29  std           (144,)         train-only per-bin CQT std  (normalize IN)

  FORWARD (for the Dart port — the layer graph the fixture pins):
    x0 = (CQT_in - mean) / std                     # (100,144) → (100,144,1)
    for b in 1..3:
        x = relu(conv2d_same(x, convb_k) + convb_b)   # Conv fuses ReLU
        x = batchnorm(x; gamma,beta,mean,var, eps=1e-3)  # Keras BN default eps
        x = maxpool(x, pool=(1,2))                    # halve FREQ, keep TIME
    x = reshape(x, (100, 18*32=576))                  # C-order: freq,then chan
    x = relu(x @ dense1_k + dense1_b)                 # (100,128)
    hf = GRU_fwd(x); hb = GRU_bwd(reverse(x))         # each (100,96), seq out
    h  = concat(hf, hb, axis=-1)                      # (100,192)
    y  = softmax(h @ dense2_k + dense2_b)             # (100,25)

  GRU CONVENTION (recorded explicitly — Dart MUST match Keras exactly):
    * Keras GRU default reset_after=True → bias has TWO rows (input, recurrent);
      the reset gate is applied AFTER the recurrent matmul:
        z  = sigmoid( x·Wk[:,z] + b_in[z] + h·Wrk[:,z] + b_rec[z] )
        r  = sigmoid( x·Wk[:,r] + b_in[r] + h·Wrk[:,r] + b_rec[r] )
        hh = tanh(   x·Wk[:,h] + b_in[h] + r * ( h·Wrk[:,h] + b_rec[h] ) )
        h' = z*h + (1-z)*hh
    * Gate column order in every kernel/bias block is [z, r, h]
      (update, reset, candidate) — units-wide blocks 0:96 / 96:192 / 192:288.
    (Identical to the shipped strum net; see crnn_strum_net.dart _gruLastState —
     the chord port differs only by the extra Dense(128) before the GRU and by
     being Bidirectional.)
============================================================================
"""
from __future__ import annotations

import json
import os
import struct
import sys

import numpy as np

# Make `from chords import ...` importable when run as a script from repo root.
_ML_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ML_DIR not in sys.path:
    sys.path.insert(0, _ML_DIR)

MAGIC = b"CCRN"
VERSION = 1

# npz `arr_i` index -> exported name, in model.get_weights() order. This mirrors
# build_chord_model's layer graph: Conv+BN (x3), Dense(128), Bidirectional(GRU)
# = forward-then-backward each [kernel, recurrent_kernel, bias], Dense(25).
# BatchNormalization.get_weights() order is [gamma, beta, moving_mean,
# moving_variance] (Keras standard). train_chord.py saves via
#   np.savez(path, *model.get_weights(), mean=mean, std=std)
# so the weight arrays land under keys arr_0..arr_27 and mean/std are named.
WEIGHT_NAMES = [
    "conv1_k", "conv1_b", "bn1_gamma", "bn1_beta", "bn1_mean", "bn1_var",
    "conv2_k", "conv2_b", "bn2_gamma", "bn2_beta", "bn2_mean", "bn2_var",
    "conv3_k", "conv3_b", "bn3_gamma", "bn3_beta", "bn3_mean", "bn3_var",
    "dense1_k", "dense1_b",
    "gru_fwd_k", "gru_fwd_rk", "gru_fwd_b",
    "gru_bwd_k", "gru_bwd_rk", "gru_bwd_b",
    "dense2_k", "dense2_b",
]
N_WEIGHTS = len(WEIGHT_NAMES)  # 28

# Expected ndim per array — a cheap drift tripwire (shapes fully validated by
# set_weights against the freshly built model below).
_EXPECTED_NDIM = {
    "conv1_k": 4, "conv2_k": 4, "conv3_k": 4,
    "conv1_b": 1, "conv2_b": 1, "conv3_b": 1,
    "dense1_k": 2, "dense2_k": 2, "dense1_b": 1, "dense2_b": 1,
    "gru_fwd_k": 2, "gru_fwd_rk": 2, "gru_fwd_b": 2,
    "gru_bwd_k": 2, "gru_bwd_rk": 2, "gru_bwd_b": 2,
}


def _out_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


def load_npz(npz_path):
    """Return (weight_list[28], mean(144,), std(144,)) from chord_weights.npz.

    Reads the `arr_i` keys train_chord.py actually writes (NOT assumed names)
    and validates the count matches the architecture so a graph change trips
    here rather than silently mis-mapping."""
    d = np.load(npz_path)
    arr_keys = sorted(
        (k for k in d.files if k.startswith("arr_")),
        key=lambda k: int(k.split("_")[1]),
    )
    if len(arr_keys) != N_WEIGHTS:
        raise ValueError(
            f"npz has {len(arr_keys)} weight arrays, expected {N_WEIGHTS} — "
            f"build_chord_model changed? keys={arr_keys}")
    weights = [d[k] for k in arr_keys]
    if "mean" not in d.files or "std" not in d.files:
        raise ValueError(f"npz missing mean/std (has {d.files})")
    return weights, d["mean"], d["std"]


def build_loaded_model(weights):
    """Build build_chord_model() and load the npz weights into it (validates
    every shape via Keras set_weights)."""
    from chords.train_chord import build_chord_model  # noqa: WPS433 (needs TF)
    model = build_chord_model()
    model.set_weights(weights)  # raises if any shape mismatches
    return model


def write_bin(path, named_arrays):
    """Write the CCRN container (see module docstring for the byte layout)."""
    with open(path, "wb") as fh:
        fh.write(MAGIC)
        fh.write(struct.pack("<II", VERSION, len(named_arrays)))
        for name, arr in named_arrays:
            arr = np.ascontiguousarray(arr, dtype="<f4")
            nb = name.encode("utf-8")
            fh.write(struct.pack("<I", len(nb)))
            fh.write(nb)
            fh.write(struct.pack("<I", arr.ndim))
            fh.write(struct.pack(f"<{arr.ndim}I", *arr.shape))
            fh.write(arr.tobytes())


def export_bin(weights, mean, std, path):
    named = list(zip(WEIGHT_NAMES, weights))
    for name, arr in named:
        exp = _EXPECTED_NDIM.get(name)
        if exp is not None and arr.ndim != exp:
            raise ValueError(f"{name}: ndim {arr.ndim} != expected {exp}")
    # Record reset_after=True explicitly: the 2-row GRU bias proves it.
    fb = dict(named)["gru_fwd_b"]
    if fb.ndim != 2 or fb.shape[0] != 2:
        raise ValueError(
            f"gru_fwd_b shape {fb.shape} — expected (2, 3*units); a single-row "
            f"bias would mean reset_after=False, breaking the Dart contract.")
    named = named + [("mean", np.asarray(mean)), ("std", np.asarray(std))]
    write_bin(path, named)
    return named


def _demo_pcm():
    """Deterministic (no-RNG) two-chord PCM long enough for exactly 100 CQT
    frames: C-major triad then A-minor triad. Content is irrelevant to the
    parity contract (the RAW CQT is shipped verbatim and the golden recomputed
    from it) — two chords just give the golden some per-frame variety."""
    from chords import cqt  # noqa: WPS433
    ns = 100 * cqt.HOP  # n_frames(ns) = 1 + (ns-1)//HOP = 100 exactly
    t = np.arange(ns, dtype=np.float64) / cqt.SR
    half = ns // 2
    sig = np.zeros(ns, dtype=np.float64)
    cmaj = (261.63, 329.63, 392.00)   # C4 E4 G4
    amin = (220.00, 261.63, 329.63)   # A3 C4 E4
    for f in cmaj:
        sig[:half] += np.sin(2 * np.pi * f * t[:half])
    for f in amin:
        sig[half:] += np.sin(2 * np.pi * f * t[half:])
    return (0.3 * sig).astype(np.float32)


def make_fixture(model, mean, std, path, win=100):
    """Run the loaded Keras model on a deterministic (win,144) CQT and dump the
    golden (raw input + per-frame softmax + argmax) for the r196 parity test."""
    from chords import cqt  # noqa: WPS433
    from chords.labels import class_to_label  # noqa: WPS433

    X = cqt.cqt(_demo_pcm(), cqt.SR)          # (>=100, 144) raw log1p CQT
    X = X[:win]
    if X.shape != (win, cqt.N_BINS):
        raise ValueError(f"CQT fixture input shape {X.shape} != ({win},144)")

    # r143 pattern: ship the ROUNDED raw input and compute the golden FROM it so
    # both sides consume literally identical numbers (cross-platform CQT float
    # drift is irrelevant — the .bin/Dart never recompute this CQT).
    Xr = X.astype(np.float64).round(5).astype(np.float32)
    Xn = (Xr - mean) / std
    probs = model.predict(Xn[None].astype(np.float32), verbose=0)[0]  # (win,25)
    argmax = probs.argmax(-1).astype(int)

    fixture = {
        "note": "RAW (un-normalised) CQT (win,144) + Keras float32 per-frame "
                "softmax; the Dart chord forward pass (normalize by mean/std "
                "then the CCRN graph) must match probs to <=1e-3. Golden was "
                "computed from the ROUNDED input shipped here.",
        "sr": cqt.SR,
        "n_bins": cqt.N_BINS,
        "win": win,
        "n_classes": int(probs.shape[1]),
        "input_cqt": Xr.astype(float).tolist(),
        "probs": np.round(probs.astype(float), 6).tolist(),
        "argmax": [int(v) for v in argmax],
        "argmax_labels": [class_to_label(int(v)) for v in argmax],
    }
    with open(path, "w") as fh:
        json.dump(fixture, fh)
    return fixture


def main():
    npz = os.path.join(_out_dir(), "chord_weights.npz")
    if not os.path.exists(npz):
        print(f"missing {npz} — run train_chord.py first", file=sys.stderr)
        sys.exit(1)

    weights, mean, std = load_npz(npz)
    model = build_loaded_model(weights)

    out_bin = os.path.join(_out_dir(), "chord_crnn.bin")
    named = export_bin(weights, mean, std, out_bin)
    print(f"wrote {out_bin} ({os.path.getsize(out_bin)} bytes, "
          f"{len(named)} arrays)")
    for name, arr in named:
        print(f"  {name:12s} {tuple(np.asarray(arr).shape)}")

    out_fix = os.path.join(_out_dir(), "chord_infer_fixture.json")
    fx = make_fixture(model, mean, std, out_fix)
    print(f"wrote {out_fix} (win={fx['win']}, {fx['n_classes']} classes)")
    # Small indicative sanity print (NOT an accuracy claim — synthetic input).
    uniq = sorted(set(fx["argmax"]))
    print(f"fixture argmax classes present: {uniq}")


if __name__ == "__main__":
    main()
