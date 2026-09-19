# -*- coding: utf-8 -*-
"""Read the SSML v1 weight blobs back out of `assets/ml/*.bin` (pure NumPy).

`export_dart_weights.write_bin` is the only writer; until E18-R43 there was no reader, so a
shipped asset could only be evaluated through Dart. That made one comparison impossible in
Python: the SHIPPED 3-class model against the SETTLED one, because only the settled model's
weights survive as an `.npz` (`weights_live_3c_settled.npz`) -- the shipped model's training
artefacts are gone and only its `.bin` remains.

Without this reader the two assets could only be compared through two different instruments,
which is the mistake LESSONS L682 §1 records. With it, one instrument runs both.

The format, from `write_bin`:

    "SSML" | uint32 version | uint32 nArrays
    then per array: uint32 nameLen | name | uint32 ndim | ndim x uint32 shape | float32 data

Little-endian throughout, C-contiguous data.
"""
from __future__ import annotations

import struct

import numpy as np

MAGIC = b"SSML"
SUPPORTED_VERSION = 1

#: The weight order `export_dart_weights` writes and `train.build_model` expects.
WEIGHT_NAMES = (
    "conv1_k", "conv1_b", "conv2_k", "conv2_b", "conv3_k", "conv3_b",
    "gru_k", "gru_rk", "gru_b", "dense_k", "dense_b",
)


def read_ssml(path: str) -> dict[str, np.ndarray]:
    """{name: array} for every array in the blob, in file order (dicts keep it)."""
    with open(path, "rb") as handle:
        blob = handle.read()
    if blob[:4] != MAGIC:
        raise ValueError(f"{path}: not an SSML blob (magic {blob[:4]!r})")
    version, n_arrays = struct.unpack_from("<II", blob, 4)
    if version != SUPPORTED_VERSION:
        raise ValueError(f"{path}: SSML version {version}, expected {SUPPORTED_VERSION}")
    out: dict[str, np.ndarray] = {}
    offset = 12
    for index in range(n_arrays):
        (name_len,) = struct.unpack_from("<I", blob, offset)
        offset += 4
        name = blob[offset:offset + name_len].decode()
        offset += name_len
        (ndim,) = struct.unpack_from("<I", blob, offset)
        offset += 4
        shape = struct.unpack_from(f"<{ndim}I", blob, offset)
        offset += 4 * ndim
        count = int(np.prod(shape)) if ndim else 1
        data = np.frombuffer(blob, dtype="<f4", count=count, offset=offset)
        offset += 4 * count
        if name in out:
            raise ValueError(f"{path}: array {name!r} appears twice (index {index})")
        out[name] = data.reshape(shape).copy()
    if offset != len(blob):
        raise ValueError(
            f"{path}: {len(blob) - offset} trailing byte(s) after {n_arrays} arrays -- "
            "the reader and the writer disagree about the format")
    return out


def load_keras(path: str, frames: int = 15, mels: int = 128, n_classes: int = 3):
    """(model, mean, std) -- a Keras model carrying the blob's weights.

    Imports TensorFlow lazily so `read_ssml` stays usable without it.
    """
    import tensorflow as tf  # noqa: F401  (imported for its side effect on Keras)
    from train import build_model

    arrays = read_ssml(path)
    missing = [name for name in WEIGHT_NAMES if name not in arrays]
    if missing:
        raise ValueError(f"{path}: missing {missing}")
    model = build_model(frames, mels, n_classes=n_classes)
    model.set_weights([arrays[name] for name in WEIGHT_NAMES])
    return model, arrays["mean"], arrays["std"]


if __name__ == "__main__":
    import sys

    for target in sys.argv[1:] or ["assets/ml/strum_crnn_live_3c.bin"]:
        print(target)
        for name, array in read_ssml(target).items():
            print(f"  {name:<10} {tuple(array.shape)}")
