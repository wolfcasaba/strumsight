"""Add the community_club_pinned_posts junction table (E09-R25, ADR 0420).

Revision ID: e09_r25_0019
Revises: e09_r24_0018
Create Date: 2026-08-24

The pinned-post relation (brief §3 — "pinned post reláció maximum
konfigurált darabszámmal") is persisted as a small
``community_club_pinned_posts`` junction table. It carries only the
(cclub, post) tuple plus the audit columns; it does NOT duplicate
post content (the Kör 11 ``community_posts`` row is the canonical
post, and the Kör 24 ``community_clubs`` row is the canonical club).
The pin-limit (A4) is enforced at the service layer on top of this
table, so re-tuning the cap in a future round does NOT require a
migration.

Design contract — these are the load-bearing guarantees the service
and the migration-contract test pin:

* **Composite primary key.** ``(club_id, post_id)`` is the
  relational identity: a post can be pinned at most once inside a
  single club; cross-club pins are a different row.

* **Cascade on club / post delete.** Both ``club_id`` and ``post_id``
  carry ``ondelete='CASCADE'`` so a club hard-delete (or a post
  hard-delete) cleans up the junction rows in the same transaction.
  Mirrors the Kör 24 ``community_club_members`` /
  ``community_club_invites`` FK semantics — a profile- or
  entity-level CASCADE is the project-wide convention.

* **Migration is STRICTLY ADDITIVE.** No existing column / constraint
  / index on any prior table is touched.

The migration registers the inline ``Table`` declaration with
``Base.metadata`` so ``alembic compare_metadata`` (the round-12
migration-contract guard, ``backend/tests/test_migrations.py``) sees
the new table as part of the expected schema. The migration body
itself uses raw ``sa.Column`` / ``op.create_table`` calls so the
schema is migration-source-of-truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the inline ``Table`` declaration with ``Base.metadata`` so
# ``alembic compare_metadata`` (the round-12 migration-contract test,
# ``backend/tests/test_migrations.py``) sees the new table as part of
# the expected schema. The migration body itself does not rely on the
# ``Table`` object — it uses raw ``sa.Column`` calls so the schema is
# migration-source-of-truth, not ORM-derived autogenerate. The import
# is a deliberate side-effect registration, matching the Kör 11 /
# Kör 24 precedent.
from app.community.services.club_content_service import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    community_club_pinned_posts,
)

revision: str = "e09_r25_0019"
down_revision: str | Sequence[str] | None = "e09_r24_0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# SQLite-shared variant — same BigInteger / Integer-on-SQLite seam as
# the rest of the community module (ADR 0396 §1).
_bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def upgrade() -> None:
    """Create the E09-R25 community_club_pinned_posts junction table."""
    op.create_table(
        "community_club_pinned_posts",
        sa.Column("club_id", _bigint, nullable=False),
        sa.Column("post_id", _bigint, nullable=False),
        sa.Column("pinned_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("pinned_by_profile_id", _bigint, nullable=False),
        sa.ForeignKeyConstraint(
            ["club_id"],
            ["community_clubs.id"],
            ondelete="CASCADE",
            name="fk_community_club_pinned_posts_club",
        ),
        sa.ForeignKeyConstraint(
            ["post_id"],
            ["community_posts.id"],
            ondelete="CASCADE",
            name="fk_community_club_pinned_posts_post",
        ),
        sa.PrimaryKeyConstraint("club_id", "post_id"),
    )


def downgrade() -> None:
    """Reverse the E09-R25 schema delta."""
    op.drop_table("community_club_pinned_posts")
