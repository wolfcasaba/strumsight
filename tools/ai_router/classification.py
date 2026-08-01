"""Deterministic failure classification and stable error fingerprints."""

from __future__ import annotations

import hashlib
import json
import re
from enum import Enum
from typing import Iterable, Mapping


class FailureClass(str, Enum):
    PASS = "pass"
    CODE_FAILURE = "code_failure"
    PROVIDER_TRANSIENT = "provider_transient"
    PROVIDER_QUOTA = "provider_quota"
    CREDENTIAL_BLOCKED = "credential_blocked"
    ENV_BLOCKED = "env_blocked"
    POLICY_BLOCKED = "policy_blocked"
    INVALID_TASK = "invalid_task"
    STOPPED = "stopped"


def classify_gate_failure(outcome: str) -> FailureClass:
    return {
        "pass": FailureClass.PASS,
        "code_failure": FailureClass.CODE_FAILURE,
        "environment_failure": FailureClass.ENV_BLOCKED,
        "invalid_gate": FailureClass.INVALID_TASK,
        "internal_failure": FailureClass.STOPPED,
    }.get(outcome, FailureClass.STOPPED)


def classify_provider_failure(
    returncode: int,
    events: Iterable[Mapping[str, object]],
    stderr: str,
    *,
    timed_out: bool = False,
) -> FailureClass:
    if returncode == 0 and not timed_out:
        return FailureClass.PASS
    structured = json.dumps(tuple(events), ensure_ascii=False, sort_keys=True)
    evidence = f"{structured}\n{stderr}".lower()
    if returncode == 127 or re.search(
        r"executable unavailable|command not found|no such file or directory", evidence
    ):
        return FailureClass.ENV_BLOCKED
    if re.search(r"\b(?:401|403)\b|unauthori[sz]ed|invalid[^\n]*(?:credential|api.?key)", evidence):
        return FailureClass.CREDENTIAL_BLOCKED
    if re.search(r"\b429\b|rate[ _-]?limit|quota|token[ _-]?plan", evidence):
        return FailureClass.PROVIDER_QUOTA
    if timed_out or re.search(
        r"\b5\d\d\b|timed?\s*out|timeout|dns|tls|network|connection|stream[^\n]*error",
        evidence,
    ):
        return FailureClass.PROVIDER_TRANSIENT
    return FailureClass.STOPPED


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TIMESTAMP = re.compile(r"\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\b")
TEMP_PATH = re.compile(r"/tmp/[A-Za-z0-9_.-]*\d+[A-Za-z0-9_.-]*")
RUN_ID = re.compile(r"\b(?:run[_ -]?id|request[_ -]?id)\s*[=:]\s*[A-Za-z0-9_-]+", re.I)


def normalize_error(text: str) -> str:
    normalized = ANSI.sub("", text)
    normalized = TIMESTAMP.sub("<timestamp>", normalized)
    normalized = TEMP_PATH.sub("/tmp/<workspace>", normalized)
    normalized = RUN_ID.sub("run_id=<id>", normalized)
    normalized = re.sub(r"[ \t]+", " ", normalized)
    normalized = re.sub(r"\n{3,}", "\n\n", normalized)
    return normalized.strip()


def error_fingerprint(failed_step: str, log: str) -> str:
    payload = f"{failed_step}\n{normalize_error(log)}".encode()
    return "sha256:" + hashlib.sha256(payload).hexdigest()
