"""Add visibility + audience_default columns to ``community_privacy_settings``.

Revision ID: e09_r04_0004
Revises: e09_r03_0003
Create Date: 2026-08-22

E09-R04, ADR 0398 §1, §5. The schema delta is intentionally minimal — two
plain-String columns on the existing ``community_privacy_settings`` table:

* ``visibility`` — the profile-level visibility (``public``/``followers``/
  ``private``). Default ``followers`` per ADR 0398 §5 (never ``public``).
* ``audience_default`` — the default audience for new content authored by
  this profile. Same value space, same default.

Why **plain ``String`` and not SQLAlchemy ``Enum``**: the project ships
``theme_mode: Mapped[str] = mapped_column(String, ...)`` on
``backend/app/models.py:46`` as its established "enum-as-plain-string"
pattern. The brief §0.0 B1 + ADR 0398 §1 explicitly adopt the same
convention here — DB-level ``CHECK`` constraints are not added (the
domain layer's Pydantic schema is the validation chokepoint).

Why **``server_default="followers"``** (not just Python-side default):
the column is ``NOT NULL`` and a future round may run this migration
against a non-empty table (Kör 6+ will start onboarding real users).
The ``server_default`` makes the migration safe to apply on a populated
table without a separate data-backfill step.

The ``render_as_batch`` mode in ``alembic/env.py`` handles SQLite's lack
of native ``ALTER``; ``downgrade()`` removes both columns in a single
batch.

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard)
sees the same surface as the production schema. The migration body itself
does NOT rely on the model classes — it uses raw ``sa.Column`` calls so
the schema is migration-source-of-truth, not ORM-derived.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the CommunityPrivacySettings ORM model with ``Base.metadata`` so
# that ``alembic compare_metadata`` sees the new columns as part of the
# expected schema (round-12 migration-contract test, exercised by
# ``backend/tests/test_migrations.py``). Without this side-effect import,
# the autogenerate diff would flag the new ``visibility`` / ``audience_default``
# columns as "missing from metadata" — a regression this round ships the
# round-12 guard to catch.
from app.community.models.profile import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityPrivacySettings,
)

revision: str = "e09_r04_0004"
down_revision: str | Sequence[str] | None = "e09_r03_0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add ``visibility`` + ``audience_default`` to ``community_privacy_settings``."""
    with op.batch_alter_table("community_privacy_settings") as batch:
        batch.add_column(
            sa.Column(
                "visibility",
                sa.String(),
                nullable=False,
                server_default="followers",
            )
        )
        batch.add_column(
            sa.Column(
                "audience_default",
                sa.String(),
                nullable=False,
                server_default="followers",
            )
        )


def downgrade() -> None:
    """Reverse the privacy-fields schema delta."""
    with op.batch_alter_table("community_privacy_settings") as batch:
        batch.drop_column("audience_default")
        batch.drop_column("visibility")
