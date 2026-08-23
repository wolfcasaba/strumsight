"""Safety-relationship ORM models — E09-R08, ADR 0402 §D1.

Two tables back the block / mute state machine:

* ``CommunityBlock`` — one row per block edge
  (blocker → blocked). Self-block is forbidden by ``CHECK``;
  duplicate edges are forbidden by ``UNIQUE`` (the §6.1 A2 race
  protection). The two FKs cascade so a parent profile removal
  cleans up its block rows in the same transaction, mirroring the
  ``community_follows`` pattern.

* ``CommunityMute`` — one row per mute edge (muter → muted). Same
  layout as ``CommunityBlock``: ``UNIQUE`` on the pair, ``CHECK``
  against self-mute, CASCADE FKs.

Both tables use the project-wide ``BigInteger`` PK with the
``with_variant(Integer(), "sqlite")`` port (ADR 0396 §1), mirroring
``CommunityFollow`` / ``CommunityFollowRequest`` exactly.

The block row carries NO state machine — block is binary (the row
exists, or it does not). The single state-transition is the
``unblock`` DELETE; the brief §5.3 invariant is that unblock does
NOT recreate any previously deleted follow. Likewise mute is binary;
the brief §5.2 invariant is that mute carries NO signal to the
muted party and does NOT mutate the follow graph.

Challenge-invite rows are NOT modelled here — the
``community_challenges`` / ``community_challenge_invites`` tables
are Kör 21 scope (ADR 0402 §D3).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityBlock(Base):
    """A block edge from one profile to another.

    The brief §5.1 / ADR 0402 §D1 invariants live at the DB layer:

    * ``UNIQUE (blocker_profile_id, blocked_profile_id)`` — the §6.1
      A2 race protection. Two concurrent block calls cannot both
      land; the service layer reads the existing row and short-
      circuits the second writer to success (the same
      idempotency-at-retry pattern as ``CommunityFollow``).
    * ``CHECK (blocker_profile_id != blocked_profile_id)`` — self-
      block is impossible at the DB layer, not just the service
      layer. Mirrors ``ck_community_follows_no_self_follow``.

    The CASCADE on both FKs mirrors the ``community_follows`` /
    ``community_follow_requests`` pattern: removing a profile cleans
    up its block rows in the same transaction.

    A block row carries no state machine — the existence of the row
    IS the block. The single transition is the ``unblock`` DELETE;
    a previous ``block`` is NEVER recreated by the unblock path
    (brief §5.3, ADR 0402 §D1 — the existing ``community_follows``
    follow edges are DELETEd inside the block transaction, NOT
    re-created on unblock).
    """

    __tablename__ = "community_blocks"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        unique=True,
        index=True,
        default=uuid.uuid4,
        nullable=False,
    )
    blocker_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    blocked_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    __table_args__ = (
        UniqueConstraint(
            "blocker_profile_id",
            "blocked_profile_id",
            name="uq_community_blocks_blocker_blocked",
        ),
        CheckConstraint(
            "blocker_profile_id != blocked_profile_id",
            name="ck_community_blocks_no_self_block",
        ),
        Index(
            "ix_community_blocks_blocker_created",
            "blocker_profile_id",
            "created_at",
            "id",
        ),
        Index(
            "ix_community_blocks_blocked_created",
            "blocked_profile_id",
            "created_at",
            "id",
        ),
    )


class CommunityMute(Base):
    """A mute edge from one profile to another.

    Mirrors the ``CommunityBlock`` layout. The mute is view-only
    (brief §5.2): no signal is sent to the muted party, the follow
    graph is untouched, and the row's existence is the entire state
    machine.

    ``UNIQUE`` on the pair keeps the DB idempotency guarantee. The
    composite ``(muter_profile_id, created_at, id)`` index supports
    the cursor-paginated ``GET /community/muted`` listing.
    """

    __tablename__ = "community_mutes"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        unique=True,
        index=True,
        default=uuid.uuid4,
        nullable=False,
    )
    muter_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    muted_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    __table_args__ = (
        UniqueConstraint(
            "muter_profile_id",
            "muted_profile_id",
            name="uq_community_mutes_muter_muted",
        ),
        CheckConstraint(
            "muter_profile_id != muted_profile_id",
            name="ck_community_mutes_no_self_mute",
        ),
        Index(
            "ix_community_mutes_muter_created",
            "muter_profile_id",
            "created_at",
            "id",
        ),
    )


__all__ = ["CommunityBlock", "CommunityMute"]
