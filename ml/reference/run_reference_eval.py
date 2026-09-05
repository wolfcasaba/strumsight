#!/usr/bin/env python3
"""One-command reproduction + integrity check for the pinned Klangio ISMIR
2025 reference model (ADR 0369, E14-R17). See ml/reference/README.md for the
full picture — this module is intentionally small enough to read start to
finish.

    python3 ml/reference/run_reference_eval.py \\
        --manifest ml/reference/reference_manifest.json --verify-only

    python3 ml/reference/run_reference_eval.py \\
        --manifest ml/reference/reference_manifest.json \\
        --workdir <path outside this repository>

Contract (ADR 0369 D1/D3/D4/D6):
  * ``--workdir`` is mandatory for a full run and MUST resolve outside this
    repository — nothing this script does may write into the repo tree, and
    the manifest identifies artifacts by checksum, never by copying bytes in.
  * A missing Python dependency or a missing on-disk artifact is a typed,
    speaking error that names the gap and the exact command to rerun once
    it's closed — never an estimated or invented metric.
  * The official-fixture result and the StrumSight held-out result are two
    independent structures, each carrying its own corpus hash; they are
    never merged into one table or one averaged number.
  * Every path this script reports is relative to ``--workdir`` — never an
    absolute path baked in from the machine that ran it (L530).
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_PLACEHOLDER_LICENCE_VALUES = {"unknown", "n/a", "na", "none", ""}
_REQUIRED_LICENSE_FIELDS = ("spdx", "source", "evidence", "verdict")

#: requirements.txt package name -> the name it is `import`-ed under, for the
#: handful where they differ.
_IMPORT_NAME_OVERRIDES = {
    "note-seq": "note_seq",
    "hydra-core": "hydra",
}

_RERUN_COMMAND = (
    "python3 ml/reference/run_reference_eval.py "
    "--manifest ml/reference/reference_manifest.json "
    "--workdir <path outside this repository>"
)


class ManifestValidationError(ValueError):
    """The manifest fails ADR 0369 D1's schema — typed, never a soft default."""


class WorkdirInsideRepositoryError(ValueError):
    """``--workdir`` resolved inside this repository (ADR 0369 D3)."""


class MissingDependencyError(RuntimeError):
    """A requirements.txt package is not importable in this interpreter."""


class MissingArtifactError(RuntimeError):
    """A cloned/fetched artifact is missing or fails its checksum."""


def validate_manifest(document: dict) -> list[str]:
    """Independent Python-side twin of the Dart schema check in
    ``test/tooling/reference_model_licence_guard_test.dart`` — enforces the
    same ADR 0369 D1 rule: three separate license verdicts, and the literal
    "unknown"/"n/a" string is never a valid license (L546).
    """
    errors: list[str] = []

    if "license" in document:
        errors.append(
            "a single top-level 'license' field cannot independently cover "
            "code, checkpoint and dataset"
        )

    artifacts = document.get("artifacts")
    if not isinstance(artifacts, dict):
        return errors + ["missing 'artifacts' object"]

    for artifact_key in ("code", "checkpoint", "dataset"):
        artifact = artifacts.get(artifact_key)
        if not isinstance(artifact, dict):
            errors.append(f"missing artifact block '{artifact_key}'")
            continue
        license_ = artifact.get("license")
        if not isinstance(license_, dict):
            errors.append(f"'{artifact_key}.license' is missing")
            continue
        for field in _REQUIRED_LICENSE_FIELDS:
            if field not in license_:
                errors.append(f"'{artifact_key}.license.{field}' is missing")
        spdx = license_.get("spdx")
        verdict = license_.get("verdict")
        if spdx is None:
            if verdict != "blocking":
                errors.append(
                    f"'{artifact_key}.license.spdx' is null (undeclared) but "
                    f"verdict is {verdict!r}, expected 'blocking'"
                )
        elif (
            isinstance(spdx, str)
            and spdx.strip().lower() in _PLACEHOLDER_LICENCE_VALUES
        ):
            errors.append(
                f"'{artifact_key}.license.spdx' = {spdx!r} is a placeholder, "
                "never a valid license — use a real SPDX id or explicit null"
            )
        for field in ("source", "evidence"):
            value = license_.get(field)
            if (
                isinstance(value, str)
                and value.strip().lower() in _PLACEHOLDER_LICENCE_VALUES
            ):
                errors.append(
                    f"'{artifact_key}.license.{field}' = {value!r} is a placeholder"
                )

    source = document.get("source")
    if not isinstance(source, dict) or not _COMMIT_RE.match(
        str(source.get("pinned_commit"))
    ):
        errors.append(
            "'source.pinned_commit' must be a 40-character lowercase hex commit hash"
        )

    checkpoint = artifacts.get("checkpoint")
    if isinstance(checkpoint, dict):
        if not _SHA256_RE.match(str(checkpoint.get("sha256"))):
            errors.append(
                "'checkpoint.sha256' must be a 64-character lowercase hex sha256"
            )
        if not isinstance(checkpoint.get("bytes"), int) or checkpoint["bytes"] <= 0:
            errors.append("'checkpoint.bytes' must be a positive integer")

    dataset = artifacts.get("dataset")
    if isinstance(dataset, dict):
        for field in ("bytes", "blob_count"):
            if not isinstance(dataset.get(field), int) or dataset[field] <= 0:
                errors.append(f"'dataset.{field}' must be a positive integer")

    return errors


