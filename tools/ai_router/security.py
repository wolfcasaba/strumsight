"""Secret redaction and complete Git workspace scope auditing."""

from __future__ import annotations

import hashlib
import os
import re
import stat
import subprocess
from dataclasses import dataclass
from fnmatch import fnmatch
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
    # A Flutter SAJÁT, gitignore-olt, de KÖTELEZŐ generált artefaktumai. A
    # `flutter pub get` / `flutter gen-l10n` minden friss klónban és minden
    # worktree-ben létrehozza őket (a HANDOFF.md dokumentált klón-csapdája:
    # nélkülük az analyze/test el sem indul). Ha a baseline-őr ezeket
    # "unsafe ignored"-nak veszi, EGYETLEN Flutter kör sem megy át a
    # precheck-en — mérve 2026-08-01, E02-R21 (H6 halt).
    "android/local.properties",
    "ios/Flutter/Generated.xcconfig",
    "ios/Flutter/flutter_export_environment.sh",
    "ios/Flutter/ephemeral",
    "macos/Flutter/ephemeral",
    "macos/Flutter/Flutter-Generated.xcconfig",
    "linux/flutter/ephemeral",
    "windows/flutter/ephemeral",
    # A router SAJÁT jelzőfájlja (tools/codex-signal.sh írja, NEM az M3
    # modell) és a reviewer/orchestrátor dokumentált review-artefaktuma
    # (docs/execution/02-codex-playbook.md §13, 09-review-report.md) — ezeket
    # a `resume` munkafolyamat MINDIG a munkapéldányba írja a leletekkel
    # együtt, tehát scope-sértésként kezelésük önmagával ütközteti a
    # dokumentált folyamatot. Mérve 2026-08-01, E02-R21 (H6 halt, 3. eset).
    ".codex-round-status",
    "docs/reviews",
)

# Ugyanaz a kategória, de a fájlnév változó része miatt mintával fogható:
# a lokalizáció nyelvenként külön fájlt generál (app_localizations_hu.dart),
# a plugin-registrant pedig platformonként más kiterjesztést kap.
GENERATED_IGNORED_GLOBS = (
    "lib/l10n/app_localizations*.dart",
    "GeneratedPluginRegistrant.*",
    "*/GeneratedPluginRegistrant.*",
    # A resume-hoz átadott review-findings fájl neve a hívó választása
    # (orchestrátor-prompt §1.1 "<review-findings.md>"), de mindig ezzel a
    # `.ai/`-alatti előtaggal íródik — lásd a fenti .codex-round-status
    # megjegyzést.
    ".ai/review-findings-*.md",
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
    # A "történt-e valódi munka" jelzésre szánt, generált/ignorált (pl.
    # .dart_tool/build build-cache churn, a router saját jelzőfájlja, a
    # reviewer docs/reviews artefaktuma) útvonalaktól MEGTISZTÍTOTT halmaz —
    # lásd L38 (docs/LESSONS.md): a violation-check és a "volt-e diff" check
    # korábban ugyanazt a changed_paths halmazt használta, ezért a
    # BASELINE_GATE saját melléktermékét "M3 diffnek" nézte. `None` esetén
    # (pl. kézzel írt ScopeAudit teszt-fixture-ökben) megegyezik
    # changed_paths-szal.
    scoped_changed_paths: tuple[str, ...] | None = None

    def __post_init__(self) -> None:
        if self.scoped_changed_paths is None:
            object.__setattr__(self, "scoped_changed_paths", self.changed_paths)


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


def _is_generated_ignored(
    path: str,
    prefixes: Sequence[str],
    globs: Sequence[str] = GENERATED_IGNORED_GLOBS,
) -> bool:
    parts = PurePosixPath(path).parts
    return (
        _matches(path, prefixes)
        or any(fnmatch(path, pattern) for pattern in globs)
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
    generated_ignored: set[str] = set()
    current_head = _git(repo, ["rev-parse", "HEAD"]).decode().strip()
    if current_head != baseline.baseline_head:
        violations.append("model-created commit is not allowed: HEAD changed from baseline")
    for path in sorted(changed):
        # Korábban csak az ÚJONNAN ignorált útvonalakra (new_ignored) állt
        # fenn ez a mentesség — egy MÁR TRACKELT fájl (pl. az orchestrátor
        # docs/reviews/<kör>.md review-jelentésének módosítása) így SOHA nem
        # kaphatott mentességet, függetlenül a GENERATED_IGNORED_PREFIXES
        # tartalmától. A kategória (tracked/untracked/ignored) itt nem a
        # bizalmi döntés alapja — a `_is_generated_ignored` minta az. Mérve
        # 2026-08-01, E02-R21 (H6 halt, 3. eset, L38).
        is_ignored_generated = _is_generated_ignored(path, ignored_allow_paths)
        if is_ignored_generated:
            generated_ignored.add(path)
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
        scoped_changed_paths=tuple(sorted(changed - generated_ignored)),
    )
