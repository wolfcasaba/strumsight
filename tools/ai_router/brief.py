"""Strict parser for the versioned ai-router block in round briefs."""

from __future__ import annotations

import hashlib
import json
import re
import tomllib
from pathlib import Path, PurePosixPath

from .models import BriefMetadata, TaskBrief


class BriefMetadataError(ValueError):
    pass


BLOCK = re.compile(r"^```ai-router[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL)
TASK_ID = re.compile(r"(?i)(e\d{2}-r\d{2})")
METADATA_KEYS = {"schema_version", "risk", "allowed_paths", "gate_tests", "native_gate"}
SAFE_GATE = re.compile(r"^test/[A-Za-z0-9_.\-/]+$")
SAFE_PATH = re.compile(r"^[A-Za-z0-9_.\-/]+$")


def _paths(value: object, *, gate: bool) -> tuple[str, ...]:
    label = "gate_tests" if gate else "allowed_paths"
    if not isinstance(value, list) or not value:
        raise BriefMetadataError(f"{label} must be a non-empty array")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item or "\\" in item or "\x00" in item:
            raise BriefMetadataError(f"{label} contains an invalid path")
        parsed = PurePosixPath(item)
        if parsed.is_absolute() or any(part in ("", ".", "..") for part in parsed.parts):
            raise BriefMetadataError(f"{label} paths must be normalized and repository-relative")
        if not SAFE_PATH.fullmatch(item):
            raise BriefMetadataError(f"{label} contains an unsafe path")
        if gate and not SAFE_GATE.fullmatch(item):
            raise BriefMetadataError("gate_tests accepts only safe test/ paths")
        result.append(item)
    if len(set(result)) != len(result):
        raise BriefMetadataError(f"{label} must not contain duplicates")
    return tuple(result)


def parse_brief_metadata(text: str) -> TaskBrief:
    blocks = BLOCK.findall(text)
    if len(blocks) != 1:
        raise BriefMetadataError("brief must contain exactly one ai-router block")
    try:
        raw = tomllib.loads(blocks[0])
    except tomllib.TOMLDecodeError as error:
        raise BriefMetadataError("ai-router block is invalid TOML") from error
    unknown = set(raw) - METADATA_KEYS
    missing = METADATA_KEYS - set(raw)
    if unknown:
        raise BriefMetadataError(f"unknown metadata key(s): {', '.join(sorted(unknown))}")
    if missing:
        raise BriefMetadataError(f"missing metadata key(s): {', '.join(sorted(missing))}")
    if raw["schema_version"] != 1 or isinstance(raw["schema_version"], bool):
        raise BriefMetadataError("unsupported metadata schema_version")
    if raw["risk"] not in ("normal", "high"):
        raise BriefMetadataError("risk must be normal or high")
    if not isinstance(raw["native_gate"], bool):
        raise BriefMetadataError("native_gate must be boolean")
    metadata = BriefMetadata(
        schema_version=1,
        risk=raw["risk"],
        allowed_paths=_paths(raw["allowed_paths"], gate=False),
        gate_tests=_paths(raw["gate_tests"], gate=True),
        native_gate=raw["native_gate"],
    )
    canonical = json.dumps(
        {
            "schema_version": metadata.schema_version,
            "risk": metadata.risk,
            "allowed_paths": metadata.allowed_paths,
            "gate_tests": metadata.gate_tests,
            "native_gate": metadata.native_gate,
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return TaskBrief(
        task_id="INLINE",
        path=None,
        text=text,
        metadata=metadata,
        metadata_hash="sha256:" + hashlib.sha256(canonical).hexdigest(),
    )


def load_brief(path: Path) -> TaskBrief:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise BriefMetadataError(f"brief is unreadable: {path}") from error
    parsed = parse_brief_metadata(text)
    match = TASK_ID.search(path.name)
    if not match:
        raise BriefMetadataError("brief filename has no E##-R## task id")
    return TaskBrief(
        task_id=match.group(1).upper(),
        path=path,
        text=text,
        metadata=parsed.metadata,
        metadata_hash=parsed.metadata_hash,
    )


def load_brief_metadata(path: Path) -> BriefMetadata:
    return load_brief(path).metadata
