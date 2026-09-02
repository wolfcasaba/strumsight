#!/usr/bin/env python3
"""Closed Beta cohort-profile verifier (E12-R27, round brief §0.0.1 P2/P4).

Validates `docs/beta/cohort-profiles.yaml` against the MEASURED feature-flag
catalog `lib/core/feature_flags/feature_flag_registry.dart` (Kör 5, ADR
0446, 40 entries): every flag a cohort profile names must exist in that
catalog (A1/A2), and no `high`-risk flag may default to `true` in any
cohort (A3). A third mode, `--kill-switch`, is a READ-ONLY dry-run: it
prints a deterministic before/after view of one cohort with one flag forced
to `false`, and never writes to disk (round brief §0.0.1 P4).

Two independently-disciplined parsers, on purpose (L566 — a hand-written
line parser defaults to fail-OPEN; what does not match the expected shape
must be an error, never a silent skip):

  * The cohort profile is real YAML, parsed with PyYAML (`import yaml` at
    module scope, a hard dependency — precedent `tool/release/
    build_ai_report.py`, exercised green in CI via `test/tooling/
    ai_release_report_test.dart`'s full `flutter test` run).
  * The Dart registry cannot be executed from here, so it is read with a
    regex tuned to the fixed `key:`/`owner:`/`risk:`/`failClosedDefault:`
    field order every entry in the shipped file uses. The parse is
    fail-closed: the number of `FeatureFlagDefinition(` occurrences in the
    file must equal the number of entries the regex fully matched (a
    silently-unparsed entry is caught, not dropped), and a parse of fewer
    than 40 entries is itself an error, never a smaller catalog.

Exit codes:
  0  validation passed (default mode) or the kill-switch dry-run printed
     successfully (--kill-switch mode)
  1  the profile fails a validation rule (A1/A2 unknown flag, A3 a
     high-risk flag defaulting to true)
  2  usage or format error: a missing/malformed file, a registry parse that
     yields fewer than 40 entries or a mismatched entry count, a profile
     whose YAML does not decode to the expected shape, or an unknown
     --kill-switch flag/--cohort in dry-run mode
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

DEFAULT_REGISTRY_PATH = Path("lib/core/feature_flags/feature_flag_registry.dart")
MIN_REGISTRY_ENTRIES = 40

# Every shipped entry in feature_flag_registry.dart opens with this exact
# field order (key, owner, risk, failClosedDefault) before any optional
# field (adr, killSwitchPath, expiresOn) — see feature_flag_definition.dart
# for the type this mirrors.
_ENTRY_PATTERN = re.compile(
    r"FeatureFlagDefinition\(\s*"
    r"key:\s*'(?P<key>[^']+)',\s*"
    r"owner:\s*'[^']*',\s*"
    r"risk:\s*FeatureFlagRisk\.(?P<risk>low|medium|high),\s*"
    r"failClosedDefault:\s*(?P<failClosedDefault>true|false),",
    re.DOTALL,
)
_ENTRY_OPEN = re.compile(r"FeatureFlagDefinition\(")

_ALLOWED_COHORT_KEYS = {"id", "description", "versionRange", "maxTesters", "flags"}


class VerifyError(Exception):
    """A usage/format error (exit 2) — parsing could not even determine
    what to check, as opposed to a validation finding (exit 1)."""


def load_registry(path: Path) -> dict[str, dict]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"registry not found: {path}") from error

    raw_count = len(_ENTRY_OPEN.findall(text))
    entries: dict[str, dict] = {}
    for match in _ENTRY_PATTERN.finditer(text):
        entries[match.group("key")] = {
            "risk": match.group("risk"),
            "failClosedDefault": match.group("failClosedDefault") == "true",
        }

    if len(entries) != raw_count:
        raise VerifyError(
            f"{path}: found {raw_count} \"FeatureFlagDefinition(\" occurrence(s) "
            f"but only parsed {len(entries)} complete key/risk/failClosedDefault "
            "triple(s) — at least one entry does not match the expected field "
            "order and was not silently skipped"
        )
    if len(entries) < MIN_REGISTRY_ENTRIES:
        raise VerifyError(
            f"{path}: registry parse yielded {len(entries)} entries, expected "
            f">= {MIN_REGISTRY_ENTRIES}"
        )
    return entries


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
        raise VerifyError(f"{where}: cohort {cohort_id!r} is missing a non-empty \"flags\" mapping")
    for flag_key, flag_value in flags.items():
        if not isinstance(flag_key, str) or not flag_key:
            raise VerifyError(f"{where}: cohort {cohort_id!r} has a non-string flag key")
        if not isinstance(flag_value, bool):
            raise VerifyError(
                f"{where}: cohort {cohort_id!r} flag {flag_key!r} must map to a boolean, "
                f"got {flag_value!r}"
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


def validate(profile: dict[str, dict], registry: dict[str, dict]) -> list[str]:
    findings: list[str] = []
    for cohort_id, cohort in profile.items():
        for flag_key, flag_value in cohort["flags"].items():
            if flag_key not in registry:
                findings.append(
                    f"cohort {cohort_id!r}: flag {flag_key!r} does not exist in the "
                    "feature flag registry (A1/A2)"
                )
                continue
            if registry[flag_key]["risk"] == "high" and flag_value is True:
                findings.append(
                    f"cohort {cohort_id!r}: high-risk flag {flag_key!r} defaults to "
                    "true — every high-risk flag must default to false in every "
                    "cohort (A3)"
                )
    return findings


def _render_flags_block(flags: dict[str, bool]) -> str:
    return "\n".join(f"{key}: {str(value).lower()}" for key, value in sorted(flags.items()))


def run_kill_switch(profile: dict[str, dict], *, flag: str, cohort_id: str) -> str:
    if cohort_id not in profile:
        raise VerifyError(f"unknown cohort {cohort_id!r}")
    cohort = profile[cohort_id]
    if flag not in cohort["flags"]:
        raise VerifyError(f"unknown flag {flag!r} in cohort {cohort_id!r}")

    before = dict(cohort["flags"])
    after = dict(before)
    after[flag] = False

    lines = [
        f"kill-switch dry-run: cohort={cohort_id} flag={flag} (read-only, "
        "nothing written to disk)",
        "before:",
        _render_flags_block(before),
        "after:",
        _render_flags_block(after),
    ]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY_PATH)
    parser.add_argument(
        "--kill-switch",
        metavar="FLAG",
        help="Read-only dry-run: print a before/after view of --cohort with "
        "FLAG forced to false. Requires --cohort. Writes nothing to disk.",
    )
    parser.add_argument("--cohort", help="Cohort id, required with --kill-switch.")
    args = parser.parse_args(argv)

    if args.kill_switch is not None and args.cohort is None:
        print("verify_beta_profile: --kill-switch requires --cohort", file=sys.stderr)
        return 2
    if args.cohort is not None and args.kill_switch is None:
        print("verify_beta_profile: --cohort requires --kill-switch", file=sys.stderr)
        return 2

    try:
        registry = load_registry(args.registry)
        profile = load_profile(args.profile)
    except VerifyError as error:
        print(f"verify_beta_profile: {error}", file=sys.stderr)
        return 2

    if args.kill_switch is not None:
        try:
            print(run_kill_switch(profile, flag=args.kill_switch, cohort_id=args.cohort))
        except VerifyError as error:
            print(f"verify_beta_profile: {error}", file=sys.stderr)
            return 2
        return 0

    findings = validate(profile, registry)
    if findings:
        print(f"verify_beta_profile: {len(findings)} finding(s):", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1

    flag_count = sum(len(cohort["flags"]) for cohort in profile.values())
    print(
        f"verify_beta_profile: ok — {flag_count} flag assignment(s) across "
        f"{len(profile)} cohort(s), all present in a {len(registry)}-entry registry"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
