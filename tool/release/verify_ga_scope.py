#!/usr/bin/env python3
"""GA-scope consistency verifier (E12-R28, ADR 0489).

Validates `docs/release/ga-scope.md` (and its companion
`docs/release/contract-freeze.md`) against three MEASURED sources of truth:

  * `docs/beta/cohort-profiles.yaml` — the closed set of capabilities this
    round classifies is exactly this file's flag-key set (ADR 0489 D1).
  * `docs/release/blockers.md` — whether an open P0/P1 blocker forces the
    GA-scope header into an explicit NOT-READY state (D7).
  * the classification table itself — every row's `evidence` column must
    name a repo-relative path that actually resolves on this tree (D3),
    every classification must be one of the closed four values (D2), a
    `disabled` classification must match a cohort profile where the flag is
    `false` in EVERY cohort (D4), and every capability a core-path row names
    as required must be classified `ga` (D5).

`docs/release/contract-freeze.md` is validated separately: every row must
carry a non-empty resolution condition, and that condition may not be one of
the three banned non-events named in ADR 0489 D6 (or their English
equivalents) — a non-empty-but-vague condition is exactly the failure mode
D6 exists to catch, so this is a substring ban list, not just a
non-emptiness check.

Two independently-disciplined parsers, on purpose (L566 — a hand-written
line parser defaults to fail-OPEN; what does not match the expected shape
must be an error, never a silent skip):

  * The cohort profile is real YAML, parsed with PyYAML (`import yaml` at
    module scope, a hard dependency — precedent `tool/release/
    verify_beta_profile.py`, itself following `tool/release/
    build_ai_report.py`; the fan measured `PyYAML 6.0.1` on this tree).
  * `ga-scope.md`, `contract-freeze.md` and `blockers.md` cannot be executed
    from here, so each is read with a regex tuned to its own fixed table
    shape. Every parse is fail-closed: every non-header, non-separator line
    inside a marker block is a required data row, and it must fully match
    that table's row shape — one that does not is a `VerifyError` naming
    the offending line, never a silently-dropped row (E12-R28 MAJOR-1: a
    core-path row that missed only the looser pre-filter, not the row
    shape itself, used to vanish with no error and no effect on any count).
  * `docs/release/ga-scope.md`'s capability table also carries a
    `production_default` column, cross-checked against a fail-closed read
    of `lib/app/config/feature_flags.dart`'s `FeatureFlags.forEnvironment`
    body (E12-R28 MAJOR-2): a documented `ga` classification is not enough
    on its own — production must actually default the flag on, or the row
    must name a checkable unlock condition in its `note` column.

Exit codes:
  0  every check passed
  1  a validation rule failed (D1 missing/duplicate/unknown key, D2 unknown
     classification, D3 dangling evidence path, D4 disabled/profile
     mismatch, D5 a non-`ga` capability required by the core path, D6 empty
     or banned-phrase resolution condition, D7 NOT-READY header missing
     while a P0/P1 blocker is open, a `production_default` column that
     disagrees with the measured `FeatureFlags.forEnvironment` default, or
     a `ga` capability whose measured production default is `false` with no
     named production-unlock condition — MAJOR-2)
  2  usage or format error: a missing/malformed file, a table row that does
     not match the expected shape, a `FeatureFlags.forEnvironment` field
     assignment whose shape this reader does not recognize, or a profile
     whose YAML does not decode to the expected shape
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

DEFAULT_SCOPE_PATH = Path("docs/release/ga-scope.md")
DEFAULT_PROFILE_PATH = Path("docs/beta/cohort-profiles.yaml")
DEFAULT_CONTRACT_FREEZE_PATH = Path("docs/release/contract-freeze.md")
DEFAULT_BLOCKERS_PATH = Path("docs/release/blockers.md")
DEFAULT_FEATURE_FLAGS_PATH = Path("lib/app/config/feature_flags.dart")

_CLOSED_CLASSIFICATIONS = {"ga", "preview", "disabled", "postponed"}

# ADR 0489 D6's three named non-events, plus their direct English
# equivalents — a resolution condition matching any of these (case-
# insensitive substring) is not a named, checkable event.
_BANNED_RESOLUTION_PHRASES = [
    "szükség esetén módosítható",
    "a csapat döntése alapján",
    "későbbi körben újratárgyalható",
    "as needed",
    "team's decision",
    "team decision",
    "renegotiable in a later round",
]

_NOT_READY_MARKER = re.compile(r"állapot\s*:\s*nem kész", re.IGNORECASE)
_GA_READY_CLAIM = re.compile(r"\bga[\s-]*kész\b", re.IGNORECASE)

# A `ga`-classified capability whose measured production_default is `false`
# must name its unlock condition in the capability row's `note` column,
# introduced by this literal marker (E12-R28 MAJOR-2).
_PRODUCTION_UNLOCK_MARKER = re.compile(r"Production unlock:\s*(?P<condition>.+)$")

_ALLOWED_COHORT_KEYS = {"id", "description", "versionRange", "maxTesters", "flags"}


class VerifyError(Exception):
    """A usage/format error (exit 2) — parsing could not even determine
    what to check, as opposed to a validation finding (exit 1)."""


class Finding(str):
    """A validation finding (exit 1) — parsing succeeded, a rule failed."""


# ---------------------------------------------------------------------------
# docs/beta/cohort-profiles.yaml (PyYAML, precedent verify_beta_profile.py)
# ---------------------------------------------------------------------------


def _require_cohort_shape(entry: object, *, where: str) -> dict:
    if not isinstance(entry, dict):
        raise VerifyError(f"{where}: a cohort entry must be a mapping")
    unknown_keys = set(entry.keys()) - _ALLOWED_COHORT_KEYS
    if unknown_keys:
        raise VerifyError(
            f"{where}: cohort entry has unrecognized key(s) {sorted(unknown_keys)!r}"
        )
    cohort_id = entry.get("id")
    if not isinstance(cohort_id, str) or not cohort_id:
        raise VerifyError(f"{where}: cohort entry is missing a non-empty \"id\"")
    flags = entry.get("flags")
    if not isinstance(flags, dict) or not flags:
        raise VerifyError(
            f"{where}: cohort {cohort_id!r} is missing a non-empty \"flags\" mapping"
        )
    for flag_key, flag_value in flags.items():
        if not isinstance(flag_key, str) or not flag_key:
            raise VerifyError(f"{where}: cohort {cohort_id!r} has a non-string flag key")
        if not isinstance(flag_value, bool):
            raise VerifyError(
                f"{where}: cohort {cohort_id!r} flag {flag_key!r} must map to a "
                f"boolean, got {flag_value!r}"
            )
    return entry


def load_profile(path: Path) -> dict[str, dict]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            document = yaml.safe_load(handle)
    except FileNotFoundError as error:
        raise VerifyError(f"profile not found: {path}") from error
    except yaml.YAMLError as error:
        raise VerifyError(f"{path} is not valid YAML: {error}") from error

    if not isinstance(document, dict):
        raise VerifyError(f"{path} does not decode to a mapping")
    cohorts = document.get("cohorts")
    if not isinstance(cohorts, list) or not cohorts:
        raise VerifyError(f"{path}: missing a non-empty \"cohorts\" list")

    parsed: dict[str, dict] = {}
    for entry in cohorts:
        cohort = _require_cohort_shape(entry, where=str(path))
        cohort_id = cohort["id"]
        if cohort_id in parsed:
            raise VerifyError(f"{path}: duplicate cohort id {cohort_id!r}")
        parsed[cohort_id] = cohort
    return parsed


def profile_flag_keys(profile: dict[str, dict]) -> set[str]:
    keys: set[str] = set()
    for cohort in profile.values():
        keys.update(cohort["flags"].keys())
    return keys


# ---------------------------------------------------------------------------
# docs/release/ga-scope.md — fail-closed table + header parser
# ---------------------------------------------------------------------------

# `| `flagKey` | `classification` | `productionDefault` | `evidence/path` | free-text note |`
_CAPABILITY_ROW = re.compile(
    r"^\|\s*`(?P<key>[^`]+)`\s*\|\s*`(?P<classification>[^`]+)`\s*\|\s*"
    r"`(?P<production_default>[^`]+)`\s*\|\s*`(?P<evidence>[^`]+)`\s*\|\s*"
    r"(?P<note>.*?)\s*\|\s*$"
)

# `| step text | `capabilityKey` | `evidence/path` |`
_CORE_PATH_ROW = re.compile(
    r"^\|\s*(?P<step>[^|`][^|]*)\|\s*`(?P<capability>[^`]+)`\s*\|\s*"
    r"`(?P<evidence>[^`]+)`\s*\|\s*$"
)


def _extract_table(
    text: str, *, begin_marker: str, end_marker: str, path: Path
) -> list[tuple[int, str]]:
    lines = text.splitlines()
    begin_index = end_index = None
    for index, line in enumerate(lines):
        if begin_marker in line:
            begin_index = index
        elif end_marker in line and begin_index is not None:
            end_index = index
            break
    if begin_index is None or end_index is None:
        raise VerifyError(
            f"{path}: markers {begin_marker!r}/{end_marker!r} not found or out of order"
        )
    return [
        (line_number, line)
        for line_number, line in enumerate(lines[begin_index + 1 : end_index], start=begin_index + 2)
        if line.strip().startswith("|")
    ]


def _parse_table(
    rows: list[tuple[int, str]],
    *,
    row_pattern: re.Pattern,
    path: Path,
    header_prefixes: tuple[str, ...],
) -> list[tuple[int, re.Match]]:
    """Every `|`-starting, non-header, non-separator line is a REQUIRED data
    row (E12-R28 MAJOR-1): what does not fully match `row_pattern` is a
    `VerifyError` naming the line, never a silently-dropped row. There is no
    separate, looser "is this even a data row" pre-filter — a row that
    misses the shape a hair (a missing leading space, a step cell that
    starts with a backtick) used to vanish into that pre-filter with no
    error and no effect on any reported count; it now fails loud."""
    parsed: list[tuple[int, re.Match]] = []
    for line_number, line in rows:
        stripped = line.strip()
        if stripped.startswith(header_prefixes) or set(stripped.replace("|", "").strip()) <= {"-", " "}:
            continue
        match = row_pattern.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: table row does not match the expected "
                f"shape — {line!r}"
            )
        parsed.append((line_number, match))
    return parsed


def load_ga_scope(path: Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"scope document not found: {path}") from error

    header_text = text.split("<!-- ga-scope-capabilities:begin -->", 1)[0]
    not_ready = bool(_NOT_READY_MARKER.search(header_text))
    ga_ready_claim = bool(_GA_READY_CLAIM.search(header_text))

    capability_rows = _extract_table(
        text,
        begin_marker="<!-- ga-scope-capabilities:begin -->",
        end_marker="<!-- ga-scope-capabilities:end -->",
        path=path,
    )
    capabilities = _parse_table(
        capability_rows,
        row_pattern=_CAPABILITY_ROW,
        path=path,
        header_prefixes=("| flag_key", "| `flag_key`"),
    )

    core_path_rows = _extract_table(
        text,
        begin_marker="<!-- ga-scope-core-path:begin -->",
        end_marker="<!-- ga-scope-core-path:end -->",
        path=path,
    )
    core_path = _parse_table(
        core_path_rows,
        row_pattern=_CORE_PATH_ROW,
        path=path,
        header_prefixes=("| step", "| Step"),
    )

    return {
        "not_ready": not_ready,
        "ga_ready_claim": ga_ready_claim,
        "capabilities": capabilities,
        "core_path": core_path,
    }


# ---------------------------------------------------------------------------
# lib/app/config/feature_flags.dart — fail-closed FeatureFlags.forEnvironment
# production-default reader (E12-R28 MAJOR-2)
# ---------------------------------------------------------------------------

_FOR_ENVIRONMENT_FACTORY_MARKER = "factory FeatureFlags.forEnvironment("
_FOR_ENVIRONMENT_RETURN_MARKER = "return FeatureFlags("
_FOR_ENVIRONMENT_CLOSE_MARKER = "\n    );"
_FIELD_ASSIGNMENT = re.compile(r"^(?P<key>[a-zA-Z_][a-zA-Z0-9_]*):\s*(?P<rest>.*)$")


def _extract_for_environment_field_assignments(
    text: str, *, path: Path
) -> dict[str, str]:
    """Join `FeatureFlags.forEnvironment`'s `return FeatureFlags(...)` call
    into one raw right-hand-side string per field. A multi-line assignment
    (`const bool.fromEnvironment(...)` wraps its define name onto its own
    line for the Community flags) is joined; a `//` comment-only line
    between fields is dropped, never merged into a neighboring value. Any
    line that is neither a `field: value` start nor a continuation of one
    is a `VerifyError` — fail-closed, per MAJOR-1's same principle."""
    factory_index = text.find(_FOR_ENVIRONMENT_FACTORY_MARKER)
    if factory_index == -1:
        raise VerifyError(f"{path}: `{_FOR_ENVIRONMENT_FACTORY_MARKER}` not found")
    return_index = text.find(_FOR_ENVIRONMENT_RETURN_MARKER, factory_index)
    if return_index == -1:
        raise VerifyError(
            f"{path}: `{_FOR_ENVIRONMENT_RETURN_MARKER}` not found after the "
            "forEnvironment factory"
        )
    body_start = return_index + len(_FOR_ENVIRONMENT_RETURN_MARKER)
    close_index = text.find(_FOR_ENVIRONMENT_CLOSE_MARKER, body_start)
    if close_index == -1:
        raise VerifyError(
            f"{path}: no matching `{_FOR_ENVIRONMENT_CLOSE_MARKER.strip()}` "
            "found for the forEnvironment return call"
        )
    body = text[body_start:close_index]

    fields: dict[str, str] = {}
    current_key: str | None = None
    current_parts: list[str] = []

    def _flush() -> None:
        if current_key is not None:
            fields[current_key] = " ".join(current_parts).strip()

    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        match = _FIELD_ASSIGNMENT.match(line)
        if match:
            _flush()
            current_key = match.group("key")
            current_parts = [match.group("rest")]
        elif current_key is not None:
            current_parts.append(line)
        else:
            raise VerifyError(
                f"{path}: forEnvironment return body has a line that is "
                f"neither a `field: value` assignment nor a continuation of "
                f"one — {raw_line!r}"
            )
    _flush()
    return fields


