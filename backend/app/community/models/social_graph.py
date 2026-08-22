"""Social-graph ORM models — E09-R07, ADR 0401 §4–5.

Two tables back the follow lifecycle:

* ``CommunityFollow`` — one row per active follow edge
  (follower → followed). Self-follow is forbidden by ``CHECK``;
  duplicate edges are forbidden by ``UNIQUE``. The brief §5.1
  invariant lives at the DB layer, not in the service layer — a
  race between two concurrent follow calls cannot land two rows.
* ``CommunityFollowRequest`` — at most one row per
  (requester, target) pair. The row is recycled (``UPDATE``) across
  follow / decline / cancel / refollow cycles so the plain
  ``UNIQUE`` constraint enforces "at most one open request per pair"
  without a dialect-specific partial index. Self-targeting is
  forbidden by ``CHECK``.

Both tables use the project-wide ``BigInteger`` PK with the
``with_variant(Integer(), "sqlite")`` port (ADR 0396 §1).

The ``status`` column on the request is a plain ``String`` per the
project-wide ``visibility`` / ``audience_default`` pattern
(ADR 0398 §1) — DB-level ``CHECK`` is intentionally absent so the
value-set can grow without a migration.
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
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityFollow(Base):
    """An active follow edge from one profile to another.

    The brief §5.1 invariant lives at the DB layer:

    * ``UNIQUE (follower_profile_id, followed_profile_id)`` — the
      §6.1 A2 race protection. Two concurrent follow calls cannot
      both land; the second raises ``IntegrityError`` which the
      service layer translates to ``FollowAlreadyExists``.
    * ``CHECK (follower_profile_id != followed_profile_id)`` — the
      §6.1 A1 self-follow protection. A request to follow yourself
      never even hits the application layer.

    The CASCADE on both FKs mirrors the existing ``handle_history``
    / ``community_privacy_settings`` pattern: removing a profile
    cleans up its graph edges in the same transaction.
    """

    __tablename__ = "community_follows"

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
    follower_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    followed_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    __table_args__ = (
        UniqueConstraint(
            "follower_profile_id",
            "followed_profile_id",
            name="uq_community_follows_follower_followed",
        ),
        CheckConstraint(
            "follower_profile_id != followed_profile_id",
            name="ck_community_follows_no_self_follow",
        ),
        Index(
            "ix_community_follows_followed_created",
            "followed_profile_id",
            "created_at",
            "id",
        ),
        Index(
            "ix_community_follows_follower_created",
            "follower_profile_id",
            "created_at",
            "id",
        ),
    )


class CommunityFollowRequest(Base):
    """A pending or resolved follow request for a private profile.

    The plain ``UNIQUE (requester_profile_id, target_profile_id)``
    is the §6.1 A2 race protection — a concurrent retry from the
    same caller cannot land a second row. The service layer reads
    the existing row and ``UPDATE``s its ``status`` instead of
    issuing a fresh ``INSERT``, so the pair always carries exactly
    one row across follow / decline / cancel / refollow cycles
    (ADR 0401 §4).

    Self-targeting is forbidden by ``CHECK``.

    ``status`` is plain ``String`` per the project-wide
    ``visibility`` / ``audience_default`` pattern (ADR 0398 §1).
    The valid value-set is ``requested`` / ``accepted`` / ``declined``
    / ``cancelled``; the service layer enforces it (no DB CHECK).
    """

    __tablename__ = "community_follow_requests"

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
    requester_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    target_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    status: Mapped[str] = mapped_column(
        String,
        default="requested",
        server_default="requested",
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint(
            "requester_profile_id",
            "target_profile_id",
            name="uq_community_follow_requests_pair",
        ),
        CheckConstraint(
            "requester_profile_id != target_profile_id",
            name="ck_community_follow_requests_no_self_request",
        ),
        Index(
            "ix_community_follow_requests_target_status",
            "target_profile_id",
            "status",
        ),
        Index(
            "ix_community_follow_requests_requester_created",
            "requester_profile_id",
            "created_at",
            "id",
        ),
    )


__all__ = ["CommunityFollow", "CommunityFollowRequest"]
