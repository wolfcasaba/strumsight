"""Add the Community comments table (E09-R16, ADR 0407).

Revision ID: e09_r16_0010
Revises: e09_r15_0009
Create Date: 2026-08-23

This migration introduces the ``community_comments`` table — the
comment layer on top of the Kör 11 ``community_posts`` surface. The
schema follows the same ``public UUID + bigint PK`` pattern as the
Kör 2–15 tables (ADR 0396 §1) and reuses every existing convention:

* ``id`` — BigInteger internal PK, variant to Integer on SQLite for
  autoincrement portability (same ``_bigint`` seam used by Kör
  5–15 migrations).
* ``public_id`` — ``Uuid(as_uuid=True)``, ``unique=True``,
  ``index=True``, default ``uuid.uuid4``. The wire shape only ever
  carries the public_id; the internal ``id`` is the join surface.
* ``post_id`` — FK to ``community_posts.id`` with
  ``ondelete='CASCADE'`` so a post hard-delete (the future retention
  policy) cleans up its comments in the same transaction. Soft-delete
  leaves the rows in place — the list query is responsible for
  filtering (the Kör 11 §D7 uniform-404 invariant at the post level
  prevents soft-deleted posts from being visible to viewers in the
  first place).
* ``author_profile_id`` — FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'`` so a profile deletion removes its comments
  in the same transaction (the Kör 5 follow-graph precedent).
* ``parent_id`` — self-FK to ``community_comments.id``, nullable for
  top-level (depth 0) comments, set to the parent row's id for a
  reply. ``ondelete='CASCADE'`` so deleting a parent comment also
  removes its reply chain.
* ``depth`` — plain ``Integer``, NOT NULL, default 0. Top-level
  comments are ``depth=0``; a reply has ``depth = parent.depth + 1``.
  The service layer rejects ``create_comment`` when the parent
  ``depth >= 1`` so no row with ``depth >= 2`` ever lands (the §6.1
  valódi-sértés próba removes this guard and asserts the A1 cell
  goes red).
* ``body`` — ``String(1000)``, the wire-shape max length (brief
  §14.2). The service layer re-validates the same bound via the
  ``COMMENT_BODY_MAX_LENGTH`` constant. TEXT would be more idiomatic
  on PostgreSQL; keeping the explicit length pins the schema
  contract on both dialects (the Kör 11 post-body seam).
* ``moderation_state`` — plain ``String`` with
  ``server_default='visible'`` (ADR 0407 §D5 — the Kör 11 two-value
  pattern, NOT the Dart ``ModerationState`` five-state enum). The
  active moderation workflow is Kör 26/27 scope; this round only
  consumes the field, never writes a value other than the default.
* ``created_at`` / ``updated_at`` — ``DateTime(timezone=True)``.
  ``updated_at`` doubles as the resource-version token (ADR 0398 §6
  precedent; ADR 0407 §D1 — NO separate ``version`` column).
* ``deleted_at`` — nullable ``DateTime(timezone=True)``, the
  soft-delete tombstone (D7 uniform-404 invariant at the row level).

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard,
``backend/tests/test_migrations.py``) sees the new table as part of
the expected schema. The migration body uses raw ``sa.Column`` calls
— the schema is the migration-source-of-truth, not ORM-derived
autogenerate.
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
from app.community.models.comment import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityComment,
)

revision: str = "e09_r16_0010"
down_revision: str | Sequence[str] | None = "e09_r15_0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the community_comments table on top of the Kör 15 reaction schema."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_comments",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("post_id", _bigint, nullable=False),
        sa.Column("author_profile_id", _bigint, nullable=False),
        # Self-FK for the reply chain (ADR 0407 §D4). Nullable for
        # top-level comments.
        sa.Column("parent_id", _bigint, nullable=True),
        # Explicit depth column — NOT NULL, default 0. The service
        # rejects create_comment when parent.depth >= 1 so no row
        # with depth >= 2 ever lands (§6.1 valódi-sértés próba
        # target).
        sa.Column(
            "depth",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("body", sa.String(length=1000), nullable=False),
        sa.Column(
            "moderation_state",
            sa.String(),
            nullable=False,
            server_default="visible",
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["post_id"],
            ["community_posts.id"],
            ondelete="CASCADE",
            name="fk_community_comments_post_community_posts",
        ),
        sa.ForeignKeyConstraint(
            ["author_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_comments_author_community_profiles",
        ),
        sa.ForeignKeyConstraint(
            ["parent_id"],
            ["community_comments.id"],
            ondelete="CASCADE",
            name="fk_community_comments_parent_community_comments",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_comments_public_id",
        "community_comments",
        ["public_id"],
        unique=True,
    )
    # Two composite indexes back the comment list pagination:
    # * (post_id, parent_id, created_at, id) — the per-post list
    #   paginator. Top-level comments come first (parent_id IS NULL),
    #   then replies, ordered by (created_at DESC, id DESC) per ADR
    #   0407 §D6.
    op.create_index(
        "ix_community_comments_post_parent_created",
        "community_comments",
        ["post_id", "parent_id", "created_at", "id"],
        unique=False,
    )
    # * (post_id, created_at, id) — the unfiltered fallback when the
    #   parent_id filter isn't pushed down (the §0.0 "every query
    #   path through the same index" preference).
    op.create_index(
        "ix_community_comments_post_created",
        "community_comments",
        ["post_id", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the community_comments schema in FK-safe order."""
    op.drop_index(
        "ix_community_comments_post_created",
        table_name="community_comments",
    )
    op.drop_index(
        "ix_community_comments_post_parent_created",
        table_name="community_comments",
    )
    op.drop_index(
        "ix_community_comments_public_id",
        table_name="community_comments",
    )
    op.drop_table("community_comments")