def _resolve_production_default(key: str, raw_value: str, *, path: Path) -> bool | None:
    """Fail-closed classification of one field's right-hand-side text into
    its measured PRODUCTION default. Exactly four shapes are recognized;
    anything else is a `VerifyError` naming the field, never a silent guess:

      * `nonProd` — production means non-production is `false`.
      * a literal `true`/`false`.
      * `const bool.fromEnvironment(...)` — the measured Dart default is
        `false` unless the same call also passes `defaultValue: true`.
      * a bare pass-through identical to the field's own name — the value
        comes from the caller, not from this file (today's sole instance is
        `accountEnabled`, sourced from `lib/core/api/api_config.dart`); this
        reader cannot measure it from `feature_flags.dart` alone, so it
        returns `None` rather than guessing.
    """
    value = raw_value.strip()
    if value.endswith(","):
        value = value[:-1].strip()
    if value == "nonProd":
        return False
    if value == "true":
        return True
    if value == "false":
        return False
    if value == key:
        return None
    if value.startswith("const bool.fromEnvironment("):
        return "defaultValue: true" in value
    raise VerifyError(
        f"{path}: FeatureFlags.forEnvironment assigns {key!r} = {raw_value!r}, "
        "an unrecognized shape for a fail-closed production-default read"
    )


