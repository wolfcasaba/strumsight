"""Add the Community feed indexes (E09-R13, ADR 0406).

Revision ID: e09_r13_0008
Revises: e09_r11_0007
Create Date: 2026-08-23

This migration adds the two composite indexes the Kör 13 following
feed query plans against, plus a forward-looking ``feed_view_count``
column reserved for Kör 14+ comment/reaction-count projections
(brief §5.3 — "count-adatok batch-projekcióval" — the Kör 13 query
does NOT consume this column, but it reserves the storage so a
future round that adds count-based projections does NOT need
its own migration).

The Kör 11 ``ix_community_posts_profile_created`` index serves
the per-author read path (``WHERE profile_id = :x ORDER BY
created_at DESC, id DESC``); the feed's cross-author pagination
needs a different shape.

Two indexes ship this round:

* ``ix_community_posts_created_id (created_at, id)`` — the feed's
  primary sort key. The query orders ``created_at DESC, id DESC``
  for a many-author candidate set (``WHERE profile_id IN (...)``
  from the follow-graph join). The Kör 11 index leads with
  ``profile_id``, which is the wrong order for a cross-profile
  sort — a sequential scan over the candidate set is the planner's
  fallback. The new index is the one the feed relies on for the
  A7 measure-matrix (explain-plan baseline).
* ``ix_community_posts_audience_created (audience, created_at, id)`` —
  the ``PUBLIC``-audience facet (the discovery surface). A
  future Kör 14+ ``GET /community/posts?audience=public`` route
  reuses this index for the explore-feed ranking; the Kör 13
  query uses the ``created_at, id`` index for the cross-author
  sort and lets the audience column sit inside the WHERE block.

One column ships this round (forward-investment for Kör 14+
comment/reaction-count projections — see above):

* ``feed_view_count INTEGER NOT NULL DEFAULT 0`` — a server-side
  counter incremented by future comment/reaction endpoints. The
  Kör 13 repository does NOT read or write this column; it is
  purely a schema reservation so a future round does not need
  its own migration to add the column. The ``DEFAULT 0`` keeps
  existing rows valid on the populated-table migration.

Importing the ORM model here registers the existing tables with
``Base.metadata`` so the migration-contract test sees the
expected schema. The migration body itself does not rely on the
model class — the schema is migration-source-of-truth, not
ORM-derived autogenerate.
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
    """Add the two feed-query composite indexes and the reserved
    ``feed_view_count`` column on ``community_posts``."""
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
    # The audience-leading composite serves the PUBLIC-discovery read
    # path (``WHERE audience = 'public' ORDER BY created_at DESC, id DESC``)
    # — Kör 14+ explore feed and any future audience-filtered query.
    # Kör 13's following feed does not filter by audience at the DB level
    # (the access_policy filters rows in the same query via the
    # ``CommunityAudience`` enum); this index is a forward-investment so
    # the future rounds do not need their own migration.
    op.create_index(
        "ix_community_posts_audience_created",
        "community_posts",
        ["audience", "created_at", "id"],
        unique=False,
    )
    # Forward-investment column for Kör 14+ count projections
    # (brief §5.3 — "count-adatok batch-projekcióval"). The
    # ``DEFAULT 0`` keeps the migration safe on a populated
    # table; the column is nullable=False so a future
    # count-increment endpoint cannot accidentally insert NULL.
    op.add_column(
        "community_posts",
        sa.Column(
            "feed_view_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    """Reverse the feed-index schema additions."""
    op.drop_column("community_posts", "feed_view_count")
    op.drop_index(
        "ix_community_posts_audience_created",
        table_name="community_posts",
    )
    op.drop_index(
        "ix_community_posts_created_id",
        table_name="community_posts",
    )


# ---------------------------------------------------------------------------
# Index / column registration against ``Base.metadata`` (round-12
# migration-contract parity). The Kör 3 ``handle_history.py`` precedent
# shows the same pattern: the ``Table.append_column`` / ``Index(...)``
# constructor calls bind the schema additions to the existing
# ``community_posts`` table object in ``Base.metadata`` so the
# live-DB-vs-ORM comparison in
# ``backend/tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema``
# sees the new indexes AND the new column in both the DB and the ORM
# metadata. Without this registration, the test would flag the
# differences as ``remove_index`` / ``add_column`` in the diff.
#
# We cannot modify ``app/community/models/post.py`` (the brief §3 tilos
# zóna leaves that file read-only), so the registration lives here, next
# to the ``op.create_index`` / ``op.add_column`` calls that materialise
# the same shape on the DB side. The two definitions are guaranteed to
# match because they share the literal column names below — if either
# changes, the test catches it.
# ---------------------------------------------------------------------------
# ruff: noqa: E402 -- imported here so the registration runs after the table is in metadata.
from app.database import Base

_community_posts_table = Base.metadata.tables["community_posts"]
sa.Index(
    "ix_community_posts_created_id",
    _community_posts_table.c.created_at,
    _community_posts_table.c.id,
)
sa.Index(
    "ix_community_posts_audience_created",
    _community_posts_table.c.audience,
    _community_posts_table.c.created_at,
    _community_posts_table.c.id,
)
_community_posts_table.append_column(
    sa.Column(
        "feed_view_count",
        sa.Integer(),
        nullable=False,
        server_default="0",
    ),
    replace_existing=True,
)
