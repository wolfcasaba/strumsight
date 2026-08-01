"""Secret redaction and complete Git workspace scope auditing."""

from __future__ import annotations

import hashlib
import os
import re
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Sequence


class SecurityError(RuntimeError):
    pass


GENERATED_IGNORED_PREFIXES = (
    ".dart_tool",
    "build",
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
    ".ai/runs",
)


@dataclass(frozen=True)
class WorkspaceManifest:
    baseline_head: str
    untracked_paths: frozenset[str]
    ignored_paths: frozenset[str]
    tracked_paths: frozenset[str] = frozenset()


@dataclass(frozen=True)
class ScopeAudit:
    ok: bool
    changed_paths: tuple[str, ...]
    violations: tuple[str, ...]
    high_risk: bool
    diff_hash: str


def redact_text(text: str, *, secret_values: Iterable[str] = ()) -> str:
    redacted = text
    for secret in sorted((value for value in secret_values if value), key=len, reverse=True):
        redacted = redacted.replace(secret, "[REDACTED]")
    redacted = re.sub(
        r"(?i)(Authorization\s*:\s*Bearer\s+)[^\s]+", r"\1[REDACTED]", redacted
    )
    redacted = re.sub(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [REDACTED]", redacted)
    redacted = re.sub(
        r"(?i)\b(MINIMAX_API_KEY|OPENAI_API_KEY|CODEX_API_KEY|API_KEY|TOKEN)\s*=\s*[^\s]+",
        r"\1=[REDACTED]",
        redacted,
    )
    redacted = re.sub(
        r"(?i)([?&](?:token|api_key|key)=)[^&#\s]+", r"\1[REDACTED]", redacted
    )
    redacted = re.sub(r"\bsk-[A-Za-z0-9_-]{20,}\b", "[REDACTED]", redacted)
    return redacted


def _git(repo: Path, arguments: Sequence[str]) -> bytes:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise SecurityError(f"git {' '.join(arguments[:2])} failed")
    return completed.stdout


def _paths(output: bytes) -> frozenset[str]:
    return frozenset(part.decode("utf-8", errors="strict") for part in output.split(b"\0") if part)


def capture_workspace_manifest(repo: Path) -> WorkspaceManifest:
    head = _git(repo, ["rev-parse", "HEAD"]).decode().strip()
    return WorkspaceManifest(
        baseline_head=head,
        untracked_paths=_paths(_git(repo, ["ls-files", "--others", "--exclude-standard", "-z"])),
        ignored_paths=_paths(
            _git(repo, ["ls-files", "--others", "--ignored", "--exclude-standard", "-z"])
        ),
        tracked_paths=_paths(_git(repo, ["diff", "--name-only", "-z", "HEAD", "--"])),
    )


def _matches(path: str, prefixes: Sequence[str]) -> bool:
    return any(path == prefix.rstrip("/") or path.startswith(prefix.rstrip("/") + "/") for prefix in prefixes)


def _is_generated_ignored(path: str, prefixes: Sequence[str]) -> bool:
    parts = PurePosixPath(path).parts
    return (
        _matches(path, prefixes)
        or "__pycache__" in parts
        or path.endswith(".pyc")
    )


def validate_baseline_manifest(
    manifest: WorkspaceManifest,
    *,
    ignored_allow_paths: Sequence[str] = GENERATED_IGNORED_PREFIXES,
) -> tuple[str, ...]:
    violations: list[str] = []
    if manifest.tracked_paths:
        violations.append(
            "baseline has tracked changes: " + ", ".join(sorted(manifest.tracked_paths)[:20])
        )
    if manifest.untracked_paths:
        violations.append(
            "baseline has untracked files: " + ", ".join(sorted(manifest.untracked_paths)[:20])
        )
    unsafe_ignored = sorted(
        path
        for path in manifest.ignored_paths
        if not _is_generated_ignored(path, ignored_allow_paths)
    )
    if unsafe_ignored:
        violations.append(
            "baseline has unsafe ignored files: " + ", ".join(unsafe_ignored[:20])
        )
    return tuple(violations)


def _has_symlink_component(repo: Path, relative: str) -> bool:
    current = repo
    for part in PurePosixPath(relative).parts:
        current = current / part
        try:
            if stat.S_ISLNK(current.lstat().st_mode):
                return True
        except FileNotFoundError:
            return False
    return False


def audit_scope(
    repo: Path,
    *,
    allowed_paths: Sequence[str],
    protected_paths: Sequence[str],
    baseline: WorkspaceManifest,
    ignored_allow_paths: Sequence[str] = GENERATED_IGNORED_PREFIXES,
    high_risk_fragments: Sequence[str] = (
        "auth",
        "credential",
        "crypto",
        "migration",
        "payment",
        "secret",
    ),
) -> ScopeAudit:
    tracked = _paths(_git(repo, ["diff", "--name-only", "-z", baseline.baseline_head, "--"]))
    untracked_now = _paths(_git(repo, ["ls-files", "--others", "--exclude-standard", "-z"]))
    ignored_now = _paths(
        _git(repo, ["ls-files", "--others", "--ignored", "--exclude-standard", "-z"])
    )
    new_untracked = untracked_now - baseline.untracked_paths
    new_ignored = ignored_now - baseline.ignored_paths
    changed = set(tracked) | set(new_untracked) | set(new_ignored)
    violations: list[str] = []
    current_head = _git(repo, ["rev-parse", "HEAD"]).decode().strip()
    if current_head != baseline.baseline_head:
        violations.append("model-created commit is not allowed: HEAD changed from baseline")
    for path in sorted(changed):
        is_ignored_generated = path in new_ignored and _is_generated_ignored(
            path, ignored_allow_paths
        )
        if is_ignored_generated:
            continue
        if _matches(path, protected_paths):
            violations.append(f"protected path changed: {path}")
        elif not _matches(path, allowed_paths):
            violations.append(f"path outside allowed scope: {path}")
        if _has_symlink_component(repo, path):
            violations.append(f"symlink path is not allowed: {path}")
    digest = hashlib.sha256()
    digest.update(_git(repo, ["diff", "--binary", baseline.baseline_head, "--"]))
    for path in sorted(new_untracked | new_ignored):
        digest.update(path.encode())
        candidate = repo / path
        if candidate.is_file() and not candidate.is_symlink():
            try:
                with candidate.open("rb") as handle:
                    digest.update(handle.read(1_048_576))
            except OSError:
                digest.update(b"<unreadable>")
    high_risk = any(
        fragment.lower() in path.lower()
        for path in changed
        for fragment in high_risk_fragments
    )
    return ScopeAudit(
        ok=not violations,
        changed_paths=tuple(sorted(changed)),
        violations=tuple(violations),
        high_risk=high_risk,
        diff_hash="sha256:" + digest.hexdigest(),
    )
