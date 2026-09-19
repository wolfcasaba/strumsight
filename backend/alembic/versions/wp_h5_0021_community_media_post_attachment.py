"""Attach community media to a post (WP-H5).

Revision ID: wp_h5_0021
Revises: e09_r27_0020
Create Date: 2026-09-06

Adds the single column that gives a media row an audience:
``community_media.post_id``, a nullable FK to ``community_posts.id``.

Why a nullable FK rather than an ``audience`` column on the media row:
the media's visibility is DERIVED from the post it hangs on
(``routers/media.py::_visible_media`` resolves it through
``post_service.get_post``, which already applies the audience + block +
soft-delete + moderation gate). A second ``audience`` column would be a
copy that can drift — a post edited down to ``private`` whose attached
recording stayed ``public`` is exactly the leak this shape cannot
express. NULL means "not attached yet", which the router reads as
owner-only.

``ondelete='SET NULL'``, not CASCADE: deleting a post must not destroy
the author's recording. The detached row falls back to owner-only
visibility, which is the correct fail-closed outcome.

The migration is strictly additive — no existing column, index or
constraint on ``community_media`` is touched, so the E09-R18 upload
state machine and the E09-R19 processing state machine are unchanged.

The inline ``sa.ForeignKey`` on the added column is what keeps SQLite
and PostgreSQL in agreement: SQLite cannot ``ADD CONSTRAINT`` after the
fact, but it does accept ``ALTER TABLE ... ADD COLUMN ... REFERENCES``,
so rendering the constraint inline is the one form both dialects take.
``tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema``
is the measurement — it runs ``compare_metadata`` against the ORM after
``upgrade head`` and requires an empty diff.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Side-effect import: registers the updated ORM model with
# ``Base.metadata`` so the migration-contract test's
# ``compare_metadata`` sees the new column as part of the expected
# schema. The migration body below does not use the class — the schema
# is migration-source-of-truth, not ORM-derived autogenerate.
from app.community.models.media import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityMedia,
)

revision: str = "wp_h5_0021"
down_revision: str | Sequence[str] | None = "e09_r27_0020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add ``community_media.post_id`` and its lookup index."""
    op.add_column(
        "community_media",
        sa.Column(
            "post_id",
            # BigInteger on PostgreSQL (matching community_posts.id),
            # Integer on SQLite — the same variant the ORM model
            # declares, so compare_metadata sees no type drift.
            sa.BigInteger().with_variant(sa.Integer, "sqlite"),
            sa.ForeignKey("community_posts.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index(
        "ix_community_media_post",
        "community_media",
        ["post_id"],
        unique=False,
    )


def downgrade() -> None:
    """Drop the index, then the column."""
    op.drop_index("ix_community_media_post", table_name="community_media")
    op.drop_column("community_media", "post_id")
