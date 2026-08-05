#!/usr/bin/env python3
"""PreToolUse guard over the measure itself (ADR 0138).

`H-GATEGUARD` (ADR 0112 §"egyetlen emberi határ") says the one thing an
autonomous session may never do is weaken the measure that judges it: the gate
script, the CI workflows, the CI checkers, the router's security module and the
hook files themselves.  Until now that rule lived only in prose, and prose is
not an enforcement mechanism — the same lesson the legacy scope audit encodes
(docs/LESSONS.md L116, `tools/ai_router/git-guard/git`).

This hook turns it into a fail-closed check for every Claude-side session in
this repository: the round orchestrator, the self-heal session and interactive
work alike.  It runs on `Edit`/`Write`/`NotebookEdit` and — best effort — on
mutating `Bash` commands.

Deliberately NOT protected, because the pipeline legitimately writes them:
`docs/execution/pipeline-queue.tsv` (the orchestrator marks rounds done),
`.pipeline/**` (round status), `HANDOFF.md`, the RTM and the round docs.

**Scope of the guarantee.**  This hook covers tool calls that write inside the
project directory.  It does NOT cover `git` plumbing, nor writes into a round's
isolated work copy — both sit outside `CLAUDE_PROJECT_DIR` or bypass the write
tools entirely.  That is by design, not oversight: the audited control for work
copies is `tools/scope-audit.py`, and the audited control for what reaches
`main` is the independent review plus the branch's CI run.  Treat this hook as
the fast, local layer of a defence in depth, never as the only one.

Human-authorized governance work uses one of two visible escapes (L117):

* `STRUMSIGHT_GATE_EDIT_OK=1` in the environment — for scripted contexts that
  can set the variable before the session starts.
* `.claude/gate-edit-authorized` — a gitignored marker file whose first line is
  the reason.  Measured 2026-08-05: an interactive session cannot set its own
  environment variable, so an env-only escape is documentation rather than a
  mechanism.  A marker file can be created from inside the session that needs
  it, and it stays visible to the next reader.

Both escapes are echoed to stderr so the bypass appears in the transcript
rather than happening silently.  Neither unlocks secret paths.

Hook contract: exit 0 allows, exit 2 blocks and returns stderr to the model.
Any unexpected error also blocks — an unprovable guard is treated as a failed
guard, not as permission.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from fnmatch import fnmatch

# Az egyetlen dolog, amit egy önmagát mérő session nem írhat át: a MÉRCE.
PROTECTED_GLOBS = (
    # a futtatható mérce
    "tools/round-gate.sh",
    "tool/ci",
    "tool/ci/*",
    ".github/workflows",
    ".github/workflows/*",
    ".github/actions",
    ".github/actions/*",
    ".github/actions/*/*",
    # a router biztonsági rétege és konfigurációja
    "tools/ai_router",
    "tools/ai_router/*",
    "tools/ai_router/*/*",
    "tools/model-router.py",
    "tools/scope-audit.py",
    "tools/round-scope-audit.sh",
    ".ai/router.toml",
    # séma-szerződések
    "schemas",
    "schemas/*",
    # maga az őr
    ".claude/hooks",
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

ESCAPE_VARIABLE = "STRUMSIGHT_GATE_EDIT_OK"
ESCAPE_MARKER = ".claude/gate-edit-authorized"

# Parancsok, amelyek az operandusukba ÍRNAK, és MELYIK operandusba.
#   all  — minden operandus célpont (`rm a b`, `tee a b`)
#   last — csak az utolsó a cél, a többi FORRÁS (`cp forrás cél`)
#   tail — az első operandus nem útvonal (`chmod +x fájl`)
_WRITING_COMMANDS = {
    "rm": "all",
    "rmdir": "all",
    "truncate": "all",
    "shred": "all",
    "tee": "all",
    "patch": "all",
    "cp": "last",
    "mv": "last",
    "install": "last",
    "ln": "last",
    "chmod": "tail",
    "chown": "tail",
}


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


def _bash_write_targets(command: str) -> list[str]:
    """Only the paths a shell command actually WRITES to.

    Measured 2026-08-05 (docs/LESSONS.md L117): the first version scanned every
    token of the command, so a documentation append whose *text* merely
    mentioned a protected path was blocked, as was running the guard's own
    test and committing it.  A guard that punishes mention obstructs its own
    documentation.  Parse write targets instead: redirection destinations,
    `sed -i` arguments and the operands of commands that write where they
    point.
    """
    try:
        tokens = shlex.split(command, comments=False)
    except ValueError:
        # Lezáratlan idézőjel: a parancs nem elemezhető, célpontot nem tudunk
        # azonosítani. Nem állítunk semmit — az auditált réteg a scope-audit.
        return []

    targets: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]

        # 1) átirányítás: `>cél`, `> cél`, `>>cél`, `2>cél`
        if redirect := re.fullmatch(r"\d*>>?(.*)", token):
            destination = redirect.group(1)
            if destination:
                targets.append(destination)
            elif index + 1 < len(tokens):
                targets.append(tokens[index + 1])
                index += 1
            index += 1
            continue

        # 2) `dd of=cél`
        if token.startswith("of="):
            targets.append(token[3:])
            index += 1
            continue

        base = os.path.basename(token)

        # 3) `sed -i ... fájl`
        if base == "sed":
            in_place = any(
                argument == "-i"
                or argument.startswith("-i.")
                or argument.startswith("--in-place")
                for argument in tokens[index + 1 :]
            )
            if in_place:
                targets.extend(
                    argument
                    for argument in tokens[index + 1 :]
                    if not argument.startswith("-")
                )
            index += 1
            continue

        # 4) a célpontjukba író parancsok
        if base in _WRITING_COMMANDS:
            arguments = tokens[index + 1 :]
            operands = [argument for argument in arguments if not argument.startswith("-")]
            # `cp -t CÉLKÖNYVTÁR forrás...` — a `-t` argumentuma a célpont.
            explicit_target = None
            for position, argument in enumerate(arguments):
                if argument in ("-t", "--target-directory") and position + 1 < len(arguments):
                    explicit_target = arguments[position + 1]
                elif argument.startswith("--target-directory="):
                    explicit_target = argument.split("=", 1)[1]

            mode = _WRITING_COMMANDS[base]
            if explicit_target is not None:
                targets.append(explicit_target)
            elif mode == "tail":
                targets.extend(operands[1:])   # chmod/chown: az első operandus a mód
            elif mode == "last":
                # `cp forrás cél`: a forrásokat OLVASSA, csak a célba ír.
                if operands:
                    targets.append(operands[-1])
            else:
                targets.extend(operands)
            index += 1
            continue

        index += 1

    return targets


def _paths_from_input(tool_name: str, tool_input: dict) -> list[str]:
    if tool_name in ("Edit", "Write", "NotebookEdit"):
        candidate = tool_input.get("file_path") or tool_input.get("notebook_path")
        return [candidate] if isinstance(candidate, str) else []
    if tool_name == "Bash":
        command = tool_input.get("command")
        if not isinstance(command, str):
            return []
        return _bash_write_targets(command)
    return []


def _escape_reason() -> str | None:
    """The visible human authorization for this session, if any."""
    if os.environ.get(ESCAPE_VARIABLE) == "1":
        return f"{ESCAPE_VARIABLE}=1"
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    marker = os.path.join(project, ESCAPE_MARKER) if project else ESCAPE_MARKER
    try:
        with open(marker, encoding="utf-8") as handle:
            reason = handle.readline().strip()
    except OSError:
        return None
    return f"{ESCAPE_MARKER}: {reason or '(indok nélkül)'}"


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

    escape = _escape_reason()

    for raw in _paths_from_input(tool_name, tool_input):
        if not isinstance(raw, str) or not raw:
            continue
        path = _relative(raw)
        if not path:
            continue

        if pattern := _matches(path, SECRET_GLOBS):
            print(
                f"protect_factory_files: TILTOTT titok-útvonal ({pattern}): {path}. "
                "Secret nem kerülhet sessionbe, logba vagy commitba (AGENTS.md §5). "
                "Erre az emberi engedély SEM érvényes.",
                file=sys.stderr,
            )
            return 2

        if pattern := _matches(path, PROTECTED_GLOBS):
            if escape:
                print(
                    f"protect_factory_files: {path} VÉDETT ({pattern}), de "
                    f"emberi engedély van rá — {escape}.",
                    file=sys.stderr,
                )
                continue
            print(
                f"protect_factory_files: BLOKKOLVA — {path} a MÉRCE része ({pattern}).\n"
                "A mércét nem javíthatja az, akit mér (H-GATEGUARD, ADR 0112/0138).\n"
                "Ha a kör tényleg ezt kívánja: ÁLLJ MEG és jelezz "
                "(`tools/codex-signal.sh stopped`), az ember dönt.\n"
                f"Emberi engedély: {ESCAPE_VARIABLE}=1, vagy a(z) {ESCAPE_MARKER} "
                "marker-fájl (első sora az indok).",
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
