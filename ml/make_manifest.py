#!/usr/bin/env python3
"""Generate the shipping ML asset manifest from the checked-in binaries.

Checksums are always measured from the files. Existing ``created_at`` values
are retained while a checksum is unchanged, so rerunning this script is
idempotent and metadata-only edits do not rewrite an asset's creation time.
"""

from __future__ import annotations

import hashlib
import json
import struct
from datetime import datetime, timezone
from math import prod
from pathlib import Path
from typing import BinaryIO

REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPO_ROOT / "assets" / "ml" / "model_manifest.json"

_PITCH_CLASSES = (
    "C",
    "C#",
    "D",
    "D#",
    "E",
    "F",
    "F#",
    "G",
    "G#",
    "A",
    "A#",
    "B",
)
_CHORD_CLASSES = ("N.C.", *_PITCH_CLASSES, *(f"{name}m" for name in _PITCH_CLASSES))

_MODEL_SPECS = (
    {
        "path": "assets/ml/chord_crnn.bin",
        "input_frames": 100,
        "output_array": "dense2_b",
        "output_classes": _CHORD_CLASSES,
        "format": "CCRN",
        "export_script": {
            "path": "ml/chords/export_chord_dart.py",
            "version": "git:ea2bc103edc515cfa9ddc75096e2ded3f5b013b4",
        },
        "training_run": {
            "origin": "repository-history",
            "identifier": "git:9150dbc9765b4390617a13ecd807f7b3461cc11f",
        },
        "initial_created_at": "2026-07-15T06:58:37Z",
    },
    {
        "path": "assets/ml/strum_crnn.bin",
        "input_frames": 15,
        "output_array": "dense_b",
        "output_classes": ("down", "up"),
        "format": "SSML",
        "export_script": {
            "path": "ml/export_dart_weights.py",
            "version": "git:66c0f9a2e60f2e386e0d62de38a46fc0b11b96a2",
        },
        "training_run": {
            "origin": "repository-history",
            "identifier": "git:66c0f9a2e60f2e386e0d62de38a46fc0b11b96a2",
        },
        "initial_created_at": "2026-07-13T09:13:39Z",
    },
    {
        "path": "assets/ml/strum_crnn_live.bin",
        "input_frames": 15,
        "output_array": "dense_b",
        "output_classes": ("down", "up"),
        "format": "SSML",
        "export_script": {
            "path": "ml/export_live_weights.py",
            "version": "git:cb325a2b698fffc124cfb5875f5eed055b9dd124",
        },
        "training_run": {
            "origin": "repository-history",
            "identifier": "git:cb325a2b698fffc124cfb5875f5eed055b9dd124",
        },
        "initial_created_at": "2026-07-13T11:34:32Z",
    },
    {
        "path": "assets/ml/strum_crnn_live_3c.bin",
        "input_frames": 15,
        "output_array": "dense_b",
        "output_classes": ("down", "up", "no-strum"),
        "format": "SSML",
        "export_script": {
            "path": "ml/train_live_3c.py",
            "version": "git:f9293d6ab0693d9d56aeca4898cb229afe7392ea",
        },
        "training_run": {
            "origin": "repository-history",
            "identifier": "git:f9293d6ab0693d9d56aeca4898cb229afe7392ea",
        },
        "initial_created_at": "2026-07-14T00:38:31Z",
    },
)


def _read_exact(stream: BinaryIO, size: int, *, context: str) -> bytes:
    data = stream.read(size)
    if len(data) != size:
        raise ValueError(f"truncated model binary while reading {context}")
    return data


def _read_u32(stream: BinaryIO, *, context: str) -> int:
    return struct.unpack("<I", _read_exact(stream, 4, context=context))[0]


