#!/usr/bin/env python3
"""Hotfix path policy gate (ADR 0490).

Two modes, one script, one `main(argv) -> int` (round brief §0.0.P5 — the
`verify_signing_policy.py` / `verify_rollout_decision.py` argparse pattern:
`sys.exit(main(sys.argv[1:]))`):

  static (default) — `--workflow PATH` (default:
  `docs/release/workflows/hotfix.proposal.yml`). Statically audits the
  hotfix workflow PROPOSAL document:
    - the `incident_id` `workflow_dispatch` input is `required: true` (D2),
      and no `skip_scan`/`emergency`-shaped input exists anywhere (D1);
    - a step named like "security scan" and a step named like "sign" both
      exist and are BOTH unconditional — no `if:`, no `continue-on-error:`
      (D1);
    - exactly one job carries an `environment:` key, and every job whose
      steps build, sign, assemble, or upload a release artifact
      transitively `needs:` it (D3).

  request — `--incident-id --previous-version --version`. Audits a single
  hotfix REQUEST:
    - the incident id is non-empty (D2);
    - `--version` is STRICTLY greater than `--previous-version` (D5) — the
      same semantics as `tool/release/verify_artifacts.py`'s build-number
      monotonicity check (`>`, never `>=`), extended from a bare integer to
      dotted-integer version strings.

`--incident-id` switches the script into request mode; omitting it runs
static mode. The two modes are mutually exclusive: request mode additionally
requires `--previous-version` and `--version`.

Standard library only — no `package:yaml` (see `generate_sbom.py`'s module
docstring: the CI runner image does not guarantee any third-party Python
package is installed). The job/step/input parser below is a hand-rolled
restricted subset of the GitHub Actions YAML shape this repo's proposal
documents use — the same shape `test/tooling/rc_assembly_test.dart`'s
`parseWorkflowJobs` reads for `release-candidate.proposal.yml` (ADR 0488
D6), reimplemented here in Python so this script can perform its own D3
job-graph audit rather than delegate it to the Dart gate test. A line inside
a recognized block (`jobs:`, `workflow_dispatch: inputs:`) that matches no
recognized shape is a `VerifyError` naming the line — never a silently
skipped line (L566).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


class VerifyError(Exception):
    """A hotfix-policy violation, or a document too malformed to audit."""


# ---------------------------------------------------------------------------
# Restricted GitHub Actions job/step parser (ADR 0490 D7).
# ---------------------------------------------------------------------------


class ParsedStep:
    def __init__(self, name: str, fields: dict) -> None:
        self.name = name
        self.fields = fields

    @property
    def run(self) -> str | None:
        return self.fields.get("run")

    @property
    def uses(self) -> str | None:
        return self.fields.get("uses")

    @property
    def if_condition(self) -> str | None:
        return self.fields.get("if")

    @property
    def continue_on_error(self) -> str | None:
        return self.fields.get("continue-on-error")


class ParsedJob:
    def __init__(self, job_id: str, fields: dict, steps: list[ParsedStep]) -> None:
        self.id = job_id
        self.fields = fields
        self.steps = steps

    @property
    def environment(self) -> str | None:
        return self.fields.get("environment")

    @property
    def needs(self) -> list[str]:
        return _parse_needs(self.fields.get("needs"))


_JOB_HEADER = re.compile(r"^  ([a-z][a-z0-9_-]*):$")
_JOB_FIELD = re.compile(r"^ {4}([a-zA-Z_-]+):(.*)$")
_STEP_HEADER = re.compile(r"^ {6}- name: (.*)$")
_STEP_FIELD = re.compile(r"^ {8}([a-zA-Z_-]+):(.*)$")
_STEP_MAP_LINE = re.compile(r"^ {10}([a-zA-Z0-9_-]+):(.*)$")
_INPUT_NAME = re.compile(r"^      ([a-z][a-z0-9_]*):$")
_INPUT_FIELD = re.compile(r"^ {8}([a-zA-Z_-]+):(.*)$")


def _unquote(raw: str) -> str:
    trimmed = raw.strip()
    if len(trimmed) >= 2 and trimmed[0] == '"' and trimmed[-1] == '"':
        return trimmed[1:-1]
    return trimmed


def _is_blank_or_comment(line: str) -> bool:
    trimmed = line.strip()
    return trimmed == "" or trimmed.startswith("#")


def _parse_needs(raw: str | None) -> list[str]:
    if raw is None or raw.strip() == "":
        return []
    trimmed = raw.strip()
    if trimmed.startswith("[") and trimmed.endswith("]"):
        inner = trimmed[1:-1]
        return [_unquote(part.strip()) for part in inner.split(",") if part.strip()]
    return [_unquote(trimmed)]


def parse_workflow_jobs(source_text: str, *, source_label: str) -> list[ParsedJob]:
    lines = source_text.split("\n")
    try:
        jobs_line_index = lines.index("jobs:")
    except ValueError as error:
        raise VerifyError(f'{source_label}: no top-level "jobs:" key found') from error

    i = jobs_line_index + 1
    jobs: list[ParsedJob] = []
    while i < len(lines):
        if _is_blank_or_comment(lines[i]):
            i += 1
            continue
        header = _JOB_HEADER.match(lines[i])
        if header is None:
            raise VerifyError(
                f'{source_label}:{i + 1}: expected a 2-space-indented job id '
                f'"  <id>:", got: "{lines[i]}"'
            )
        job_id = header.group(1)
        i += 1
        fields: dict[str, str] = {}
        steps: list[ParsedStep] = []
        while i < len(lines):
            if _is_blank_or_comment(lines[i]):
                i += 1
                continue
            field_match = _JOB_FIELD.match(lines[i])
            if field_match is None:
                break
            key = field_match.group(1)
            rest = field_match.group(2).strip()
            line_number = i + 1
            i += 1
            if key == "steps":
                if rest:
                    raise VerifyError(
                        f'{source_label}:{line_number}: "steps:" must start a '
                        f"block list, not an inline value"
                    )
                parsed_steps: list[ParsedStep] = []
                while i < len(lines):
                    if _is_blank_or_comment(lines[i]):
                        i += 1
                        continue
                    step_header = _STEP_HEADER.match(lines[i])
                    if step_header is None:
                        break
                    name = _unquote(step_header.group(1))
                    i += 1
                    step_fields: dict = {}
                    while i < len(lines):
                        step_field_match = _STEP_FIELD.match(lines[i])
                        if step_field_match is None:
                            break
                        step_key = step_field_match.group(1)
                        step_rest = step_field_match.group(2).strip()
                        step_line_number = i + 1
                        i += 1
                        if step_rest == "|":
                            block_lines = []
                            while i < len(lines) and (
                                lines[i].startswith(" " * 10) or lines[i].strip() == ""
                            ):
                                block_lines.append(lines[i][10:] if lines[i] else "")
                                i += 1
                            step_fields[step_key] = "\n".join(block_lines)
                        elif step_rest == "":
                            mapping: dict[str, str] = {}
                            while i < len(lines) and _STEP_MAP_LINE.match(lines[i]):
                                map_match = _STEP_MAP_LINE.match(lines[i])
                                assert map_match is not None
                                mapping[map_match.group(1)] = _unquote(map_match.group(2))
                                i += 1
                            if not mapping:
                                raise VerifyError(
                                    f'{source_label}:{step_line_number}: "{step_key}:" '
                                    f"started a block mapping but no "
                                    f'10-space-indented "key: value" line followed'
                                )
                            step_fields[step_key] = mapping
                        else:
                            step_fields[step_key] = _unquote(step_rest)
                    parsed_steps.append(ParsedStep(name=name, fields=step_fields))
                steps = parsed_steps
            else:
                fields[key] = rest
        jobs.append(ParsedJob(job_id=job_id, fields=fields, steps=steps))
    return jobs


def parse_workflow_dispatch_inputs(source_text: str, *, source_label: str) -> dict:
    lines = source_text.split("\n")
    try:
        inputs_line_index = lines.index("    inputs:")
    except ValueError as error:
        raise VerifyError(
            f'{source_label}: no "workflow_dispatch: inputs:" block found '
            f'(expected a "    inputs:" line)'
        ) from error

    inputs: dict[str, dict] = {}
    current_name: str | None = None
    i = inputs_line_index + 1
    while i < len(lines):
        line = lines[i]
        if _is_blank_or_comment(line):
            i += 1
            continue
        if not line.startswith("      "):
            break
        name_match = _INPUT_NAME.match(line)
        if name_match is not None:
            current_name = name_match.group(1)
            inputs[current_name] = {}
            i += 1
            continue
        field_match = _INPUT_FIELD.match(line)
        if field_match is not None and current_name is not None:
            inputs[current_name][field_match.group(1)] = _unquote(field_match.group(2))
            i += 1
            continue
        raise VerifyError(
            f'{source_label}:{i + 1}: unrecognized line inside the '
            f'"workflow_dispatch: inputs:" block: "{line}"'
        )
    return inputs


def job_transitively_needs(jobs: list[ParsedJob], start_job_id: str, target_job_id: str) -> bool:
    by_id = {job.id: job for job in jobs}
    visited: set[str] = set()
    queue = [start_job_id]
    while queue:
        current = queue.pop()
        if current in visited:
            continue
        visited.add(current)
        job = by_id.get(current)
        if job is None:
            continue
        for need in job.needs:
            if need == target_job_id:
                return True
            queue.append(need)
    return False


# ---------------------------------------------------------------------------
# Static mode (ADR 0490 D1/D2/D3).
# ---------------------------------------------------------------------------

_SKIP_INPUT_NAME_PATTERN = re.compile(r"skip|emergency", re.IGNORECASE)
_SECURITY_SCAN_STEP_NAME = re.compile(r"security scan", re.IGNORECASE)
_SIGNING_STEP_NAME = re.compile(r"sign", re.IGNORECASE)
_RELEASE_VERB = re.compile(r"build|sign|assembl|upload", re.IGNORECASE)


def static_check(workflow_text: str, *, source_label: str) -> list[str]:
    violations: list[str] = []

    inputs = parse_workflow_dispatch_inputs(workflow_text, source_label=source_label)

    incident_input = inputs.get("incident_id")
    if incident_input is None:
        violations.append(
            'incident-id-required: no "incident_id" workflow_dispatch input found (ADR 0490 D2)'
        )
    elif incident_input.get("required") != "true":
        violations.append(
            'incident-id-required: "incident_id" input is not "required: true" '
            f"(got required={incident_input.get('required')!r}) (ADR 0490 D2)"
        )

    for name in inputs:
        if _SKIP_INPUT_NAME_PATTERN.search(name):
            violations.append(
                f'gate-not-skippable: workflow_dispatch input "{name}" looks like a '
                f"skip/emergency switch — forbidden (ADR 0490 D1)"
            )

    jobs = parse_workflow_jobs(workflow_text, source_label=source_label)
    all_steps = [(job, step) for job in jobs for step in job.steps]

    security_steps = [
        (job, step) for job, step in all_steps if _SECURITY_SCAN_STEP_NAME.search(step.name)
    ]
    if not security_steps:
        violations.append(
            'security-scan-required: no step named like "security scan" found (ADR 0490 D1)'
        )
    for job, step in security_steps:
        if step.if_condition is not None:
            violations.append(
                f'security-scan-unconditional: step "{step.name}" (job "{job.id}") '
                f'carries an "if:" condition — forbidden (ADR 0490 D1)'
            )
        if step.continue_on_error is not None:
            violations.append(
                f'security-scan-unconditional: step "{step.name}" (job "{job.id}") '
                f'carries "continue-on-error:" — forbidden (ADR 0490 D1)'
            )

    signing_steps = [
        (job, step) for job, step in all_steps if _SIGNING_STEP_NAME.search(step.name)
    ]
    if not signing_steps:
        violations.append(
            'production-signing-required: no step named like "sign" found (ADR 0490 D1)'
        )
    for job, step in signing_steps:
        if step.if_condition is not None:
            violations.append(
                f'production-signing-unconditional: step "{step.name}" (job "{job.id}") '
                f'carries an "if:" condition — forbidden (ADR 0490 D1)'
            )
        if step.continue_on_error is not None:
            violations.append(
                f'production-signing-unconditional: step "{step.name}" (job "{job.id}") '
                f'carries "continue-on-error:" — forbidden (ADR 0490 D1)'
            )

    approval_jobs = [job for job in jobs if job.environment is not None]
    if len(approval_jobs) != 1:
        violations.append(
            f'approval-gate-unique: expected exactly one job with an "environment:" '
            f"key, found {len(approval_jobs)} ({[job.id for job in approval_jobs]}) "
            f"(ADR 0490 D3)"
        )
    else:
        approval_job_id = approval_jobs[0].id
        for job in jobs:
            if job.id == approval_job_id:
                continue
            touches_release_artifact = any(
                _RELEASE_VERB.search(step.name) or _RELEASE_VERB.search(step.uses or "")
                for step in job.steps
            )
            if not touches_release_artifact:
                continue
            if not job_transitively_needs(jobs, job.id, approval_job_id):
                violations.append(
                    f'approval-gate-transitive: job "{job.id}" builds/signs/assembles/'
                    f'uploads a release artifact but does not transitively need the '
                    f'approval job "{approval_job_id}" (ADR 0490 D3)'
                )

    return violations


# ---------------------------------------------------------------------------
# Request mode (ADR 0490 D2/D5).
# ---------------------------------------------------------------------------

_VERSION_PART = re.compile(r"^\d+$")


def _parse_version(raw: str, *, label: str) -> tuple[int, ...]:
    parts = raw.strip().split(".")
    if not raw.strip() or any(not _VERSION_PART.match(part) for part in parts):
        raise VerifyError(f'{label}: not a valid dotted-integer version: "{raw}"')
    return tuple(int(part) for part in parts)


def request_check(*, incident_id: str, previous_version: str, version: str) -> list[str]:
    violations: list[str] = []

    if incident_id.strip() == "":
        violations.append(
            "incident-id-required: --incident-id is empty or missing (ADR 0490 D2)"
        )

    previous_tuple = _parse_version(previous_version, label="--previous-version")
    version_tuple = _parse_version(version, label="--version")

    if version_tuple <= previous_tuple:
        violations.append(
            f'version-strictly-greater: --version "{version}" is not strictly greater '
            f'than --previous-version "{previous_version}" (ADR 0490 D5 — same or '
            f"stricter than verify_artifacts.py's monotonicity check, never looser)"
        )

    return violations


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--workflow",
        default="docs/release/workflows/hotfix.proposal.yml",
        help="Static mode: path to the hotfix workflow proposal document.",
    )
    parser.add_argument(
        "--incident-id", default=None, help="Request mode: incident identifier."
    )
    parser.add_argument("--previous-version", default=None, help="Request mode.")
    parser.add_argument("--version", default=None, help="Request mode.")
    args = parser.parse_args(argv)

    if args.incident_id is not None:
        if args.previous_version is None or args.version is None:
            parser.error(
                "request mode (--incident-id given) also requires --previous-version "
                "and --version"
            )
        try:
            violations = request_check(
                incident_id=args.incident_id,
                previous_version=args.previous_version,
                version=args.version,
            )
        except VerifyError as error:
            print(f"verify_hotfix: {error}", file=sys.stderr)
            return 1
        mode_label = "request"
        ok_message = (
            f'verify_hotfix (request mode): ok — incident_id="{args.incident_id}", '
            f"{args.previous_version} -> {args.version}"
        )
    else:
        workflow_path = Path(args.workflow)
        try:
            workflow_text = workflow_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            print(f"verify_hotfix: workflow file not found: {workflow_path}", file=sys.stderr)
            return 1
        try:
            violations = static_check(workflow_text, source_label=str(workflow_path))
        except VerifyError as error:
            print(f"verify_hotfix: {error}", file=sys.stderr)
            return 1
        mode_label = "static"
        ok_message = f"verify_hotfix (static mode): ok — {workflow_path}"

    if violations:
        print(
            f"verify_hotfix ({mode_label} mode): {len(violations)} violation(s):",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  VIOLATION {violation}", file=sys.stderr)
        return 1

    print(ok_message)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
