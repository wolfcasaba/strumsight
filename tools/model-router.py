#!/usr/bin/env python3
"""Headless CLI for the deterministic MiniMax-first development router."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import fields
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ai_router.brief import BriefMetadataError, load_brief
from ai_router.config import ConfigError, load_config
from ai_router.execution import CodexResult, ProcessRunner, run_codex
from ai_router.quota import QuotaStatus
from ai_router.router import DevelopmentRouter, GateRun, RouterStatus
from ai_router.security import (
    WorkspaceManifest,
    audit_scope,
    capture_workspace_manifest,
    rebase_workspace_manifest,
    redact_text,
)
from ai_router.state import StateError, StateStore


_TASK_ID = re.compile(r"^E\d{2}-R\d{2}$", re.IGNORECASE)


def _expanded(value: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(value)))


def _manifest_from_state(value: object) -> WorkspaceManifest:
    if not isinstance(value, dict):
        raise StateError("task has no baseline manifest")
    head = value.get("baseline_head")
    untracked = value.get("untracked_paths")
    ignored = value.get("ignored_paths")
    tracked = value.get("tracked_paths", [])
    if (
        not isinstance(head, str)
        or not isinstance(untracked, list)
        or not isinstance(ignored, list)
        or not isinstance(tracked, list)
        or not all(isinstance(path, str) for path in (*untracked, *ignored, *tracked))
    ):
        raise StateError("task baseline manifest is invalid")
    return WorkspaceManifest(
        baseline_head=head,
        untracked_paths=frozenset(untracked),
        ignored_paths=frozenset(ignored),
        tracked_paths=frozenset(tracked),
    )


def _manifest_to_state(manifest: WorkspaceManifest) -> dict[str, object]:
    return {
        "baseline_head": manifest.baseline_head,
        "untracked_paths": sorted(manifest.untracked_paths),
        "ignored_paths": sorted(manifest.ignored_paths),
        "tracked_paths": sorted(manifest.tracked_paths),
    }


def _rebase_brief_path(task: Path, worktree: Path) -> Path:
    """Resolve a rebase brief path, including one unambiguous task identifier.

    `rebase-baseline` is an operator recovery command.  Accepting the task ID
    that appears in the persisted state prevents a path/identifier mix-up from
    turning a recoverable blocked task into an INTERNAL_ERROR.  The lookup is
    deliberately constrained to one matching brief inside this worktree.
    """
    if task.exists():
        return task
    task_id = task.name.upper()
    if task.parent != Path(".") or not _TASK_ID.fullmatch(task_id):
        return task
    matches = sorted((worktree / "docs" / "rounds").glob(f"{task_id.lower()}-*.md"))
    if len(matches) != 1:
        raise BriefMetadataError(
            f"task id must resolve to exactly one brief in docs/rounds: {task_id}"
        )
    return matches[0]


def rebase_blocked_task_baseline(
    *, state: StateStore, brief: object, worktree: Path, config: object
) -> dict[str, object]:
    """Safely advance a stale BLOCKED task baseline to its pre-flight head.

    The persisted state remains the source of truth.  This intentionally does
    not reset attempts or discard any model diff: it verifies that the current
    diff is still within the brief before returning it for independent review.
    """
    task_id = brief.task_id
    with state.task_lock(task_id):
        task = state.load_task(task_id)
        if task.get("task_id") != task_id:
            raise StateError("task state has a mismatched task_id")
        if task.get("status") != RouterStatus.BLOCKED.value:
            raise StateError("only a BLOCKED task baseline may be rebased")
        previous = _manifest_from_state(task.get("baseline_manifest"))
        refreshed = rebase_workspace_manifest(worktree, previous)
        audit = audit_scope(
            worktree,
            allowed_paths=brief.metadata.allowed_paths,
            protected_paths=config.security.protected_paths,
            baseline=refreshed,
            high_risk_fragments=config.security.high_risk_path_fragments,
        )
        if not audit.ok:
            raise StateError("rebased baseline still fails scope audit: " + "; ".join(audit.violations))
        task["baseline_manifest"] = _manifest_to_state(refreshed)
        task["changed_paths"] = list(audit.scoped_changed_paths)
        # The old BLOCKED result was fully committed to the Terra ledger
        # before this operator-only recovery began. Keeping its two-phase
        # terminal intent would make `resume` replay that stale result before
        # it can inspect the rebased baseline. Keep the reservation history
        # and attempt counters, but clear only the superseded terminal intent.
        task.pop("terra_terminal_status", None)
        task.pop("terra_terminal_reason", None)
        task["status"] = RouterStatus.READY_FOR_REVIEW.value
        task["phase"] = "BASELINE_REBASED"
        task["reason"] = (
            "stale baseline rebased from "
            f"{previous.baseline_head[:12]} to {refreshed.baseline_head[:12]}; "
            "existing scoped diff preserved for review"
        )
        state.save_task(task_id, task)
    return task


def recover_stopped_task_after_heal(
    *, state: StateStore, brief: object, worktree: Path, config: object, run_gate: object
) -> dict[str, object]:
    """Re-open a STOPPED task for review after an independently merged heal.

    This is deliberately narrower than ``reset``: it preserves the completed
    M3/Terra attempt ledger and accepts no new model call.  The worktree must
    pass a fresh scope audit and its exact target gate before the task can
    become reviewable again.
    """
    task_id = brief.task_id
    with state.task_lock(task_id):
        task = state.load_task(task_id)
        if task.get("task_id") != task_id:
            raise StateError("task state has a mismatched task_id")
        if task.get("status") != RouterStatus.STOPPED.value:
            raise StateError("only a STOPPED task may recover after a heal")
        previous = _manifest_from_state(task.get("baseline_manifest"))
        refreshed = rebase_workspace_manifest(worktree, previous)
        audit = audit_scope(
            worktree,
            allowed_paths=brief.metadata.allowed_paths,
            protected_paths=config.security.protected_paths,
            baseline=refreshed,
            high_risk_fragments=config.security.high_risk_path_fragments,
        )
        if not audit.ok:
            raise StateError("healed worktree still fails scope audit: " + "; ".join(audit.violations))
        gate = run_gate(worktree, brief.metadata.gate_tests, brief.metadata.native_gate)
        if gate.outcome != "pass":
            detail = gate.failed_step or gate.outcome
            raise StateError(f"healed worktree target gate is not green: {detail}")
        task["baseline_manifest"] = _manifest_to_state(refreshed)
        task["changed_paths"] = list(audit.scoped_changed_paths)
        # The terminal intent belongs to the earlier, now superseded gate
        # result.  Keep its reservation and all counters as audit evidence.
        task.pop("terra_terminal_status", None)
        task.pop("terra_terminal_reason", None)
        task["status"] = RouterStatus.READY_FOR_REVIEW.value
        task["phase"] = "HEAL_GATE_PASSED"
        task["reason"] = "merged self-heal passed the target gate; ready for independent review"
        state.save_task(task_id, task)
    return task


def _dart_bin() -> str:
    # Same resolution order as tools/round-gate.sh's own `dart_bin` default,
    # so the pre-gate normalize pass and the gate script agree on which
    # toolchain they're running.
    return os.environ.get("DART_BIN") or os.path.expanduser("~/flutter/bin/dart")


def _flutter_bin() -> str:
    # Keep the bootstrap invocation aligned with round-gate.sh.  A clean
    # worktree has neither package_config.json nor Flutter's ignored l10n
    # output, both of which analyze needs before the model may be called.
    return os.environ.get("FLUTTER_BIN") or os.path.expanduser("~/flutter/bin/flutter")


def _prepare_flutter_baseline(
    process: ProcessRunner, worktree: Path, timeout_seconds: float
) -> None:
    """Restore generated Flutter prerequisites without changing source code.

    This is intentionally baseline-only preparation, not the post-model
    normalizer: pub get and gen-l10n create ignored tool output required by a
    fresh clone, while dart fix would hide an existing source-quality failure.
    """
    if not (worktree / "pubspec.yaml").exists():
        return
    flutter_bin = _flutter_bin()
    process.run([flutter_bin, "pub", "get"], cwd=worktree, timeout_seconds=timeout_seconds)
    if (worktree / "l10n.yaml").exists():
        process.run([flutter_bin, "gen-l10n"], cwd=worktree, timeout_seconds=timeout_seconds)


def _pre_gate_normalize(process: ProcessRunner, worktree: Path, timeout_seconds: float) -> None:
    # E02-R21 H4 (Update 7, measured 2026-08-02): two of the M3/Terra attempts
    # burned their whole budget on `format`/`analyze` failures caused by
    # mechanically fixable debris (unformatted files, an unused import left
    # over from an earlier draft) in files the model DID touch correctly —
    # the round's actual acceptance-criteria work was done, the gate still
    # STOPPED the task. `dart format`/`dart fix --apply` are deterministic
    # and safe on an otherwise-clean baseline (measured: `flutter analyze`
    # is clean before any model call), so running them before the gate lets
    # the gate measure the model's real content instead of spending a scarce
    # attempt on cosmetics it could not have retried its way out of anyway
    # (the M3/Terra budget is fixed at 2+1, not re-triable per gate step).
    if not (worktree / "pubspec.yaml").exists():
        return
    dart_bin = _dart_bin()
    process.run([dart_bin, "format", "lib", "test", "tool"], cwd=worktree, timeout_seconds=timeout_seconds)
    process.run([dart_bin, "fix", "--apply"], cwd=worktree, timeout_seconds=timeout_seconds)


def _gate_runner(config: object, process: ProcessRunner, *, baseline: bool = False):
    expected_exits = {"pass": 0, "code_failure": 10, "environment_failure": 20, "invalid_gate": 30}

    def run(worktree: Path, tests: tuple[str, ...], native: bool) -> GateRun:
        gate_script = worktree / config.runtime.gate_script
        selected_tests = tuple(path for path in tests if not baseline or (worktree / path).exists())
        mode_args = ["--baseline"] if baseline else []
        if baseline:
            _prepare_flutter_baseline(process, worktree, config.runtime.gate_timeout_seconds)
        else:
            _pre_gate_normalize(process, worktree, config.runtime.gate_timeout_seconds)
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


def terra_status_payload(config: object, state: StateStore) -> dict[str, object]:
    """Snapshot of today's automatic Terra daily policy and audit count."""
    now = datetime.now(timezone.utc)
    day = now.date().isoformat()
    count = state.daily_terra_count(day)
    limit = config.limits.max_automatic_terra_calls_per_utc_day
    unlimited = limit == 0
    next_reset = None
    if not unlimited:
        next_reset = datetime.combine(
            now.date() + timedelta(days=1),
            datetime.min.time(),
            tzinfo=timezone.utc,
        )
    return {
        "schema_version": 1,
        "utc_day": day,
        "daily_limit": limit,
        "daily_count": count,
        "unlimited": unlimited,
        "exhausted": not unlimited and count >= limit,
        "next_reset_utc": next_reset.isoformat() if next_reset is not None else None,
        "next_reset_epoch": int(next_reset.timestamp()) if next_reset is not None else None,
    }


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

    reset = commands.add_parser("reset")
    reset.add_argument("--task-id", required=True)

    rebase = commands.add_parser("rebase-baseline")
    rebase.add_argument("--task", type=Path, required=True)
    rebase.add_argument("--worktree", type=Path, required=True)

    recover = commands.add_parser("recover-stopped-after-heal")
    recover.add_argument("--task", type=Path, required=True)
    recover.add_argument("--worktree", type=Path, required=True)

    commands.add_parser("terra-status")

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
        if args.command == "reset":
            state.reset_task(args.task_id)
            payload = {"schema_version": 1, "task_id": args.task_id, "status": "NOT_STARTED"}
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if args.command == "rebase-baseline":
            brief = load_brief(_rebase_brief_path(args.task, args.worktree.resolve()))
            task = rebase_blocked_task_baseline(
                state=state,
                brief=brief,
                worktree=args.worktree.resolve(),
                config=config,
            )
            print(json.dumps(task, ensure_ascii=False, sort_keys=True))
            return 0
        if args.command == "recover-stopped-after-heal":
            worktree = args.worktree.resolve()
            brief = load_brief(_rebase_brief_path(args.task, worktree))
            router = _build_router(args.config, args.state_root, worktree)
            task = recover_stopped_task_after_heal(
                state=state,
                brief=brief,
                worktree=worktree,
                config=config,
                run_gate=router.run_gate,
            )
            print(json.dumps(task, ensure_ascii=False, sort_keys=True))
            return 0
        if args.command == "terra-status":
            payload = terra_status_payload(config, state)
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1 if payload["exhausted"] else 0
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
