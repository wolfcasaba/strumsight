#!/usr/bin/env python3
"""Fail-closed release security scan (ADR 0481).

Binds the program-level threat model (`docs/security/threat-model.md`) to
machine-checkable evidence. Four independent branches:

  guards        — every `release_gate: true` countermeasure in the threat
                  model names a `guard` (a file path and, where meaningful,
                  a test name); this branch measures that the guard still
                  exists on the tree (ADR 0481 D2). It does NOT re-implement
                  the protections themselves — replay, path traversal,
                  oversize payloads and model-checksum integrity are already
                  measured by the tests the guards point at.
  exceptions    — validates `docs/security/exceptions.yaml` (every entry
                  needs `owner`, `expires`, `finding`, `reason` — ADR 0481
                  D4) and applies still-live entries to suppress the finding
                  they name.
  dependencies  — every line in the given requirements file must carry an
                  upper version bound, and is checked against a short,
                  dated, real advisory list (ADR 0481 §5.3).
  secrets       — DELEGATES to `tool/ci/check_secrets.dart` (the one source
                  of secret patterns, ADR 0138/0481 D3). This branch never
                  declares a second regex set; a secrets command that
                  cannot run, or exits non-zero, is itself a critical
                  finding — never a silent "skipped".

Exit codes (D5/D6, no other value and no absorbing flag):
  0  no critical (or fatal) finding
  1  at least one critical finding
  2  an input (threat model / exceptions registry / requirements manifest)
     could not be read or parsed at all — the scan cannot prove anything,
     so it refuses to report clean (the `check_secrets_test.dart` L220
     failure class generalized: "found no input, therefore clean" is not an
     acceptable branch).

`--only` restricts execution to exactly one branch, and each branch reads
only the input(s) that branch actually needs — `--only secrets` never
touches the threat model, `--only guards` never touches the exceptions
registry. Exception suppression is therefore only available where it is
actually exercised (the default full run, and `--only dependencies`); a
guard whose test was renamed cannot be waved away by an exceptions entry in
this round's scope.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - measured available on box + CI
    yaml = None


class InputError(Exception):
    """Tier-1 failure: the given input cannot be parsed at all (D6).

    Distinct from a `Finding` with severity "critical": a critical finding
    describes something the scan COULD read but disapproves of (a missing
    guard, an expired exception, an unbounded dependency). An `InputError`
    means the scan could not even form an opinion, so it must not report
    exit 0 — a missing or garbled file must never look like "nothing to
    report" (D6).
    """


@dataclass(frozen=True)
class Finding:
    id: str
    severity: str  # "critical" | "fatal"
    branch: str
    message: str


@dataclass(frozen=True)
class GuardEntry:
    id: str
    component: str
    threat: str
    release_gate: bool
    guard_path: str
    guard_test: str | None


_VALID_THREATS = {
    "spoofing",
    "tampering",
    "repudiation",
    "information-disclosure",
    "denial-of-service",
    "elevation-of-privilege",
}
_ALLOWED_BLOCK_KEYS = {"id", "component", "threat", "release_gate", "guard"}
_ALLOWED_GUARD_KEYS = {"path", "test"}
_ID_PATTERN = re.compile(r"^[A-Z0-9-]+$")

_YAML_BLOCK = re.compile(r"```yaml\n(.*?)\n```", re.DOTALL)


# ---------------------------------------------------------------------------
# guards branch
# ---------------------------------------------------------------------------


def _require_yaml() -> None:
    if yaml is None:  # pragma: no cover - measured available on box + CI
        raise InputError(
            "security_scan: PyYAML is not importable — cannot parse YAML input "
            "(measured available on this box and CI as of the E12-R18 "
            "pre-flight; a missing interpreter dependency is fail-closed, "
            "not a silent skip)"
        )


def _validate_guard_block(data: object) -> list[Finding]:
    if not isinstance(data, dict):
        raise InputError(
            "threat-model.md: a ```yaml``` guard block is not a mapping"
        )
    findings: list[Finding] = []
    unknown = set(data) - _ALLOWED_BLOCK_KEYS
    if unknown:
        findings.append(
            Finding(
                id="guards.unknown-key",
                severity="critical",
                branch="guards",
                message=f"guard block has unknown key(s): {sorted(unknown)}",
            )
        )
    missing = [key for key in _ALLOWED_BLOCK_KEYS if key not in data]
    if missing:
        findings.append(
            Finding(
                id="guards.missing-key",
                severity="critical",
                branch="guards",
                message=f"guard block is missing required key(s): {missing}",
            )
        )
    if findings:
        return findings

    block_id = data["id"]
    if not isinstance(block_id, str) or not _ID_PATTERN.match(block_id):
        findings.append(
            Finding(
                id="guards.invalid-id",
                severity="critical",
                branch="guards",
                message=f"guard id {block_id!r} does not match [A-Z0-9-]+",
            )
        )
    component = data["component"]
    if not isinstance(component, str) or not component.strip():
        findings.append(
            Finding(
                id="guards.invalid-component",
                severity="critical",
                branch="guards",
                message=f"guard {block_id!r}: component must be a non-empty string",
            )
        )
    threat = data["threat"]
    if threat not in _VALID_THREATS:
        findings.append(
            Finding(
                id="guards.unknown-threat",
                severity="critical",
                branch="guards",
                message=f"guard {block_id!r}: unknown threat value {threat!r}",
            )
        )
    release_gate = data["release_gate"]
    if not isinstance(release_gate, bool):
        findings.append(
            Finding(
                id="guards.invalid-release-gate",
                severity="critical",
                branch="guards",
                message=f"guard {block_id!r}: release_gate must be a boolean",
            )
        )
    guard = data["guard"]
    if not isinstance(guard, dict):
        raise InputError(f"threat-model.md: guard {block_id!r}: `guard` is not a mapping")
    unknown_guard = set(guard) - _ALLOWED_GUARD_KEYS
    if unknown_guard:
        findings.append(
            Finding(
                id="guards.unknown-guard-key",
                severity="critical",
                branch="guards",
                message=f"guard {block_id!r}: guard has unknown key(s): {sorted(unknown_guard)}",
            )
        )
    if "path" not in guard or not isinstance(guard.get("path"), str) or not guard["path"].strip():
        findings.append(
            Finding(
                id="guards.missing-guard-path",
                severity="critical",
                branch="guards",
                message=f"guard {block_id!r}: guard.path is required and must be a non-empty string",
            )
        )
    test_value = guard.get("test")
    if test_value is not None and (not isinstance(test_value, str) or not test_value.strip()):
        findings.append(
            Finding(
                id="guards.invalid-guard-test",
                severity="critical",
                branch="guards",
                message=f"guard {block_id!r}: guard.test must be a non-empty string when present",
            )
        )
    return findings


def load_threat_model(path: Path) -> tuple[list[GuardEntry], list[Finding]]:
    """Parses every ```yaml``` guard block in the threat model.

    Raises `InputError` for structural failures (missing file, invalid YAML,
    a block that is not a mapping). Semantic issues within an otherwise
    well-formed block (unknown key, missing key, bad enum value) are
    returned as critical `Finding`s instead — the block is skipped, but the
    rest of the document is still measured (ADR 0481 §5.1).
    """
    _require_yaml()
    if not path.is_file():
        raise InputError(f"threat model not found: {path}")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise InputError(f"threat model is not valid UTF-8: {path}: {error}") from error

    entries: list[GuardEntry] = []
    findings: list[Finding] = []
    seen_ids: set[str] = set()
    for raw_block in _YAML_BLOCK.findall(text):
        try:
            data = yaml.safe_load(raw_block)
        except yaml.YAMLError as error:
            raise InputError(f"threat model: invalid YAML in a guard block: {error}") from error
        block_findings = _validate_guard_block(data)
        if block_findings:
            findings.extend(block_findings)
            continue
        entry = GuardEntry(
            id=data["id"],
            component=data["component"],
            threat=data["threat"],
            release_gate=data["release_gate"],
            guard_path=data["guard"]["path"],
            guard_test=data["guard"].get("test"),
        )
        if entry.id in seen_ids:
            findings.append(
                Finding(
                    id="guards.duplicate-id",
                    severity="critical",
                    branch="guards",
                    message=f"guard id {entry.id!r} is used more than once in the document",
                )
            )
            continue
        seen_ids.add(entry.id)
        entries.append(entry)
    return entries, findings


def check_guards(entries: list[GuardEntry], root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for entry in entries:
        if not entry.release_gate:
            continue
        guard_path = root / entry.guard_path
        if not guard_path.is_file():
            findings.append(
                Finding(
                    id=entry.id,
                    severity="critical",
                    branch="guards",
                    message=(
                        f"{entry.id} ({entry.component}): guard.path does not "
                        f"exist: {entry.guard_path}"
                    ),
                )
            )
            continue
        if entry.guard_test:
            try:
                guard_text = guard_path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as error:
                findings.append(
                    Finding(
                        id=entry.id,
                        severity="critical",
                        branch="guards",
                        message=f"{entry.id}: guard.path could not be read: {error}",
                    )
                )
                continue
            needle_python = f"def {entry.guard_test}"
            needle_dart = f"test('{entry.guard_test}'"
            if needle_python not in guard_text and needle_dart not in guard_text:
                findings.append(
                    Finding(
                        id=entry.id,
                        severity="critical",
                        branch="guards",
                        message=(
                            f"{entry.id} ({entry.component}): guard.test "
                            f"{entry.guard_test!r} not found in {entry.guard_path}"
                        ),
                    )
                )
    return findings


# ---------------------------------------------------------------------------
# exceptions branch
# ---------------------------------------------------------------------------

_REQUIRED_EXCEPTION_KEYS = ("owner", "expires", "finding", "reason")


def load_exceptions(
    path: Path, today: dt.date
) -> tuple[dict[str, dict], list[Finding]]:
    """Returns (live_exceptions_by_finding_id, hygiene_findings).

    Raises `InputError` for structural failures (missing file, invalid YAML,
    a document whose top-level shape is not `{exceptions: [...]}`). A
    well-formed entry missing `owner`/`expires`/`finding`/`reason`, or one
    that has already expired, is a critical `Finding` instead (ADR 0481 D4)
    — the registry keeps loading, so one bad entry does not hide the rest.
    """
    _require_yaml()
    if not path.is_file():
        raise InputError(f"exceptions registry not found: {path}")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise InputError(f"exceptions registry is not valid UTF-8: {path}: {error}") from error
    try:
        document = yaml.safe_load(text)
    except yaml.YAMLError as error:
        raise InputError(f"exceptions registry: invalid YAML: {error}") from error

    if document is None:
        document = {"exceptions": []}
    if not isinstance(document, dict) or "exceptions" not in document:
        raise InputError(
            f"exceptions registry: expected a top-level `exceptions:` list in {path}"
        )
    entries = document["exceptions"]
    if not isinstance(entries, list):
        raise InputError(f"exceptions registry: `exceptions` must be a list in {path}")

    live: dict[str, dict] = {}
    findings: list[Finding] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise InputError(
                f"exceptions registry: entry #{index} is not a mapping in {path}"
            )
        missing = [key for key in _REQUIRED_EXCEPTION_KEYS if not entry.get(key)]
        if missing:
            findings.append(
                Finding(
                    id="exceptions.missing-field",
                    severity="critical",
                    branch="exceptions",
                    message=(
                        f"exceptions[{index}] is missing required field(s) "
                        f"{missing} — an exception without owner+expires does "
                        "not exist (ADR 0481 D4)"
                    ),
                )
            )
            continue
        expires_raw = entry["expires"]
        try:
            expires = dt.date.fromisoformat(str(expires_raw))
        except ValueError:
            findings.append(
                Finding(
                    id="exceptions.invalid-expires",
                    severity="critical",
                    branch="exceptions",
                    message=(
                        f"exceptions[{index}] (finding={entry['finding']!r}): "
                        f"expires {expires_raw!r} is not an ISO YYYY-MM-DD date"
                    ),
                )
            )
            continue
        if expires < today:
            findings.append(
                Finding(
                    id="exceptions.expired",
                    severity="critical",
                    branch="exceptions",
                    message=(
                        f"exceptions[{index}] (finding={entry['finding']!r}, "
                        f"owner={entry['owner']!r}) expired {expires.isoformat()} "
                        f"— today is {today.isoformat()}"
                    ),
                )
            )
            continue
        # Live (expires >= today, the boundary is inclusive per ADR 0481 D4).
        live[str(entry["finding"])] = entry
    return live, findings


def _apply_exceptions(findings: list[Finding], live: dict[str, dict]) -> list[Finding]:
    if not live:
        return findings
    return [f for f in findings if f.id not in live]


# ---------------------------------------------------------------------------
# dependencies branch
# ---------------------------------------------------------------------------

# Dated 2026-08-29 (E12-R18 pre-flight). Real, historical advisories only —
# inventing a CVE against a currently-pinned dependency would be the
# `check_secrets_test.dart` L220 failure class generalized to this branch.
# Add an entry only when a genuinely documented advisory exists.
_ADVISORIES: list[dict[str, str]] = [
    {
        "package": "pyjwt",
        "affected": "<2.4.0",
        "id": "CVE-2022-29217",
        "severity": "high",
        # PyJWT's decode() before 2.4.0 could accept a token whose header
        # names a different algorithm than the caller expected (algorithm
        # confusion), fixed in 2.4.0. Our own pin (PyJWT>=2.8,<3, see
        # backend/requirements.txt) starts above the affected ceiling, so
        # this never fires on the real tree — it exists so the dependencies
        # branch has a genuine, dated advisory to prove the red path
        # against (A6), not an invented one.
    },
]

_REQUIREMENT_LINE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^\]]*\])?\s*(.*)$")
_CONSTRAINT_CLAUSE = re.compile(r"^(==|!=|<=|>=|~=|<|>)\s*([0-9][0-9A-Za-z.\-]*)$")
_UPPER_BOUNDING_OPS = {"<", "<=", "==", "~="}


def _vtuple(version: str) -> tuple[int, ...]:
    parts: list[int] = []
    for segment in version.split("."):
        match = re.match(r"\d+", segment)
        parts.append(int(match.group(0)) if match else 0)
    return tuple(parts)


def _vcmp(a: tuple[int, ...], b: tuple[int, ...]) -> int:
    length = max(len(a), len(b))
    a = a + (0,) * (length - len(a))
    b = b + (0,) * (length - len(b))
    if a < b:
        return -1
    if a > b:
        return 1
    return 0


def _parse_requirement_line(line: str) -> tuple[str, list[tuple[str, tuple[int, ...]]]] | None:
    match = _REQUIREMENT_LINE.match(line)
    if not match:
        return None
    name = match.group(1)
    rest = match.group(3).strip()
    if not rest:
        return name, []
    constraints: list[tuple[str, tuple[int, ...]]] = []
    for clause in rest.split(","):
        clause = clause.strip()
        clause_match = _CONSTRAINT_CLAUSE.match(clause)
        if not clause_match:
            # Unparsable clause: fail closed by not counting it as a bound.
            constraints.append(("invalid", (0,)))
            continue
        constraints.append((clause_match.group(1), _vtuple(clause_match.group(2))))
    return name, constraints


def _effective_floor(constraints: list[tuple[str, tuple[int, ...]]]) -> tuple[int, ...]:
    exact: tuple[int, ...] | None = None
    lo: tuple[int, ...] | None = None
    for op, version in constraints:
        if op == "==":
            exact = version
        elif op in (">=", ">", "~="):
            if lo is None or _vcmp(version, lo) > 0:
                lo = version
    if exact is not None:
        return exact
    return lo if lo is not None else (0,)


def _matches_advisory(candidate: tuple[int, ...], affected_expr: str) -> bool:
    match = _CONSTRAINT_CLAUSE.match(affected_expr.strip())
    if not match:
        return False
    op, version = match.group(1), _vtuple(match.group(2))
    cmp = _vcmp(candidate, version)
    if op == "<":
        return cmp < 0
    if op == "<=":
        return cmp <= 0
    if op == ">":
        return cmp > 0
    if op == ">=":
        return cmp >= 0
    if op == "==":
        return cmp == 0
    return False


def check_dependencies(path: Path) -> list[Finding]:
    if not path.is_file():
        raise InputError(f"dependency manifest not found: {path}")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise InputError(f"dependency manifest is not valid UTF-8: {path}: {error}") from error

    findings: list[Finding] = []
    for lineno, raw_line in enumerate(text.split("\n"), start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parsed = _parse_requirement_line(line)
        if parsed is None:
            findings.append(
                Finding(
                    id=f"dependencies.unparsable-line-{lineno}",
                    severity="critical",
                    branch="dependencies",
                    message=f"{path.name}:{lineno}: could not parse requirement line: {line!r}",
                )
            )
            continue
        name, constraints = parsed
        has_upper_bound = any(op in _UPPER_BOUNDING_OPS for op, _ in constraints)
        if not has_upper_bound:
            findings.append(
                Finding(
                    id=f"dependencies.{name.lower()}-no-upper-bound",
                    severity="critical",
                    branch="dependencies",
                    message=(
                        f"{path.name}:{lineno}: {name} has no upper version "
                        f"bound (<, <=, == or ~=): {line!r}"
                    ),
                )
            )
            continue
        candidate = _effective_floor(constraints)
        for advisory in _ADVISORIES:
            if advisory["package"].lower() != name.lower():
                continue
            if _matches_advisory(candidate, advisory["affected"]):
                findings.append(
                    Finding(
                        id=advisory["id"],
                        severity="critical",
                        branch="dependencies",
                        message=(
                            f"{path.name}:{lineno}: {name} matches advisory "
                            f"{advisory['id']} ({advisory['severity']}): affected "
                            f"{advisory['affected']}"
                        ),
                    )
                )
    return findings


# ---------------------------------------------------------------------------
# secrets branch (delegates — ADR 0481 D3)
# ---------------------------------------------------------------------------


def check_secrets_delegate(root: Path, command: str) -> list[Finding]:
    try:
        argv = shlex.split(command)
    except ValueError as error:
        return [
            Finding(
                id="secrets.invalid-command",
                severity="critical",
                branch="secrets",
                message=f"--secrets-cmd could not be parsed: {error}",
            )
        ]
    try:
        result = subprocess.run(
            argv,
            cwd=root,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return [
            Finding(
                id="secrets.delegate-unavailable",
                severity="critical",
                branch="secrets",
                message=f"secrets delegate command {command!r} could not be run: {error}",
            )
        ]
    if result.returncode != 0:
        detail = (result.stdout + "\n" + result.stderr).strip()
        return [
            Finding(
                id="secrets.delegate-failed",
                severity="critical",
                branch="secrets",
                message=(
                    f"secrets delegate command {command!r} exited "
                    f"{result.returncode}: {detail}"
                ),
            )
        ]
    return []


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _today_utc() -> dt.date:
    return dt.datetime.now(dt.timezone.utc).date()


def render_text(findings: list[Finding]) -> str:
    if not findings:
        return "security_scan: OK — no critical or fatal finding."
    lines = [f"security_scan: {len(findings)} finding(s)."]
    for finding in findings:
        lines.append(f"- [{finding.severity}] {finding.branch}: {finding.message} ({finding.id})")
    return "\n".join(lines)


def render_json(findings: list[Finding]) -> str:
    return json.dumps(
        {
            "findings": [
                {
                    "id": f.id,
                    "severity": f.severity,
                    "branch": f.branch,
                    "message": f.message,
                }
                for f in findings
            ]
        },
        indent=2,
        sort_keys=True,
    )


def run(argv: list[str]) -> tuple[int, str]:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".")
    parser.add_argument("--threat-model", default="docs/security/threat-model.md")
    parser.add_argument("--exceptions", default="docs/security/exceptions.yaml")
    parser.add_argument("--requirements", default="backend/requirements.txt")
    parser.add_argument("--today", default=None)
    parser.add_argument("--only", choices=["guards", "exceptions", "dependencies", "secrets"], default=None)
    parser.add_argument("--secrets-cmd", default="dart run tool/ci/check_secrets.dart")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    args = parser.parse_args(argv)

    root = Path(args.root)
    if args.today:
        try:
            today = dt.date.fromisoformat(args.today)
        except ValueError:
            return 2, f"security_scan: --today is not an ISO YYYY-MM-DD date: {args.today!r}"
    else:
        today = _today_utc()

    only = args.only
    findings: list[Finding] = []

    live_exceptions: dict[str, dict] = {}
    exceptions_available = only in (None, "exceptions", "dependencies")
    if exceptions_available:
        try:
            live_exceptions, exc_findings = load_exceptions(root / args.exceptions, today)
            findings.extend(exc_findings)
        except InputError as error:
            findings.append(Finding(id="exceptions.input-error", severity="fatal", branch="exceptions", message=str(error)))

    if only in (None, "guards"):
        try:
            entries, model_findings = load_threat_model(root / args.threat_model)
            findings.extend(model_findings)
            guard_findings = check_guards(entries, root)
            if exceptions_available:
                guard_findings = _apply_exceptions(guard_findings, live_exceptions)
            findings.extend(guard_findings)
        except InputError as error:
            findings.append(Finding(id="guards.input-error", severity="fatal", branch="guards", message=str(error)))

    if only in (None, "dependencies"):
        try:
            dep_findings = check_dependencies(root / args.requirements)
            if exceptions_available:
                dep_findings = _apply_exceptions(dep_findings, live_exceptions)
            findings.extend(dep_findings)
        except InputError as error:
            findings.append(Finding(id="dependencies.input-error", severity="fatal", branch="dependencies", message=str(error)))

    if only in (None, "secrets"):
        secret_findings = check_secrets_delegate(root, args.secrets_cmd)
        if exceptions_available:
            secret_findings = _apply_exceptions(secret_findings, live_exceptions)
        findings.extend(secret_findings)

    if any(f.severity == "fatal" for f in findings):
        exit_code = 2
    elif any(f.severity == "critical" for f in findings):
        exit_code = 1
    else:
        exit_code = 0

    output = render_json(findings) if args.format == "json" else render_text(findings)
    return exit_code, output


def main(argv: list[str]) -> int:
    exit_code, output = run(argv)
    print(output)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
