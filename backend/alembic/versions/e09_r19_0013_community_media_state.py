"""Add media-processing state + moderation audit columns (E09-R19, ADR 0412).

Revision ID: e09_r19_0013
Revises: e09_r18_0012
Create Date: 2026-08-23

This migration adds the SECOND, INDEPENDENT state machine
(``processing_state``) and the A6 audit column set
(``moderation_decision`` / ``moderation_confidence`` /
``moderation_provider`` / ``moderation_provider_version`` /
``moderated_at``) to ``community_media``.

The migration is STRICTLY ADDITIVE: the ``upload_state`` column,
its allowlist, its indexes, and the Kör 18 transition set are
unchanged. The new ``processing_state`` column lives on the same
row but encodes a separate axis — transzport vs. content-processing
(ADR 0412 §D2).

Columns added (each nullable=False where a default applies):

* ``processing_state`` — ``String``, NOT NULL,
  ``server_default='uploaded'``. The seven-value machine is
  enforced at the task / service layer rather than the DB (the
  same pattern as ``upload_state`` and ``moderation_state``).
* ``moderation_decision`` — ``String(length=64)``, NULLABLE. Set
  by the human-review-gate path (``resolve_review``); NULL while
  the row is still in ``processing_state='review'``.
* ``moderation_confidence`` — ``Float``, NULLABLE. Set by the
  triage path; NULL until triage runs.
* ``moderation_provider`` — ``String(length=128)``, NULLABLE.
* ``moderation_provider_version`` — ``String(length=64)``, NULLABLE.
* ``moderated_at`` — ``DateTime(timezone=True)``, NULLABLE. The
  stamp of the LAST moderation write (decision or confidence,
  whichever the moderation flow wrote last).

A composite (profile_id, processing_state) index is added so the
post-fetch query that filters out non-ready media can use an
index. The existing (profile_id, upload_state) index is
INTENTIONALLY UNCHANGED — the two axes are independent.

Importing the ORM model here registers it with ``Base.metadata``
so ``alembic compare_metadata`` (round-12 migration-contract test)
sees the new columns as part of the expected schema. The
migration body itself uses raw ``sa.Column`` / ``op.add_column``
calls so the schema is migration-source-of-truth, not
ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test)
# sees the updated table as part of the expected schema. The
# migration body itself does not rely on the model class — it
# uses raw ``sa.Column`` calls so the schema is
# migration-source-of-truth, not ORM-derived autogenerate.
from app.community.models.media import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityMedia,
)

revision: str = "e09_r19_0013"
down_revision: str | Sequence[str] | None = "e09_r18_0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add the E09-R19 columns to ``community_media`` additively."""
    # The SECOND, independent state machine. ``upload_state`` and
    # its indexes are intentionally untouched.
    op.add_column(
        "community_media",
        sa.Column(
            "processing_state",
            sa.String(),
            nullable=False,
            server_default="uploaded",
        ),
    )
    # A6 acceptance audit columns — all nullable, populated by the
    # moderation flow as it runs.
    op.add_column(
        "community_media",
        sa.Column(
            "moderation_decision",
            sa.String(length=64),
            nullable=True,
        ),
    )
    op.add_column(
        "community_media",
        sa.Column(
            "moderation_confidence",
            sa.Float(),
            nullable=True,
        ),
    )
    op.add_column(
        "community_media",
        sa.Column(
            "moderation_provider",
            sa.String(length=128),
            nullable=True,
        ),
    )
    op.add_column(
        "community_media",
        sa.Column(
            "moderation_provider_version",
            sa.String(length=64),
            nullable=True,
        ),
    )
    op.add_column(
        "community_media",
        sa.Column(
            "moderated_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    # Composite (profile_id, processing_state) index backing the
    # post-fetch filter that drops non-ready media. Same naming
    # convention as the Kör 18 ``ix_community_media_profile_state``
    # — the column is the second, independent machine, so the
    # index is independent too (ADR 0412 D2).
    op.create_index(
        "ix_community_media_profile_processing",
        "community_media",
        ["profile_id", "processing_state"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the E09-R19 additive schema in column-safe order."""
    op.drop_index(
        "ix_community_media_profile_processing",
        table_name="community_media",
    )
    op.drop_column("community_media", "moderated_at")
    op.drop_column("community_media", "moderation_provider_version")
    op.drop_column("community_media", "moderation_provider")
    op.drop_column("community_media", "moderation_confidence")
    op.drop_column("community_media", "moderation_decision")
    op.drop_column("community_media", "processing_state")