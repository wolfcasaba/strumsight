"""Add the direct-upload Community media table (javító sáv R27).

Revision ID: e09_r28_0021
Revises: e09_r27_0020
Create Date: 2026-09-08

One table, ``community_media_uploads``, behind
``STRUMSIGHT_COMMUNITY_MEDIA_ENABLED``. It is deliberately NOT a
modification of the Kör 18/19 ``community_media`` table: that one models
a signed-URL bucket handoff (``object_key`` NOT NULL + UNIQUE,
``expires_at`` NOT NULL, ``upload_state`` pending→uploaded→finalized) and
is left byte-untouched by this migration — see
``app/community/models/media_upload.py`` for the full rationale.

``post_id`` carries no FOREIGN KEY on purpose (the
``community_posts.club_id`` precedent): the cross-table constraint would
force ``community_posts`` into ``Base.metadata`` wherever the media model
is imported, which the Community test engines (schema built from
whatever the importing module pulled in) cannot guarantee.

The downgrade drops the table; the stored FILES under
``STRUMSIGHT_MEDIA_ROOT`` are NOT touched by a downgrade — a migration
must not delete user content, and the runbook's rollback step says to
keep the volume so a re-upgrade finds its bytes intact.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

# Register the ORM model with ``Base.metadata`` so the migration-contract
# test (``backend/tests/test_migrations.py``) sees the new table.
from app.community.models.media_upload import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityMediaUpload,
)

revision: str = "e09_r28_0021"
down_revision: str | Sequence[str] | None = "e09_r27_0020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create ``community_media_uploads`` on top of Kör 27."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_media_uploads",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("profile_id", _bigint, nullable=False),
        sa.Column("post_id", _bigint, nullable=True),
        sa.Column(
            "attach_position",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column(
            "state",
            sa.String(length=32),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("rejection_code", sa.String(length=64), nullable=True),
        sa.Column("content_type", sa.String(length=64), nullable=False),
        sa.Column("content_sha256", sa.String(length=64), nullable=True),
        sa.Column("source_sha256", sa.String(length=64), nullable=False),
        sa.Column("size_bytes", _bigint, nullable=False, server_default="0"),
        sa.Column("source_size_bytes", _bigint, nullable=False),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("scanner", sa.String(length=32), nullable=True),
        sa.Column("scanned_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ready_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_media_uploads_profile",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_media_uploads_public_id",
        "community_media_uploads",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        "ix_community_media_uploads_profile_state",
        "community_media_uploads",
        ["profile_id", "state"],
        unique=False,
    )
    op.create_index(
        "ix_community_media_uploads_post_position",
        "community_media_uploads",
        ["post_id", "attach_position"],
        unique=False,
    )
    op.create_index(
        "ix_community_media_uploads_content_sha256",
        "community_media_uploads",
        ["content_sha256"],
        unique=False,
    )


def downgrade() -> None:
    """Drop the table. The media ROOT volume is intentionally left alone."""
    op.drop_index(
        "ix_community_media_uploads_content_sha256",
        table_name="community_media_uploads",
    )
    op.drop_index(
        "ix_community_media_uploads_post_position",
        table_name="community_media_uploads",
    )
    op.drop_index(
        "ix_community_media_uploads_profile_state",
        table_name="community_media_uploads",
    )
    op.drop_index(
        "ix_community_media_uploads_public_id",
        table_name="community_media_uploads",
    )
    op.drop_table("community_media_uploads")
