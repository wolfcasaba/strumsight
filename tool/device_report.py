#!/usr/bin/env python3
"""Device-matrix report generator and release-readiness check (E12-R13).

Reads the machine-readable device registry (`docs/testing/device-matrix.yaml`)
and an optional manual-run results file, and:

  --check   verifies every MANDATORY measurement — every `required_suite`
             entry of every `release_blocking: true` device — has a recorded
             run in the `--results` file. A recorded run may legitimately be
             `pending` (docs/testing/device-lab.md §4: "not yet run" is a
             valid state, not a placeholder). A run with NO entry at all is a
             hard failure, never a silent warning: with no `--results` file
             at all, every mandatory run is missing by definition. A
             `release_blocking: true` device whose `required_suite` is
             itself empty or absent is ALSO a hard failure — it never reads
             as "0 missing runs" (independent review F1).
  --report  prints a human-readable summary of devices, capabilities and
             recorded run coverage. Always exits 0 — it is informational,
             `--check` is the gate.

Uses PyYAML (`import yaml`) as a hard dependency, the same choice
`tool/audit_repository_policy.py` documents: a missing PyYAML install fails
loudly (ModuleNotFoundError) rather than silently falling back to a weaker
check. PyYAML 6.0.1 is present on this tree (measured, not assumed).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml


def load_yaml(path: Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def find_missing_required_runs(matrix: dict, results: dict) -> list[str]:
    """Returns "device_id:suite_item" for every mandatory run this results
    set does not record at all, plus a "device_id: required_suite is empty
    ..." entry for any release_blocking device whose required_suite itself
    is empty or absent.

    A mandatory run is one `required_suite` entry of one `release_blocking:
    true` device. Recommended (non-blocking) devices are informational and
    never produce a mandatory run. An entry recorded with any value —
    including "pending" — counts as present; only a wholly absent entry is
    "missing".

    An emptied `required_suite` on a release_blocking device must never
    look identical to "every mandatory run recorded" — that was the
    independent review's F1 finding (docs/reviews/e12-r13-review.md): with
    zero declared runs there is nothing left to be "missing", so the old
    check reported a clean 0-missing-runs pass. This is checked fail-closed,
    ahead of and regardless of any --results file.
    """
    runs = (results or {}).get("runs") or {}
    missing: list[str] = []
    for device in matrix.get("devices") or []:
        if not device.get("release_blocking"):
            continue
        device_id = device.get("id")
        required_suite = device.get("required_suite") or []
        if not required_suite:
            missing.append(
                f"{device_id}: required_suite is empty for a "
                "release_blocking device"
            )
            continue
        device_runs = runs.get(device_id) or {}
        for suite_item in required_suite:
            if suite_item not in device_runs:
                missing.append(f"{device_id}:{suite_item}")
    return missing


def build_report(matrix: dict, results: dict) -> str:
    runs = (results or {}).get("runs") or {}
    lines: list[str] = []

    devices = matrix.get("devices") or []
    lines.append(f"Devices: {len(devices)}")
    for device in devices:
        device_id = device.get("id")
        role = "blocking" if device.get("release_blocking") else "recommended"
        required = device.get("required_suite") or []
        device_runs = runs.get(device_id) or {}
        recorded = sum(1 for item in required if item in device_runs)
        lines.append(
            f"  - {device.get('name')} ({device_id}, {role}): "
            f"{recorded}/{len(required)} required run(s) recorded"
        )

    capabilities = matrix.get("capabilities") or []
    lines.append(f"Capabilities: {len(capabilities)}")
    for capability in capabilities:
        scope = "GA" if capability.get("ga_scope") else "preview"
        covering = capability.get("devices") or []
        lines.append(
            f"  - {capability.get('id')} ({scope}): "
            f"{len(covering)} covering device(s)"
        )

    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", required=True, type=Path)
    parser.add_argument("--results", type=Path, default=None)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)

    matrix = load_yaml(args.matrix)
    if not isinstance(matrix, dict):
        print(f"device_report: {args.matrix} does not decode to a mapping", file=sys.stderr)
        return 2

    results: dict = {}
    if args.results is not None:
        loaded = load_yaml(args.results)
        if isinstance(loaded, dict):
            results = loaded

    if not args.check and not args.report:
        print("device_report: pass --check and/or --report", file=sys.stderr)
        return 2

    exit_code = 0

    if args.check:
        missing = find_missing_required_runs(matrix, results)
        if missing:
            print(f"device_report check: {len(missing)} missing mandatory run(s):")
            for entry in missing:
                print(f"  - {entry}")
            exit_code = 1
        else:
            print("device_report check: every mandatory run is recorded.")

    if args.report:
        print(build_report(matrix, results))

    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
