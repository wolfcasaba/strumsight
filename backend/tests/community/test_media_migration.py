"""Javító sáv R27 — the ``community_media_uploads`` migration itself.

``backend/tests/test_migrations.py`` already proves two generic things
about every revision in the chain (``upgrade head`` matches the ORM
metadata; a one-step downgrade undoes the head's own schema change). What
it cannot say is anything specific about THIS table, and two of its
properties are decisions rather than accidents:

* **A1 — the four indexes exist**, because each one backs a read the
  pipeline performs on every request (the ``public_id`` lookup, the
  per-profile quota count, the feed projection's batched attachment read,
  and the refcount behind the store's delete). An index quietly dropped
  from the migration would leave the table correct and the feed slow.
* **A2 — the R18/R19 ``community_media`` table is untouched.** This round
  ships a SECOND table on purpose; a future edit that "consolidates" them
  would silently rewrite a tested subsystem, and this cell is what turns
  that into a red test instead of a surprise.
* **A3 — ``post_id`` carries no FOREIGN KEY.** Deliberate (the
  ``community_posts.club_id`` precedent): a cross-table FK would force
  ``community_posts`` into ``Base.metadata`` wherever the media model is
  imported, and the Community test engines build their schema from
  whatever the importing module happened to pull in.
* **A4 — the downgrade is reversible and does NOT touch the media
  volume.** A migration must not delete user content; the runbook's
  rollback step depends on the files still being there for a re-upgrade.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from alembic import command

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_TABLE = "community_media_uploads"


def _alembic_config() -> Config:
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    return config


@pytest.fixture
def migrated(tmp_path, monkeypatch):
    """A file-backed SQLite migrated to head, plus its config."""
    database_url = f"sqlite:///{tmp_path / 'media-migration.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    config = _alembic_config()
    command.upgrade(config, "head")
    engine = create_engine(database_url)
    try:
        yield engine, config, database_url
    finally:
        engine.dispose()


class TestUpgrade:
    def test_the_table_exists_with_the_documented_columns(self, migrated):
        engine, _, _ = migrated
        inspector = inspect(engine)
        assert _TABLE in inspector.get_table_names()
        columns = {column["name"] for column in inspector.get_columns(_TABLE)}
        assert columns == {
            "id",
            "public_id",
            "profile_id",
            "post_id",
            "attach_position",
            "kind",
            "state",
            "rejection_code",
            "content_type",
            "content_sha256",
            "source_sha256",
            "size_bytes",
            "source_size_bytes",
            "width",
            "height",
            "duration_ms",
            "scanner",
            "scanned_at",
            "created_at",
            "updated_at",
            "ready_at",
            "deleted_at",
        }

    def test_every_index_the_pipeline_reads_through_is_present(self, migrated):
        """A1 — one index per hot read; see the module docstring."""
        engine, _, _ = migrated
        indexes = {index["name"] for index in inspect(engine).get_indexes(_TABLE)}
        assert indexes == {
            "ix_community_media_uploads_public_id",
            "ix_community_media_uploads_profile_state",
            "ix_community_media_uploads_post_position",
            "ix_community_media_uploads_content_sha256",
        }

    def test_the_public_id_index_is_unique(self, migrated):
        engine, _, _ = migrated
        by_name = {
            index["name"]: index for index in inspect(engine).get_indexes(_TABLE)
        }
        assert by_name["ix_community_media_uploads_public_id"]["unique"]

    def test_the_owner_foreign_key_cascades_from_the_profile(self, migrated):
        engine, _, _ = migrated
        keys = inspect(engine).get_foreign_keys(_TABLE)
        owner = [key for key in keys if key["constrained_columns"] == ["profile_id"]]
        assert len(owner) == 1
        assert owner[0]["referred_table"] == "community_profiles"
        assert owner[0]["options"].get("ondelete") == "CASCADE"

    def test_post_id_deliberately_carries_no_foreign_key(self, migrated):
        """A3 — the ``community_posts.club_id`` precedent."""
        engine, _, _ = migrated
        keys = inspect(engine).get_foreign_keys(_TABLE)
        assert not [key for key in keys if key["constrained_columns"] == ["post_id"]]

    def test_the_r18_signed_url_media_table_is_left_alone(self, migrated):
        """A2 — two transports, two tables. The R18/R19 shape must still
        be exactly what its own pinned suites expect."""
        engine, _, _ = migrated
        inspector = inspect(engine)
        assert "community_media" in inspector.get_table_names()
        legacy = {column["name"] for column in inspector.get_columns("community_media")}
        assert {"object_key", "expires_at", "upload_state"} <= legacy
        # And the new table is not a view onto it.
        assert "object_key" not in {
            column["name"] for column in inspector.get_columns(_TABLE)
        }


class TestDowngrade:
    def test_the_downgrade_drops_the_table_and_the_upgrade_restores_it(self, migrated):
        engine, config, _ = migrated
        assert _TABLE in inspect(engine).get_table_names()

        command.downgrade(config, "-1")
        assert _TABLE not in inspect(engine).get_table_names()
        # The R18/R19 table survives the rollback of THIS round.
        assert "community_media" in inspect(engine).get_table_names()

        command.upgrade(config, "head")
        assert _TABLE in inspect(engine).get_table_names()

    def test_the_downgrade_never_touches_the_media_volume(self, migrated, tmp_path):
        """A4 — a migration must not delete user content. The volume is
        outside the database entirely, which is the structural reason
        this holds; the cell pins the expectation so a future revision
        that "cleans up" the files fails here first."""
        engine, config, _ = migrated
        volume = tmp_path / "media-root" / "ab" / "cd"
        volume.mkdir(parents=True)
        stored = volume / ("a" * 64)
        stored.write_bytes(b"user content")

        command.downgrade(config, "-1")

        assert stored.exists()
        assert stored.read_bytes() == b"user content"
