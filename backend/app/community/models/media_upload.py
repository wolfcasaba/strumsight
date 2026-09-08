"""ORM model for directly-uploaded Community media (javító sáv R27).

Why a SECOND media table
------------------------

``models/media.py`` (E09-R18/R19, ADR 0410/0412) models a **signed-URL
bucket handoff**: the client asks for an intent, PUTs the bytes straight
into an S3-compatible bucket, then calls finalize. Its columns encode
that shape structurally — ``object_key`` is NOT NULL and UNIQUE (the
bucket key claimed by exactly one intent), ``expires_at`` is NOT NULL
(the signed URL's deadline), and ``upload_state`` walks
``pending → uploaded → finalized``. That surface never got an HTTP
router, and the bucket it presumes is not part of the deploy.

This round ships the shape the app actually needs: a **direct multipart
POST into the backend**, which re-encodes the bytes itself and stores
them on a local volume. Reusing ``community_media`` would have meant
nulling out two NOT NULL columns, re-purposing a UNIQUE key, and
rewriting the pinned R18/R19 suites — three destructive edits to a
tested subsystem in exchange for one fewer table. The two rows model two
different transports; they are kept apart, and the R18/R19 code is left
byte-untouched.

State machine
-------------

ONE machine on this row (unlike ``CommunityMedia``'s two)::

    pending → scanning → transcoding → review? → ready
                  │           │           │
                  └───────────┴───────────┴────────→ rejected → deleted
                                                        ready ─┘

``review`` is entered only when ``Settings.media_review_required`` is on.
``deleted`` is the owner's DELETE (terminal, and the stored file is
unlinked when nothing else references its digest).

Six of the seven literals are byte-identical to the client's existing
vocabulary (``CommunityMediaProcessingState`` in
``lib/features/community/presentation/widgets/community_media_player.dart``
plus the ``communityMediaState*`` / ``communityMediaPending*`` ARB keys,
R21). The SEVENTH is the measured exception and must not be papered over:
the client calls the first, pre-scan state ``uploaded`` (its R18/R19
signed-URL flow only learned about a row AFTER the bucket PUT, so
"uploaded" was literally true there); a direct multipart POST has no such
moment, and ``pending`` is the honest name for "the bytes are in, nothing
has looked at them yet". The client therefore maps ``pending`` → its
``uploaded`` face in ONE place
(``domain/entities/community_media.dart``), whose ARB string
(``communityMediaPendingQueued`` — "Media is queued for processing") is
already the right sentence for this state. Renaming the Dart enum instead
would have touched the R19 widget, its pinned test and two ARB files for
no behavioural gain.

``rejection_code`` is the machine-readable reason a row is in
``rejected``; it is one of the module-level codes in :mod:`media.sniff`,
:mod:`media.scanner` and :mod:`media.transcode`, never free text and
never an attacker-influenced string (a clamd signature name is audit
data, not a wire value).

Content addressing
------------------

``content_sha256`` is the digest of the STORED (re-encoded) bytes and is
the only thing that maps a row to a file
(``<root>/<aa>/<bb>/<digest>``). ``source_sha256`` is the digest of what
the client sent, kept for the audit trail and for duplicate-upload
diagnosis; it never becomes a path.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Final

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


MEDIA_STATE_PENDING: Final[str] = "pending"
MEDIA_STATE_SCANNING: Final[str] = "scanning"
MEDIA_STATE_TRANSCODING: Final[str] = "transcoding"
MEDIA_STATE_REVIEW: Final[str] = "review"
MEDIA_STATE_READY: Final[str] = "ready"
MEDIA_STATE_REJECTED: Final[str] = "rejected"
MEDIA_STATE_DELETED: Final[str] = "deleted"

MEDIA_STATE_ALLOWLIST: Final[frozenset[str]] = frozenset(
    {
        MEDIA_STATE_PENDING,
        MEDIA_STATE_SCANNING,
        MEDIA_STATE_TRANSCODING,
        MEDIA_STATE_REVIEW,
        MEDIA_STATE_READY,
        MEDIA_STATE_REJECTED,
        MEDIA_STATE_DELETED,
    }
)

#: Terminal states — a row here never moves again except ``ready`` →
#: ``deleted`` (the owner's DELETE).
MEDIA_TERMINAL_STATES: Final[frozenset[str]] = frozenset(
    {MEDIA_STATE_READY, MEDIA_STATE_REJECTED, MEDIA_STATE_DELETED}
)

#: The transitions the pipeline is allowed to make. The DB does not
#: enforce this (the project-wide ``moderation_state`` discipline); the
#: pipeline is the authoritative enforcer and this set is what it reads.
MEDIA_TRANSITIONS: Final[frozenset[tuple[str, str]]] = frozenset(
    {
        (MEDIA_STATE_PENDING, MEDIA_STATE_SCANNING),
        (MEDIA_STATE_PENDING, MEDIA_STATE_REJECTED),
        (MEDIA_STATE_SCANNING, MEDIA_STATE_TRANSCODING),
        (MEDIA_STATE_SCANNING, MEDIA_STATE_REJECTED),
        (MEDIA_STATE_TRANSCODING, MEDIA_STATE_REVIEW),
        (MEDIA_STATE_TRANSCODING, MEDIA_STATE_READY),
        (MEDIA_STATE_TRANSCODING, MEDIA_STATE_REJECTED),
        (MEDIA_STATE_REVIEW, MEDIA_STATE_READY),
        (MEDIA_STATE_REVIEW, MEDIA_STATE_REJECTED),
        (MEDIA_STATE_READY, MEDIA_STATE_DELETED),
        (MEDIA_STATE_REJECTED, MEDIA_STATE_DELETED),
    }
)


def is_allowed_media_state(value: str) -> bool:
    """True when ``value`` is one of the seven pipeline states."""
    return value in MEDIA_STATE_ALLOWLIST


def is_allowed_media_transition(from_state: str, to_state: str) -> bool:
    """True when the pipeline may move ``from_state`` → ``to_state``."""
    return (from_state, to_state) in MEDIA_TRANSITIONS


class CommunityMediaUpload(Base):
    """One directly-uploaded media object and its pipeline state."""

    __tablename__ = "community_media_uploads"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        default=uuid.uuid4,
        nullable=False,
    )
    #: Owner — the internal ``community_profiles.id``. CASCADE so a
    #: profile deletion takes its media rows with it; the file-side
    #: cleanup is the deletion path's job.
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    #: The post this media is attached to, or NULL while it is a loose
    #: upload sitting in the composer.
    #:
    #: Deliberately a plain BigInteger with **NO** ForeignKey — the same
    #: decision (and the same reason) as ``CommunityPost.club_id``. A
    #: cross-table FK forces ``community_posts`` into ``Base.metadata``
    #: wherever this model is registered, and the Community test engines
    #: build their schema from whatever the importing module happened to
    #: pull in; the FK would turn an unrelated test's import list into a
    #: ``NoReferencedTableError``. Post deletion is SOFT anyway
    #: (``deleted_at``), so an ``ondelete`` clause would almost never
    #: fire; the visibility gate on the download path reads the post row
    #: through ``get_post``, which honours the soft delete.
    post_id: Mapped[int | None] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=True,
    )
    #: Ordering within a post's attachment list (0-based).
    attach_position: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )
    #: ``image`` | ``audio`` — the SERVER's verdict from the magic-byte
    #: sniffer, never the client's claim.
    kind: Mapped[str] = mapped_column(String(length=16), nullable=False)
    state: Mapped[str] = mapped_column(
        String(length=32),
        nullable=False,
        default=MEDIA_STATE_PENDING,
        server_default=MEDIA_STATE_PENDING,
    )
    #: Machine-readable reason for ``state == 'rejected'``.
    rejection_code: Mapped[str | None] = mapped_column(
        String(length=64),
        nullable=True,
    )
    #: The media type of the STORED bytes — what the download endpoint
    #: sends as ``Content-Type``.
    content_type: Mapped[str] = mapped_column(String(length=64), nullable=False)
    #: Digest of the stored (re-encoded) bytes: the content address.
    content_sha256: Mapped[str | None] = mapped_column(
        String(length=64),
        nullable=True,
    )
    #: Digest of what the client sent. Audit only — never a path input.
    source_sha256: Mapped[str] = mapped_column(String(length=64), nullable=False)
    #: Size of the stored bytes (0 until the transcode lands).
    size_bytes: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=False,
        default=0,
        server_default="0",
    )
    #: Size of the uploaded bytes — the number the quota accounting and
    #: the size-cap rejection read.
    source_size_bytes: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=False,
    )
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: Which scanner adapter produced the verdict (``clamd`` /
    #: ``disabled``) — the A6.2.5 audit evidence that a decision was
    #: made by a named component.
    scanner: Mapped[str | None] = mapped_column(String(length=32), nullable=True)
    scanned_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
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
    ready_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    __table_args__ = (
        Index(
            "ix_community_media_uploads_public_id",
            "public_id",
            unique=True,
        ),
        # The per-profile quota count ("live rows I hold") and the
        # owner-listing read.
        Index(
            "ix_community_media_uploads_profile_state",
            "profile_id",
            "state",
        ),
        # The feed projection's batched "media for these posts" read.
        Index(
            "ix_community_media_uploads_post_position",
            "post_id",
            "attach_position",
        ),
        # The refcount behind the store's delete ("does anything else
        # still point at this digest?").
        Index(
            "ix_community_media_uploads_content_sha256",
            "content_sha256",
        ),
    )


__all__ = [
    "MEDIA_STATE_ALLOWLIST",
    "MEDIA_STATE_DELETED",
    "MEDIA_STATE_PENDING",
    "MEDIA_STATE_READY",
    "MEDIA_STATE_REJECTED",
    "MEDIA_STATE_REVIEW",
    "MEDIA_STATE_SCANNING",
    "MEDIA_STATE_TRANSCODING",
    "MEDIA_TERMINAL_STATES",
    "MEDIA_TRANSITIONS",
    "CommunityMediaUpload",
    "is_allowed_media_state",
    "is_allowed_media_transition",
]
