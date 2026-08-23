"""Add the Community posts table (E09-R11, ADR 0405).

Revision ID: e09_r11_0007
Revises: e09_r08_0006
Create Date: 2026-08-23

This migration introduces the ``community_posts`` table — the first
real content endpoint surface of the Community module. The schema
follows the same ``public UUID + bigint PK`` pattern as the Kör 2–8
tables (ADR 0396 §1) and reuses every existing convention:

* ``id`` — BigInteger internal PK, variant to Integer on SQLite for
  autoincrement portability (same ``_bigint = BigInteger().with_variant
  (Integer(), 'sqlite')`` seam used by Kör 5–8 migrations).
* ``public_id`` — ``Uuid(as_uuid=True)``, unique + indexed. The wire
  shape only ever carries the public_id; the internal id is the join
  surface.
* ``profile_id`` — FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'`` so a profile removal cleans up its posts in
  the same transaction (the Kör 7 follow-graph precedent).
* ``audience`` — plain ``String`` (the project-wide
  ``visibility``/``audience_default`` pattern from
  ``community_privacy_settings``). The value set is enforced at the
  Pydantic / domain layer; the DB does not constrain it (ADR 0398
  §1). ``server_default='public'`` keeps the migration safe on a
  populated table — a fresh post is public until the author moves it.
* ``club_id`` — **nullable BigInteger, NO ForeignKey**. The
  ``community_clubs`` table is Kör 24 scope (pre-flight §0.0 D6);
  this round only reserves the column. The brief is explicit that
  adding the FK in a separate migration is the future round's job.
* ``body`` — ``String(5000)``, the wire-shape max length (brief
  §0.0 D9). The Pydantic layer re-validates the same bound. TEXT
  would be more idiomatic on PostgreSQL; keeping the explicit length
  pins the schema contract on both dialects.
* Artifact columns — ``artifact_type``, ``artifact_schema_version``,
  ``artifact_payload`` are NULLABLE; the post may be text-only. The
  ``artifact_payload`` column is the JSON-encoded validated envelope
  from ``schemas/artifacts.parse_share_artifact`` (ADR 0404, brief
  §0.0 D10). The validated ``artifact`` object's ``type`` and
  ``schema_version`` are mirrored into the typed sibling columns so
  the Kör 13 feed-query can filter / facet without re-parsing JSON.
* ``moderation_state`` — plain ``String`` with
  ``server_default='visible'`` (brief §0.0 D8: two-value field, the
  active workflow is Kör 27/28 scope). The Kör 11 GET/PATCH/DELETE
  treats anything != ``'visible'`` as D7's uniform 404.
* ``idempotency_key`` — nullable ``String`` with a partial-ish
  ``UNIQUE(profile_id, idempotency_key)``. SQLite's UNIQUE allows
  multiple NULLs, so a post WITHOUT an idempotency_key remains
  allowed; a retry with the SAME (profile_id, idempotency_key) lands
  on the existing row (brief §0.0 D4 — the A2 idempotency invariant).
  A shared ``community_idempotency_records`` table is a future
  round's call when a SECOND endpoint needs the same dedup; this
  round ships the column-local form.
* ``created_at`` / ``updated_at`` — ``DateTime(timezone=True)``.
  ``updated_at`` doubles as the resource-version token (ADR 0398 §6
  precedent: the Kör 4 privacy row uses the same single-column
  optimistic-concurrency pattern; brief §0.0 D3 — NO separate
  ``version`` column).
* ``deleted_at`` — nullable ``DateTime(timezone=True)``, the
  soft-delete tombstone (brief §5.3, D7 404).

Importing the ORM model here registers it with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard)
sees the new table as part of the expected schema. The migration
body uses raw ``sa.Column`` calls — the schema is the
migration-source-of-truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test,
# ``backend/tests/test_migrations.py``) sees the new table as part of
# the expected schema. The migration body itself does not rely on the
# model class — it uses raw ``sa.Column`` calls so the schema is
# migration-source-of-truth, not ORM-derived autogenerate.
from app.community.models.post import (
    CommunityPost,  # noqa: F401,E402 -- side-effect import registers ORM metadata
)

revision: str = "e09_r11_0007"
down_revision: str | Sequence[str] | None = "e09_r08_0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the community_posts table on top of the Kör 8 safety schema."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_posts",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
            unique=True,
        ),
        sa.Column("profile_id", _bigint, nullable=False),
        sa.Column(
            "audience",
            sa.String(),
            nullable=False,
            server_default="public",
        ),
        # club_id — nullable, NO FK (pre-flight §0.0 D6; the
        # community_clubs table is Kör 24 scope).
        sa.Column("club_id", _bigint, nullable=True),
        sa.Column("body", sa.String(length=5000), nullable=False),
        # Artifact columns (NULL when the post is text-only).
        sa.Column("artifact_type", sa.String(), nullable=True),
        sa.Column("artifact_schema_version", sa.Integer(), nullable=True),
        sa.Column("artifact_payload", sa.JSON(), nullable=True),
        sa.Column(
            "moderation_state",
            sa.String(),
            nullable=False,
            server_default="visible",
        ),
        # Idempotency key — nullable, UNIQUE on the (profile, key)
        # pair. SQLite allows multiple NULLs in a UNIQUE column, so
        # text-only posts (no key) remain allowed; a retry with the
        # same key is rejected at the DB layer (brief §0.0 D4).
        sa.Column("idempotency_key", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_posts_profile_community_profiles",
        ),
        sa.UniqueConstraint(
            "profile_id",
            "idempotency_key",
            name="uq_community_posts_profile_idempotency",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_posts_public_id",
        "community_posts",
        ["public_id"],
        unique=True,
    )
    # The read-path filter for "posts authored by profile X" and the
    # soft-delete exclusion both read by (profile_id, created_at
    # DESC, id DESC); the composite index matches that query plan.
    op.create_index(
        "ix_community_posts_profile_created",
        "community_posts",
        ["profile_id", "created_at", "id"],
        unique=False,
    )
    # The Kör 13 feed-query will paginate posts in audience order
    # (``public`` posts are the default discovery surface). A separate
    # partial index is left to that round's migration; here we ship
    # the lean composite that covers the per-author read path.
    op.create_index(
        "ix_community_posts_idempotency_key",
        "community_posts",
        ["profile_id", "idempotency_key"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the community_posts schema in FK-safe order."""
    op.drop_index(
        "ix_community_posts_idempotency_key",
        table_name="community_posts",
    )
    op.drop_index(
        "ix_community_posts_profile_created",
        table_name="community_posts",
    )
    op.drop_index(
        "ix_community_posts_public_id",
        table_name="community_posts",
    )
    op.drop_table("community_posts")
