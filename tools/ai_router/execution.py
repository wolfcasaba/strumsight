"""Shell-free process execution for the model router."""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


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


def build_codex_argv(codex_bin: str, profile: str, worktree: Path) -> list[str]:
    if profile not in {"m3", "terra"}:
        raise ValueError(f"unsupported Codex profile: {profile}")
    return [
        codex_bin,
        "exec",
        "--profile",
        profile,
        "--cd",
        os.fspath(worktree.resolve()),
        "--sandbox",
        "workspace-write",
        "--ask-for-approval",
        "never",
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
        env=env,
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
