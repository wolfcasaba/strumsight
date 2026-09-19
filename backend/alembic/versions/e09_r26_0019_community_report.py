"""Add the Community report table (E09-R26, ADR 0422 §5.1).

Revision ID: e09_r26_0019
Revises: e09_r25_0019
Create Date: 2026-08-24

The new ``community_reports`` table is the persistence layer for the
user-report workflow (brief §1, §3, §5). The table has two
UNIQUE constraints — both load-bearing:

* ``uq_community_reports_dedup_key`` — the §6 A2 dedup key
  ``f"{reporter_profile_id}:{target_type}:{target_id}:{category}"``.
  Two concurrent submits on the same triple cannot both land; the
  service layer reads the existing row and short-circuits the second
  writer to success (same precedent as ``CommunityBlock`` /
  ``CommunityFollow``).

* ``uq_community_reports_reporter_target_category`` — the structural
  invariant: every ``(reporter, target_type, target_id, category)``
  quadruple can land AT MOST ONE row, independent of the dedup-key
  format. A future round that changes the dedup-key format will
  still be guarded.

The ``reporter_profile_id`` FK cascades so removing a reporter cleans
up their report rows in the same transaction. The model does NOT
expose this FK to the wire — the §5.1 retaliation-risk invariant is
enforced at the model layer by omission and at the service layer by
sanitization.

``target_type`` is a plain ``String(32)`` with ``server_default='post'``,
mirroring the project-wide ``visibility`` / ``audience_default``
pattern (ADR 0398 §1). The DB does not constrain the value set —
:mod:`app.community.services.report_service` rejects unknown values
BEFORE the INSERT (§6 A5 / §6.1 measure-matrix).

``extra_metadata_json`` is the §3 optional detail column used by the
``copyright`` / ``privacy`` categories for a minimal evidence payload
(URL of the source, etc.). For all other categories it is NULL. The
service layer's response-sanitization helper drops the column from
any wire response.

The composite ``(target_type, target_id, created_at, id)`` index is
the Kör 27 moderation queue's read-path index — cheap to add now,
fixed contract.

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` (round-12 migration-contract test,
``backend/tests/test_migrations.py``) sees the new table as part of
the expected schema.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the report ORM model with ``Base.metadata`` so the
# migration-contract test sees the new table. The migration body
# itself uses raw ``sa.Column`` calls — the schema is the migration
# source of truth, not ORM-derived autogenerate.
from app.community.models.report import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityReport,
)

revision: str = "e09_r26_0019"
down_revision: str | Sequence[str] | None = "e09_r25_0019"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the community_reports table on top of Kör 25."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_reports",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("reporter_profile_id", _bigint, nullable=False),
        sa.Column(
            "target_type",
            sa.String(length=32),
            nullable=False,
            server_default="post",
        ),
        sa.Column("target_id", sa.String(length=64), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("extra_metadata_json", sa.Text(), nullable=True),
        sa.Column("dedup_key", sa.String(length=200), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column(
            "target_deleted_at_submit",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.ForeignKeyConstraint(
            ["reporter_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_reports_reporter_community_profiles",
        ),
        sa.UniqueConstraint(
            "dedup_key",
            name="uq_community_reports_dedup_key",
        ),
        sa.UniqueConstraint(
            "reporter_profile_id",
            "target_type",
            "target_id",
            "category",
            name="uq_community_reports_reporter_target_category",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_reports_public_id",
        "community_reports",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        "ix_community_reports_target_created",
        "community_reports",
        ["target_type", "target_id", "created_at", "id"],
        unique=False,
    )
    op.create_index(
        "ix_community_reports_reporter_created",
        "community_reports",
        ["reporter_profile_id", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the report schema in index-then-table order."""
    op.drop_index(
        "ix_community_reports_reporter_created",
        table_name="community_reports",
    )
    op.drop_index(
        "ix_community_reports_target_created",
        table_name="community_reports",
    )
    op.drop_index(
        "ix_community_reports_public_id",
        table_name="community_reports",
    )
    op.drop_table("community_reports")
