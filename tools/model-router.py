#!/usr/bin/env python3
"""Headless CLI for the deterministic MiniMax-first development router."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import fields
from pathlib import Path

from ai_router.brief import BriefMetadataError, load_brief
from ai_router.config import ConfigError, load_config
from ai_router.execution import CodexResult, ProcessRunner, run_codex
from ai_router.quota import QuotaStatus
from ai_router.router import DevelopmentRouter, GateRun, RouterStatus
from ai_router.security import audit_scope, capture_workspace_manifest, redact_text
from ai_router.state import StateError, StateStore


def _expanded(value: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(value)))


def _gate_runner(config: object, process: ProcessRunner, *, baseline: bool = False):
    expected_exits = {"pass": 0, "code_failure": 10, "environment_failure": 20, "invalid_gate": 30}

    def run(worktree: Path, tests: tuple[str, ...], native: bool) -> GateRun:
        gate_script = worktree / config.runtime.gate_script
        selected_tests = tuple(path for path in tests if not baseline or (worktree / path).exists())
        mode_args = ["--baseline"] if baseline else []
        with tempfile.TemporaryDirectory(prefix="strumsight-gate-") as directory:
            result_file = Path(directory) / "result.json"
            completed = process.run(
                [os.fspath(gate_script), "--result-json", os.fspath(result_file), *mode_args, *selected_tests],
                cwd=worktree,
                timeout_seconds=config.runtime.gate_timeout_seconds,
            )
            log = redact_text(completed.stdout + completed.stderr)
            if completed.timed_out:
                return GateRun("environment_failure", "round-gate timeout", 124, None, log)
            if completed.returncode == 127:
                return GateRun(
                    "environment_failure",
                    "round-gate executable unavailable",
                    127,
                    None,
                    log,
                )
            try:
                payload = json.loads(result_file.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                return GateRun("internal_failure", "missing structured result", completed.returncode, None, log)
            outcome = payload.get("outcome")
            if outcome not in expected_exits or completed.returncode != expected_exits[outcome]:
                return GateRun("internal_failure", "gate result/exit mismatch", completed.returncode, None, log)
            if outcome != "pass":
                return GateRun(
                    outcome,
                    payload.get("failed_step") if isinstance(payload.get("failed_step"), str) else None,
                    int(payload.get("command_exit_code", completed.returncode)),
                    payload.get("error_hash") if isinstance(payload.get("error_hash"), str) else None,
                    log,
                )
            diff_check = process.run(
                ["git", "diff", "--check"],
                cwd=worktree,
                timeout_seconds=config.runtime.gate_timeout_seconds,
            )
            if diff_check.returncode != 0:
                combined = redact_text(diff_check.stdout + diff_check.stderr)
                digest = hashlib.sha256(combined.encode()).hexdigest()
                return GateRun("code_failure", "git diff --check", diff_check.returncode, f"sha256:{digest}", combined)
            if native:
                native_result = process.run(
                    list(config.security.native_gate_command),
                    cwd=worktree,
                    timeout_seconds=config.runtime.gate_timeout_seconds,
                )
                if native_result.returncode != 0:
                    combined = redact_text(native_result.stdout + native_result.stderr)
                    digest = hashlib.sha256(combined.encode()).hexdigest()
                    return GateRun(
                        "code_failure",
                        "native gate",
                        native_result.returncode,
                        f"sha256:{digest}",
                        combined,
                    )
            return GateRun("pass", None, 0, None, log)

    return run


def _quota_checker(config: object, process: ProcessRunner, cwd: Path):
    allowed = {field.name for field in fields(QuotaStatus)}

    def check() -> QuotaStatus:
        helper = _expanded(config.runtime.quota_helper)
        result = process.run([os.fspath(helper), "--check-only"], cwd=cwd, timeout_seconds=15)
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            return QuotaStatus("invalid_response", False, False)
        if not isinstance(payload, dict):
            return QuotaStatus("invalid_response", False, False)
        values = {key: value for key, value in payload.items() if key in allowed}
        try:
            return QuotaStatus(**values)
        except TypeError:
            return QuotaStatus("invalid_response", False, False)

    return check


def _diff_context(worktree: Path) -> tuple[str, str]:
    def git(*args: str) -> str:
        completed = subprocess.run(
            ["git", *args], cwd=worktree, text=True, capture_output=True, check=False
        )
        return completed.stdout if completed.returncode == 0 else ""

    return git("diff", "--stat", "HEAD"), git("diff", "--no-ext-diff", "HEAD", "--")


def _build_router(config_path: Path, state_root: Path | None, worktree: Path) -> DevelopmentRouter:
    config = load_config(config_path)
    state = StateStore(state_root or _expanded(config.runtime.state_dir))
    process = ProcessRunner()

    def model(profile: str, cwd: Path, prompt: str) -> CodexResult:
        return run_codex(
            profile=profile,
            worktree=cwd,
            prompt=prompt,
            runner=process,
            codex_bin=config.runtime.codex_bin,
            timeout_seconds=config.runtime.model_timeout_seconds,
        )

    def scope(worktree_path: Path, metadata: object, baseline: object):
        return audit_scope(
            worktree_path,
            allowed_paths=metadata.allowed_paths,
            protected_paths=config.security.protected_paths,
            baseline=baseline,
            high_risk_fragments=config.security.high_risk_path_fragments,
        )

    return DevelopmentRouter(
        config=config,
        state=state,
        run_model=model,
        run_gate=_gate_runner(config, process),
        run_baseline_gate=_gate_runner(config, process, baseline=True),
        check_quota=_quota_checker(config, process, worktree),
        capture_manifest=capture_workspace_manifest,
        audit_scope=scope,
        diff_context=_diff_context,
    )


def _smoke(profile: str, codex_bin: str, worktree: Path) -> int:
    expected = "M3_OK" if profile == "m3" else "TERRA_OK"
    prompt = f"Válaszolj kizárólag ezzel: {expected}"
    argv = [
        codex_bin,
        "--ask-for-approval",
        "never",
        "exec",
        "--profile",
        profile,
        "--cd",
        os.fspath(worktree.resolve()),
        "--sandbox",
        "read-only",
        "--ephemeral",
        "--json",
        "-",
    ]
    result = ProcessRunner().run(argv, input_text=prompt, cwd=worktree, timeout_seconds=300)
    messages: list[str] = []
    for line in result.stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = event.get("item") if isinstance(event, dict) else None
        if isinstance(item, dict) and item.get("type") == "agent_message":
            message = item.get("text")
            if isinstance(message, str):
                messages.append(message.strip())
    if result.returncode == 0 and expected in messages:
        print(expected)
        return 0
    print(f"smoke failed for profile {profile}", file=sys.stderr)
    return 1


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--config", type=Path, default=Path(__file__).resolve().parents[1] / ".ai" / "router.toml")
    cli.add_argument("--state-root", type=Path)
    commands = cli.add_subparsers(dest="command", required=True)

    run = commands.add_parser("run")
    run.add_argument("--task", type=Path, required=True)
    run.add_argument("--worktree", type=Path, required=True)
    run.add_argument("--result-json", type=Path, required=True)
    run.add_argument("--resume", action="store_true")
    run.add_argument("--review-findings", type=Path)

    status = commands.add_parser("status")
    status.add_argument("--task-id", required=True)
    status.add_argument("--json", action="store_true")

    resume = commands.add_parser("resume")
    resume.add_argument("--task", type=Path, required=True)
    resume.add_argument("--worktree", type=Path, required=True)
    resume.add_argument("--result-json", type=Path, required=True)
    resume.add_argument("--review-findings", type=Path)

    smoke = commands.add_parser("smoke")
    smoke.add_argument("--profile", choices=("m3", "terra"), required=True)
    smoke.add_argument("--codex-bin", default="codex")
    smoke.add_argument("--worktree", type=Path, default=Path.cwd())
    return cli


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "smoke":
            return _smoke(args.profile, args.codex_bin, args.worktree)
        config = load_config(args.config)
        state = StateStore(args.state_root or _expanded(config.runtime.state_dir))
        if args.command == "status":
            value = state.load_task(args.task_id)
            payload = value or {"schema_version": 1, "task_id": args.task_id, "status": "NOT_STARTED"}
            if args.json:
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            else:
                print(f"{args.task_id}: {payload.get('status', 'NOT_STARTED')}")
            return 0
        brief = load_brief(args.task)
        worktree = args.worktree.resolve()
        findings = ""
        findings_path = getattr(args, "review_findings", None)
        if findings_path is not None:
            findings = findings_path.read_text(encoding="utf-8")
        router = _build_router(args.config, args.state_root, worktree)
        result = router.run(
            brief,
            worktree,
            result_path=args.result_json,
            resume=args.command == "resume" or bool(getattr(args, "resume", False)),
            review_findings=findings,
        )
        print(json.dumps(result.to_dict(), ensure_ascii=False, sort_keys=True))
        return result.exit_code
    except (BriefMetadataError, ConfigError, StateError, OSError, ValueError) as error:
        print(json.dumps({"schema_version": 1, "status": RouterStatus.INTERNAL_ERROR.value, "reason": redact_text(str(error))}), file=sys.stderr)
        return 50


if __name__ == "__main__":
    raise SystemExit(main())
