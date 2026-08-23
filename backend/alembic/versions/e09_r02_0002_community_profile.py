"""Add the Community profile and privacy-settings tables.

Revision ID: e09_r02_0002
Revises: e01_r12_0001
Create Date: 2026-08-22

E09-R02, ADR 0396 §1–2, §5.

The schema follows the brief §8 1. lépés: ``BigInteger`` internal PK (NEVER
serialised) + ``Uuid`` public_id (PostgreSQL native UUID on Postgres,
``CHAR(32)`` on SQLite — SQLAlchemy 2.0 dialect-portable, no manual string
conversion).

The 1:1 invariants are enforced by database-level ``UNIQUE`` constraints on
``community_profiles.user_id`` and ``community_privacy_settings.profile_id``
— A7. The ``ondelete="CASCADE"`` foreign keys mirror the existing
``user_settings`` pattern (round 120 / ADR 0060 §8), so a parent
``users`` deletion cleans up its Community row in the same transaction.

No backfill, no ``get_or_create`` (ADR 0395 Következmények + ADR 0396
§5.1): the migration creates the schema only, and the service-layer will
create rows on explicit onboarding (a Kör 6 surface).

The ``render_as_batch`` mode is enabled in ``alembic/env.py`` (driven by
SQLite's lack of ``ALTER`` for some constraints); both ``upgrade`` and
``downgrade`` are idempotent so the round-gate can be re-run against a
fresh SQLite in CI.
"""

# Register the Community ORM models with ``Base.metadata`` so that
# ``alembic compare_metadata`` (used by the round-12 migration-contract
# tests) sees the same surface as the production schema. Without this, the
# autogenerate diff would flag the Community tables/indexes as "missing
# from metadata" — a false positive that would break the existing
# ``test_upgrade_head_matches_current_orm_schema`` guard. Importing the
# module here is safe because (a) ``alembic upgrade`` loads every revision
# before applying any of them, and (b) the migration body itself does not
# rely on the model classes — it uses raw ``sa.Column`` calls so the
# schema is migration-source-of-truth, not ORM-derived.
from app.community.models.profile import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityPrivacySettings,
    CommunityProfile,
)

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "e09_r02_0002"
down_revision: str | Sequence[str] | None = "e01_r12_0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the Community schema on top of the account baseline."""
    # Dialect-portable column type: BigInteger on PostgreSQL (native bigserial),
    # Integer on SQLite (so the rowid-based autoincrement kicks in — the box
    # runs SQLite for CI, PostgreSQL for production). The ORM model mirrors
    # this exact variant so ``compare_metadata`` stays clean (ADR 0396 §1).
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_profiles",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("user_id", _bigint, nullable=False, unique=True),
        sa.Column("display_name", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
            name="fk_community_profiles_user_id_users",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_profiles_public_id",
        "community_profiles",
        ["public_id"],
        unique=True,
    )

    op.create_table(
        "community_privacy_settings",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("profile_id", _bigint, nullable=False, unique=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_privacy_settings_profile_id_community_profiles",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_privacy_settings_public_id",
        "community_privacy_settings",
        ["public_id"],
        unique=True,
    )


def downgrade() -> None:
    """Drop the Community schema in reverse FK order."""
    op.drop_index(
        "ix_community_privacy_settings_public_id",
        table_name="community_privacy_settings",
    )
    op.drop_table("community_privacy_settings")
    op.drop_index("ix_community_profiles_public_id", table_name="community_profiles")
    op.drop_table("community_profiles")