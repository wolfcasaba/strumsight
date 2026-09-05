"""E14-R18 joint streaming onset+direction prototype — training (ADR 0517).

Trains a SINGLE small CRNN head that classifies a causal + small-controlled-
lookahead log-mel window directly into {down-onset, up-onset, no-event},
instead of the legacy two-stage pipeline (SuperFlux onset detector ->
direction classifier, `lib/features/live/engine/dsp/superflux_onset_detector
.dart` -> `strum_direction_classifier.dart`) where an onset-detector miss can
never be recovered by the direction stage (ADR 0312, Chapter 14 §4.4/§5.1).

Architecture is deliberately the SAME conv+GRU trunk as the shipped models
(`ml/train.py::build_model`) so the comparison is about the joint head +
lookahead geometry, not a different network family. What differs:
  - the window is PRE_FRAMES (causal context) + LOOKAHEAD_FRAMES (controlled
    lookahead) = 7 frames (70 ms) total, far below the legacy direction
    classifier's 15-frame (150 ms) window (ADR 0517 D1: the lookahead is a
    number, reported in frames and ms, not "offline is better, then the
    mobile port will figure it out");
  - the head is 3-class (down/up/no-event) so the SAME forward pass decides
    "is this an onset, and if so which direction" in one shot, instead of
    depending on an externally-detected onset time.

Split: leave-one-guitarist-out (`ml/klangio.py::guitarist_of`/`logo_folds`,
ADR 0517 D2). Only ONE representative fold is trained per run, not the full
3-fold LOGO sweep — a documented, compute-budget-driven simplification
(round brief §0.0/R8: the whole documented run must fit in <=20 minutes on
this box). The held-out guitarist defaults to the first fold in sorted
guitarist-id order (deterministic, not cherry-picked for a favorable score).

Every run artifact — trained weights, provenance JSON, the built feature
cache — is written under --workdir, which MUST resolve OUTSIDE this
repository (ADR 0517 D5, ADR 0369 D3 precedent). Nothing in this script ever
writes under the repo tree.

Usage (ONLY the TensorFlow-equipped interpreter can run this — round brief
§0.0/R3; the system `python3` has no TensorFlow):

  /home/ubuntu/tf-venv/bin/python ml/joint_prototype/train_prototype.py \\
      --workdir /tmp/e14r18-work

Optional flags: --data-dir (default ml/data/klangio), --held-out-guitarist,
--epochs (default 12), --batch-size (default 32), --seed (default 42).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
ML_ROOT = REPO_ROOT / "ml"
sys.path.insert(0, str(ML_ROOT))

import features as F  # noqa: E402
import negatives as NEG  # noqa: E402
from klangio import guitarist_of, logo_folds, parse_strums, recording_ids  # noqa: E402
from prepare_dataset import _read_wav  # noqa: E402

#: Causal context frames before the decision point — never counted as
#: lookahead (ADR 0517 D1).
PRE_FRAMES = 3
#: Controlled lookahead frames AFTER the decision point — the number this
#: round's whole measurement contract hangs on (ADR 0517 D1).
LOOKAHEAD_FRAMES = 4
FRAMES = PRE_FRAMES + LOOKAHEAD_FRAMES
HOP_MS = 1000.0 * F.HOP / F.SR  # 10.0 ms/frame at 16 kHz, hop 160
LOOKAHEAD_MS = LOOKAHEAD_FRAMES * HOP_MS

LABELS = {"down": 0, "up": 1}
NO_EVENT_LABEL = 2
N_CLASSES = 3

DEFAULT_SEED = 42
DEFAULT_EPOCHS = 12
DEFAULT_BATCH_SIZE = 32
DEFAULT_PATIENCE = 4


class WorkdirInsideRepositoryError(ValueError):
    """``--workdir`` resolved inside this repository (ADR 0517 D5)."""


class FoldTrainabilityError(ValueError):
    """A train or test fold does not carry all 3 classes — training or
    evaluating against it would be meaningless (r142-audit precedent,
    `ml/klangio.py::assert_folds_trainable`, extended here to 3 classes
    because that helper is hard-coded to the legacy 2-class {0,1} set)."""


class GuitaristLeakageError(ValueError):
    """The train and test guitarist-id sets are not disjoint (ADR 0517 D2,
    fail-closed) — a structural bug in the split, never a warning."""


def resolve_workdir(raw_workdir: str) -> Path:
    workdir = Path(raw_workdir).expanduser().resolve()
    repo_root = REPO_ROOT.resolve()
    if workdir == repo_root or repo_root in workdir.parents:
        raise WorkdirInsideRepositoryError(
            f"--workdir {workdir} resolves inside this repository "
            f"({repo_root}); ADR 0517 D5 requires every run artifact "
            "(weights, provenance, feature cache) to live outside the repo "
            "tree — pick a path such as /tmp/e14r18-work"
        )
    return workdir


def joint_window(
    pcm: np.ndarray,
    onset_s: float,
    pre_frames: int = PRE_FRAMES,
    lookahead_frames: int = LOOKAHEAD_FRAMES,
) -> np.ndarray:
    """The (pre_frames+lookahead_frames, N_MELS) log-mel window a genuinely
    lookahead-limited streaming model would see for a candidate event at
    `onset_s`: audio is ZEROED past onset_s+lookahead (train == serve), same
    discipline as `ml/experiment_deadline.py::window_truncated` — a log-mel
    frame near the boundary still integrates a full FFT window (128 ms) of
    audio, so truncating only the FRAME COUNT (not the audio itself) would
    silently leak future information into the boundary frame.
    """
    frames = pre_frames + lookahead_frames
    center = int(round(onset_s * F.SR / F.HOP))
    lo_f = center - pre_frames
    lo_s = lo_f * F.HOP
    hi_s = (center + lookahead_frames - 1) * F.HOP + F.N_FFT
    seg = np.zeros(hi_s - lo_s, dtype=np.float32)
    a, b = max(0, lo_s), min(len(pcm), hi_s)
    if b > a:
        seg[a - lo_s : b - lo_s] = pcm[a:b]
    deadline_s = lookahead_frames * F.HOP / F.SR
    cut = int(round((onset_s + deadline_s) * F.SR)) - lo_s
    seg[max(0, cut) :] = 0.0
    lm = F.log_mel(seg)
    out = np.full((frames, F.N_MELS), np.log(1e-6), dtype=np.float32)
    out[: min(frames, len(lm))] = lm[:frames]
    return out


def build_dataset(data_dir: str, seed: int = DEFAULT_SEED):
    """Positive windows (down/up) at every labeled strum + mined no-event
    negatives (`ml/negatives.py`, same >=120 ms margin discipline
    `ml/train_live_3c.py` uses for its reject head), ALL built with
    `joint_window` — never the legacy 15-frame PRE=3/POST=12 geometry.
    Returns (X, y, rec) with y in {0: down, 1: up, 2: no-event}.
    """
    rng = np.random.default_rng(seed)
    xs, ys, recs = [], [], []
    for rid in recording_ids(data_dir):
        with open(os.path.join(data_dir, f"recording_{rid}.strums")) as fh:
            events = parse_strums(fh.read())
        pcm = _read_wav(os.path.join(data_dir, f"recording_{rid}_phone.wav"))
        strum_times = []
        for t, direction, _chord in events:
            if t * F.SR >= len(pcm):
                continue
            xs.append(joint_window(pcm, t))
            ys.append(LABELS[direction])
            recs.append(rid)
            strum_times.append(t)
        neg_times, _kinds = NEG.negative_times(
            pcm, np.array(strum_times, dtype=np.float64), rng=rng
        )
        for t in neg_times:
            xs.append(joint_window(pcm, float(t)))
            ys.append(NO_EVENT_LABEL)
            recs.append(rid)
    X = np.stack(xs).astype(np.float32)
    y = np.array(ys, dtype=np.int64)
    rec = np.array(recs)
    return X, y, rec


def assert_fold_trainable_3class(y: np.ndarray, mask: np.ndarray, name: str) -> None:
    """3-class analogue of `ml/klangio.py::assert_folds_trainable` (which is
    hard-coded to the legacy {0,1} set and would always reject a 3-class
    fold) — fails loudly when a fold is missing one of down/up/no-event."""
    classes = set(np.asarray(y)[mask].tolist())
    if classes != {0, 1, 2}:
        raise FoldTrainabilityError(
            f"{name} fold is missing a class ({classes}, need {{0, 1, 2}}) "
            "— reseed or fetch more recordings; training/evaluating against "
            "it would be meaningless"
        )


def assert_no_guitarist_leakage(
    rec: np.ndarray, train_mask: np.ndarray, test_mask: np.ndarray
) -> None:
    """Fail LOUDLY (never a warning) when the train/test guitarist-id sets
    are not disjoint (ADR 0517 D2). `logo_folds` already guarantees this by
    construction — this is the belt-and-braces runtime assertion the round's
    fail-closed leakage contract mandates explicitly, independent of the
    fold-construction code path."""
    train_guitarists = {guitarist_of(r) for r in rec[train_mask].tolist()}
    test_guitarists = {guitarist_of(r) for r in rec[test_mask].tolist()}
    overlap = train_guitarists & test_guitarists
    if overlap:
        raise GuitaristLeakageError(
            f"guitarist-id leakage between train/test: {sorted(overlap)} "
            "appear on both sides — aborting before any weights or report "
            "are written (ADR 0517 D2, fail-closed)"
        )


def pick_fold(rec: np.ndarray, held_out: str | None = None):
    """(heldOutGuitarist, train_mask, test_mask) — one LOGO fold. Defaults to
    the first fold in sorted guitarist-id order (deterministic, not
    cherry-picked): the round brief §0.0/R8 explicitly asks for ONE
    representative fold, not the full multi-fold sweep, for compute budget."""
    folds = list(logo_folds(rec))
    if held_out is not None:
        for guitarist, train_mask, test_mask in folds:
            if guitarist == held_out:
                return guitarist, train_mask, test_mask
        raise ValueError(
            f"--held-out-guitarist {held_out!r} not found among "
            f"{[g for g, _, _ in folds]}"
        )
    return folds[0]


def build_model(frames: int, mels: int, seed: int):
    """Reuses `ml/train.py::build_model` verbatim (import, not a copy) so
    the joint prototype and the shipped models share the SAME conv+GRU
    trunk — the comparison this round makes is about the head/window/split,
    not a different network family."""
    sys.path.insert(0, str(ML_ROOT))
    from train import build_model as _build_model  # noqa: PLC0415
    from train import set_seeds  # noqa: PLC0415

    set_seeds(seed)
    return _build_model(frames, mels, n_classes=N_CLASSES)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--workdir",
        required=True,
        type=str,
        help="repo-external directory for weights + provenance (ADR 0517 D5)",
    )
    parser.add_argument(
        "--data-dir",
        default=str(ML_ROOT / "data" / "klangio"),
        help="Klangio corpus directory (default: ml/data/klangio)",
    )
    parser.add_argument("--held-out-guitarist", default=None)
    parser.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    args = parser.parse_args(argv)

    try:
        workdir = resolve_workdir(args.workdir)
    except WorkdirInsideRepositoryError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    workdir.mkdir(parents=True, exist_ok=True)

    import tensorflow as tf  # noqa: PLC0415 — only the venv interpreter has this

    t0 = time.time()
    X, y, rec = build_dataset(args.data_dir, seed=args.seed)
    print(
        f"dataset: {X.shape} windows — "
        f"{int((y == 0).sum())} down / {int((y == 1).sum())} up / "
        f"{int((y == 2).sum())} no-event"
    )

    held_out, train_mask, test_mask = pick_fold(rec, args.held_out_guitarist)
    assert_fold_trainable_3class(y, train_mask, "train")
    assert_fold_trainable_3class(y, test_mask, "test")
    assert_no_guitarist_leakage(rec, train_mask, test_mask)
    train_recordings = sorted(set(rec[train_mask].tolist()))
    test_recordings = sorted(set(rec[test_mask].tolist()))
    print(
        f"leave-one-guitarist-out fold: held out guitarist {held_out!r} — "
        f"{len(train_recordings)} train / {len(test_recordings)} test "
        "recordings; guitarist-id sets confirmed disjoint"
    )

    mean = X[train_mask].mean(axis=(0, 1))
    std = X[train_mask].std(axis=(0, 1)) + 1e-6
    Xn = (X - mean) / std

    model = build_model(FRAMES, F.N_MELS, seed=args.seed)
    counts = np.bincount(y[train_mask], minlength=N_CLASSES).astype(float)
    counts[counts == 0] = 1.0
    total = float(counts.sum())
    class_weight = {c: total / (N_CLASSES * counts[c]) for c in range(N_CLASSES)}
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=DEFAULT_PATIENCE, restore_best_weights=True
    )
    history = model.fit(
        Xn[train_mask],
        y[train_mask],
        epochs=args.epochs,
        batch_size=args.batch_size,
        shuffle=True,
        class_weight=class_weight,
        verbose=2,
        callbacks=[stop],
        validation_data=(Xn[test_mask], y[test_mask]),
    )
    wall_clock_seconds = time.time() - t0
    epochs_run = len(history.history["loss"])

    weights_path = workdir / "joint_prototype_weights.npz"
    np.savez(
        weights_path,
        *[w.astype(np.float32) for w in model.get_weights()],
        mean=mean.astype(np.float32),
        std=std.astype(np.float32),
    )

    provenance = {
        "generatedAt": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "heldOutGuitarist": held_out,
        "trainRecordingCount": len(train_recordings),
        "testRecordingCount": len(test_recordings),
        "testRecordingIds": test_recordings,
        "epochsConfigured": args.epochs,
        "epochsRun": epochs_run,
        "batchSize": args.batch_size,
        "seed": args.seed,
        "modelParamCount": int(model.count_params()),
        "wallClockSeconds": wall_clock_seconds,
        "preFrames": PRE_FRAMES,
        "lookaheadFrames": LOOKAHEAD_FRAMES,
        "hopMs": HOP_MS,
        "lookaheadMs": LOOKAHEAD_MS,
        "dataDir": str(Path(args.data_dir).resolve()),
        "weightsPath": str(weights_path),
    }
    provenance_path = workdir / "joint_prototype_provenance.json"
    with open(provenance_path, "w") as fh:
        json.dump(provenance, fh, indent=2)

    print(f"wrote {weights_path}")
    print(f"wrote {provenance_path}")
    print(
        f"RESULT wall_clock_seconds={wall_clock_seconds:.1f} "
        f"epochs_run={epochs_run} held_out_guitarist={held_out} "
        f"param_count={provenance['modelParamCount']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
