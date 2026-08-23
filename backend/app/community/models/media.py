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

* ``processing_state`` (E09-R19, ADR 0412 §D2) is a SECOND,
  independent state machine on the same row — NOT an extension
  of ``upload_state``. The seven-value set is
  ``uploaded → scanning → transcoding → review → ready`` on
  success, plus ``rejected`` and ``deleted`` terminals. The DB
  does NOT enforce the transition set; the task-layer
  :mod:`tasks.media_processing` is the authoritative enforcer.
  ``upload_state`` and ``processing_state`` move independently
  — a row may be ``upload_state="finalized"`` and
  ``processing_state="scanning"`` at the same time. The literal
  ``uploaded`` collides between the two machines BY DESIGN
  (transzport vs. processing axis, ADR 0412 D2).

* ``moderation_decision`` / ``moderation_confidence`` /
  ``moderation_provider`` / ``moderation_provider_version`` /
  ``moderated_at`` (E09-R19, ADR 0412 §D2 — A6 acceptance
  evidence): nullable audit columns on the SAME row. The
  provider + provider-version is the audit evidence that a
  decision was made by a specific external model; ``decision``
  carries the human-review verdict, ``confidence`` carries the
  triage confidence, ``moderated_at`` is the stamp. They are
  nullable because the moderation flow is multi-step and any
  one of them may be set without the others.

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
    Float,
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
#
# E09-R19 / ADR 0412 §D2 — ``processing_state`` is a SECOND,
# INDEPENDENT state machine on the same row. ``upload_state``
# tracks the transzport pipeline (Kör 18, immutable); the new
# ``processing_state`` tracks the content-processing pipeline
# (Kör 19: uploaded → scanning → transcoding → review → ready /
# rejected / deleted). The two machines move independently;
# a media row may be ``upload_state="finalized"`` AND
# ``processing_state="scanning"`` simultaneously. The
# ``upload_state`` block below is INTENTIONALLY UNCHANGED —
# adding ``processing_state`` is additive (see ADR 0412 D2 /
# brief §0.0 D2).

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


# --- Processing-state machine (E09-R19, ADR 0412 §D2) ------------------
#
# Seven-value machine, additive on the same row. The DB does NOT
# enforce the transition set — the task / service layer does
# (the same pattern as ``upload_state`` and ``moderation_state``).
# The literal value set follows brief §3 / §8 verbatim. The
# ``uploaded`` literal intentionally collides with
# ``UPLOAD_STATE_UPLOADED`` — they are two independent axes, not
# the same concept (transzport vs. processing pipeline); the
# collision is documented in ADR 0412 §D2.

PROCESSING_STATE_UPLOADED: str = "uploaded"
PROCESSING_STATE_SCANNING: str = "scanning"
PROCESSING_STATE_TRANSCODING: str = "transcoding"
PROCESSING_STATE_REVIEW: str = "review"
PROCESSING_STATE_READY: str = "ready"
PROCESSING_STATE_REJECTED: str = "rejected"
PROCESSING_STATE_DELETED: str = "deleted"

PROCESSING_STATE_ALLOWLIST: frozenset[str] = frozenset(
    {
        PROCESSING_STATE_UPLOADED,
        PROCESSING_STATE_SCANNING,
        PROCESSING_STATE_TRANSCODING,
        PROCESSING_STATE_REVIEW,
        PROCESSING_STATE_READY,
        PROCESSING_STATE_REJECTED,
        PROCESSING_STATE_DELETED,
    }
)


def is_allowed_processing_state(value: str) -> bool:
    """True when ``value`` is one of the seven processing states."""
    return value in PROCESSING_STATE_ALLOWLIST


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
        # No column-level UNIQUE / index: the named
        # ``ix_community_media_public_id`` index in
        # ``__table_args__`` carries BOTH the uniqueness
        # constraint AND the index (same project-wide pattern
        # as ``CommunityBookmark.public_id`` — explicit named
        # index instead of column-level flags). Setting either
        # ``unique=True`` or ``index=True`` here would collide
        # with the explicit Index on the same name.
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
    # E09-R19 / ADR 0412 §D2 — SECOND independent state machine.
    # The two machines move independently; ``processing_state``
    # tracks the content-processing pipeline
    # (uploaded → scanning → transcoding → review → ready /
    # rejected / deleted). See the docstring above.
    processing_state: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default=PROCESSING_STATE_UPLOADED,
        server_default=PROCESSING_STATE_UPLOADED,
    )
    # A6 acceptance audit columns — nullable, set during /
    # after the moderation flow. ``moderation_decision`` carries
    # the human-review verdict (``approved`` / ``rejected`` /
    # similar — the literal set is the provider / human layer's
    # choice, not the model's); ``moderation_confidence`` is the
    # triage-side float in [0.0, 1.0]; ``moderation_provider`` is
    # the (mock) adapter name the triage ran against;
    # ``moderation_provider_version`` is the adapter-version
    # string the audit log can later correlate with;
    # ``moderated_at`` is the stamp of the LAST write (decision
    # or confidence, whichever the moderation flow wrote last).
    moderation_decision: Mapped[str | None] = mapped_column(
        String(length=64),
        nullable=True,
    )
    moderation_confidence: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )
    moderation_provider: Mapped[str | None] = mapped_column(
        String(length=128),
        nullable=True,
    )
    moderation_provider_version: Mapped[str | None] = mapped_column(
        String(length=64),
        nullable=True,
    )
    moderated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
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
        # E09-R19 — composite (profile_id, processing_state) backing
        # the post-fetch query that filters out non-ready media
        # (the A2 / A3 acceptance cells — only ``processing_state
        # = 'ready'`` rows are playable). Same naming convention as
        # the Kör 18 ``ix_community_media_profile_state`` index
        # above; the column is the SECOND, INDEPENDENT machine so
        # the index is independent too (ADR 0412 D2).
        Index(
            "ix_community_media_profile_processing",
            "profile_id",
            "processing_state",
        ),
    )


__all__ = [
    "CommunityMedia",
    "PROCESSING_STATE_ALLOWLIST",
    "PROCESSING_STATE_DELETED",
    "PROCESSING_STATE_READY",
    "PROCESSING_STATE_REJECTED",
    "PROCESSING_STATE_REVIEW",
    "PROCESSING_STATE_SCANNING",
    "PROCESSING_STATE_TRANSCODING",
    "PROCESSING_STATE_UPLOADED",
    "UPLOAD_STATE_ALLOWLIST",
    "UPLOAD_STATE_CANCELLED",
    "UPLOAD_STATE_FAILED",
    "UPLOAD_STATE_FINALIZED",
    "UPLOAD_STATE_PENDING",
    "UPLOAD_STATE_UPLOADED",
    "is_allowed_processing_state",
    "is_allowed_upload_state",
]