def _read_binary_metadata(path: Path) -> tuple[str, int, dict[str, tuple[int, ...]]]:
    file_size = path.stat().st_size
    with path.open("rb") as stream:
        try:
            model_format = _read_exact(stream, 4, context="format magic").decode(
                "ascii"
            )
        except UnicodeDecodeError as error:
            raise ValueError(f"{path}: format magic is not ASCII") from error
        format_version = _read_u32(stream, context="format version")
        array_count = _read_u32(stream, context="array count")
        if array_count > 1_000:
            raise ValueError(f"{path}: implausible array count {array_count}")

        arrays: dict[str, tuple[int, ...]] = {}
        for index in range(array_count):
            name_length = _read_u32(stream, context=f"array {index} name length")
            try:
                name = _read_exact(
                    stream,
                    name_length,
                    context=f"array {index} name",
                ).decode("utf-8")
            except UnicodeDecodeError as error:
                raise ValueError(f"{path}: array {index} name is not UTF-8") from error
            dimensions = _read_u32(stream, context=f"{name} dimension count")
            if dimensions > 16:
                raise ValueError(f"{path}: {name} has {dimensions} dimensions")
            shape = tuple(
                _read_u32(stream, context=f"{name} dimension {dimension}")
                for dimension in range(dimensions)
            )
            if not shape or any(value == 0 for value in shape):
                raise ValueError(f"{path}: {name} has invalid shape {shape}")
            if name in arrays:
                raise ValueError(f"{path}: duplicate array {name}")
            arrays[name] = shape

            byte_count = prod(shape) * 4
            if stream.tell() + byte_count > file_size:
                raise ValueError(f"{path}: truncated float data for {name}")
            stream.seek(byte_count, 1)

        if stream.tell() != file_size:
            raise ValueError(
                f"{path}: parsed {stream.tell()} of {file_size} bytes "
                "(unexpected trailing data)"
            )
    return model_format, format_version, arrays


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_previous_entries() -> dict[str, dict[str, object]]:
    if not MANIFEST_PATH.exists():
        return {}
    try:
        document = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read existing manifest: {error}") from error
    models = document.get("models")
    if not isinstance(models, list):
        raise ValueError("existing manifest must contain a models list")
    return {
        entry["path"]: entry
        for entry in models
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }


# E05-R12 — vision model manifest sibling key. The model asset is
# `status = "deferred"` in this round (ADR 0185 §Döntés 2): the spec
# tuple is the single source of truth, and there is no real binary on
# disk — the `sha256` is a documented placeholder (64 lowercase zeros)
# so the validator's `sha256 must be 64 lowercase hex characters`
# format branch has a stable value to exercise. The activation round
# replaces this with a real entry whose `status == "active"` and whose
# `sha256` is the measured hash of the shipped binary.
_DEFERRED_SHA256_PLACEHOLDER = "0" * 64
_VISION_MODEL_SPECS: tuple[dict[str, object], ...] = (
    {
        "model_id": "hand_landmarker",
        "version": "1.0.0",
        "path": "assets/ml/hand_landmarker_deferred.tflite",
        "status": "deferred",
        # No real asset in this round — placeholder, the activation
        # round swaps this for a measured hash.
        "sha256": _DEFERRED_SHA256_PLACEHOLDER,
        "input_shape": [256, 256, 3],
        "output_schema": "strumsight.hand_landmarks.v1",
        "license": {"spdx": "Apache-2.0", "name": "MediaPipe Hands"},
        "minimum_device_tier": "basic",
        "evaluation_report": "docs/eval/vision/hand_landmarker.md",
    },
    # E05-R14 — additive pose entry (ADR 0186 §Döntés 2). Same deferred
    # posture as the hand entry: no binary on disk, documented placeholder
    # sha256, and its OWN output_schema — reusing the hand schema would be
    # false manifest metadata.
    {
        "model_id": "pose_landmarker",
        "version": "1.0.0",
        "path": "assets/ml/pose_landmarker_deferred.tflite",
        "status": "deferred",
        "sha256": _DEFERRED_SHA256_PLACEHOLDER,
        "input_shape": [256, 256, 3],
        "output_schema": "strumsight.pose_landmarks.v1",
        "license": {"spdx": "Apache-2.0", "name": "MediaPipe Pose"},
        "minimum_device_tier": "basic",
        "evaluation_report": "docs/eval/vision/pose_landmarker.md",
    },
)


