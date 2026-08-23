"""Add the Community bookmarks table (E09-R17, ADR 0408).

Revision ID: e09_r17_0011
Revises: e09_r16_0010
Create Date: 2026-08-23

This migration introduces the ``community_bookmarks`` table — the
private "saved by me" surface on top of the Kör 11
``community_posts`` table. One row per ``(post, viewer)`` pair.
The bookmark is a binary existence predicate: the row exists, or
it does not. There is no kind / category / annotation column.

The schema follows the same ``public UUID + bigint PK`` convention
as the Kör 2–16 tables (ADR 0396 §1) but does NOT carry a
``public_id`` column: the bookmark is private to the viewer/post
pair and is never surfaced as a wire resource.

* ``id`` — BigInteger internal PK, variant to Integer on SQLite for
  autoincrement portability (same ``_bigint`` seam used by Kör
  5–16 migrations).
* ``post_id`` — FK to ``community_posts.id`` with
  ``ondelete='CASCADE'`` so a post hard-delete (the future
  retention policy) cleans up its bookmarks in the same
  transaction. Soft-delete leaves the row in place — the bookmark-
  list query is responsible for emitting a tombstone element (D3 /
  §5.2).
* ``profile_id`` — FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'`` so a profile deletion removes its
  bookmarks in the same transaction (the Kör 5 follow-graph
  precedent).
* ``created_at`` — ``DateTime(timezone=True)`` — the cursor key
  (D4, ``(created_at DESC, id DESC)`` pagination).
* ``UNIQUE(post_id, profile_id)`` — the §6 A1 invariant. A retry
  with the same pair hits the existing row (no duplicate, no
  count-doubling). The composite ``(profile_id, created_at, id)``
  index backs the caller's own bookmark list pagination.

Importing the ORM model here registers it with ``Base.metadata``
so ``alembic compare_metadata`` (round-12 migration-contract test)
sees the new table as part of the expected schema. The migration
body itself does not rely on the model class — it uses raw
``sa.Column`` calls so the schema is migration-source-of-truth,
not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test)
# sees the new table as part of the expected schema. The migration
# body itself does not rely on the model class — it uses raw
# ``sa.Column`` calls so the schema is migration-source-of-truth,
# not ORM-derived autogenerate.
from app.community.models.bookmark import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityBookmark,
)

revision: str = "e09_r17_0011"
down_revision: str | Sequence[str] | None = "e09_r16_0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the community_bookmarks table on top of the Kör 16 comment schema."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_bookmarks",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("post_id", _bigint, nullable=False),
        sa.Column("profile_id", _bigint, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["post_id"],
            ["community_posts.id"],
            ondelete="CASCADE",
            name="fk_community_bookmarks_post_community_posts",
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_bookmarks_profile_community_profiles",
        ),
        # §6 A1 — duplicate set with the same (post, profile) lands
        # on the existing row, never a second row.
        sa.UniqueConstraint(
            "post_id",
            "profile_id",
            name="uq_community_bookmarks_post_profile",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    # Composite index backing the caller's own bookmark list
    # pagination — the D4 cursor keyset
    # ``(created_at DESC, id DESC)`` keyed on ``profile_id``.
    op.create_index(
        "ix_community_bookmarks_profile_created",
        "community_bookmarks",
        ["profile_id", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the community_bookmarks schema in FK-safe order."""
    op.drop_index(
        "ix_community_bookmarks_profile_created",
        table_name="community_bookmarks",
    )
    op.drop_table("community_bookmarks")
