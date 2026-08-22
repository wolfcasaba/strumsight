"""Add the Community follow and follow-request tables (E09-R07).

Revision ID: e09_r07_0005
Revises: e09_r04_0004
Create Date: 2026-08-22

This migration introduces the two tables that back the social-graph
lifecycle (ADR 0401 §4–5, brief §5.1 / §5.4):

* ``community_follows`` — one row per active follow edge
  (follower → followed). Self-follow is forbidden by ``CHECK``.
  Duplicate edges are forbidden by ``UNIQUE``.

* ``community_follow_requests`` — at most one row per
  (requester, target) pair; the row is recycled (``UPDATE``-on-replay)
  across follow/decline/cancel/refollow cycles so the plain
  ``UNIQUE`` constraint enforces the "at most one open request per
  pair" invariant without needing a partial index (dialect-portable
  between SQLite and PostgreSQL — ADR 0401 §4). Self-targeting is
  forbidden by ``CHECK``.

Both FKs cascade on the parent ``community_profiles.id`` row's
deletion so a profile removal cleans up its graph in the same
transaction (mirrors the Kör 2 / Kör 3 pattern).

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard)
sees the new tables as part of the expected schema. The migration
body uses raw ``sa.Column`` calls — the schema is the
migration-source-of-truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the social-graph ORM models with ``Base.metadata`` so that
# ``alembic compare_metadata`` (round-12 migration-contract test,
# ``backend/tests/test_migrations.py``) sees the new tables as part
# of the expected schema. The migration body itself does not rely on
# the model classes — it uses raw ``sa.Column`` calls so the schema
# is migration-source-of-truth, not ORM-derived autogenerate.
from app.community.models.social_graph import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityFollow,
    CommunityFollowRequest,
)

revision: str = "e09_r07_0005"
down_revision: str | Sequence[str] | None = "e09_r04_0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the social-graph schema on top of the Kör 4 community schema."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    # community_follows — one row per active follow edge.
    # UNIQUE on (follower, followed) is the §6.1 A2 enforcement:
    # a race between two concurrent follow calls cannot land two rows.
    # CHECK on (follower != followed) is the §6.1 A1 enforcement:
    # self-follow is impossible at the DB layer, not just the service
    # layer.
    op.create_table(
        "community_follows",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("follower_profile_id", _bigint, nullable=False),
        sa.Column("followed_profile_id", _bigint, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["follower_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_follows_follower_community_profiles",
        ),
        sa.ForeignKeyConstraint(
            ["followed_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_follows_followed_community_profiles",
        ),
        sa.UniqueConstraint(
            "follower_profile_id",
            "followed_profile_id",
            name="uq_community_follows_follower_followed",
        ),
        sa.CheckConstraint(
            "follower_profile_id != followed_profile_id",
            name="ck_community_follows_no_self_follow",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_follows_public_id",
        "community_follows",
        ["public_id"],
        unique=True,
    )
    # The explicit named unique index backs the UniqueConstraint. The
    # ``UniqueConstraint`` DDL would create an auto-named
    # ``sqlite_autoindex_*`` that the §6.1 valódi-sértés próba cannot
    # target deterministically — by creating the index here too, the
    # regression test can drop it by name, exercise the duplicate
    # path, and restore it. The UniqueConstraint remains in place as
    # the contract; the index is the physical enforcement surface.
    op.create_index(
        "ix_community_follows_pair_unique",
        "community_follows",
        ["follower_profile_id", "followed_profile_id"],
        unique=True,
    )
    # The pagination query orders by (followed_profile_id, created_at
    # DESC, id DESC) for "followers of X" lists. The composite index
    # matches the query plan exactly so the round-gate's A5 cursor
    # pagination test does not depend on a full scan.
    op.create_index(
        "ix_community_follows_followed_created",
        "community_follows",
        ["followed_profile_id", "created_at", "id"],
        unique=False,
    )
    op.create_index(
        "ix_community_follows_follower_created",
        "community_follows",
        ["follower_profile_id", "created_at", "id"],
        unique=False,
    )

    # community_follow_requests — one row per (requester, target)
    # pair, recycled across follow/decline/cancel/refollow cycles.
    # The plain UNIQUE on (requester, target) enforces "at most one
    # row per pair" — the service layer reads the current row and
    # UPDATEs its `status` on a re-request, so the constraint blocks
    # the race-window INSERT path (the §6.1 A2 cell).
    # `status` is plain String per the project-wide `visibility` /
    # `audience_default` pattern (ADR 0398 §1) — DB-level CHECK is
    # intentionally absent so the value-set can grow without a
    # migration.
    op.create_table(
        "community_follow_requests",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("requester_profile_id", _bigint, nullable=False),
        sa.Column("target_profile_id", _bigint, nullable=False),
        sa.Column(
            "status",
            sa.String(),
            nullable=False,
            server_default="requested",
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("responded_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["requester_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_follow_requests_requester_community_profiles",
        ),
        sa.ForeignKeyConstraint(
            ["target_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_follow_requests_target_community_profiles",
        ),
        sa.UniqueConstraint(
            "requester_profile_id",
            "target_profile_id",
            name="uq_community_follow_requests_pair",
        ),
        sa.CheckConstraint(
            "requester_profile_id != target_profile_id",
            name="ck_community_follow_requests_no_self_request",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_follow_requests_public_id",
        "community_follow_requests",
        ["public_id"],
        unique=True,
    )
    # Explicit named unique index for the pair constraint — see the
    # rationale on ``ix_community_follows_pair_unique``. The
    # §6.1 valódi-sértés próba for A2 targets this name.
    op.create_index(
        "ix_community_follow_requests_pair_unique",
        "community_follow_requests",
        ["requester_profile_id", "target_profile_id"],
        unique=True,
    )
    # Pending-request lookups read by (target_profile_id, status);
    # accepted/declined lookups (for the caller's own history) read
    # by (requester_profile_id, created_at DESC). Two indexes, both
    # narrow, keep the cursor pagination deterministic.
    op.create_index(
        "ix_community_follow_requests_target_status",
        "community_follow_requests",
        ["target_profile_id", "status"],
        unique=False,
    )
    op.create_index(
        "ix_community_follow_requests_requester_created",
        "community_follow_requests",
        ["requester_profile_id", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the social-graph schema in FK-safe order."""
    op.drop_index(
        "ix_community_follow_requests_requester_created",
        table_name="community_follow_requests",
    )
    op.drop_index(
        "ix_community_follow_requests_target_status",
        table_name="community_follow_requests",
    )
    op.drop_index(
        "ix_community_follow_requests_pair_unique",
        table_name="community_follow_requests",
    )
    op.drop_index(
        "ix_community_follow_requests_public_id",
        table_name="community_follow_requests",
    )
    op.drop_table("community_follow_requests")

    op.drop_index(
        "ix_community_follows_follower_created",
        table_name="community_follows",
    )
    op.drop_index(
        "ix_community_follows_followed_created",
        table_name="community_follows",
    )
    op.drop_index(
        "ix_community_follows_pair_unique",
        table_name="community_follows",
    )
    op.drop_index(
        "ix_community_follows_public_id",
        table_name="community_follows",
    )
    op.drop_table("community_follows")