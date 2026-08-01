"""Strict MiniMax credential loading without environment propagation."""

from __future__ import annotations

import json
import os
import stat
from pathlib import Path


class CredentialError(RuntimeError):
    pass


def read_minimax_api_key(path: Path, *, expected_uid: int | None = None) -> str:
    expected_uid = os.getuid() if expected_uid is None else expected_uid
    try:
        metadata = path.lstat()
    except OSError as error:
        raise CredentialError(f"credential file unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise CredentialError("credential must be a regular, non-symlink file")
    if metadata.st_uid != expected_uid:
        raise CredentialError("credential owner does not match the current user")
    permissions = stat.S_IMODE(metadata.st_mode)
    if permissions & ~0o600 or not permissions & stat.S_IRUSR:
        raise CredentialError("credential permissions must be owner-readable and at most 0600")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CredentialError("credential file is not valid private JSON") from error
    key = payload.get("api_key") if isinstance(payload, dict) else None
    if not isinstance(key, str) or not key.strip():
        raise CredentialError("credential JSON has no non-empty api_key")
    if "\n" in key or "\r" in key:
        raise CredentialError("credential api_key contains an invalid line break")
    return key.strip()