def load_feature_flags_production_defaults(path: Path) -> dict[str, bool | None]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"feature-flags source not found: {path}") from error

    fields = _extract_for_environment_field_assignments(text, path=path)
    return {
        key: _resolve_production_default(key, raw_value, path=path)
        for key, raw_value in fields.items()
    }


# ---------------------------------------------------------------------------
# docs/release/contract-freeze.md — fail-closed table parser
# ---------------------------------------------------------------------------

# `| contract text | frozen scope text | `evidence/path` | resolution condition text |`
_FREEZE_ROW = re.compile(
    r"^\|\s*(?P<contract>[^|]+?)\s*\|\s*(?P<frozen_scope>[^|]+?)\s*\|\s*"
    r"`(?P<evidence>[^`]+)`\s*\|\s*(?P<condition>[^|]+?)\s*\|\s*$"
)


def load_contract_freeze(path: Path) -> list[tuple[int, re.Match]]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"contract-freeze document not found: {path}") from error

    rows = _extract_table(
        text,
        begin_marker="<!-- contract-freeze:begin -->",
        end_marker="<!-- contract-freeze:end -->",
        path=path,
    )
    return _parse_table(
        rows,
        row_pattern=_FREEZE_ROW,
        path=path,
        header_prefixes=("| contract", "| Contract"),
    )


