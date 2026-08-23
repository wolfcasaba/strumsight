"""Add the Community media table (E09-R18, ADR 0410).

Revision ID: e09_r18_0012
Revises: e09_r17_0011
Create Date: 2026-08-23

This migration introduces the ``community_media`` table — the
server-side accounting row behind the Kör 18 upload pipeline.

The schema follows the same ``public UUID + bigint PK`` pattern
as the Kör 2–17 tables (ADR 0396 §1) and reuses every existing
convention:

* ``id`` — BigInteger internal PK, variant to Integer on SQLite for
  autoincrement portability (same ``_bigint`` seam used by Kör
  5–17 migrations).
* ``public_id`` — ``Uuid(as_uuid=True)``, ``unique=True``,
  ``index=True``, default ``uuid.uuid4``. The wire shape only ever
  carries the public_id; the internal ``id`` is the join surface.
  The finalize / cancel / ownership checks operate on
  ``public_id`` (ADR 0410 §D5).
* ``profile_id`` — FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'``. A profile deletion removes its media
  rows in the same transaction (the Kör 5 follow-graph precedent).
* ``expires_at`` — ``DateTime(timezone=True)`` NOT NULL. The
  absolute UTC expiry of the signed URL ``create_upload_intent``
  issued for this row — copied from ``SignedUpload.expires_at``
  at intent time. ``finalize_upload`` compares ``now >= expires_at``
  against this stored value (defense-in-depth — see ADR 0410
  §5.2 / §6 A2; the BLOCKER B1 / F1 fix in this revision ensures
  the re-check uses the ACTUAL issued TTL, not a hardcoded
  module constant).
* ``object_key`` — the bucket-side key the client PUTs the bytes
  to (``profile_id / public_id`` shaped — see D2 below). NOT NULL
  and unique so an upload intent can't be reused by a parallel
  finalize from a different media row.
* ``content_type`` — the MIME the client uploads (``audio/mpeg``,
  ``video/mp4``, ``image/jpeg`` …). The finalize path re-reads
  the bucket-side ``Content-Type`` and rejects mismatches — the
  brief §6.1 measure-matrix "extension-based MIME check" cell
  goes red only when the server accepts the client-claimed type
  without consulting the actual object metadata.
* ``size_bytes`` — ``BigInteger`` (dialects differ — SQLite stores
  as 64-bit INTEGER anyway). The finalize path re-measures the
  object via ``head_object`` and rejects when the size exceeds
  ``MAX_UPLOAD_BYTES`` (defense-in-depth, brief §6.1 threshold-
  triple).
* ``duration_ms`` — nullable ``Integer`` (audio / video files carry
  a duration; image uploads don't). The Kör 19 media-processing
  round will write this; Kör 18 only persists what the client
  sent (the field is the wire-side seat for the future
  ``processing_state``).
* ``checksum_sha256`` — 64-char hex digest (the §6 A5 wire-shape
  field). The finalize path compares against the ``head_object``
  SHA-256 and rejects on mismatch.
* ``upload_state`` — plain ``String`` with
  ``server_default='pending'``. The Kör 18 state machine is
  ``pending`` → ``uploaded`` → ``finalized`` (success) or
  ``cancelled`` / ``failed`` (terminal). The finalize path
  enforces the transition; the orphan-cleanup function scans
  rows older than the ``retention_window`` whose state is still
  ``pending`` / ``uploaded`` / ``cancelled`` and removes them.
* ``retention_until`` — nullable ``DateTime(timezone=True)``. The
  Kör 18 upload sets this to ``created_at + retention_window``
  so the orphan-cleanup function has a stable cutoff; the future
  retention policy rounds replace it with the per-profile
  computed value.
* ``created_at`` / ``updated_at`` — ``DateTime(timezone=True)``.
  ``updated_at`` is bumped on every state transition.
* ``finalized_at`` — nullable ``DateTime(timezone=True)``, the
  finalize-success stamp.

Importing the ORM model here registers it with ``Base.metadata``
so ``alembic compare_metadata`` (round-12 migration-contract
guard) sees the new table as part of the expected schema. The
migration body itself does not rely on the model class — it uses
raw ``sa.Column`` calls so the schema is migration-source-of-
truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test)
# sees the new table as part of the expected schema. The migration
# body itself does not rely on the model class — it uses raw
# ``sa.Column`` calls so the schema is migration-source-of-truth,
# not ORM-derived autogenerate.
from app.community.models.media import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityMedia,
)

revision: str = "e09_r18_0012"
down_revision: str | Sequence[str] | None = "e09_r17_0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the community_media table on top of the Kör 17 bookmark schema."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_media",
        sa.Column("id", _bigint, nullable=False),
        sa.Column(
            "public_id",
            sa.Uuid(),
            nullable=False,
        ),
        sa.Column("profile_id", _bigint, nullable=False),
        sa.Column("object_key", sa.String(length=512), nullable=False),
        sa.Column("content_type", sa.String(length=128), nullable=False),
        sa.Column("size_bytes", _bigint, nullable=False),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=True),
        sa.Column(
            "upload_state",
            sa.String(),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("retention_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finalized_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        # ``object_key`` is unique so an upload intent can't be
        # claimed by a parallel finalize from a different media
        # row. The wire-side ``public_id`` is the identity the
        # client carries; ``object_key`` is the bucket-side
        # handle (D2 — see ADR 0410).
        sa.UniqueConstraint(
            "object_key",
            name="uq_community_media_object_key",
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_media_profile_community_profiles",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    # The wire identity the client / finalize / cancel calls
    # carry. Explicit named unique index (the project-wide
    # pattern — same shape as ``ix_community_bookmarks_public_id``
    # and the Kör 2–17 wire-identity indexes). m2 cleanup: this
    # is the SINGLE source of uniqueness for ``public_id`` (no
    # column-level ``unique=True``) — a previous revision carried
    # both, creating two unique indexes on the same column.
    op.create_index(
        "ix_community_media_public_id",
        "community_media",
        ["public_id"],
        unique=True,
    )
    # Composite (profile_id, created_at, id) backing the orphan-
    # cleanup function's scan — the §6 A7 acceptance cell walks
    # this index when scanning for ``pending`` / ``uploaded`` /
    # ``cancelled`` rows past the retention window.
    op.create_index(
        "ix_community_media_profile_created",
        "community_media",
        ["profile_id", "created_at", "id"],
        unique=False,
    )
    # Composite (profile_id, state) backing the quota policy's
    # "live uploads per profile" count (ADR 0410 §D2 — the quota
    # policy lives in the service module, not as a constraint).
    op.create_index(
        "ix_community_media_profile_state",
        "community_media",
        ["profile_id", "upload_state"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the community_media schema in FK-safe order."""
    op.drop_index(
        "ix_community_media_profile_state",
        table_name="community_media",
    )
    op.drop_index(
        "ix_community_media_profile_created",
        table_name="community_media",
    )
    op.drop_index(
        "ix_community_media_public_id",
        table_name="community_media",
    )
    op.drop_table("community_media")