def load_manifest(manifest_path: Path) -> dict:
    try:
        document = json.loads(manifest_path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ManifestValidationError(
            f"cannot read manifest {manifest_path}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise ManifestValidationError(
            f"{manifest_path} is not valid JSON: {error}"
        ) from error

    errors = validate_manifest(document)
    if errors:
        raise ManifestValidationError(
            f"{manifest_path} failed schema validation:\n  - " + "\n  - ".join(errors)
        )
    return document


def resolve_workdir(raw_workdir: str) -> Path:
    workdir = Path(raw_workdir).expanduser().resolve()
    repo_root = REPO_ROOT.resolve()
    if workdir == repo_root or repo_root in workdir.parents:
        raise WorkdirInsideRepositoryError(
            f"--workdir {workdir} resolves inside this repository ({repo_root}); "
            "ADR 0369 D3 requires the reproduction to run entirely outside the "
            "repo tree — pick a path such as /tmp/klangio-repro"
        )
    return workdir


def check_dependencies(requirements: list[str]) -> None:
    missing = []
    for requirement in requirements:
        package_name = re.split(r"[<>=]", requirement, maxsplit=1)[0].strip()
        import_name = _IMPORT_NAME_OVERRIDES.get(
            package_name, package_name.replace("-", "_")
        )
        try:
            importlib.import_module(import_name)
        except ImportError:
            missing.append(requirement)
    if missing:
        raise MissingDependencyError(
            "missing Python dependencies for the reference reproduction: "
            + ", ".join(missing)
            + f"\n  pip install {' '.join(missing)}"
            + "\nthen rerun:\n  "
            + _RERUN_COMMAND
        )


def clone_pinned_commit(document: dict, workdir: Path) -> Path:
    """Clone the upstream repo into ``workdir`` and check out the manifest's
    pinned commit exactly. The dataset ships as ordinary (non-LFS) blobs in
    the same tree, so a plain clone fetches it too — only the checkpoint
    needs a separate LFS pull (see ``verify_checkpoint``). Never touches the
    repository this script lives in.
    """
    repo_url = document["source"]["repository"]
    pinned_commit = document["source"]["pinned_commit"]
    clone_dir = workdir / "guitar-strumming-transcription"
    if not clone_dir.exists():
        subprocess.run(["git", "clone", repo_url, str(clone_dir)], check=True)
    subprocess.run(["git", "checkout", pinned_commit], check=True, cwd=clone_dir)
    actual_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        check=True,
        cwd=clone_dir,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if actual_commit != pinned_commit:
        raise MissingArtifactError(
            f"checked out {actual_commit}, expected the manifest's pinned "
            f"commit {pinned_commit}. Remove {clone_dir} and rerun:\n  "
            + _RERUN_COMMAND
        )
    return clone_dir


def verify_checkpoint(document: dict, clone_dir: Path) -> Path:
    checkpoint = document["artifacts"]["checkpoint"]
    checkpoint_path = clone_dir / checkpoint["path"]
    subprocess.run(
        ["git", "lfs", "pull", "--include", checkpoint["path"]],
        check=True,
        cwd=clone_dir,
    )
    if not checkpoint_path.is_file():
        raise MissingArtifactError(
            f"{checkpoint_path} was not materialized by 'git lfs pull'. "
            "Confirm git-lfs is installed, then rerun:\n  " + _RERUN_COMMAND
        )
    digest = hashlib.sha256()
    with checkpoint_path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    actual_sha256 = digest.hexdigest()
    if actual_sha256 != checkpoint["sha256"]:
        raise MissingArtifactError(
            f"{checkpoint_path} sha256 {actual_sha256} does not match the "
            f"manifest's pinned {checkpoint['sha256']} — refusing to evaluate "
            "an unverified checkpoint"
        )
    return checkpoint_path


def run_official_fixture_eval(clone_dir: Path) -> dict:
    """Reproduce the upstream paper's own evaluation split and metrics.

    NOT implemented in this round (ADR 0369 §0.0 C/D): the upstream
    repository's only evaluation entry point is a notebook
    (``scripts/evaluate.ipynb``, measured 2026-09-05 — no single-command
    ``.py`` form exists upstream), and its cell-output contract was not read
    during the pre-flight because there is no PyTorch runtime on this box to
    open it against. Reading that contract and wiring an nbconvert-based
    extraction is follow-up work for whichever round first has a
    PyTorch-capable box; this function fails loudly rather than guessing at a
    metric key or inventing a number.
    """
    notebook = clone_dir / "scripts" / "evaluate.ipynb"
    raise NotImplementedError(
        f"official-fixture evaluation needs {notebook}'s cell-output contract "
        "read on a PyTorch-capable box; not available in this round — see "
        "ml/reference/README.md"
    )


def run_strumsight_holdout_eval(clone_dir: Path, checkpoint_path: Path) -> dict:
    """Evaluate the pinned checkpoint on StrumSight's own held-out split
    (the grouped-by-recording harness from E14-R08).

    NOT implemented in this round for the same reason as
    ``run_official_fixture_eval``: it needs a PyTorch/Lightning runtime to
    load the checkpoint via the upstream
    ``klangio/modules/strumming_crnn`` model classes, unavailable on this box.
    """
    raise NotImplementedError(
        f"StrumSight held-out evaluation needs PyTorch/Lightning to load "
        f"{checkpoint_path} via the upstream klangio/modules/strumming_crnn "
        "classes; not available in this round — see ml/reference/README.md"
    )


def _relative_to_workdir(path: Path, workdir: Path) -> str:
    try:
        return str(path.relative_to(workdir))
    except ValueError:
        return path.name


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--manifest", required=True, type=Path, help="path to reference_manifest.json"
    )
    parser.add_argument(
        "--workdir",
        type=Path,
        default=None,
        help="repo-external directory for the clone + checkpoint + dataset "
        "(required unless --verify-only)",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="validate the manifest's integrity and exit — no network, no clone",
    )
    args = parser.parse_args(argv)

    try:
        document = load_manifest(args.manifest)
    except ManifestValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.verify_only:
        print(
            json.dumps(
                {
                    "manifest": str(args.manifest),
                    "schema": "ok",
                    "pinned_commit": document["source"]["pinned_commit"],
                    "go_no_go": document["go_no_go"]["product_use"],
                },
                indent=2,
            )
        )
        return 0

    if args.workdir is None:
        print(
            "error: --workdir is required for a full run (ADR 0369 D3) — "
            "pass --verify-only for a network-free manifest check instead",
            file=sys.stderr,
        )
        return 1

    try:
        workdir = resolve_workdir(str(args.workdir))
    except WorkdirInsideRepositoryError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    try:
        check_dependencies(document["requirements"])
    except MissingDependencyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    workdir.mkdir(parents=True, exist_ok=True)
    try:
        clone_dir = clone_pinned_commit(document, workdir)
        checkpoint_path = verify_checkpoint(document, clone_dir)
        official_fixture = run_official_fixture_eval(clone_dir)
        strumsight_holdout = run_strumsight_holdout_eval(clone_dir, checkpoint_path)
    except (MissingArtifactError, NotImplementedError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(
        json.dumps(
            {
                "official_fixture": official_fixture,
                "strumsight_held_out": strumsight_holdout,
                "clone_dir": _relative_to_workdir(clone_dir, workdir),
                "checkpoint_path": _relative_to_workdir(checkpoint_path, workdir),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
