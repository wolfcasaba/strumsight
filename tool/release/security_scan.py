#!/usr/bin/env python3
"""Fail-closed release security scan (ADR 0481).

Binds the program-level threat model (`docs/security/threat-model.md`) to
machine-checkable evidence. Four independent branches:

  guards        — every `release_gate: true` countermeasure in the threat
                  model names a `guard` (a file path and, where meaningful,
                  a test name); this branch measures that the guard still
                  RESOLVES on the tree (ADR 0481 D2): the file exists, is
                  inside the repo root, at least one `release_gate: true`
                  entry exists at all (an empty or gate-less model is a
                  critical finding, not a clean scan), and — where a `test`
                  is named — that test is present, uncommented, and not
                  `skip`/`xfail`-marked, INCLUDING a file-wide silencer (a
                  Python module-level `pytestmark = pytest.mark.skip(...)`,
                  a bare module-level `pytest.skip(..., allow_module_level=
                  True)` call, a class-level `@pytest.mark.skip`/`xfail`
                  decorator on the guard test's own class, or a Dart
                  `@Skip(...)` annotation above the file's first
                  import/export/part/library directive, with or without an
                  explicit `library;` line, or a Dart `group(..., skip:
                  true)` wrapping the test. It does
                  NOT re-implement the
                  protections themselves — replay, path traversal, oversize
                  payloads and model-checksum integrity are already measured
                  by the tests the guards point at.
  exceptions    — validates `docs/security/exceptions.yaml` (every entry
                  needs `owner`, `expires`, `branch`, `finding`, `reason` —
                  ADR 0481 D4) and applies still-live entries to suppress
                  the finding they name — but ONLY on the branch (`guards`
                  or `dependencies`) the entry itself declares.
  dependencies  — every line in the given requirements file must carry an
                  upper version bound, and is checked against a short,
                  dated, real advisory list (ADR 0481 §5.3).
  secrets       — DELEGATES to `tool/ci/check_secrets.dart` (the one source
                  of secret patterns, ADR 0138/0481 D3). This branch never
                  declares a second regex set; a secrets command that
                  cannot run, or exits non-zero, is itself a critical
                  finding — never a silent "skipped". Its findings are
                  NEVER exception-suppressible, in any `--only` mode: the
                  secret gate is a fail-closed delegation, not a risk
                  anyone can accept away (D3).

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
guard whose test was renamed CAN be waved away, but only by an exceptions
entry that names that exact `branch: guards` and the exact finding id — an
entry scoped to `dependencies` (or any other value) never reaches it, and
no entry, of any branch, ever reaches `secrets` (see above).
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
    gated_entries = [entry for entry in entries if entry.release_gate]
    if not gated_entries:
        # A threat model that parses but names zero `release_gate: true`
        # countermeasures cannot prove anything — the `check_secrets_test.dart`
        # L220 failure class ("found no input, therefore clean") generalized
        # to a present-but-empty document (MINOR-3).
        return [
            Finding(
                id="guards.no-release-gate-entries",
                severity="critical",
                branch="guards",
                message=(
                    "the threat model has zero `release_gate: true` guard "
                    "blocks — an empty or gate-less document is a critical "
                    "finding, not a clean scan"
                ),
            )
        ]

    resolved_root = root.resolve()
    findings: list[Finding] = []
    for entry in gated_entries:
        guard_path = root / entry.guard_path
        resolved_guard = guard_path.resolve()
        if not resolved_guard.is_relative_to(resolved_root):
            findings.append(
                Finding(
                    id=entry.id,
                    severity="critical",
                    branch="guards",
                    message=(
                        f"{entry.id} ({entry.component}): guard.path escapes "
                        f"the repo root: {entry.guard_path}"
                    ),
                )
            )
            continue
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
            if guard_path.suffix == ".py":
                py_stripped = _strip_python_trivia(guard_text)
                found, disabled = _python_guard_status(py_stripped, entry.guard_test)
                disabled = disabled or (
                    found
                    and (
                        _python_module_skip_disabled(py_stripped)
                        or _python_class_skip_disabled(py_stripped, entry.guard_test)
                    )
                )
            else:
                dart_stripped = _strip_dart_comments(guard_text)
                found, disabled = _dart_guard_status(dart_stripped, entry.guard_test)
                disabled = disabled or (found and _dart_file_skipped(dart_stripped))
            if not found:
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
            elif disabled:
                findings.append(
                    Finding(
                        id=entry.id,
                        severity="critical",
                        branch="guards",
                        message=(
                            f"{entry.id} ({entry.component}): guard.test "
                            f"{entry.guard_test!r} is present but disabled "
                            f"(skip/xfail marker) in {entry.guard_path} — a "
                            "silenced protection is release-blocking, not a "
                            "silent regression (ADR 0481 D2)"
                        ),
                    )
                )
    return findings


# ---------------------------------------------------------------------------
# guard.test resolution — trivia-aware, so a commented-out or skip-marked
# protection cannot masquerade as a live one (MAJOR-2). The comment/string
# stripping mirrors the repo's own trivia convention
# (`test/core/architecture_dependency_test.dart:1227` `_withoutTrivia`).
# ---------------------------------------------------------------------------

_PY_SKIP_MARKERS = (
    "@pytest.mark.skip",
    "@pytest.mark.xfail",
    "@unittest.skip",
    "pytest.skip(",
)
_DART_SKIP_MARKERS = ("skip:", "@Skip(")
_DART_TEST_CALL = re.compile(r"\btest\(")


def _strip_python_trivia(text: str) -> str:
    """Removes `#` comments and string-literal contents from Python source
    so a commented-out or docstring-quoted `def <name>(` cannot count as a
    live guard."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "#":
            newline = text.find("\n", i)
            i = n if newline == -1 else newline
            continue
        if ch in "'\"":
            triple = text[i : i + 3] == ch * 3
            delimiter = ch * 3 if triple else ch
            i += len(delimiter)
            while i < n and text[i : i + len(delimiter)] != delimiter:
                i += 2 if text[i] == "\\" and i + 1 < n else 1
            i += len(delimiter)
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _strip_dart_comments(text: str) -> str:
    """Removes `//` and `/* */` comments only. Dart string CONTENTS stay
    intact — the `test('<name>', ...)` needle itself lives inside a string
    literal, so masking strings would defeat the search."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        if text[i : i + 2] == "//":
            newline = text.find("\n", i)
            i = n if newline == -1 else newline
            continue
        if text[i : i + 2] == "/*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if text[i : i + 2] == "/*":
                    depth += 1
                    i += 2
                elif text[i : i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        ch = text[i]
        if ch in "'\"":
            start = i
            triple = text[i : i + 3] == ch * 3
            delimiter = ch * 3 if triple else ch
            i += len(delimiter)
            while i < n and text[i : i + len(delimiter)] != delimiter:
                i += 2 if text[i] == "\\" and i + 1 < n else 1
            i = min(i + len(delimiter), n)
            out.append(text[start:i])
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _python_guard_status(stripped: str, guard_test: str) -> tuple[bool, bool]:
    """Returns (found, disabled). The needle is CLOSED (`def <name>(`) so a
    suffix-renamed test (`..._v2(`) no longer slips through as a substring
    of the original name."""
    needle = f"def {guard_test}("
    idx = stripped.find(needle)
    if idx == -1:
        return False, False
    prelude = stripped[max(0, idx - 400) : idx]
    disabled = any(marker in prelude for marker in _PY_SKIP_MARKERS)
    return True, disabled


def _dart_call_span(text: str, call_start: int) -> str:
    """Returns the full `test(...)` call text starting at `call_start`,
    balancing parens while skipping over string-literal contents, so a
    `skip:` argument anywhere inside a multi-line call is still seen."""
    n = len(text)
    open_paren = text.find("(", call_start)
    if open_paren == -1:
        return text[call_start:]
    i = open_paren
    depth = 0
    while i < n:
        ch = text[i]
        if ch in "'\"":
            triple = text[i : i + 3] == ch * 3
            delimiter = ch * 3 if triple else ch
            i += len(delimiter)
            while i < n and text[i : i + len(delimiter)] != delimiter:
                i += 2 if text[i] == "\\" and i + 1 < n else 1
            i += len(delimiter)
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[call_start : i + 1]
        i += 1
    return text[call_start:]


def _dart_guard_status(stripped: str, guard_test: str) -> tuple[bool, bool]:
    """Returns (found, disabled) for a Dart `test('<guard_test>', ...)`
    call. `found` joins consecutive, Dart-auto-concatenated string literals
    right after `test(` (`'part one '` \\n `'part two'`) so a name split
    across lines still resolves. `disabled` is True when that same call
    carries a `skip:` argument, or an `@Skip(` annotation sits immediately
    above it."""
    n = len(stripped)
    for match in _DART_TEST_CALL.finditer(stripped):
        i = match.end()
        while i < n and stripped[i].isspace():
            i += 1
        parts: list[str] = []
        while i < n and stripped[i] in "'\"":
            quote = stripped[i]
            triple = stripped[i : i + 3] == quote * 3
            delimiter = quote * 3 if triple else quote
            i += len(delimiter)
            start = i
            while i < n and stripped[i : i + len(delimiter)] != delimiter:
                i += 2 if stripped[i] == "\\" and i + 1 < n else 1
            parts.append(stripped[start:i])
            i += len(delimiter)
            while i < n and stripped[i].isspace():
                i += 1
        if not parts or "".join(parts) != guard_test:
            continue
        call_text = _dart_call_span(stripped, match.start())
        prelude = stripped[max(0, match.start() - 200) : match.start()]
        disabled = (
            any(marker in call_text for marker in _DART_SKIP_MARKERS)
            or "@Skip(" in prelude
            or _dart_enclosing_group_skipped(stripped, match.start())
        )
        return True, disabled
    return False, False


# ---------------------------------------------------------------------------
# file/group-level elnémítás (S8) — a fenti `_python_guard_status` /
# `_dart_guard_status` csak a névre illeszkedő def/test hívás KÖZVETLEN
# környezetét nézi; egy modul-szintű `pytestmark`, egy Dart library-szintű
# `@Skip(`, vagy egy körülölelő `group(..., skip: true)` ugyanúgy elnémít
# egy egyébként jelen lévő, dekorálatlan tesztet, csak nem a hívás mellett.
# ---------------------------------------------------------------------------

_PY_MODULE_SKIP_MARKERS = ("pytest.mark.skip", "pytest.mark.xfail")
_PY_PYTESTMARK_ASSIGN = re.compile(r"(?m)^[ \t]*pytestmark\s*=\s*")
# Column-0 (NOT indented) — a `pytest.skip(...)` call inside a function/test
# body is always indented, so an unindented one can only be a real
# module-level statement (S11). pytest itself additionally requires
# `allow_module_level=True` on such a call (otherwise it raises instead of
# skipping) — either way the module fails to collect its tests, so this
# does not gate on that keyword being present.
_PY_MODULE_LEVEL_SKIP_CALL = re.compile(r"(?m)^pytest\.skip\(")


def _python_module_skip_disabled(stripped: str) -> bool:
    """True when a module-level `pytestmark = pytest.mark.skip(...)` (or
    `.xfail(...)`, bare or inside a `pytestmark = [...]` list), OR a bare
    module-level `pytest.skip(..., allow_module_level=True)` call, sits
    ANYWHERE in the module — either silences every test the module defines,
    not just one near the assignment/call (S8, and S11's `pytest.skip(`
    variant, which `pytestmark` alone does not catch)."""
    if _PY_MODULE_LEVEL_SKIP_CALL.search(stripped):
        return True
    n = len(stripped)
    for match in _PY_PYTESTMARK_ASSIGN.finditer(stripped):
        start = match.end()
        if start < n and stripped[start] == "[":
            depth, i = 0, start
            while i < n:
                if stripped[i] == "[":
                    depth += 1
                elif stripped[i] == "]":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            value = stripped[start:i]
        else:
            newline = stripped.find("\n", start)
            value = stripped[start:] if newline == -1 else stripped[start:newline]
        if any(marker in value for marker in _PY_MODULE_SKIP_MARKERS):
            return True
    return False


_PY_CLASS_DEF = re.compile(r"(?m)^class\s+\w+")
_PY_CLASS_SKIP_MARKERS = ("@pytest.mark.skip", "@pytest.mark.xfail", "@unittest.skip")


def _python_class_skip_disabled(stripped: str, guard_test: str) -> bool:
    """True when the `def <guard_test>(` belongs to a top-level class whose
    OWN class-level skip/xfail decorator sits directly above the class —
    checked independent of distance from the class to the method, so a
    class skipped thousands of bytes above its guarded method counts
    exactly like one immediately above it (S12, which the `def`-local
    400-byte prelude window in `_python_guard_status` cannot reach)."""
    def_idx = stripped.find(f"def {guard_test}(")
    if def_idx == -1:
        return False
    class_start = None
    for match in _PY_CLASS_DEF.finditer(stripped, 0, def_idx):
        class_start = match.start()
    if class_start is None:
        return False
    lines = stripped[:class_start].splitlines()
    idx = len(lines) - 1
    disabled = False
    while idx >= 0:
        line = lines[idx].strip()
        if not line.startswith("@"):
            break
        if any(marker in line for marker in _PY_CLASS_SKIP_MARKERS):
            disabled = True
        idx -= 1
    return disabled


_DART_SKIP_ANNOTATION = re.compile(r"@Skip\(")
_DART_DIRECTIVE = re.compile(r"(?m)^[ \t]*(?:library|import|part|export)\b")


def _dart_file_skipped(stripped: str) -> bool:
    """True when an `@Skip(...)` annotation sits anywhere before the file's
    FIRST directive (`library`/`import`/`part`/`export`) — this silences
    every test the file declares, not just one local to a single `test(`
    call (S8, and S10's `library;`-less variant).

    `package:test` reads the metadata of the file's first DIRECTIVE, not
    specifically a `library` one (`test_core`'s `parse_metadata.dart`:
    `_annotations = directives.isEmpty ? [] : directives.first.metadata`) —
    so `@Skip('…')` placed directly above the first `import` is a fully
    valid, and just as silent, file-wide skip; the `library;`-prefixed form
    is only ONE of the shapes this idiom takes (S10).

    Restricted to the text BEFORE that first directive — real placements
    never occur later, since Dart requires any directive-level annotation to
    precede all directives. If the file has NO directive at all, `test_core`
    has nothing to read `.first.metadata` from, so no file-wide skip is
    possible via this mechanism and this returns False rather than treating
    the whole file as header — which also keeps the check from matching an
    `@Skip(...)` shape that merely appears inside a later string literal —
    e.g. this scan's own test fixtures for this branch, string-embedded in
    `security_scan_test.dart`, whose own guard.path is this same file."""
    boundary = _DART_DIRECTIVE.search(stripped)
    if boundary is None:
        return False
    header = stripped[: boundary.start()]
    return bool(_DART_SKIP_ANNOTATION.search(header))


_DART_GROUP_CALL = re.compile(r"\bgroup\(")


def _dart_call_head(text: str, call_start: int) -> str:
    """Returns the ARGUMENT HEAD of the call starting at `call_start` — the
    text between its opening `(` and the zero-arg callback param list `()`
    that `group`/`test` always take as their body (`() {`/`() async {`) —
    with string-literal contents stripped out entirely. Every fixture and
    real usage on this tree writes named arguments (like `skip: true`)
    BEFORE that callback (`group('d', skip: true, () {...})`), so this is
    where a group's OWN `skip:` argument lives. Text belonging to the
    callback BODY — a sibling test's own `skip:` argument, or a `skip:`-
    shaped substring inside a description string — is excluded (S13)."""
    n = len(text)
    open_paren = text.find("(", call_start)
    if open_paren == -1:
        return ""
    i = open_paren + 1
    depth = 1
    out: list[str] = []
    while i < n:
        ch = text[i]
        if ch in "'\"":
            triple = text[i : i + 3] == ch * 3
            delimiter = ch * 3 if triple else ch
            i += len(delimiter)
            while i < n and text[i : i + len(delimiter)] != delimiter:
                i += 2 if text[i] == "\\" and i + 1 < n else 1
            i += len(delimiter)
            continue
        if depth == 1 and text[i : i + 2] == "()":
            break
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
        i += 1
    return "".join(out)


def _dart_enclosing_group_skipped(stripped: str, call_start: int) -> bool:
    """True when a `group(...)` call enclosing the `test(` call at
    `call_start` carries its own `skip:` argument in its OWN argument head
    — a group-level skip silences every test nested inside it even though
    the test's own call carries no marker (S8). Narrowed to the group's
    argument head (`_dart_call_head`), not its full body text, so a NESTED
    sibling test's own `skip:` argument, or a `skip:`-shaped substring
    inside a description string, is never mistaken for the group's own
    named argument (S13)."""
    for match in _DART_GROUP_CALL.finditer(stripped, 0, call_start):
        span = _dart_call_span(stripped, match.start())
        if match.start() + len(span) > call_start:
            if "skip:" in _dart_call_head(stripped, match.start()):
                return True
    return False


# ---------------------------------------------------------------------------
# exceptions branch
# ---------------------------------------------------------------------------

_REQUIRED_EXCEPTION_KEYS = ("owner", "expires", "finding", "reason", "branch")
# Only these two branches can ever be suppressed by an exception — `secrets`
# is deliberately absent: the secret gate is a fail-closed delegation, and
# no exceptions entry, of any shape, can wave it away (ADR 0481 D3).
_EXCEPTABLE_BRANCHES = {"guards", "dependencies"}


def load_exceptions(
    path: Path, today: dt.date
) -> tuple[dict[tuple[str, str], dict], list[Finding]]:
    """Returns (live_exceptions_by_branch_and_finding_id, hygiene_findings).

    Raises `InputError` for structural failures (missing file, invalid YAML,
    a document whose top-level shape is not `{exceptions: [...]}`). A
    well-formed entry missing `owner`/`expires`/`branch`/`finding`/`reason`,
    one naming a branch other than `guards`/`dependencies`, or one that has
    already expired, is a critical `Finding` instead (ADR 0481 D4) — the
    registry keeps loading, so one bad entry does not hide the rest. The key
    is `(branch, finding)`, not just `finding`: an exception only ever
    suppresses a finding of that id on that SAME branch, so a
    `dependencies`-scoped entry can never silence a `guards` finding (or
    vice-versa) that happens to share an id.
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

    live: dict[tuple[str, str], dict] = {}
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
                        f"{missing} — an exception without owner+expires+"
                        "branch does not exist (ADR 0481 D4)"
                    ),
                )
            )
            continue
        entry_branch = entry["branch"]
        if entry_branch not in _EXCEPTABLE_BRANCHES:
            findings.append(
                Finding(
                    id="exceptions.invalid-branch",
                    severity="critical",
                    branch="exceptions",
                    message=(
                        f"exceptions[{index}] (finding={entry['finding']!r}): "
                        f"branch {entry_branch!r} is not exceptable — only "
                        f"{sorted(_EXCEPTABLE_BRANCHES)} findings can ever be "
                        "suppressed; `secrets` can never be waved away "
                        "(ADR 0481 D3)"
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
        live[(entry_branch, str(entry["finding"]))] = entry
    return live, findings


def _apply_exceptions(
    findings: list[Finding], live: dict[tuple[str, str], dict], branch: str
) -> list[Finding]:
    """Suppresses a finding only when a LIVE exception names this exact
    `branch` and the finding's own id — a `dependencies`-scoped entry never
    reaches a `guards` finding of the same id, or vice-versa (MAJOR-1)."""
    if not live:
        return findings
    return [f for f in findings if (branch, f.id) not in live]


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

    live_exceptions: dict[tuple[str, str], dict] = {}
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
                guard_findings = _apply_exceptions(guard_findings, live_exceptions, "guards")
            findings.extend(guard_findings)
        except InputError as error:
            findings.append(Finding(id="guards.input-error", severity="fatal", branch="guards", message=str(error)))

    if only in (None, "dependencies"):
        try:
            dep_findings = check_dependencies(root / args.requirements)
            if exceptions_available:
                dep_findings = _apply_exceptions(dep_findings, live_exceptions, "dependencies")
            findings.extend(dep_findings)
        except InputError as error:
            findings.append(Finding(id="dependencies.input-error", severity="fatal", branch="dependencies", message=str(error)))

    if only in (None, "secrets"):
        # No exception suppression here, ever (D3) — see the module
        # docstring and MAJOR-1: the secret gate is a fail-closed
        # delegation, not a risk anyone can accept away via exceptions.yaml.
        findings.extend(check_secrets_delegate(root, args.secrets_cmd))

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
