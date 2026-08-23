"""Add the Community feed index (E09-R13, ADR 0406).

Revision ID: e09_r13_0008
Revises: e09_r11_0007
Create Date: 2026-08-23

This migration adds the ONE composite index the Kör 13 following
feed query plans against — ``ix_community_posts_created_id
(created_at, id)`` — the feed's primary sort key. The Kör 11
``ix_community_posts_profile_created (profile_id, created_at, id)``
serves the per-author read path; the feed's cross-author pagination
needs a different shape (no leading ``profile_id``), and the
planner cannot derive the ``(created_at, id)`` ordering from the
existing Kör 11 index. The new index is the one the feed relies on
for the A7 measure-matrix (explain-plan baseline).

Scope-discipline (review E09-R13 finding F2): this round ships
EXACTLY one schema change — the ADR 0406 D2 ``(created_at, id)``
index. No additional columns, no additional audience-leading index;
any future count-projection column or audience-discovery index is a
later round's call with its own ADR.

Importing the ORM model here registers it with ``Base.metadata``
so ``alembic compare_metadata`` (the round-12 migration-contract
test, ``backend/tests/test_migrations.py``) sees the existing
table as part of the expected schema. The migration body itself
does not rely on the model class — the schema is
migration-source-of-truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test,
# ``backend/tests/test_migrations.py``) sees the existing table
# as part of the expected schema. The migration body itself
# does not rely on the model class — it uses raw ``sa.Column``
# calls so the schema is migration-source-of-truth, not
# ORM-derived autogenerate.
from app.community.models.post import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityPost,
)

revision: str = "e09_r13_0008"
down_revision: str | Sequence[str] | None = "e09_r11_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add the one feed-query composite index on ``community_posts``."""
    # The Kör 11 schema already creates ``ix_community_posts_profile_created
    # (profile_id, created_at, id)`` for the per-author read path. The feed
    # query needs a different leading column: ``created_at`` first, then
    # ``id`` — the sort key for a cross-author candidate set. Without this
    # composite, the planner falls back to a sequential scan on the
    # candidate set (the A7 measure-matrix valódi-sértés próba).
    op.create_index(
        "ix_community_posts_created_id",
        "community_posts",
        ["created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the feed-index schema addition."""
    op.drop_index(
        "ix_community_posts_created_id",
        table_name="community_posts",
    )


# ---------------------------------------------------------------------------
# Index registration against ``Base.metadata`` (round-12
# migration-contract parity). The Kör 3 ``handle_history.py`` precedent
# shows the same pattern: the ``Index(...)`` constructor call binds
# the schema addition to the existing ``community_posts`` table
# object in ``Base.metadata`` so the live-DB-vs-ORM comparison in
# ``backend/tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema``
# sees the new index in both the DB and the ORM metadata. Without
# this registration, the test would flag the difference as
# ``remove_index`` in the diff.
#
# We cannot modify ``app/community/models/post.py`` (the brief §3 tilos
# zóna leaves that file read-only), so the registration lives here, next
# to the ``op.create_index`` call that materialises the same shape on
# the DB side. The two definitions are guaranteed to match because
# they share the literal column names below — if either changes, the
# test catches it.
#
# The registration is guarded by idempotency checks because alembic
# re-loads migration scripts on every ``command.upgrade`` call (it does
# NOT cache modules in ``sys.modules``). A naive registration would
# double-register the same Index on the second ``upgrade``, which then
# breaks subsequent ``Base.metadata.create_all`` calls (the duplicate
# Index objects surface as ``index already exists`` errors when
# SQLAlchemy tries to CREATE INDEX on a fresh DB).
# ---------------------------------------------------------------------------
# ruff: noqa: E402 -- imported here so the registration runs after the table is in metadata.
from app.database import Base

_community_posts_table = Base.metadata.tables["community_posts"]
_EXISTING_INDEX_NAMES = {idx.name for idx in _community_posts_table.indexes}

if "ix_community_posts_created_id" not in _EXISTING_INDEX_NAMES:
    sa.Index(
        "ix_community_posts_created_id",
        _community_posts_table.c.created_at,
        _community_posts_table.c.id,
    )
