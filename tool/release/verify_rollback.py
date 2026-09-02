#!/usr/bin/env python3
"""Post-restore rollback verification — four independent, fail-closed dimensions.

Run AFTER `backend/scripts/restore.py` has rebuilt a target database from a
`backend/scripts/backup.py` dump (see `docs/operations/database-recovery.md`).
This tool answers: did the restore actually land the state the backup
recorded, not just "did the process exit 0"?

Four dimensions (E12-R26 round brief §0.0.1 P4):

  1. migration head   — live DB `MigrationContext.get_current_heads()` vs the
                         backup dump's recorded `revision`.
  2. record counts    — live DB per-table row count vs the backup dump's
                         per-table row count (ADR 0487 D1: "it connects, so
                         it's fine" is not evidence — this is numeric).
  3. model manifest    — `assets/ml/model_manifest.json` (`schema_version`,
                         `models[].filename/sha256`) vs the on-disk files'
                         actual `hashlib.sha256`.
  4. flag profile      — a supplied EXPECTED flag-value profile vs a supplied
                         OBSERVED one, both `{"<flag key>": <bool>}` JSON.
                         This tool does not parse Dart (no machine-readable
                         flag profile exists on the tree today) — both
                         profiles are inputs, not derived here.

Fail-closed contract (the [L566](../../docs/LESSONS.md#l566) hibaosztály
against a dimension that goes quietly "SKIPPED" and exits 0):

  - A missing, unreadable, or unparseable input is a FAIL for that dimension
    — never SKIPPED.
  - The ONLY dimension that can be left out is `flag_profile`, and only via
    the explicit `--no-flag-profile` CLI switch (or `skip_flag_profile=True`
    in the importable core) — the opt-out is itself visible in the report
    (`status == "SKIPPED"`, with a stated reason).
  - Any `FAIL` in the report makes the overall report `ok == False`, and the
    CLI exits non-zero.
  - Every dimension carries a measured `elapsed_seconds` — this is the input
    the disaster-recovery drill log's machine-checked duration cells read.

Depends on the standard library plus the backend's already-installed
dependencies (SQLAlchemy, Alembic) — no new pip package. Importable, with a
clean functional core (`check_*` / `run_verification`) so
`backend/tests/test_rollback_drill.py` can call it directly, not just via the
CLI `main()`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Engine

_REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_MODEL_MANIFEST_RELPATH = "assets/ml/model_manifest.json"

_STATUS_PASS = "PASS"
_STATUS_FAIL = "FAIL"
_STATUS_SKIPPED = "SKIPPED"

# `alembic_version` is migration bookkeeping, not application data — it is
# never in a `backup.py` dump and must be excluded from the live/dump table
# SET comparison explicitly, not by accident of the dump never mentioning it.
_MIGRATION_BOOKKEEPING_TABLES = frozenset({"alembic_version"})


@dataclass
class DimensionResult:
    name: str
    status: str
    detail: str
    elapsed_seconds: float

    @property
    def ok(self) -> bool:
        # Allowlist, not a `!= FAIL` denylist (MINOR-6): an unknown or
        # mistyped status must fail closed, not default to `ok=True`.
        return self.status in (_STATUS_PASS, _STATUS_SKIPPED)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "status": self.status,
            "detail": self.detail,
            "elapsed_seconds": round(self.elapsed_seconds, 6),
        }


@dataclass
class VerifyReport:
    dimensions: list[DimensionResult] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return all(dimension.ok for dimension in self.dimensions)

    def to_dict(self) -> dict:
        return {"ok": self.ok, "dimensions": [d.to_dict() for d in self.dimensions]}

    def format(self) -> str:
        lines = [
            f"[{d.status}] {d.name} ({d.elapsed_seconds:.3f}s): {d.detail}"
            for d in self.dimensions
        ]
        lines.append(f"OVERALL: {'PASS' if self.ok else 'FAIL'}")
        return "\n".join(lines)


def _make_engine(database_url: str) -> Engine:
    connect_args = (
        {"check_same_thread": False} if database_url.startswith("sqlite") else {}
    )
    return create_engine(database_url, connect_args=connect_args)


# ---------------------------------------------------------------------------
# Input loading — every load path returns (value, error) instead of raising,
# so a missing/unreadable/unparseable input becomes a FAIL dimension, never
# an uncaught exception that would abort the whole report.
# ---------------------------------------------------------------------------


def load_backup(path: str | Path) -> tuple[dict | None, str | None]:
    try:
        raw = Path(path).read_text()
    except OSError as exc:
        return None, f"cannot read backup dump {path}: {exc}"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"backup dump {path} is not valid JSON: {exc}"
    if not isinstance(data, dict) or "tables" not in data:
        return None, f"backup dump {path} is missing the expected 'tables' key"
    return data, None


def load_flag_profile(path: str | Path) -> tuple[dict | None, str | None]:
    try:
        raw = Path(path).read_text()
    except OSError as exc:
        return None, f"cannot read flag profile {path}: {exc}"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"flag profile {path} is not valid JSON: {exc}"
    if not isinstance(data, dict):
        return None, f"flag profile {path} must be a JSON object of {{flagKey: bool}}"
    for key, value in data.items():
        if not isinstance(value, bool):
            # MAJOR-4: never echo `value` — an operator who points this at a
            # backup dump by mistake (also "a JSON file path") would leak
            # PII/password hashes into stdout, --json, and the drill log.
            return None, (
                f"flag profile {path} key {key!r} must be a boolean, "
                f"got a {type(value).__name__}"
            )
    return data, None


# ---------------------------------------------------------------------------
# Dimension 1 — migration head
# ---------------------------------------------------------------------------


def check_migration_head(
    database_url: str,
    backup: dict | None,
    *,
    backup_error: str | None = None,
) -> DimensionResult:
    start = time.perf_counter()
    if backup_error is not None or backup is None:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "migration_head",
            _STATUS_FAIL,
            backup_error or "backup dump unavailable",
            elapsed,
        )
    expected_revision = backup.get("revision")
    if not expected_revision:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "migration_head",
            _STATUS_FAIL,
            "backup dump has no recorded revision",
            elapsed,
        )
    try:
        engine = _make_engine(database_url)
        try:
            with engine.connect() as connection:
                heads = MigrationContext.configure(connection).get_current_heads()
        finally:
            engine.dispose()
    except Exception as exc:  # noqa: BLE001 -- MINOR-2: fail-closed on ANY
        # error (e.g. a missing driver module raises ModuleNotFoundError,
        # not a SQLAlchemyError) — this dimension must still report FAIL
        # instead of an uncaught traceback that skips the rest of the report.
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "migration_head",
            _STATUS_FAIL,
            f"could not read live migration head: {exc}",
            elapsed,
        )
    live_head = next(iter(heads), None)
    elapsed = time.perf_counter() - start
    if live_head != expected_revision:
        return DimensionResult(
            "migration_head",
            _STATUS_FAIL,
            f"live head {live_head!r} != backup revision {expected_revision!r}",
            elapsed,
        )
    return DimensionResult("migration_head", _STATUS_PASS, f"head={live_head}", elapsed)


# ---------------------------------------------------------------------------
# Dimension 2 — per-table record counts (ADR 0487 D1: numeric, not "it
# connects so it's fine")
# ---------------------------------------------------------------------------


def check_record_counts(
    database_url: str,
    backup: dict | None,
    *,
    backup_error: str | None = None,
) -> DimensionResult:
    start = time.perf_counter()
    if backup_error is not None or backup is None:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "record_counts",
            _STATUS_FAIL,
            backup_error or "backup dump unavailable",
            elapsed,
        )
    tables = backup.get("tables")
    if not isinstance(tables, dict) or not tables:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "record_counts", _STATUS_FAIL, "backup dump has no 'tables' data", elapsed
        )
    try:
        engine = _make_engine(database_url)
        mismatches: list[str] = []
        try:
            # MAJOR-1: compare the LIVE database's ACTUAL table set against
            # the dump's, not `Base.metadata.sorted_tables` (only the ORM
            # models `app.models` registers — 2 tables — while migrations
            # create Community tables via raw DDL with no ORM model, so a
            # live schema can hold 29). Every set difference is a FAIL: a
            # live table the dump never covered would otherwise be silently
            # `continue`d past, and a restore that lost 27/29 tables read
            # as "2 table(s) match".
            live_tables = (
                set(inspect(engine).get_table_names()) - _MIGRATION_BOOKKEEPING_TABLES
            )
            dump_tables = set(tables)

            for name in sorted(live_tables - dump_tables):
                mismatches.append(
                    f"{name}: present in the live database but not covered by "
                    "the backup dump"
                )
            for name in sorted(dump_tables - live_tables):
                mismatches.append(
                    f"{name}: present in the backup dump but not a live database table"
                )

            compared = sorted(live_tables & dump_tables)
            with engine.connect() as connection:
                quote = connection.dialect.identifier_preparer.quote
                for name in compared:
                    info = tables[name]
                    expected_count = (
                        info.get("count") if isinstance(info, dict) else None
                    )
                    if expected_count is None:
                        mismatches.append(f"{name}: backup dump missing a count")
                        continue
                    actual_count = connection.execute(
                        text(f"SELECT COUNT(*) FROM {quote(name)}")
                    ).scalar_one()
                    if actual_count != expected_count:
                        mismatches.append(
                            f"{name}: expected={expected_count} actual={actual_count}"
                        )
        finally:
            engine.dispose()
    except Exception as exc:  # noqa: BLE001 -- MINOR-2, see check_migration_head
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "record_counts",
            _STATUS_FAIL,
            f"could not read live record counts: {exc}",
            elapsed,
        )
    elapsed = time.perf_counter() - start
    if mismatches:
        return DimensionResult(
            "record_counts", _STATUS_FAIL, "; ".join(mismatches), elapsed
        )
    # The PASS text states the number ACTUALLY compared (live ∩ dump), never
    # the dump's table count — the pre-fix text made a 2/29 comparison read
    # as complete.
    return DimensionResult(
        "record_counts", _STATUS_PASS, f"{len(compared)} table(s) compared", elapsed
    )


# ---------------------------------------------------------------------------
# Dimension 3 — model manifest vs on-disk checksums
# ---------------------------------------------------------------------------


def check_model_manifest(
    project_root: str | Path,
    manifest_relpath: str = DEFAULT_MODEL_MANIFEST_RELPATH,
) -> DimensionResult:
    start = time.perf_counter()
    manifest_path = Path(project_root) / manifest_relpath
    try:
        raw = manifest_path.read_text()
    except OSError as exc:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "model_manifest",
            _STATUS_FAIL,
            f"cannot read {manifest_path}: {exc}",
            elapsed,
        )
    try:
        manifest = json.loads(raw)
    except json.JSONDecodeError as exc:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "model_manifest",
            _STATUS_FAIL,
            f"{manifest_path} is not valid JSON: {exc}",
            elapsed,
        )
    if not isinstance(manifest, dict):
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "model_manifest",
            _STATUS_FAIL,
            f"{manifest_path} root must be a JSON object",
            elapsed,
        )

    mismatches: list[str] = []
    if manifest.get("schema_version") != 1:
        mismatches.append(
            f"schema_version={manifest.get('schema_version')!r}, expected 1"
        )
    models = manifest.get("models")
    if not isinstance(models, list) or not models:
        mismatches.append("manifest 'models' must be a non-empty list")
        models = []
    project_root_resolved = Path(project_root).resolve()
    for entry in models:
        if not isinstance(entry, dict):
            # MAJOR-4: keys/type only, never the content — same rule as
            # `load_flag_profile`.
            mismatches.append(
                f"malformed models[] entry: expected an object, got a "
                f"{type(entry).__name__}"
            )
            continue
        filename = entry.get("filename")
        rel_path = entry.get("path")
        expected_sha = entry.get("sha256")
        if not filename or not rel_path or not expected_sha:
            mismatches.append(
                "malformed models[] entry: missing filename/path/sha256; "
                f"keys present={sorted(entry.keys())}"
            )
            continue
        # MINOR-1: the resolved asset path must stay UNDER project_root — an
        # absolute path (`/etc/passwd`) or a `..`-escape must FAIL, not be
        # read and hashed. A manifest is a followed input, but the
        # model-rollback use case is exactly a manifest arriving from a
        # RESTORED package, where the trust level is lower than "on this
        # tree today".
        asset_path = (Path(project_root) / rel_path).resolve()
        try:
            asset_path.relative_to(project_root_resolved)
        except ValueError:
            mismatches.append(
                f"{filename}: path {rel_path!r} escapes project_root, refusing "
                "to read it"
            )
            continue
        if not asset_path.is_file():
            mismatches.append(f"{filename}: missing on disk at {rel_path}")
            continue
        actual_sha = hashlib.sha256(asset_path.read_bytes()).hexdigest()
        if actual_sha != expected_sha:
            mismatches.append(
                f"{filename}: sha256 mismatch expected={expected_sha} actual={actual_sha}"
            )
    elapsed = time.perf_counter() - start
    if mismatches:
        return DimensionResult(
            "model_manifest", _STATUS_FAIL, "; ".join(mismatches), elapsed
        )
    return DimensionResult(
        "model_manifest", _STATUS_PASS, f"{len(models)} model(s) verified", elapsed
    )


# ---------------------------------------------------------------------------
# Dimension 4 — flag profile (expected vs observed, both supplied inputs;
# this tool never parses Dart — §0.0.1 P4's measured constraint)
# ---------------------------------------------------------------------------


def check_flag_profile(
    expected: dict | None,
    observed: dict | None,
    *,
    expected_error: str | None = None,
    observed_error: str | None = None,
) -> DimensionResult:
    start = time.perf_counter()
    if expected_error is not None or expected is None:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "flag_profile",
            _STATUS_FAIL,
            expected_error or "expected flag profile unavailable",
            elapsed,
        )
    if observed_error is not None or observed is None:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "flag_profile",
            _STATUS_FAIL,
            observed_error or "observed flag profile unavailable",
            elapsed,
        )
    # MAJOR-3: an empty `{}` profile on EITHER side must FAIL, not PASS — an
    # empty `expected`/`observed` pair makes `all_keys` empty, so the
    # comparison loop below never runs and would otherwise report
    # "0 flag(s) match" as PASS. That is worse than `--no-flag-profile`: it
    # is invisible in the report as an opt-out, and it bypasses P4's rule
    # that the ONLY way to leave this dimension out is the explicit switch.
    if not expected:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "flag_profile",
            _STATUS_FAIL,
            "expected flag profile is empty — a dimension must compare at "
            "least one key; use --no-flag-profile to opt out explicitly",
            elapsed,
        )
    if not observed:
        elapsed = time.perf_counter() - start
        return DimensionResult(
            "flag_profile",
            _STATUS_FAIL,
            "observed flag profile is empty — a dimension must compare at "
            "least one key; use --no-flag-profile to opt out explicitly",
            elapsed,
        )

    mismatches: list[str] = []
    all_keys = sorted(set(expected) | set(observed))
    for key in all_keys:
        if key not in expected:
            mismatches.append(f"{key}: present in observed profile but not in expected")
        elif key not in observed:
            mismatches.append(f"{key}: missing from observed profile")
        elif expected[key] != observed[key]:
            mismatches.append(
                f"{key}: expected={expected[key]} observed={observed[key]}"
            )
    elapsed = time.perf_counter() - start
    if mismatches:
        return DimensionResult(
            "flag_profile", _STATUS_FAIL, "; ".join(mismatches), elapsed
        )
    return DimensionResult(
        "flag_profile", _STATUS_PASS, f"{len(all_keys)} flag(s) match", elapsed
    )


def skipped_flag_profile(reason: str) -> DimensionResult:
    return DimensionResult("flag_profile", _STATUS_SKIPPED, reason, 0.0)


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


def run_verification(
    *,
    database_url: str,
    backup_path: str | Path,
    project_root: str | Path,
    manifest_relpath: str = DEFAULT_MODEL_MANIFEST_RELPATH,
    expected_flag_profile_path: str | Path | None = None,
    observed_flag_profile_path: str | Path | None = None,
    skip_flag_profile: bool = False,
) -> VerifyReport:
    backup, backup_error = load_backup(backup_path)
    dimensions = [
        check_migration_head(database_url, backup, backup_error=backup_error),
        check_record_counts(database_url, backup, backup_error=backup_error),
        check_model_manifest(project_root, manifest_relpath),
    ]

    if skip_flag_profile:
        dimensions.append(
            skipped_flag_profile(
                "--no-flag-profile: flag-profile dimension explicitly opted out"
            )
        )
    else:
        if expected_flag_profile_path is None:
            expected, expected_error = None, "no --expected-flag-profile given"
        else:
            expected, expected_error = load_flag_profile(expected_flag_profile_path)
        if observed_flag_profile_path is None:
            observed, observed_error = None, "no --observed-flag-profile given"
        else:
            observed, observed_error = load_flag_profile(observed_flag_profile_path)
        dimensions.append(
            check_flag_profile(
                expected,
                observed,
                expected_error=expected_error,
                observed_error=observed_error,
            )
        )

    return VerifyReport(dimensions=dimensions)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--database-url", required=True, help="the RESTORED target's URL"
    )
    parser.add_argument(
        "--backup",
        required=True,
        help="path to the backup.py JSON dump the restore used",
    )
    parser.add_argument("--project-root", default=str(_REPO_ROOT))
    parser.add_argument("--model-manifest", default=DEFAULT_MODEL_MANIFEST_RELPATH)
    parser.add_argument("--expected-flag-profile", default=None)
    parser.add_argument("--observed-flag-profile", default=None)
    parser.add_argument(
        "--no-flag-profile",
        action="store_true",
        help=(
            "explicitly opt out of the flag-profile dimension — the skip is "
            "reported, never silent; must be stated in the drill log too"
        ),
    )
    parser.add_argument(
        "--json", action="store_true", help="emit the report as JSON instead of prose"
    )
    args = parser.parse_args(argv)

    report = run_verification(
        database_url=args.database_url,
        backup_path=args.backup,
        project_root=args.project_root,
        manifest_relpath=args.model_manifest,
        expected_flag_profile_path=args.expected_flag_profile,
        observed_flag_profile_path=args.observed_flag_profile,
        skip_flag_profile=args.no_flag_profile,
    )

    if args.json:
        print(json.dumps(report.to_dict(), indent=2, sort_keys=True))
    else:
        print(report.format())

    return 0 if report.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
