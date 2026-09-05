"""Add Community moderation queue, enforcement and appeal tables (E09-R27, ADR 0425).

Revision ID: e09_r27_0020
Revises: e09_r26_0019
Create Date: 2026-08-24

The migration introduces three tables that close the §D-decisions
recorded in ADR 0425:

* ``community_moderators`` — D1, the moderator-identity source. A
  unique ``user_id`` FK to ``users.id`` (``ondelete="CASCADE"``)
  with a non-FK ``granted_by_user_id`` audit column (mirrors the
  Kör 19 ``reviewer_id`` precedent — ADR 0412 §D5). The brief §4
  tilos zóna forbids adding a ``role`` / ``is_admin`` column to
  ``User`` / ``CommunityProfile``; this table is the ONLY
  site-wide moderator grant.

* ``community_moderation_cases`` — D2/D3/D6/D8, the case row. Five
  possible ``state`` values (``visible`` / ``limited`` /
  ``pending_review`` / ``removed`` / ``author_only``), an
  ``appeal_state`` column (NULL / ``submitted`` / ``resolved``),
  a denormalized ``is_open`` flag for indexable queue reads, and
  a ``priority_score`` column the service layer computes from the
  three documented inputs (D8).

* ``community_moderation_actions`` — D5, the immutable audit row.
  INSERT-only — the table deliberately has NO ``updated_at``
  column, the structural signal that no UPDATE will land
  (A3 measure-matrix cell).

Importing the ORM models here registers the three tables with
``Base.metadata`` so ``alembic compare_metadata`` (the round-12
migration-contract guard, ``backend/tests/test_migrations.py``)
sees them as part of the expected schema.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the ORM models with ``Base.metadata`` so the
# migration-contract test sees the new tables.
from app.community.models.moderation import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityModerationAction,
    CommunityModerationCase,
    CommunityModerator,
)

revision: str = "e09_r27_0020"
down_revision: str | Sequence[str] | None = "e09_r26_0019"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the three moderation tables on top of Kör 26."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    # ---------------------------------------------------------------------------
    # community_moderators — D1
    # ---------------------------------------------------------------------------
    op.create_table(
        "community_moderators",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("user_id", _bigint, nullable=False),
        sa.Column(
            "granted_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column("granted_by_user_id", _bigint, nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
            name="fk_community_moderators_user_users",
        ),
        sa.UniqueConstraint("user_id", name="uq_community_moderators_user_id"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_moderators_user_id",
        "community_moderators",
        ["user_id"],
        unique=True,
    )

    # ---------------------------------------------------------------------------
    # community_moderation_cases — D2/D3/D6/D8
    # ---------------------------------------------------------------------------
    op.create_table(
        "community_moderation_cases",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("target_type", sa.String(length=32), nullable=False),
        sa.Column("target_id", sa.String(length=64), nullable=False),
        sa.Column(
            "state",
            sa.String(length=32),
            nullable=False,
            server_default="visible",
        ),
        sa.Column("appeal_state", sa.String(length=32), nullable=True),
        sa.Column(
            "priority_score",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "is_open",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.Column(
            "opened_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_moderation_cases_public_id",
        "community_moderation_cases",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        "ix_community_moderation_cases_priority",
        "community_moderation_cases",
        ["is_open", "priority_score", "opened_at", "id"],
        unique=False,
    )
    op.create_index(
        "ix_community_moderation_cases_target_open",
        "community_moderation_cases",
        ["target_type", "target_id", "is_open"],
        unique=False,
    )

    # ---------------------------------------------------------------------------
    # community_moderation_actions — D5 (no updated_at column)
    # ---------------------------------------------------------------------------
    op.create_table(
        "community_moderation_actions",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("case_id", _bigint, nullable=False),
        sa.Column("action_type", sa.String(length=32), nullable=False),
        sa.Column("from_state", sa.String(length=32), nullable=True),
        sa.Column("to_state", sa.String(length=32), nullable=True),
        sa.Column("actor_type", sa.String(length=16), nullable=False),
        sa.Column("actor_user_id", _bigint, nullable=True),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("evidence_json", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["case_id"],
            ["community_moderation_cases.id"],
            ondelete="CASCADE",
            name="fk_community_moderation_actions_case",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_moderation_actions_public_id",
        "community_moderation_actions",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        "ix_community_moderation_actions_case_created",
        "community_moderation_actions",
        ["case_id", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the moderation schema in reverse-dependency order."""
    op.drop_index(
        "ix_community_moderation_actions_case_created",
        table_name="community_moderation_actions",
    )
    op.drop_index(
        "ix_community_moderation_actions_public_id",
        table_name="community_moderation_actions",
    )
    op.drop_table("community_moderation_actions")

    op.drop_index(
        "ix_community_moderation_cases_target_open",
        table_name="community_moderation_cases",
    )
    op.drop_index(
        "ix_community_moderation_cases_priority",
        table_name="community_moderation_cases",
    )
    op.drop_index(
        "ix_community_moderation_cases_public_id",
        table_name="community_moderation_cases",
    )
    op.drop_table("community_moderation_cases")

    op.drop_index(
        "ix_community_moderators_user_id",
        table_name="community_moderators",
    )
    op.drop_table("community_moderators")