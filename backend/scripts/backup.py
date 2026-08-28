"""Dump every application row + the applied migration head to a JSON file.

The dump is the input `restore.py` needs to rebuild a target database: the
per-table rows, the per-table row count, and the migration revision the
source was AT when dumped (ADR 0449 D5 — the backup carries the head so the
restore can rebuild schema with Alembic instead of `create_all`).

Usage:
    python scripts/backup.py --database-url sqlite:///strumsight.db \\
        --output backup.json

See docs/operations/database-recovery.md for the full runbook.
"""

from __future__ import annotations

import argparse
import json
from datetime import date, datetime
from pathlib import Path

from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect, select
from sqlalchemy.engine import Engine

from app import models as _models  # noqa: F401 -- registers ORM metadata
from app.database import Base


def _make_engine(database_url: str) -> Engine:
    connect_args = (
        {"check_same_thread": False} if database_url.startswith("sqlite") else {}
    )
    return create_engine(database_url, connect_args=connect_args)


def _serialize(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def dump_database(database_url: str) -> dict:
    """Return a JSON-serializable snapshot of the applied migration head and
    every row, grouped by table in FK-dependency order."""
    engine = _make_engine(database_url)
    try:
        with engine.connect() as connection:
            heads = MigrationContext.configure(connection).get_current_heads()
            revision = next(iter(heads), None)
            present_tables = set(inspect(engine).get_table_names())

            tables: dict[str, dict] = {}
            for table in Base.metadata.sorted_tables:
                if table.name not in present_tables:
                    tables[table.name] = {"count": 0, "rows": []}
                    continue
                rows = [
                    {
                        column: _serialize(value)
                        for column, value in row._mapping.items()
                    }
                    for row in connection.execute(select(table))
                ]
                tables[table.name] = {"count": len(rows), "rows": rows}
    finally:
        engine.dispose()
    return {"revision": revision, "tables": tables}


def write_backup(database_url: str, output_path: str) -> dict:
    snapshot = dump_database(database_url)
    Path(output_path).write_text(json.dumps(snapshot, indent=2, sort_keys=True))
    return snapshot


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Dump StrumSight backend rows + the applied migration head."
    )
    parser.add_argument(
        "--database-url", required=True, help="source SQLAlchemy database URL"
    )
    parser.add_argument("--output", required=True, help="path to write the JSON dump")
    args = parser.parse_args(argv)

    snapshot = write_backup(args.database_url, args.output)
    table_summary = ", ".join(
        f"{name}={info['count']}" for name, info in snapshot["tables"].items()
    )
    print(
        f"backup written to {args.output} "
        f"(revision={snapshot['revision']}, {table_summary})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