def _utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _build_entry(
    spec: dict[str, object],
    previous: dict[str, object] | None,
    *,
    changed_at: str,
) -> dict[str, object]:
    relative_path = str(spec["path"])
    asset_path = REPO_ROOT / relative_path
    if not asset_path.is_file():
        raise FileNotFoundError(f"missing model asset: {relative_path}")

    checksum = _sha256(asset_path)
    model_format, format_version, arrays = _read_binary_metadata(asset_path)
    expected_format = str(spec["format"])
    if model_format != expected_format:
        raise ValueError(
            f"{relative_path}: format {model_format!r}, expected {expected_format!r}"
        )

    mean_shape = arrays.get("mean")
    if mean_shape is None or len(mean_shape) != 1:
        raise ValueError(f"{relative_path}: missing one-dimensional mean array")
    output_array = str(spec["output_array"])
    output_shape = arrays.get(output_array)
    if output_shape is None or len(output_shape) != 1:
        raise ValueError(
            f"{relative_path}: missing one-dimensional {output_array} array"
        )
    output_classes = tuple(str(value) for value in spec["output_classes"])
    if output_shape[0] != len(output_classes):
        raise ValueError(
            f"{relative_path}: binary exposes {output_shape[0]} classes, "
            f"metadata names {len(output_classes)}"
        )

    created_at = str(spec["initial_created_at"])
    if previous is not None:
        previous_checksum = previous.get("sha256")
        previous_created_at = previous.get("created_at")
        if previous_checksum == checksum and isinstance(previous_created_at, str):
            created_at = previous_created_at
        elif previous_checksum != checksum:
            created_at = changed_at

    return {
        "filename": asset_path.name,
        "path": relative_path,
        "sha256": checksum,
        "format": model_format,
        "format_version": format_version,
        "input_shape": [int(spec["input_frames"]), mean_shape[0]],
        "output_classes": list(output_classes),
        "training_run": dict(spec["training_run"]),
        "export_script": dict(spec["export_script"]),
        "created_at": created_at,
    }


def _build_vision_models(
    previous: dict[str, dict[str, object]],
) -> list[dict[str, object]]:
    """Build the `vision_models` sibling key.

    E05-R12 §0.0 R3: isolated from the audio ``models[]`` path. Only
    ``status == "active"`` specs consult the disk — for them the
    generator measures the SHA-256 of the shipped asset and fails
    fast if the file is missing. ``status == "deferred"`` specs (ADR
    0185 §Döntés 2 — no real binary this round) emit the spec's
    documented placeholder sha256 without touching the filesystem, so
    rerunning the generator never produces a FileNotFoundError for an
    asset that is intentionally not shipped.
    """
    entries: list[dict[str, object]] = []
    for spec in _VISION_MODEL_SPECS:
        relative_path = str(spec["path"])
        status = str(spec["status"])
        if status == "active":
            asset_path = REPO_ROOT / relative_path
            if not asset_path.is_file():
                raise FileNotFoundError(f"missing vision model asset: {relative_path}")
            checksum = _sha256(asset_path)
        else:
            # Deferred: spec carries the placeholder sha256 directly
            # (ADR 0185 §Döntés 2 — no real binary this round).
            checksum = str(spec["sha256"])
        entries.append(
            {
                "model_id": str(spec["model_id"]),
                "version": str(spec["version"]),
                "path": relative_path,
                "sha256": checksum,
                "status": status,
                "input_shape": [int(v) for v in spec["input_shape"]],
                "output_schema": str(spec["output_schema"]),
                "license": dict(spec["license"]),
                "minimum_device_tier": str(spec["minimum_device_tier"]),
                "evaluation_report": str(spec["evaluation_report"]),
            }
        )
    return entries


def _load_previous_vision_entries() -> dict[str, dict[str, object]]:
    if not MANIFEST_PATH.exists():
        return {}
    try:
        document = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read existing manifest: {error}") from error
    vision_models = document.get("vision_models")
    if not isinstance(vision_models, list):
        return {}
    return {
        str(entry["path"]): entry
        for entry in vision_models
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }


def main() -> None:
    previous_entries = _load_previous_entries()
    previous_vision_entries = _load_previous_vision_entries()
    changed_at = _utc_now()
    models = [
        _build_entry(
            spec,
            previous_entries.get(str(spec["path"])),
            changed_at=changed_at,
        )
        for spec in _MODEL_SPECS
    ]
    vision_models = _build_vision_models(previous_vision_entries)
    document = {
        "schema_version": 1,
        "models": models,
        "vision_models": vision_models,
    }
    rendered = json.dumps(document, indent=2, ensure_ascii=False) + "\n"

    relative_manifest = MANIFEST_PATH.relative_to(REPO_ROOT)
    if MANIFEST_PATH.exists() and MANIFEST_PATH.read_text(encoding="utf-8") == rendered:
        print(
            f"unchanged {relative_manifest} "
            f"({len(models)} models, {len(vision_models)} vision models)"
        )
        return
    MANIFEST_PATH.write_text(rendered, encoding="utf-8")
    print(
        f"wrote {relative_manifest} "
        f"({len(models)} models, {len(vision_models)} vision models)"
    )


if __name__ == "__main__":
    main()
