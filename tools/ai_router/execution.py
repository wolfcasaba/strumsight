"""Shell-free process execution for the model router."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

# ADR 0112 self-heal (E03-R05 H6, measured 2026-08-02): MiniMax-M3 committed
# d0546f0 in worktree ss-router-e03-r05-2 despite "Do not commit, push, open
# a PR..." being the first instruction line of every M3/Terra prompt
# (router.py _initial_prompt/_repair_prompt, packet.py escalation prefix) —
# security.py's scope-audit correctly hard-BLOCKed on the HEAD mismatch, but
# only after the attempt was already burned and the pipeline halted. M3/Terra
# run with --sandbox danger-full-access (workspace-write cannot create a
# bwrap network namespace here, see build_codex_argv below), so nothing at
# the process-sandbox layer stops `git commit`/`git push` either — the
# prompt instruction was the only guard, and it is not reliable. This PATH
# shim rejects `commit`/`push` at the shell layer as defense in depth;
# security.py's scope-audit and HEAD check are unchanged.
_GIT_GUARD_DIR = Path(__file__).resolve().parent / "git-guard"


@dataclass(frozen=True)
class ProcessResult:
    argv: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False


@dataclass(frozen=True)
class CodexResult:
    returncode: int
    events: tuple[dict[str, object], ...]
    agent_messages: tuple[str, ...]
    stderr: str
    timed_out: bool = False


class ProcessRunner:
    """Run a trusted argv list without invoking a shell."""

    def run(
        self,
        argv: Sequence[str],
        *,
        input_text: str = "",
        cwd: Path,
        env: Mapping[str, str] | None = None,
        timeout_seconds: float | None = None,
    ) -> ProcessResult:
        try:
            completed = subprocess.run(
                list(argv),
                cwd=os.fspath(cwd),
                env=dict(env) if env is not None else None,
                input=input_text,
                text=True,
                capture_output=True,
                timeout=timeout_seconds,
                shell=False,
                check=False,
            )
            return ProcessResult(
                argv=tuple(argv),
                returncode=completed.returncode,
                stdout=completed.stdout,
                stderr=completed.stderr,
            )
        except subprocess.TimeoutExpired as error:
            stdout = error.stdout or ""
            stderr = error.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode(errors="replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode(errors="replace")
            return ProcessResult(
                argv=tuple(argv),
                returncode=124,
                stdout=stdout,
                stderr=stderr,
                timed_out=True,
            )
        except OSError as error:
            executable = argv[0] if argv else "<empty argv>"
            return ProcessResult(
                argv=tuple(argv),
                returncode=127,
                stdout="",
                stderr=(
                    f"executable unavailable: {executable} "
                    f"({error.__class__.__name__})"
                ),
            )


def _guarded_env(env: Mapping[str, str] | None) -> dict[str, str]:
    """Prepend the git-guard shim dir to PATH so a model subprocess's own
    `git commit`/`git push` fails immediately instead of only being caught
    (after the fact, one whole attempt later) by security.py's scope-audit.
    """
    merged = dict(env) if env is not None else dict(os.environ)
    real_git = shutil.which("git", path=merged.get("PATH"))
    if real_git is None:
        raise RuntimeError("git executable not found; cannot install the router's git-guard")
    merged["STRUMSIGHT_REAL_GIT"] = real_git
    existing_path = merged.get("PATH", "")
    merged["PATH"] = (
        f"{_GIT_GUARD_DIR}{os.pathsep}{existing_path}" if existing_path else str(_GIT_GUARD_DIR)
    )
    return merged


def build_codex_argv(codex_bin: str, profile: str, worktree: Path) -> list[str]:
    if profile not in {"m3", "terra"}:
        raise ValueError(f"unsupported Codex profile: {profile}")
    return [
        codex_bin,
        "--ask-for-approval",
        "never",
        "exec",
        "--profile",
        profile,
        "--cd",
        os.fspath(worktree.resolve()),
        # danger-full-access, not workspace-write: workspace-write needs a
        # bwrap network namespace this container cannot create ("bwrap:
        # loopback: Failed RTM_NEWADDR: Operation not permitted" — measured,
        # E02-R21 H4). Isolation comes from the dedicated worktree, same as
        # tools/codex-round.sh's `-s danger-full-access`.
        "--sandbox",
        "danger-full-access",
        "--ephemeral",
        "--json",
        "-",
    ]


def run_codex(
    *,
    profile: str,
    worktree: Path,
    prompt: str,
    runner: ProcessRunner,
    codex_bin: str = "codex",
    env: Mapping[str, str] | None = None,
    timeout_seconds: float = 7200,
) -> CodexResult:
    process = runner.run(
        build_codex_argv(codex_bin, profile, worktree),
        input_text=prompt,
        cwd=worktree,
        env=_guarded_env(env),
        timeout_seconds=timeout_seconds,
    )
    events: list[dict[str, object]] = []
    messages: list[str] = []
    for line in process.stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        events.append(event)
        item = event.get("item")
        if (
            event.get("type") == "item.completed"
            and isinstance(item, dict)
            and item.get("type") == "agent_message"
            and isinstance(item.get("text"), str)
        ):
            messages.append(item["text"])
    return CodexResult(
        returncode=process.returncode,
        events=tuple(events),
        agent_messages=tuple(messages),
        stderr=process.stderr,
        timed_out=process.timed_out,
    )
