"""SQLAlchemy ORM model for community leaderboard opt-in (E09-R23,
ADR 0418 D2).

The opt-in state — one row per profile that has explicitly opted in
to leaderboard visibility. The row's PRESENCE is the opt-in signal;
a missing row means the user is excluded from any public-scope
leaderboard (A3 / §5.3).

Design contract (the §5 / §0.0 invariants):

* **Own table, not on the Kör 4 ``community_privacy_settings``
  row** (ADR 0418 D2). The Kör 4 table holds
  ``visibility`` / ``audience_default`` — orthogonal concepts to
  leaderboard participation. A user may have a public
  ``visibility`` profile AND choose to opt out of leaderboards,
  and the reverse.

* **One-row-per-profile (UNIQUE ``profile_id``).** A second
  INSERT for the same profile raises ``IntegrityError``; the
  service layer translates that to an idempotent return of the
  existing row (the same pattern as the Kör 21 invite idempotency
  surface).

* **No client-issued opt-in field on the Kör 22 ``submitResult``
  / invite endpoints (§5.1).** The opt-in lives on its OWN
  endpoint (``PUT /v1/community/leaderboards/opt-in``) and never
  piggy-backs on a write to ``community_challenge_results``.

* **Migration is STRICTLY ADDITIVE.** No existing column /
  constraint / index on any prior table is touched.

Importing this module is load-bearing for the migration's
``Base.metadata`` registration (the round-12 migration-contract
guard).
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
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityLeaderboardOptIn(Base):
    """One row per profile that has opted in to leaderboard visibility.

    The PRESENCE of a row is the opt-in signal. The
    ``opted_in_at`` column is the audit timestamp (when the user
    flipped the bit); the service exposes a single
    ``set_opt_in(db, *, profile_id, opted_in: bool, now)`` helper
    that INSERTs (opt-in) or DELETEs (opt-out) the row atomically.

    A row is CASCADE-deleted when its profile is hard-deleted
    (mirrors the project-wide ``community_privacy_settings`` /
    ``community_challenge_invites`` pattern).
    """

    __tablename__ = "community_leaderboard_opt_ins"

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
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    opted_in_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        nullable=False,
    )

    __table_args__ = (
        # The opt-in lookup — the service checks "is this profile
        # opted in" with a single SELECT by ``profile_id``.
        Index(
            "ix_community_leaderboard_opt_ins_profile",
            "profile_id",
            unique=True,
        ),
    )


__all__ = ["CommunityLeaderboardOptIn"]