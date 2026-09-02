#!/usr/bin/env python3
"""Release Candidate package assembler (E12-R25, ADR 0488 D4/D5/D7).

Assembles the seven mandatory pieces of release evidence — the signed APK,
the release manifest (ADR 0447), the SBOM, THIRD_PARTY_NOTICES.md, the AI
quality report (ADR 0477), the release security scan report (ADR 0481) and
the test/coverage report — into a single package directory, alongside a
deterministic checksum manifest covering every file the package contains.

Standard library only (D7): `argparse`, `hashlib`, `json`, `pathlib`,
`shutil`, `sys`. The CI runner image guarantees nothing beyond `python3`
itself (see `generate_sbom.py`'s module docstring for the same reasoning).

Two independent, fail-closed operations:

  assemble (default) — resolves all seven mandatory inputs BEFORE writing
    anything. If any input is missing, the tool exits non-zero and names
    every missing input; the output directory is left untouched — no
    half-built package (D4). `--dry-run` performs only this resolution
    step (prints the plan, writes nothing) and still exits non-zero on a
    missing input — a clean tree's `--dry-run` is EXPECTED to fail before
    any release artifact has been built.

  --verify — re-reads an already-assembled package's checksum manifest and
    binds it to the package directory's ACTUAL file list: a missing file,
    a changed file (sha256 mismatch) AND an extra file not named in the
    manifest are all non-zero exits (D5). This is the only mode that reads
    an existing package rather than building one.

Exit codes:
  0  assemble: package written, every input present.
     --dry-run: every input present (nothing written).
     --verify: the package matches its checksum manifest exactly.
  1  assemble / --dry-run: at least one mandatory input is missing.
     --verify: the package deviates from its checksum manifest (missing,
     changed or extra file), or has no checksum manifest at all.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

SCHEMA_VERSION = 1
PROFILES = ("production", "development")
CHECKSUM_MANIFEST_NAME = "checksum-manifest.json"

# (flag-key, human label) — order is the order missing-input messages print
# in, and the order files land in the assembled package.
REQUIRED_INPUTS: tuple[tuple[str, str], ...] = (
    ("apk", "APK artifact"),
    ("release_manifest", "release manifest"),
    ("sbom", "SBOM"),
    ("notices", "third-party notices"),
    ("ai_report", "AI quality report"),
    ("security_report", "security scan report"),
    ("test_report", "test/coverage report"),
)


class AssembleError(Exception):
    """A mandatory input is missing, or an assembled package fails --verify."""


def resolve_inputs(paths: dict[str, Path]) -> tuple[dict[str, Path], list[str]]:
    """Returns (present, missing_descriptions). Never raises — the caller
    decides whether a non-empty `missing` is fatal (it always is, but
    `--dry-run` still wants to print the plan before exiting)."""
    present: dict[str, Path] = {}
    missing: list[str] = []
    for key, label in REQUIRED_INPUTS:
        path = paths[key]
        if path.is_file():
            present[key] = path
        else:
            missing.append(f"{label}: {path}")
    return present, missing


def render_plan(paths: dict[str, Path], missing: list[str]) -> str:
    lines = ["assemble_rc: input plan"]
    for key, label in REQUIRED_INPUTS:
        path = paths[key]
        status = "present" if path.is_file() else "MISSING"
        lines.append(f"  - {label}: {path} [{status}]")
    if missing:
        lines.append(f"{len(missing)} mandatory input(s) missing:")
        for description in missing:
            lines.append(f"  - {description}")
    else:
        lines.append("all mandatory inputs present")
    return "\n".join(lines)


def _sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assemble_package(present: dict[str, Path], *, output_dir: Path, profile: str) -> dict:
    """Copies every present input into a freshly (re)created `output_dir`
    and writes its checksum manifest. Only called once every mandatory
    input has already been confirmed present — never leaves a half-built
    directory behind (D4)."""
    resolved_output = output_dir.resolve()
    labels_by_key = dict(REQUIRED_INPUTS)
    for key, source in present.items():
        if resolved_output in source.resolve().parents:
            raise AssembleError(
                f"--output-dir {output_dir} is the (or an ancestor) directory of the "
                f"{labels_by_key[key]} ({source}) — refusing to delete a mandatory input"
            )

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    entries = []
    for key, _label in REQUIRED_INPUTS:
        source = present[key]
        destination = output_dir / source.name
        if destination.exists():
            raise AssembleError(
                f"two mandatory inputs share the file name {source.name!r} — "
                "the assembled package cannot disambiguate them"
            )
        try:
            shutil.copyfile(source, destination)
        except OSError as error:
            raise AssembleError(f"failed to copy {source} to {destination}: {error}") from error
        entries.append(
            {"path": destination.relative_to(output_dir).as_posix(), "sha256": _sha256_of(destination)}
        )

    entries.sort(key=lambda entry: entry["path"])
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "profile": profile,
        "files": entries,
    }
    manifest_path = output_dir / CHECKSUM_MANIFEST_NAME
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def verify_package(package_dir: Path) -> list[str]:
    """Returns a list of human-readable deviations (empty = the package
    matches its manifest exactly). Raises AssembleError if the package
    directory or its checksum manifest cannot even be read."""
    if not package_dir.is_dir():
        raise AssembleError(f"package directory not found: {package_dir}")
    manifest_path = package_dir / CHECKSUM_MANIFEST_NAME
    if not manifest_path.is_file():
        raise AssembleError(f"no checksum manifest found in package: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise AssembleError(f"checksum manifest is not valid JSON: {manifest_path} ({error})") from error

    expected_entries = manifest.get("files")
    if not isinstance(expected_entries, list):
        raise AssembleError(f'checksum manifest is missing a "files" list: {manifest_path}')
    expected_by_name: dict[str, str] = {}
    for entry in expected_entries:
        name = entry.get("path")
        expected_sha256 = entry.get("sha256")
        if not name or not expected_sha256:
            raise AssembleError(f"malformed checksum manifest entry: {entry!r}")
        expected_by_name[name] = expected_sha256

    actual_names = {
        item.relative_to(package_dir).as_posix()
        for item in package_dir.rglob("*")
        if item.is_file() and item.relative_to(package_dir).as_posix() != CHECKSUM_MANIFEST_NAME
    }
    expected_names = set(expected_by_name)

    deviations: list[str] = []
    for missing_name in sorted(expected_names - actual_names):
        deviations.append(f"missing from package: {missing_name}")
    for extra_name in sorted(actual_names - expected_names):
        deviations.append(f"present in package but not in the checksum manifest: {extra_name}")
    for name in sorted(expected_names & actual_names):
        actual_sha256 = _sha256_of(package_dir / name)
        if actual_sha256 != expected_by_name[name]:
            deviations.append(
                f"checksum mismatch for {name}: manifest says {expected_by_name[name]}, actual is {actual_sha256}"
            )
    return deviations


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profile", choices=PROFILES, default="production")
    parser.add_argument("--dry-run", action="store_true", help="Resolve and print the input plan; write nothing.")
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify an already-assembled package (--output-dir) against its checksum manifest, instead of assembling.",
    )
    parser.add_argument("--apk", default="build/app/outputs/flutter-apk/app-release.apk")
    parser.add_argument("--release-manifest", default="build/release-manifest.json")
    parser.add_argument("--sbom", default="build/sbom.json")
    parser.add_argument("--notices", default="THIRD_PARTY_NOTICES.md")
    parser.add_argument("--ai-report", default="build/ai-report.json")
    parser.add_argument("--security-report", default="build/security-report.json")
    parser.add_argument("--test-report", default="coverage/lcov.info")
    parser.add_argument("--output-dir", default="build/rc")
    args = parser.parse_args(argv)

    output_dir = Path(args.output_dir)

    if args.verify:
        try:
            deviations = verify_package(output_dir)
        except AssembleError as error:
            print(f"assemble_rc: {error}", file=sys.stderr)
            return 1
        if deviations:
            print(f"assemble_rc: package at {output_dir} deviates from its checksum manifest:", file=sys.stderr)
            for deviation in deviations:
                print(f"  - {deviation}", file=sys.stderr)
            return 1
        print(f"assemble_rc: {output_dir} matches its checksum manifest exactly.")
        return 0

    paths = {
        "apk": Path(args.apk),
        "release_manifest": Path(args.release_manifest),
        "sbom": Path(args.sbom),
        "notices": Path(args.notices),
        "ai_report": Path(args.ai_report),
        "security_report": Path(args.security_report),
        "test_report": Path(args.test_report),
    }
    present, missing = resolve_inputs(paths)

    if args.dry_run:
        print(render_plan(paths, missing))
        return 1 if missing else 0

    if missing:
        print("assemble_rc: cannot assemble — mandatory input(s) missing:", file=sys.stderr)
        for description in missing:
            print(f"  - {description}", file=sys.stderr)
        return 1

    try:
        manifest = assemble_package(present, output_dir=output_dir, profile=args.profile)
    except AssembleError as error:
        print(f"assemble_rc: {error}", file=sys.stderr)
        return 1

    print(f"assemble_rc: package written to {output_dir} ({len(manifest['files'])} file(s)).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
