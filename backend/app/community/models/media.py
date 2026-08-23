"""SQLAlchemy ORM model for Community media uploads (E09-R18, ADR 0410).

The persisted shape behind the Kör 18 upload pipeline. One row
per upload attempt, regardless of the lifecycle outcome (finalized,
cancelled, or expired-pending) — the row is the audit trail for
the bucket-side bytes and the place the orphan-cleanup function
walks.

The schema follows the project-wide ``public UUID + bigint PK``
pattern (ADR 0396 §1) and reuses every existing convention:

* ``id`` is BigInteger internally; the SQLite variant flips to
  Integer so in-memory test engines autoincrement reliably (the
  same ``BigInteger().with_variant(Integer, 'sqlite')`` seam used
  by CommunityProfile / CommunityPost / CommunityBookmark).

* ``public_id`` is ``Uuid(as_uuid=True)``, ``unique=True``,
  ``index=True``, default ``uuid.uuid4``. The wire shape only ever
  carries this — the internal ``id`` is the join surface. The
  finalize / cancel / ownership checks operate on ``public_id``
  (ADR 0410 §D5).

* ``profile_id`` is the internal FK to ``community_profiles.id``,
  ``ondelete='CASCADE'``. A profile deletion removes its media
  rows in the same transaction (the Kör 5 follow-graph precedent).
  The A6 acceptance cell ("a foreign user cannot finalize /
  cancel someone else's media_id") depends on this FK being
  intact — the service layer re-validates via ``profile_id``, not
  trust-the-JWT.

* ``object_key`` is the bucket-side key the client PUTs the bytes
  to (``profile_id / public_id`` shaped). NOT NULL and unique so
  an upload intent cannot be claimed by a parallel finalize from
  a different media row. The service layer's
  ``create_upload_intent`` derives this from the public_id at
  intent time and the finalize path treats it as immutable.

* ``content_type`` is the MIME the client intends to upload
  (``audio/mpeg``, ``video/mp4``, ``image/jpeg`` …). The finalize
  path re-reads the bucket-side ``Content-Type`` (via
  ``head_object``) and rejects mismatches — the brief §6.1
  measure-matrix "extension-based MIME check" cell goes red only
  when the server accepts the client-claimed type without
  consulting the actual object metadata.

* ``size_bytes`` is BigInteger (dialects differ — SQLite stores as
  64-bit INTEGER anyway). The finalize path re-measures the object
  via ``head_object`` and rejects when the size exceeds
  ``MAX_UPLOAD_BYTES`` (defense-in-depth, brief §6.1 threshold-
  triple). The intent-time declaration is an upper-bound
  declaration; the finalize re-check is the load-bearing one.

* ``duration_ms`` is a nullable Integer (audio / video files
  carry a duration; image uploads don't). The Kör 19 media-
  processing round will write this; Kör 18 only persists what
  the client sent.

* ``checksum_sha256`` is the 64-char hex digest the client claims.
  The finalize path compares against the bucket-side SHA-256
  (``head_object``) and rejects on mismatch (§6 A5).

* ``upload_state`` is a plain ``String`` per the project-wide
  ``visibility`` / ``moderation_state`` pattern (ADR 0398 §1).
  The Kör 18 state machine is
  ``pending → uploaded → finalized`` (success) or
  ``cancelled`` / ``failed`` (terminal). The DB does NOT enforce
  the transition set — the service layer's
  :func:`media_upload_service.finalize_upload` and
  :func:`media_upload_service.cancel_upload` are the
  authoritative enforcers, the column-level default is the only
  server-side constraint.

* ``retention_until`` is the cutoff the orphan-cleanup function
  scans against — every row whose state is NOT ``finalized`` AND
  whose ``retention_until`` is in the past is a candidate for
  cleanup (the bucket-side ``delete_object`` + row-DELETE).

* ``created_at`` / ``updated_at`` are ``DateTime(timezone=True)``.
  ``updated_at`` is bumped on every state transition.

* ``finalized_at`` is the finalize-success stamp (nullable).

Importing this module is load-bearing for the migration's
side-effect import: it registers the table with ``Base.metadata``
so ``alembic compare_metadata`` (round-12 migration-contract guard)
sees the table as part of the expected schema.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# --- Upload-state machine (ADR 0410 §D2) -------------------------------
#
# The state set is project-wide narrow — five values, no extra
# processing sub-states until Kör 19 adds ``processing_state``.
# Mirrors the Kör 11 ``moderation_state`` discipline: a plain
# ``String`` column with ``server_default='pending'``, the value
# set enforced at the service layer rather than the DB.

UPLOAD_STATE_PENDING: str = "pending"
UPLOAD_STATE_UPLOADED: str = "uploaded"
UPLOAD_STATE_FINALIZED: str = "finalized"
UPLOAD_STATE_CANCELLED: str = "cancelled"
UPLOAD_STATE_FAILED: str = "failed"

UPLOAD_STATE_ALLOWLIST: frozenset[str] = frozenset(
    {
        UPLOAD_STATE_PENDING,
        UPLOAD_STATE_UPLOADED,
        UPLOAD_STATE_FINALIZED,
        UPLOAD_STATE_CANCELLED,
        UPLOAD_STATE_FAILED,
    }
)


def is_allowed_upload_state(value: str) -> bool:
    """True when ``value`` is one of the five MVP upload states."""
    return value in UPLOAD_STATE_ALLOWLIST


class CommunityMedia(Base):
    """A single upload intent and its server-side accounting row.

    The lifecycle is owned by
    ``services.media_upload_service``; the model here is the
    persisted shape. There is **no** back-relationship to
    ``CommunityProfile`` from Kör 2 — the foreign-key join is
    ad-hoc per query (the orphan-cleanup function's scan is the
    primary consumer this round).
    """

    __tablename__ = "community_media"

    id: Mapped[int] = mapped_column(
        # Same BigInteger / Integer-on-SQLite variant rationale as
        # ``CommunityProfile`` / ``CommunityPost`` (ADR 0396 §1).
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        # Index-only — no column-level UNIQUE: the named
        # ``ix_community_media_public_id`` index below carries
        # the uniqueness constraint (same project-wide pattern
        # as ``CommunityBookmark.public_id`` — explicit named
        # index instead of a column-level ``unique=True``).
        index=True,
        default=uuid.uuid4,
        nullable=False,
    )
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Bucket-side key — unique so a parallel finalize cannot
    # claim the same upload intent. The service layer derives
    # this from the ``public_id`` at intent time and treats it
    # as immutable thereafter.
    object_key: Mapped[str] = mapped_column(
        String(length=512),
        nullable=False,
        unique=True,
    )
    # The MIME the client intends to upload. The finalize path
    # compares this against the bucket-side ``Content-Type``
    # (via ``head_object``) and rejects mismatches — §6 A3
    # measure-matrix.
    content_type: Mapped[str] = mapped_column(
        String(length=128),
        nullable=False,
    )
    # The size the client declares at intent time. The finalize
    # path re-measures via ``head_object`` and rejects when the
    # size exceeds ``MAX_UPLOAD_BYTES`` — §6 A4 measure-matrix
    # threshold-triple. The intent-time declaration is an
    # upper-bound; the finalize re-check is the load-bearing
    # one.
    size_bytes: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=False,
    )
    # Optional duration (audio / video only). NULL for image
    # uploads; the Kör 19 media-processing round will write
    # this.
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # 64-char hex SHA-256 digest (ADR 0410 §D4 — the project's
    # uniform content-hash family). The finalize path compares
    # against the bucket-side SHA-256 (the in-memory fake's
    # ``stage_object`` populates this; the S3 adapter currently
    # reads the ETag, and the future SDK adapter can read the
    # custom ``X-Amz-Meta-Sha256`` header the bucket can echo).
    checksum_sha256: Mapped[str | None] = mapped_column(
        String(length=64),
        nullable=True,
    )
    # State machine — ``pending`` → ``uploaded`` → ``finalized``
    # on success, ``pending`` / ``uploaded`` → ``cancelled`` on
    # cancel, ``pending`` / ``uploaded`` → ``failed`` on
    # server-side validation rejection. The DB does NOT enforce
    # the transition set; the service layer does.
    upload_state: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default=UPLOAD_STATE_PENDING,
        server_default=UPLOAD_STATE_PENDING,
    )
    # Retention cutoff — the orphan-cleanup function deletes
    # every row whose state is not ``finalized`` AND whose
    # ``retention_until`` is in the past. Set at intent time to
    # ``created_at + retention_window``.
    retention_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    # The absolute UTC expiry of the signed URL actually issued
    # for this intent — ``object_store.create_upload_url(...)``
    # stamps this onto ``SignedUpload.expires_at`` at intent
    # time, and ``create_upload_intent`` persists it here.
    # ``finalize_upload`` compares ``now >= row.expires_at``,
    # NOT a module-level re-derivation — so a caller-supplied
    # short window (60 s) is honoured even when the module
    # default ``SIGNED_URL_EXPIRES_IN`` is 5 minutes (the
    # BLOCKER B1 / F1 fix; brief §6 A2 acceptance).
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )
    # The finalize-success stamp. NULL until the row reaches the
    # ``finalized`` state.
    finalized_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    # ``object_key`` UNIQUE — see the column-level ``unique=True``
    # above; the explicit constraint is the project-wide pattern
    # so the migration's table-args stay uniform with the
    # Kör 2–17 tables (each has its table-level constraint block
    # in the same shape).
    __table_args__ = (
        UniqueConstraint(
            "object_key",
            name="uq_community_media_object_key",
        ),
        # Wire-identity unique index — replaces the removed
        # column-level ``public_id unique=True`` (m2: avoid the
        # duplicate unique index in the migration). Same shape
        # as ``CommunityBookmark.ix_community_bookmarks_public_id``.
        Index(
            "ix_community_media_public_id",
            "public_id",
            unique=True,
        ),
        # Composite (profile_id, created_at, id) backing the
        # orphan-cleanup function's scan (the §6 A7 cell).
        Index(
            "ix_community_media_profile_created",
            "profile_id",
            "created_at",
            "id",
        ),
        # Composite (profile_id, state) backing the quota policy's
        # "live uploads per profile" count (the §3 quota). Mirrors
        # the Kör 13 (profile_id, state) feed index discipline.
        Index(
            "ix_community_media_profile_state",
            "profile_id",
            "upload_state",
        ),
    )


__all__ = [
    "CommunityMedia",
    "UPLOAD_STATE_ALLOWLIST",
    "UPLOAD_STATE_CANCELLED",
    "UPLOAD_STATE_FAILED",
    "UPLOAD_STATE_FINALIZED",
    "UPLOAD_STATE_PENDING",
    "UPLOAD_STATE_UPLOADED",
    "is_allowed_upload_state",
]