# ---------------------------------------------------------------------------
# docs/release/blockers.md — severity column only, fail-closed row count
# ---------------------------------------------------------------------------

_BLOCKER_ID_START = re.compile(r"^\|\s*R-[A-Z0-9-]+\s*\|")
_BLOCKER_ROW = re.compile(r"^\|\s*(?P<id>R-[A-Z0-9-]+)\s*\|\s*(?P<severity>P[0-4])\s*\|")


def load_open_blockers(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"blockers document not found: {path}") from error

    ids: list[str] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not _BLOCKER_ID_START.match(stripped):
            continue
        match = _BLOCKER_ROW.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: blocker row does not match the expected "
                f"shape — {line!r}"
            )
        if match.group("severity") in {"P0", "P1"}:
            ids.append(match.group("id"))
    return ids


# ---------------------------------------------------------------------------
# Validation (D1-D7)
# ---------------------------------------------------------------------------


def validate_scope(
    scope: dict,
    *,
    profile: dict[str, dict],
    open_blockers: list[str],
    feature_flag_defaults: dict[str, bool | None],
) -> list[str]:
    findings: list[str] = []
    profile_keys = profile_flag_keys(profile)

    seen_keys: dict[str, int] = {}
    classification_by_key: dict[str, str] = {}
    for line_number, match in scope["capabilities"]:
        key = match.group("key")
        classification = match.group("classification")
        production_default_text = match.group("production_default")
        evidence = match.group("evidence")
        note = match.group("note")

        if key in seen_keys:
            findings.append(
                f"ga-scope.md:{line_number}: capability {key!r} classified more than "
                f"once (also line {seen_keys[key]}) (D1)"
            )
        seen_keys[key] = line_number
        classification_by_key[key] = classification

        if key not in profile_keys:
            findings.append(
                f"ga-scope.md:{line_number}: capability {key!r} is not a cohort-profile "
                "flag key (D1)"
            )

        if classification not in _CLOSED_CLASSIFICATIONS:
            findings.append(
                f"ga-scope.md:{line_number}: capability {key!r} has unknown "
                f"classification {classification!r} — must be one of "
                f"{sorted(_CLOSED_CLASSIFICATIONS)} (D2)"
            )

        if not Path(evidence).exists():
            findings.append(
                f"ga-scope.md:{line_number}: capability {key!r} evidence path "
                f"{evidence!r} does not exist on this tree (D3)"
            )

        if classification == "disabled":
            for cohort_id, cohort in profile.items():
                flag_value = cohort["flags"].get(key)
                if flag_value is True:
                    findings.append(
                        f"ga-scope.md:{line_number}: capability {key!r} is "
                        f"classified disabled but cohort {cohort_id!r} sets it "
                        "to true (D4)"
                    )

        # E12-R28 MAJOR-2: a `ga` classification is not enough on its own —
        # production must actually default the flag on, or the row must
        # name a checkable unlock condition. `production_default` is
        # documented AND cross-checked against the measured
        # `FeatureFlags.forEnvironment` default in feature_flags.dart.
        documented_default: bool | None = None
        if production_default_text not in {"true", "false"}:
            findings.append(
                f"ga-scope.md:{line_number}: capability {key!r} "
                f"production_default {production_default_text!r} must be "
                "`true` or `false`"
            )
        else:
            documented_default = production_default_text == "true"

        if key not in feature_flag_defaults:
            findings.append(
                f"ga-scope.md:{line_number}: capability {key!r} has no "
                "matching field in FeatureFlags.forEnvironment "
                "(lib/app/config/feature_flags.dart) — its production_default "
                "cannot be verified"
            )
        else:
            measured_default = feature_flag_defaults[key]
            if (
                measured_default is not None
                and documented_default is not None
                and measured_default != documented_default
            ):
                findings.append(
                    f"ga-scope.md:{line_number}: capability {key!r} "
                    f"production_default is documented as {documented_default} "
                    f"but the measured FeatureFlags.forEnvironment default in "
                    f"lib/app/config/feature_flags.dart is {measured_default}"
                )

        if classification == "ga" and documented_default is False:
            unlock_match = _PRODUCTION_UNLOCK_MARKER.search(note)
            condition = unlock_match.group("condition").strip() if unlock_match else ""
            if not condition:
                findings.append(
                    f"ga-scope.md:{line_number}: capability {key!r} is "
                    "classified ga with production_default false but its "
                    "note names no 'Production unlock:' condition"
                )
            else:
                lowered_condition = condition.lower()
                for banned in _BANNED_RESOLUTION_PHRASES:
                    if banned in lowered_condition:
                        findings.append(
                            f"ga-scope.md:{line_number}: capability {key!r}'s "
                            f"production-unlock condition matches a banned "
                            f"non-event ({banned!r}) — a named, checkable "
                            "event is required"
                        )
                        break

    missing_keys = profile_keys - set(seen_keys)
    for key in sorted(missing_keys):
        findings.append(
            f"ga-scope.md: cohort-profile flag key {key!r} has no classification "
            "row (D1)"
        )

    for line_number, match in scope["core_path"]:
        step_evidence = match.group("evidence")
        if not Path(step_evidence).exists():
            findings.append(
                f"ga-scope.md:{line_number}: core-path evidence path "
                f"{step_evidence!r} does not exist on this tree (D3)"
            )

        capability = match.group("capability")
        if capability == "none":
            # A core-path step this round measured as having NO dependency
            # on any of the 16 cohort-profile capabilities (D5 only
            # constrains steps that DO depend on one).
            continue
        classification = classification_by_key.get(capability)
        if classification is None:
            findings.append(
                f"ga-scope.md:{line_number}: core-path step requires capability "
                f"{capability!r}, which has no classification row (D5)"
            )
        elif classification != "ga":
            findings.append(
                f"ga-scope.md:{line_number}: core-path step requires capability "
                f"{capability!r}, classified {classification!r} — every "
                "core-path-required capability must be classified ga (D5)"
            )

    if open_blockers:
        if not scope["not_ready"]:
            findings.append(
                "ga-scope.md: open P0/P1 blocker(s) "
                f"({', '.join(open_blockers)}) exist, but the header carries no "
                "explicit NOT-READY marker (D7)"
            )
        if scope["ga_ready_claim"]:
            findings.append(
                "ga-scope.md: open P0/P1 blocker(s) "
                f"({', '.join(open_blockers)}) exist, but the header claims "
                "GA-kész (D7)"
            )

    return findings


