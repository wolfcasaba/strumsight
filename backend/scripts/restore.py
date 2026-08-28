"""Rebuild a target database from a `backup.py` JSON dump.

The schema is built with **Alembic only** — never `create_all` or hand-written
DDL (ADR 0060, ADR 0449 D5): `command.upgrade()` walks the target to the
revision recorded in the backup, then the dumped rows are reloaded.

A target that already holds application data is never silently overwritten
(ADR 0449 D4). The default target is an empty/non-existent database. To
overwrite a target that already has rows, BOTH of the following are
required, and either missing or mismatched aborts with no data touched:

    --force
    --confirm-target <the literal --target-name value>

Usage:
    python scripts/restore.py --database-url sqlite:///staging.db \\
        --input backup.json --target-name staging-primary

See docs/operations/database-recovery.md for the full runbook.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

from alembic.config import Config as AlembicConfig
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import DateTime, create_engine, func, inspect, select
from sqlalchemy.engine import Engine

from alembic import command
from app import models as _models  # noqa: F401 -- registers ORM metadata
from app.database import Base

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_SCRIPTS = _BACKEND_ROOT / "alembic"


class RestoreRejected(Exception):
    """Raised when a restore is refused. Nothing is modified when this is
    raised — every check that can raise it runs before any write."""


def _make_engine(database_url: str) -> Engine:
    connect_args = (
        {"check_same_thread": False} if database_url.startswith("sqlite") else {}
    )
    return create_engine(database_url, connect_args=connect_args)


def _alembic_config() -> AlembicConfig:
    config = AlembicConfig(str(_ALEMBIC_INI))
    config.set_main_option("script_location", str(_ALEMBIC_SCRIPTS))
    return config


@contextmanager
def _database_url_env(database_url: str):
    """`alembic/env.py` reads the target from `Settings().database_url`
    (STRUMSIGHT_DATABASE_URL), not from the Config object — so the upgrade
    must be pointed at the restore target via the environment, scoped to the
    call and restored afterwards."""
    previous = os.environ.get("STRUMSIGHT_DATABASE_URL")
    os.environ["STRUMSIGHT_DATABASE_URL"] = database_url
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop("STRUMSIGHT_DATABASE_URL", None)
        else:
            os.environ["STRUMSIGHT_DATABASE_URL"] = previous


def _existing_row_counts(engine: Engine, table_names) -> dict[str, int]:
    present = set(inspect(engine).get_table_names())
    counts: dict[str, int] = {}
    with engine.connect() as connection:
        for table in Base.metadata.sorted_tables:
            if table.name not in table_names or table.name not in present:
                continue
            counts[table.name] = connection.execute(
                select(func.count()).select_from(table)
            ).scalar_one()
    return counts


def _deserialize_row(table, raw_row: dict) -> dict:
    values = {}
    for column in table.columns:
        if column.name not in raw_row:
            continue
        value = raw_row[column.name]
        if value is not None and isinstance(column.type, DateTime):
            value = datetime.fromisoformat(value)
        values[column.name] = value
    return values


def restore_database(
    database_url: str,
    backup: dict,
    *,
    target_name: str,
    force: bool = False,
    confirm_target: str | None = None,
) -> dict:
    """Rebuild `database_url` from `backup` (as produced by
    `backup.dump_database`). Raises `RestoreRejected` — leaving the target
    untouched — if the backup's revision is unknown, if the target's current
    schema head is already set and does not match the backup's revision (an
    `alembic upgrade` never moves a target backwards, so restoring an older
    backup over a newer schema would otherwise leave it silently
    inconsistent), or if the target already holds data and the double
    confirmation (`force` AND `confirm_target == target_name`) is not
    satisfied (ADR 0449 D4/D5)."""
    if not target_name:
        raise RestoreRejected("target_name is required")

    backup_revision = backup.get("revision")
    known_revisions = {
        rev.revision
        for rev in ScriptDirectory.from_config(_alembic_config()).walk_revisions()
    }
    if backup_revision is None or backup_revision not in known_revisions:
        raise RestoreRejected(
            f"backup revision {backup_revision!r} is not part of the "
            "migration chain — refusing to restore"
        )

    tables = backup.get("tables", {})
    engine = _make_engine(database_url)
    try:
        with engine.connect() as connection:
            target_heads = MigrationContext.configure(connection).get_current_heads()
        target_head = next(iter(target_heads), None)
        if target_head is not None and target_head != backup_revision:
            raise RestoreRejected(
                f"target schema is at {target_head!r}, which does not match "
                f"the backup's revision {backup_revision!r} — an upgrade "
                "cannot move the target backwards, so restoring would leave "
                "it in an inconsistent state; refusing"
            )

        existing_counts = _existing_row_counts(engine, tables.keys())
        has_data = any(count > 0 for count in existing_counts.values())
        if has_data and not (force and confirm_target == target_name):
            raise RestoreRejected(
                "target already contains data; refusing to overwrite without "
                "--force AND a --confirm-target matching --target-name"
            )

        with _database_url_env(database_url):
            command.upgrade(_alembic_config(), backup_revision)

        with engine.begin() as connection:
            if has_data:
                for table in reversed(Base.metadata.sorted_tables):
                    if table.name in tables:
                        connection.execute(table.delete())
            for table in Base.metadata.sorted_tables:
                info = tables.get(table.name)
                if not info or not info["rows"]:
                    continue
                rows = [_deserialize_row(table, row) for row in info["rows"]]
                connection.execute(table.insert(), rows)
    finally:
        engine.dispose()

    return {
        "revision": backup_revision,
        "tables": {name: info["count"] for name, info in tables.items()},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Restore a StrumSight backend backup.json dump."
    )
    parser.add_argument(
        "--database-url", required=True, help="destination SQLAlchemy database URL"
    )
    parser.add_argument("--input", required=True, help="path to the backup.json dump")
    parser.add_argument(
        "--target-name",
        required=True,
        help="human label for the destination; must be repeated verbatim via "
        "--confirm-target to overwrite a target that already has data",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="required (with --confirm-target) to overwrite",
    )
    parser.add_argument(
        "--confirm-target",
        default=None,
        help="must equal --target-name exactly to overwrite",
    )
    args = parser.parse_args(argv)

    backup = json.loads(Path(args.input).read_text())
    try:
        result = restore_database(
            args.database_url,
            backup,
            target_name=args.target_name,
            force=args.force,
            confirm_target=args.confirm_target,
        )
    except RestoreRejected as exc:
        print(f"restore refused: {exc}", file=sys.stderr)
        return 2

    table_summary = ", ".join(
        f"{name}={count}" for name, count in result["tables"].items()
    )
    print(f"restore complete (revision={result['revision']}, {table_summary})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
