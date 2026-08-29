#!/usr/bin/env python3
"""AI/ML release-evidence aggregator (E12-R16, ADR 0477).

Reads the evidence matrix (`--scope-file`, normally
`docs/release/ai-quality-gates.md`) — a machine-readable table between
`<!-- ai-quality-gates:begin -->` / `<!-- ai-quality-gates:end -->` markers
naming, per capability+metric, which evidence document to read, which model
(if any) it must have been measured against, and the metric's regression
direction — and resolves it against two MEASURED sources of truth:

  * `--matrix` (default `docs/testing/device-matrix.yaml`): the ONLY source
    of `ga_scope` (ADR 0477 D1). This tool never re-lists which capabilities
    are GA — a capability the evidence matrix names but the device matrix
    does not know is a usage error (exit 2), and a capability's ga_scope
    here can never be overridden by the evidence matrix.
  * `--model-manifest` (default `assets/ml/model_manifest.json`): the ONLY
    source of the CURRENT model version. `models[]` entries are identified
    by `filename` and versioned by `training_run.identifier`;
    `vision_models[]` entries are identified by `model_id` and versioned by
    `version` (two distinct shapes — ADR 0477 D5, no single "model version"
    field is assumed).

For every `ga_scope: true` capability, every evidence document the matrix
names for it must exist, parse as a JSON object, and carry `corpusId`,
`buildSha`, `modelId`, `modelVersion`, `baselineValue` and `candidateValue`
(ADR 0477 D5) — a missing document or a missing field is fail-closed, never
"no data, so no regression" (ADR 0477 D2). A `ga_scope: false` capability's
evidence is never read; it always reports `not_in_scope` and never affects
the exit code (ADR 0477 D3) — Offline AI and Computer Vision stay `hold`
without blocking release.

Regression classification imports `classify`, `WARN_THRESHOLD` and
`FAIL_THRESHOLD` from `tool/compare_benchmarks.py` (ADR 0474, re-used per
ADR 0477 D4) rather than redefining a threshold here — a second,
independently-tuned threshold is exactly the drift ADR 0474 D6 already
forbids. The two imported threshold values are echoed into the report's
top-level `thresholds` field so a saved report documents which threshold
classified it, without the source re-declaring them as literals.

Exit codes (mirrors `tool/compare_benchmarks.py`):
  0  no ga_scope:true capability is missing evidence, mismatched against
     the model manifest, or classified "fail"
  1  at least one such release-blocking finding exists (see the report's
     top-level "findings" array)
  2  usage or format error: an unknown --profile, an evidence-matrix row
     naming a capability or model unknown to --matrix / --model-manifest,
     a malformed evidence matrix, or an evidence document that parses but
     is missing a required field
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from compare_benchmarks import (  # noqa: E402  (path must be extended first)
    DIRECTIONS,
    FAIL_THRESHOLD,
    WARN_THRESHOLD,
    classify,
)

SCHEMA_VERSION = 1
PROFILES = {"development", "lab", "production"}

GATE_TABLE_BEGIN = "<!-- ai-quality-gates:begin -->"
GATE_TABLE_END = "<!-- ai-quality-gates:end -->"
GATE_TABLE_COLUMNS = ("capability", "metric", "direction", "model", "evidence_path")
REQUIRED_STRING_EVIDENCE_FIELDS = ("corpusId", "buildSha", "modelId", "modelVersion")
REQUIRED_NUMERIC_EVIDENCE_FIELDS = ("baselineValue", "candidateValue")

_SEPARATOR_CELL = re.compile(r"^:?-+:?$")


class ReportError(Exception):
    """A usage or format error (exit code 2) — the run could not even
    determine what to check, as opposed to a release-blocking finding."""


def load_yaml_mapping(path: Path, *, where: str) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            document = yaml.safe_load(handle)
    except FileNotFoundError as error:
        raise ReportError(f"{where} not found: {path}") from error
    except yaml.YAMLError as error:
        raise ReportError(f"{where} is not valid YAML: {path} ({error})") from error
    if not isinstance(document, dict):
        raise ReportError(f"{where} does not decode to a mapping: {path}")
    return document


def load_json_mapping(path: Path, *, where: str) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            document = json.load(handle)
    except FileNotFoundError as error:
        raise ReportError(f"{where} not found: {path}") from error
    except json.JSONDecodeError as error:
        raise ReportError(f"{where} is not valid JSON: {path} ({error})") from error
    if not isinstance(document, dict):
        raise ReportError(f"{where} does not decode to a JSON object: {path}")
    return document


def load_ga_scope(matrix_path: Path) -> dict[str, bool]:
    matrix = load_yaml_mapping(matrix_path, where="device matrix")
    capabilities = matrix.get("capabilities")
    if not isinstance(capabilities, list):
        raise ReportError(f"{matrix_path}: missing a \"capabilities\" list")
    scope: dict[str, bool] = {}
    for entry in capabilities:
        if not isinstance(entry, dict):
            raise ReportError(f"{matrix_path}: a \"capabilities\" entry is not a mapping")
        capability_id = entry.get("id")
        ga_scope = entry.get("ga_scope")
        if not isinstance(capability_id, str) or not capability_id:
            raise ReportError(f"{matrix_path}: a capability entry is missing a non-empty \"id\"")
        if not isinstance(ga_scope, bool):
            raise ReportError(
                f"{matrix_path}: capability {capability_id!r} is missing a boolean \"ga_scope\""
            )
        scope[capability_id] = ga_scope
    return scope


def load_model_versions(manifest_path: Path) -> dict[str, str]:
    """Returns {"model:<filename>": training_run.identifier} for every
    models[] entry and {"vision:<model_id>": version} for every
    vision_models[] entry — the two distinct identity/version shapes
    assets/ml/model_manifest.json carries (ADR 0477 D5)."""
    manifest = load_json_mapping(manifest_path, where="model manifest")
    versions: dict[str, str] = {}
    for model in manifest.get("models") or []:
        if not isinstance(model, dict):
            continue
        filename = model.get("filename")
        training_run = model.get("training_run")
        identifier = training_run.get("identifier") if isinstance(training_run, dict) else None
        if isinstance(filename, str) and filename and isinstance(identifier, str) and identifier:
            versions[f"model:{filename}"] = identifier
    for vision_model in manifest.get("vision_models") or []:
        if not isinstance(vision_model, dict):
            continue
        model_id = vision_model.get("model_id")
        version = vision_model.get("version")
        if isinstance(model_id, str) and model_id and isinstance(version, str) and version:
            versions[f"vision:{model_id}"] = version
    return versions


def _split_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def parse_gate_rows(scope_text: str, *, where: str) -> list[dict[str, str]]:
    if GATE_TABLE_BEGIN not in scope_text or GATE_TABLE_END not in scope_text:
        raise ReportError(
            f"{where}: no {GATE_TABLE_BEGIN} ... {GATE_TABLE_END} machine-readable table found"
        )
    block = scope_text.split(GATE_TABLE_BEGIN, 1)[1].split(GATE_TABLE_END, 1)[0]
    table_lines = [line.strip() for line in block.splitlines() if line.strip().startswith("|")]
    if not table_lines:
        raise ReportError(f"{where}: the gate table has no rows")

    header = tuple(_split_row(table_lines[0]))
    if header != GATE_TABLE_COLUMNS:
        raise ReportError(
            f"{where}: gate table header must be {GATE_TABLE_COLUMNS!r}, got {header!r}"
        )

    data_lines = table_lines[1:]
    if data_lines and all(_SEPARATOR_CELL.match(cell) for cell in _split_row(data_lines[0])):
        data_lines = data_lines[1:]

    rows: list[dict[str, str]] = []
    for line in data_lines:
        cells = _split_row(line)
        if len(cells) != len(GATE_TABLE_COLUMNS):
            raise ReportError(
                f"{where}: gate table row has {len(cells)} cell(s), expected "
                f"{len(GATE_TABLE_COLUMNS)}: {line!r}"
            )
        row = dict(zip(GATE_TABLE_COLUMNS, cells))
        if row["direction"] not in DIRECTIONS:
            raise ReportError(
                f"{where}: row for {row['capability']!r}/{row['metric']!r} has unknown "
                f"direction {row['direction']!r} (expected {DIRECTIONS})"
            )
        rows.append(row)
    return rows


def resolve_expected_model(model_field: str, model_versions: dict[str, str]) -> tuple[str, str]:
    """Returns (modelId, expectedModelVersion) for a gate-table "model" cell."""
    if model_field == "none":
        return "none", "none"
    if model_field.startswith("model:"):
        filename = model_field[len("model:"):]
        key = f"model:{filename}"
        if key not in model_versions:
            raise ReportError(
                f"model manifest has no models[] entry with filename {filename!r}"
            )
        return filename, model_versions[key]
    if model_field.startswith("vision:"):
        model_id = model_field[len("vision:"):]
        key = f"vision:{model_id}"
        if key not in model_versions:
            raise ReportError(
                f"model manifest has no vision_models[] entry with model_id {model_id!r}"
            )
        return model_id, model_versions[key]
    raise ReportError(
        f"gate table \"model\" cell must be \"none\", \"model:<filename>\" or "
        f"\"vision:<model_id>\", got {model_field!r}"
    )


def _require_non_empty_string(document: dict, key: str, where: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise ReportError(f"{where}: missing or empty required field {key!r}")
    return value


def _require_number(document: dict, key: str, where: str) -> float:
    value = document.get(key)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise ReportError(f"{where}: missing or non-numeric required field {key!r}")
    return float(value)


def evaluate_capability(
    capability_id: str, rows: list[dict[str, str]], *, model_versions: dict[str, str]
) -> tuple[dict, list[str]]:
    """Reads every evidence document a ga_scope:true capability's rows name.

    Returns (capabilityEntry, findings). A missing/unreadable evidence
    document stops that row (status "missing", a finding is recorded) but
    does not raise — an evidence-document format error (a JSON object
    missing a required field) DOES raise ReportError (exit 2): the document
    exists and was read, so a missing field is the matrix or the document
    being wrong, not evidence that was never produced.
    """
    metrics: list[dict] = []
    findings: list[str] = []
    missing = False
    error_message: str | None = None

    for row in rows:
        expected_model_id, expected_model_version = resolve_expected_model(
            row["model"], model_versions
        )
        evidence_path = Path(row["evidence_path"])
        where = f"{capability_id}/{row['metric']} evidence ({evidence_path})"
        try:
            with evidence_path.open("r", encoding="utf-8") as handle:
                evidence = json.load(handle)
        except (FileNotFoundError, json.JSONDecodeError, OSError) as error:
            missing = True
            error_message = f"{where}: {error}"
            findings.append(
                f"{capability_id}/{row['metric']}: required evidence document is missing or "
                f"unreadable ({evidence_path}): {error}"
            )
            continue
        if not isinstance(evidence, dict):
            missing = True
            error_message = f"{where}: evidence document must be a JSON object"
            findings.append(f"{capability_id}/{row['metric']}: {error_message}")
            continue

        for field in REQUIRED_STRING_EVIDENCE_FIELDS:
            _require_non_empty_string(evidence, field, where)
        for field in REQUIRED_NUMERIC_EVIDENCE_FIELDS:
            _require_number(evidence, field, where)

        model_id = evidence["modelId"]
        model_version = evidence["modelVersion"]
        if model_id != expected_model_id:
            findings.append(
                f"{capability_id}/{row['metric']}: evidence modelId {model_id!r} does not match "
                f"the gate table's declared model {expected_model_id!r} ({evidence_path})"
            )
        elif model_version != expected_model_version:
            findings.append(
                f"{capability_id}/{row['metric']}: evidence modelVersion {model_version!r} does "
                f"not match the model manifest's {expected_model_version!r} for modelId "
                f"{model_id!r} ({evidence_path})"
            )

        baseline_value = _require_number(evidence, "baselineValue", where)
        candidate_value = _require_number(evidence, "candidateValue", where)
        status, delta = classify(baseline_value, candidate_value, row["direction"])
        if status == "fail":
            findings.append(
                f"{capability_id}/{row['metric']}: candidate regressed past FAIL_THRESHOLD "
                f"(delta={delta:.6f}, baseline={baseline_value!r}, candidate={candidate_value!r})"
            )

        metrics.append(
            {
                "capability": capability_id,
                "metric": row["metric"],
                "corpusId": evidence["corpusId"],
                "buildSha": evidence["buildSha"],
                "modelId": model_id,
                "modelVersion": model_version,
                "baselineValue": baseline_value,
                "candidateValue": candidate_value,
                "direction": row["direction"],
                "status": status,
                "delta": delta,
            }
        )

    entry: dict = {
        "id": capability_id,
        "status": "missing" if missing else "ok",
        "metrics": metrics,
    }
    if error_message is not None:
        entry["error"] = error_message
    return entry, findings


def build_report(
    *, profile: str, ga_scope: dict[str, bool], gate_rows: list[dict[str, str]], model_versions: dict[str, str]
) -> tuple[dict, list[str]]:
    grouped: dict[str, list[dict[str, str]]] = {}
    for row in gate_rows:
        capability_id = row["capability"]
        if capability_id not in ga_scope:
            raise ReportError(
                f"evidence matrix names capability {capability_id!r}, which is not present in "
                "the device matrix (ADR 0477 D1)"
            )
        grouped.setdefault(capability_id, []).append(row)

    capabilities: list[dict] = []
    findings: list[str] = []
    for capability_id, rows in grouped.items():
        if not ga_scope[capability_id]:
            capabilities.append({"id": capability_id, "status": "not_in_scope", "metrics": []})
            continue
        entry, capability_findings = evaluate_capability(
            capability_id, rows, model_versions=model_versions
        )
        capabilities.append(entry)
        findings.extend(capability_findings)

    report = {
        "schemaVersion": SCHEMA_VERSION,
        "profile": profile,
        "capabilities": capabilities,
        "findings": findings,
        "thresholds": {"warn": WARN_THRESHOLD, "fail": FAIL_THRESHOLD},
    }
    return report, findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--scope-file", required=True, type=Path)
    parser.add_argument(
        "--matrix", type=Path, default=Path("docs/testing/device-matrix.yaml")
    )
    parser.add_argument(
        "--model-manifest", type=Path, default=Path("assets/ml/model_manifest.json")
    )
    args = parser.parse_args(argv)

    if args.profile not in PROFILES:
        print(
            f"build_ai_report: unknown --profile {args.profile!r} "
            f"(expected one of {sorted(PROFILES)})",
            file=sys.stderr,
        )
        return 2

    try:
        ga_scope = load_ga_scope(args.matrix)
        model_versions = load_model_versions(args.model_manifest)
        scope_text = args.scope_file.read_text(encoding="utf-8")
        gate_rows = parse_gate_rows(scope_text, where=str(args.scope_file))
        report, findings = build_report(
            profile=args.profile,
            ga_scope=ga_scope,
            gate_rows=gate_rows,
            model_versions=model_versions,
        )
    except ReportError as error:
        print(f"build_ai_report: {error}", file=sys.stderr)
        return 2
    except FileNotFoundError as error:
        print(f"build_ai_report: {error}", file=sys.stderr)
        return 2

    print(json.dumps(report, indent=2, sort_keys=True))

    if findings:
        print(f"build_ai_report: {len(findings)} release-blocking finding(s):", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