def validate_contract_freeze(rows: list[tuple[int, re.Match]]) -> list[str]:
    findings: list[str] = []
    for line_number, match in rows:
        evidence = match.group("evidence")
        condition = match.group("condition").strip()

        if not Path(evidence).exists():
            findings.append(
                f"contract-freeze.md:{line_number}: evidence path {evidence!r} "
                "does not exist on this tree (D3)"
            )

        if not condition:
            findings.append(
                f"contract-freeze.md:{line_number}: empty resolution condition (D6)"
            )
            continue

        lowered = condition.lower()
        for banned in _BANNED_RESOLUTION_PHRASES:
            if banned in lowered:
                findings.append(
                    f"contract-freeze.md:{line_number}: resolution condition "
                    f"matches a banned non-event ({banned!r}) — a named, "
                    "checkable event is required (D6)"
                )
                break

    return findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", type=Path, default=DEFAULT_SCOPE_PATH)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE_PATH)
    parser.add_argument(
        "--contract-freeze", type=Path, default=DEFAULT_CONTRACT_FREEZE_PATH
    )
    parser.add_argument("--blockers", type=Path, default=DEFAULT_BLOCKERS_PATH)
    parser.add_argument(
        "--feature-flags", type=Path, default=DEFAULT_FEATURE_FLAGS_PATH
    )
    args = parser.parse_args(argv)

    try:
        profile = load_profile(args.profile)
        scope = load_ga_scope(args.scope)
        freeze_rows = load_contract_freeze(args.contract_freeze)
        open_blockers = load_open_blockers(args.blockers)
        feature_flag_defaults = load_feature_flags_production_defaults(
            args.feature_flags
        )
    except VerifyError as error:
        print(f"verify_ga_scope: {error}", file=sys.stderr)
        return 2

    findings = validate_scope(
        scope,
        profile=profile,
        open_blockers=open_blockers,
        feature_flag_defaults=feature_flag_defaults,
    )
    findings += validate_contract_freeze(freeze_rows)

    if findings:
        print(f"verify_ga_scope: {len(findings)} finding(s):", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1

    print(
        f"verify_ga_scope: ok — {len(scope['capabilities'])} capability "
        f"classification(s), {len(scope['core_path'])} core-path step(s), "
        f"{len(freeze_rows)} frozen contract(s), {len(open_blockers)} open "
        "P0/P1 blocker(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
