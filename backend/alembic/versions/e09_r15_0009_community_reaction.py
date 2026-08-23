"""Add the Community reactions table (E09-R15).

Revision ID: e09_r15_0009
Revises: e09_r13_0008
Create Date: 2026-08-23

This migration introduces the ``community_reactions`` table — one
row per ``(post, viewer)`` pair. The first-version allowlist is
``{support, celebrate, inspiring, helpful}`` (brief §3); negative /
downvote reactions are explicitly out of scope (SDD §14.1).

The schema follows the same ``public UUID + bigint PK`` convention
as the Kör 2–8 tables (ADR 0396 §1) but does NOT carry a
``public_id`` column: the reaction is private to the viewer/post
pair and is never surfaced as a wire resource. The wire projection
that includes ``viewerReaction`` + ``reactionCount`` on a post is
the §0.0 D2 deferred scope — a later round wires the projection
into ``PostOut`` / ``FeedPostItem`` and the
``backend/app/community/routers/posts.py::_row_to_out`` helper.

* ``id`` — BigInteger internal PK, variant to Integer on SQLite for
  autoincrement portability (same seam used by Kör 5–13 migrations).
* ``post_id`` — FK to ``community_posts.id`` with
  ``ondelete='CASCADE'`` so a post hard-delete (the future
  retention policy) cleans up its reactions in the same
  transaction. Soft-delete leaves the row in place — the count
  column on the projection simply excludes soft-deleted posts
  upstream (the §5.3 / D7 invariant).
* ``profile_id`` — FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'`` so a profile deletion removes its
  reactions in the same transaction (the Kör 7 follow-graph
  precedent).
* ``kind`` — plain ``String`` (the project-wide ``visibility`` /
  ``audience_default`` pattern from ADR 0398 §1). The value set is
  enforced at the service boundary
  (``reaction_service.is_allowed_reaction_kind``); the DB does NOT
  constrain it — a column-level CHECK would block the
  §6.1 valódi-sértés próba, which removes the application-level
  allowlist to verify the unique constraint catches duplicate
  rows. Adding a CHECK constraint is the §6.1 cell's "next step".
* ``created_at`` / ``updated_at`` — ``DateTime(timezone=True)``.
  ``updated_at`` is the timestamp the service bumps on a kind-change
  UPDATE — a future audit-log read can reconstruct the kind history.
* ``UNIQUE(post_id, profile_id)`` — the §6 A1 invariant. A retry
  with the same kind hits the existing row (no duplicate, no
  count-doubling). A retry with a different kind translates the
  IntegrityError into an UPDATE in the service layer (the §6 A2
  "kind change is update, not insert" invariant).

Importing the ORM model here registers it with ``Base.metadata``
so ``alembic compare_metadata`` (the round-12 migration-contract
guard, ``backend/tests/test_migrations.py``) sees the new table
as part of the expected schema. The migration body uses raw
``sa.Column`` calls — the schema is the migration-source-of-truth,
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
from app.community.models.reaction import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityReaction,
)

revision: str = "e09_r15_0009"
down_revision: str | Sequence[str] | None = "e09_r13_0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the community_reactions table on top of the Kör 13 feed-index schema."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_reactions",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("post_id", _bigint, nullable=False),
        sa.Column("profile_id", _bigint, nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["post_id"],
            ["community_posts.id"],
            ondelete="CASCADE",
            name="fk_community_reactions_post_community_posts",
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_reactions_profile_community_profiles",
        ),
        # §6 A1 — duplicate set with the same (post, profile) lands
        # on the existing row, never a second row.
        sa.UniqueConstraint(
            "post_id",
            "profile_id",
            name="uq_community_reactions_post_profile",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    # Composite index backing the "viewer reactions on this post"
    # query path AND the "did viewer react" projection read. The
    # unique constraint above already provides index coverage on
    # (post_id, profile_id), but a separate index on (post_id)
    # alone is what the count aggregation plan hits — keeping it
    # explicit so the planner has a stable shape regardless of the
    # UNIQUE backing index being switched in a future refactor.
    op.create_index(
        "ix_community_reactions_post",
        "community_reactions",
        ["post_id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the community_reactions schema in FK-safe order."""
    op.drop_index("ix_community_reactions_post", table_name="community_reactions")
    op.drop_table("community_reactions")
