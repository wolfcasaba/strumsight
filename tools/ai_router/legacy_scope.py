"""Scope audit for the legacy implementer path (ADR 0138).

The `engine=auto` router audits every model diff against the brief's
`allowed_paths` (`security.audit_scope`).  The legacy `engine=codex|minimax`
wrappers had no equivalent: the only scope control was the prompt text plus the
orchestrator's later review.  Prompt text is not an enforcement mechanism — the
measured case is MiniMax-M3 committing `d0546f0` in `ss-router-e03-r05-2`
against an explicit prompt ban, which only the router's audit caught
(`tools/ai_router/git-guard/git` header, docs/LESSONS.md).  Every Epic 4 round
runs on the legacy path, and every Epic 4 brief already carries a machine
readable `allowed_paths` block, so the data for the check existed while the
check did not.

Matching semantics are deliberately shared with `security.audit_scope` (same
`_matches`, same generated/ignored exemptions) so "outside scope" means the
same thing on both paths.  Two differences are intentional:

* The legacy protocol REQUIRES the implementer to commit to its round branch
  (AGENTS.md §15.2), so a moved HEAD is not a violation here.  The audit
  compares the full `base..worktree` delta — committed *and* uncommitted.
* `base` is the work copy's HEAD at launch time, not `origin/main`.  The
  orchestrator's pre-flight commit (round ADR + brief revision) legitimately
  touches paths outside `allowed_paths`; auditing from the launch commit scopes
  the verdict to the implementer's own work.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from .security import (
    GENERATED_IGNORED_PREFIXES,
    SecurityError,
    _git,
    _has_symlink_component,
    _is_generated_ignored,
    _matches,
    _paths,
)

__all__ = ["LegacyScopeAudit", "audit_legacy_scope", "collect_changed_paths"]


@dataclass(frozen=True)
class LegacyScopeAudit:
    """Verdict over one legacy implementer run."""

    ok: bool
    base: str
    head: str
    changed_paths: tuple[str, ...]
    violations: tuple[str, ...]
    exempt_paths: tuple[str, ...]

    def format(self) -> str:
        """Human-readable report containing paths only, never file contents."""
        header = (
            f"Legacy scope audit {'OK' if self.ok else 'FAILED'} "
            f"({self.base[:12]}..{self.head[:12]}, "
            f"{len(self.changed_paths)} changed path(s), "
            f"{len(self.exempt_paths)} generated/ignored)"
        )
        if self.ok:
            return header
        lines = [header]
        for violation in self.violations:
            lines.append(f"- {violation}")
        return "\n".join(lines)


def collect_changed_paths(repo: Path, base: str) -> tuple[str, ...]:
    """Every path the implementer touched since `base`, committed or not.

    `git diff <base>` compares the *working tree* against `base`, so a single
    call covers both the branch commits and any leftover uncommitted edit.
    Untracked files are added separately because `git diff` cannot see them.
    """
    tracked = _paths(_git(repo, ["diff", "--name-only", "-z", base, "--"]))
    untracked = _paths(_git(repo, ["ls-files", "--others", "--exclude-standard", "-z"]))
    return tuple(sorted(tracked | untracked))


def audit_legacy_scope(
    repo: Path,
    *,
    base: str,
    allowed_paths: Sequence[str],
    protected_paths: Sequence[str],
    ignored_allow_paths: Sequence[str] = GENERATED_IGNORED_PREFIXES,
) -> LegacyScopeAudit:
    """Audit a legacy work copy against its brief's allowed paths.

    A path is a violation when it is protected, outside `allowed_paths`, or
    reachable only through a symlink component.  Generated/ignored artefacts
    (build caches, the round signal file, the reviewer's report) are exempt for
    the same measured reasons as on the router path.
    """
    if not allowed_paths:
        raise SecurityError("allowed_paths must not be empty")
    head = _git(repo, ["rev-parse", "HEAD"]).decode().strip()
    changed = collect_changed_paths(repo, base)

    violations: list[str] = []
    exempt: list[str] = []
    for path in changed:
        if _is_generated_ignored(path, ignored_allow_paths):
            exempt.append(path)
            continue
        if _matches(path, protected_paths):
            violations.append(f"protected path changed: {path}")
        elif not _matches(path, allowed_paths):
            violations.append(f"path outside allowed scope: {path}")
        if _has_symlink_component(repo, path):
            violations.append(f"symlink path is not allowed: {path}")

    return LegacyScopeAudit(
        ok=not violations,
        base=base,
        head=head,
        changed_paths=changed,
        violations=tuple(violations),
        exempt_paths=tuple(exempt),
    )
