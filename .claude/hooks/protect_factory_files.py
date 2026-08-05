#!/usr/bin/env python3
"""PreToolUse guard over the measure itself (ADR 0138).

`H-GATEGUARD` (ADR 0112 §"egyetlen emberi határ") says the one thing an
autonomous session may never do is weaken the measure that judges it: the gate
script, the CI workflows, the CI checkers, the router's security module and the
hook files themselves.  Until now that rule lived only in prose, and prose is
not an enforcement mechanism — the same lesson the legacy scope audit encodes
(docs/LESSONS.md, `tools/ai_router/git-guard/git`).

This hook turns it into a fail-closed check for every Claude-side session in
this repository: the round orchestrator, the self-heal session and interactive
work alike.  It runs on `Edit`/`Write`/`NotebookEdit` and — best effort — on
mutating `Bash` commands.

Deliberately NOT protected, because the pipeline legitimately writes them:
`docs/execution/pipeline-queue.tsv` (the orchestrator marks rounds done),
`.pipeline/**` (round status), `HANDOFF.md`, the RTM and the round docs.

Human-authorized governance work sets `STRUMSIGHT_GATE_EDIT_OK=1`, which is
recorded in the hook's stderr note so the escape is visible in the transcript
rather than silent.

Hook contract: exit 0 allows, exit 2 blocks and returns stderr to the model.
Any unexpected error also blocks — an unprovable guard is treated as a failed
guard, not as permission.
"""

from __future__ import annotations

import json
import os
import re
import sys
from fnmatch import fnmatch

# Az egyetlen dolog, amit egy önmagát mérő session nem írhat át: a MÉRCE.
PROTECTED_GLOBS = (
    # a futtatható mérce
    "tools/round-gate.sh",
    "tool/ci/*",
    ".github/workflows/*",
    ".github/actions/*",
    ".github/actions/*/*",
    # a router biztonsági rétege és konfigurációja
    "tools/ai_router/*",
    "tools/ai_router/*/*",
    "tools/model-router.py",
    "tools/scope-audit.py",
    "tools/round-scope-audit.sh",
    ".ai/router.toml",
    # séma-szerződések
    "schemas/*",
    # maga az őr
    ".claude/hooks/*",
    ".claude/settings.json",
)

# Titkok: olvasásuk és írásuk is tilos, függetlenül a mércétől.
SECRET_GLOBS = (
    ".env",
    ".env.*",
    "secrets/*",
    "secrets/*/*",
    "*.jks",
    "*.p12",
    "*.keystore",
)

MUTATING_BASH = re.compile(
    r"(>>?\s|\bsed\s+-i\b|\brm\b|\bmv\b|\bcp\b|\btee\b|\btruncate\b|\bchmod\b|\bdd\b|\bpatch\b)"
)

ESCAPE_VARIABLE = "STRUMSIGHT_GATE_EDIT_OK"


def _relative(path: str) -> str:
    """Repository-relative, forward-slash form of a tool-supplied path."""
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    normalized = os.path.normpath(path)
    if project:
        project = os.path.normpath(project)
        if normalized == project:
            return ""
        if normalized.startswith(project + os.sep):
            normalized = normalized[len(project) + 1 :]
    normalized = normalized.replace(os.sep, "/")
    # NEM `lstrip("./")`: az karakterhalmazt vág, tehát a `.claude/...` és a
    # `.env` elejéről is levinné a pontot, és a védett minta sosem illeszkedne.
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def _matches(path: str, globs: tuple[str, ...]) -> str | None:
    for pattern in globs:
        if fnmatch(path, pattern) or fnmatch(os.path.basename(path), pattern):
            return pattern
    return None


def _paths_from_input(tool_name: str, tool_input: dict) -> list[str]:
    if tool_name in ("Edit", "Write", "NotebookEdit"):
        candidate = tool_input.get("file_path") or tool_input.get("notebook_path")
        return [candidate] if isinstance(candidate, str) else []
    if tool_name == "Bash":
        command = tool_input.get("command")
        if not isinstance(command, str) or not MUTATING_BASH.search(command):
            return []
        # Best effort: csak akkor blokkolunk, ha a parancs EGYÜTT tartalmaz
        # mutáló műveletet és védett útvonalat. A hiteles, auditált őr a
        # scope-audit; ez a réteg a nyilvánvaló megkerülést fogja meg.
        return re.findall(r"[A-Za-z0-9_./-]+", command)
    return []


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("protect_factory_files: unreadable hook payload — blokkolva", file=sys.stderr)
        return 2

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0

    escaped = os.environ.get(ESCAPE_VARIABLE) == "1"

    for raw in _paths_from_input(tool_name, tool_input):
        if not isinstance(raw, str) or not raw:
            continue
        path = _relative(raw)
        if not path:
            continue

        if pattern := _matches(path, SECRET_GLOBS):
            print(
                f"protect_factory_files: TILTOTT titok-útvonal ({pattern}): {path}. "
                "Secret nem kerülhet sessionbe, logba vagy commitba (AGENTS.md §5).",
                file=sys.stderr,
            )
            return 2

        if pattern := _matches(path, PROTECTED_GLOBS):
            if escaped:
                print(
                    f"protect_factory_files: {path} VÉDETT ({pattern}), de "
                    f"{ESCAPE_VARIABLE}=1 — emberi engedéllyel átengedve.",
                    file=sys.stderr,
                )
                continue
            print(
                f"protect_factory_files: BLOKKOLVA — {path} a MÉRCE része ({pattern}).\n"
                "A mércét nem javíthatja az, akit mér (H-GATEGUARD, ADR 0112/0138).\n"
                "Ha a kör tényleg ezt kívánja: ÁLLJ MEG és jelezz "
                "(`tools/codex-signal.sh stopped`), az ember dönt. "
                f"Emberi engedéllyel: {ESCAPE_VARIABLE}=1.",
                file=sys.stderr,
            )
            return 2

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # fail-closed: a bizonyíthatatlan őr = bukott őr
        print(f"protect_factory_files: hiba ({error}) — blokkolva", file=sys.stderr)
        sys.exit(2)
