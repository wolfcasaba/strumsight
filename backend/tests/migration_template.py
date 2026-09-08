"""One `alembic upgrade head` per pytest process, reused by every fixture.

MEASURED (round 25, CI-class box): `command.upgrade(cfg, "head")` replays the
full 22-revision chain and costs ~0.30 s. Roughly twenty test modules
provisioned their SQLite database that way from a FUNCTION-scoped fixture, so
the suite replayed the chain once per test — hundreds of times — purely to
obtain a schema. That was the second-largest term in the backend gate's
runtime after bcrypt (the gate was cancelled at 14 min 56 s of a 15 min
limit).

`apply_head_schema()` keeps the property those fixtures actually depend on:
the schema still comes from the production Alembic chain, never from
`Base.metadata.create_all` (ADR 0060 / the E09-R02 "no create_all bootstrap"
contract). It replays the chain ONCE into a template database file and then
byte-copies that file for each caller, so every test still opens a database
that `alembic upgrade head` produced — including its `alembic_version` row,
which is what `/health/ready` and `community_readiness_failure` read.

Tests that assert something ABOUT migrating (upgrade/downgrade behaviour,
readiness on a stale head, the rollback drill, the in-process-migration
logging trap) deliberately keep calling `alembic.command` directly — this
helper is for provisioning only.
"""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

from alembic.config import Config

from alembic import command

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"

_TEMPLATE: Path | None = None


def alembic_config() -> Config:
    """The suite's standard Alembic config (ini + explicit script location)."""
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


def upgrade_to_head(database_url: str) -> None:
    """Really run `alembic upgrade head` against `database_url`.

    `alembic/env.py` resolves the URL through a fresh `Settings()`, i.e. from
    `STRUMSIGHT_DATABASE_URL`; it is set only for the duration of the call and
    restored afterwards so the caller's own environment is untouched.
    """
    previous = os.environ.get("STRUMSIGHT_DATABASE_URL")
    os.environ["STRUMSIGHT_DATABASE_URL"] = database_url
    try:
        command.upgrade(alembic_config(), "head")
    finally:
        if previous is None:
            os.environ.pop("STRUMSIGHT_DATABASE_URL", None)
        else:
            os.environ["STRUMSIGHT_DATABASE_URL"] = previous


def _template_database() -> Path:
    global _TEMPLATE
    if _TEMPLATE is None:
        directory = Path(tempfile.mkdtemp(prefix="strumsight-head-schema-"))
        template = directory / "head.db"
        upgrade_to_head(f"sqlite:///{template}")
        _TEMPLATE = template
    return _TEMPLATE


def apply_head_schema(db_path: str | Path) -> Path:
    """Materialize an `alembic upgrade head` SQLite database at `db_path`.

    Returns the path, so a fixture can write
    `db_path = apply_head_schema(tmp_path / "x.db")`.
    """
    destination = Path(db_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(_template_database(), destination)
    return destination
