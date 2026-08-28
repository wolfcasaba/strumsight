#!/usr/bin/env python3
"""Release artifact checksum + build-number monotonicity audit.

ADR 0447 D2 / D5. Standard library only (see `generate_sbom.py`'s module
docstring for why: the CI runner image does not guarantee any third-party
Python package).

Two independent checks, both fail-closed:

  1. Every entry in the release manifest's `artifacts` list must exist on
     disk with a matching sha256 — a stale or substituted artifact is a
     hard failure, not a warning.
  2. When `--previous <manifest>` is given, the new manifest's
     `app.buildNumber` must be STRICTLY greater than the previous one's —
     both a decrease AND a re-used (equal) build number are hard failures.
     Without `--previous` the monotonicity check does not run, but this
     tool says so explicitly (`baseline: none`) rather than silently
     skipping it — a silent skip would read as "checked and clean".
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


class VerifyError(Exception):
    """A checksum mismatch, missing artifact, or non-monotonic build number."""


def _load_manifest(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise VerifyError(f"manifest not found: {path}") from error
    except json.JSONDecodeError as error:
        raise VerifyError(f"manifest is not valid JSON: {path} ({error})") from error


def verify_checksums(manifest: dict, *, base_dir: Path) -> int:
    artifacts = manifest.get("artifacts", [])
    if not isinstance(artifacts, list):
        raise VerifyError('manifest "artifacts" must be a list')
    for entry in artifacts:
        name = entry.get("name")
        path_value = entry.get("path")
        expected_sha256 = entry.get("sha256")
        if not name or not path_value or not expected_sha256:
            raise VerifyError(f"malformed artifact entry: {entry!r}")
        artifact_path = Path(path_value)
        if not artifact_path.is_absolute():
            artifact_path = base_dir / artifact_path
        if not artifact_path.is_file():
            raise VerifyError(f"artifact missing on disk: {name} ({artifact_path})")
        actual_sha256 = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
        if actual_sha256 != expected_sha256:
            raise VerifyError(
                f"checksum mismatch for {name}: manifest says {expected_sha256}, "
                f"actual is {actual_sha256}"
            )
    return len(artifacts)


def verify_build_number_monotonic(manifest: dict, previous_manifest: dict) -> tuple[int, int]:
    new_build = manifest.get("app", {}).get("buildNumber")
    previous_build = previous_manifest.get("app", {}).get("buildNumber")
    if not isinstance(new_build, int) or not isinstance(previous_build, int):
        raise VerifyError('both manifests must carry an integer "app.buildNumber"')
    if new_build <= previous_build:
        raise VerifyError(
            f"build number is not strictly greater than the baseline: "
            f"new={new_build}, previous={previous_build}"
        )
    return new_build, previous_build


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--previous", default=None)
    parser.add_argument(
        "--base-dir",
        default=".",
        help="Directory relative artifact paths in the manifest are resolved against.",
    )
    args = parser.parse_args(argv)

    try:
        manifest = _load_manifest(Path(args.manifest))
        artifact_count = verify_checksums(manifest, base_dir=Path(args.base_dir))

        if args.previous is None:
            print("baseline: none")
        else:
            previous_manifest = _load_manifest(Path(args.previous))
            new_build, previous_build = verify_build_number_monotonic(manifest, previous_manifest)
            print(f"baseline: {args.previous} (build {previous_build})")
            print(f"build_number: {new_build} (previous {previous_build}, strictly greater: OK)")

        print(f"artifacts: {artifact_count} verified")
    except VerifyError as error:
        print(f"verify_artifacts: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
