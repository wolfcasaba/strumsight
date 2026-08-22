"""Add Community handle columns and the handle-history table.

Revision ID: e09_r03_0003
Revises: e09_r02_0002
Create Date: 2026-08-22

E09-R03, ADR 0397 §5.1, §5.4. The schema delta is small and surgical:

* ``community_profiles``: add ``handle_display`` (the raw form the user
  typed) and ``handle_normalized`` (the NFKC + casefold + strip result
  the policy module produces).
* ``community_profiles.handle_normalized``: UNIQUE INDEX. This is the
  §5.1 enforcement — uniqueness is on the normalized form, NOT on the
  raw display. The §6.1 valódi-sértés próba (swap the unique index to
  ``handle_display``) must turn the A1 cell red; that is the regression
  the migration structure protects against.
* ``community_handle_history``: a new table that records every handle
  change so the previous handle can redirect to the new one inside the
  redirect window (A6). The composite index on
  ``(profile_id, changed_at)`` matches the cooldown lookup query plan.

The ``render_as_batch`` mode is enabled in ``alembic/env.py`` (driven by
SQLite's lack of ``ALTER`` for some constraints); both ``upgrade`` and
``downgrade`` are idempotent so the round-gate can be re-run against a
fresh SQLite in CI.

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard) sees
the same surface as the production schema. The schema itself stays
migration-source-of-truth — the upgrade body uses raw ``sa.Column``
calls, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the handle-history ORM model with ``Base.metadata`` so that
# ``alembic compare_metadata`` sees the new table as part of the expected
# schema (round-12 migration-contract test). The migration body does not
# rely on the model classes — it uses raw ``sa.Column`` calls.
from app.community.models.handle_history import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityHandleHistory,
)

revision: str = "e09_r03_0003"
down_revision: str | Sequence[str] | None = "e09_r02_0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add the handle columns + the history table on top of the Kör 2 schema."""
    # The handle columns are NULL-able: the existing ``CommunityProfile``
    # rows from Kör 2 are pre-handle (creation was onboarding-only, the
    # handle comes from this round). The unique constraint is on the
    # normalized column and is partial-NULL-safe — multiple NULLs are
    # fine, only non-NULL duplicates collide.
    with op.batch_alter_table("community_profiles") as batch:
        batch.add_column(sa.Column("handle_display", sa.String(24), nullable=True))
        batch.add_column(sa.Column("handle_normalized", sa.String(24), nullable=True))

    # Unique index on the normalized column. The DB rejects duplicate
    # normalized handles; the service layer translates the IntegrityError
    # to a domain error (identity_service.commit_with_uniqueness_check).
    op.create_index(
        "ix_community_profiles_handle_normalized",
        "community_profiles",
        ["handle_normalized"],
        unique=True,
    )

    # Handle history table. ``id`` uses the same BigInteger/Integer
    # dialect-portable variant as the Kör 2 tables.
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")
    op.create_table(
        "community_handle_history",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("profile_id", _bigint, nullable=False),
        sa.Column("old_handle", sa.String(24), nullable=True),
        sa.Column("old_normalized", sa.String(24), nullable=True),
        sa.Column("new_handle", sa.String(24), nullable=False),
        sa.Column("new_normalized", sa.String(24), nullable=False),
        sa.Column("changed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("redirect_until", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_handle_history_profile_id_community_profiles",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    # Composite index that matches the cooldown lookup query plan
    # (profile_id, changed_at DESC LIMIT 1).
    op.create_index(
        "ix_community_handle_history_profile_changed",
        "community_handle_history",
        ["profile_id", "changed_at"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the handle schema in FK-safe order."""
    op.drop_index(
        "ix_community_handle_history_profile_changed",
        table_name="community_handle_history",
    )
    op.drop_table("community_handle_history")
    op.drop_index(
        "ix_community_profiles_handle_normalized",
        table_name="community_profiles",
    )
    with op.batch_alter_table("community_profiles") as batch:
        batch.drop_column("handle_normalized")
        batch.drop_column("handle_display")