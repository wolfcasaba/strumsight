"""Add the Community block and mute safety tables (E09-R08).

Revision ID: e09_r08_0006
Revises: e09_r07_0005
Create Date: 2026-08-22

This migration introduces the two safety-relationship tables that back
the block / mute state machine (ADR 0402 §D1, brief §5.1–5.3):

* ``community_blocks`` — one row per block edge
  (blocker → blocked). Both FKs cascade so removing a profile cleans
  up its block edges in the same transaction (mirrors the
  ``community_follows`` CASCADE pattern). Self-block is forbidden by
  ``CHECK``. Duplicate edges are forbidden by ``UNIQUE`` — the §6.1
  A1 / A2 race protection.

* ``community_mutes`` — one row per mute edge
  (muter → muted). Self-mute is forbidden by ``CHECK``. Duplicate
  edges are forbidden by ``UNIQUE``. Like ``community_blocks`` the
  CASCADE mirrors the existing follow pattern.

The block row is the SINGLE-FK pair uniqueness marker. The
follow/request cleanup that happens in ``block_service.py`` (the
D1 atomic transaction) is NOT modelled here — that lives in the
service layer because the rows it touches belong to other tables
(``community_follows`` / ``community_follow_requests``) which are
already migrated in ``e09_r07_0005``.

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` sees the new tables as part of the
expected schema. The migration body uses raw ``sa.Column`` calls —
the schema is the migration-source-of-truth, not ORM-derived
autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the safety-relationship ORM models with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test,
# ``backend/tests/test_migrations.py``) sees the new tables as part
# of the expected schema. The migration body itself does not rely on
# the model classes — it uses raw ``sa.Column`` calls.
from app.community.models.safety_relationships import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityBlock,
    CommunityMute,
)

revision: str = "e09_r08_0006"
down_revision: str | Sequence[str] | None = "e09_r07_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the safety-relationship schema on top of Kör 7."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    # community_blocks — one row per block edge (blocker → blocked).
    # UNIQUE on (blocker, blocked) is the §6.1 A2 race protection:
    # a concurrent retry from the same caller cannot land a second
    # row. CHECK on (blocker != blocked) is the same invariant the
    # follow tables enforce — self-block is impossible at the DB
    # layer.
    op.create_table(
        "community_blocks",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("blocker_profile_id", _bigint, nullable=False),
        sa.Column("blocked_profile_id", _bigint, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["blocker_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_blocks_blocker_community_profiles",
        ),
        sa.ForeignKeyConstraint(
            ["blocked_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_blocks_blocked_community_profiles",
        ),
        sa.UniqueConstraint(
            "blocker_profile_id",
            "blocked_profile_id",
            name="uq_community_blocks_blocker_blocked",
        ),
        sa.CheckConstraint(
            "blocker_profile_id != blocked_profile_id",
            name="ck_community_blocks_no_self_block",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_blocks_public_id",
        "community_blocks",
        ["public_id"],
        unique=True,
    )
    # The block-filter hot path reads by (blocker_profile_id) to list
    # a viewer's own blocked profiles, and by (blocked_profile_id)
    # to filter incoming viewers on the followers/following read path.
    # The two composite indexes match those queries exactly.
    op.create_index(
        "ix_community_blocks_blocker_created",
        "community_blocks",
        ["blocker_profile_id", "created_at", "id"],
        unique=False,
    )
    op.create_index(
        "ix_community_blocks_blocked_created",
        "community_blocks",
        ["blocked_profile_id", "created_at", "id"],
        unique=False,
    )

    # community_mutes — one row per mute edge (muter → muted).
    # Mirrors the community_blocks layout — UNIQUE on the pair, CHECK
    # against self-mute, CASCADE on both FKs.
    op.create_table(
        "community_mutes",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("muter_profile_id", _bigint, nullable=False),
        sa.Column("muted_profile_id", _bigint, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["muter_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_mutes_muter_community_profiles",
        ),
        sa.ForeignKeyConstraint(
            ["muted_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_mutes_muted_community_profiles",
        ),
        sa.UniqueConstraint(
            "muter_profile_id",
            "muted_profile_id",
            name="uq_community_mutes_muter_muted",
        ),
        sa.CheckConstraint(
            "muter_profile_id != muted_profile_id",
            name="ck_community_mutes_no_self_mute",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_mutes_public_id",
        "community_mutes",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        "ix_community_mutes_muter_created",
        "community_mutes",
        ["muter_profile_id", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the safety-relationship schema in FK-safe order."""
    op.drop_index(
        "ix_community_mutes_muter_created",
        table_name="community_mutes",
    )
    op.drop_index(
        "ix_community_mutes_public_id",
        table_name="community_mutes",
    )
    op.drop_table("community_mutes")

    op.drop_index(
        "ix_community_blocks_blocked_created",
        table_name="community_blocks",
    )
    op.drop_index(
        "ix_community_blocks_blocker_created",
        table_name="community_blocks",
    )
    op.drop_index(
        "ix_community_blocks_public_id",
        table_name="community_blocks",
    )
    op.drop_table("community_blocks")
