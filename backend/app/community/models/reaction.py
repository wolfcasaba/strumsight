"""SQLAlchemy ORM model for Community post reactions (E09-R15).

The first-version reaction table — one row per ``(post, viewer)``
pair. The wire surface (``PostOut`` / ``FeedPostItem`` projection
that includes ``viewerReaction`` + ``reactionCount``) is **NOT**
shipped in this round; the §0.0 D2 scope-shrink notes that the
projection change belongs to a later round's ``allowed_paths``. The
service layer this model backs is the same one a future round will
plug into the router.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Server-side viewer identity (§5.1).** ``set_reaction`` takes the
  JWT-resolved ``viewer_public_id`` as a parameter — there is no
  body-side override path. The §6 A7 "no learning XP" invariant lives
  next to the upsert: a reaction write MUST NOT trigger any gamification
  cross-feature adapter.

* **Idempotent set / unique constraint (§5.2, A1).** The pair
  ``UNIQUE(post_id, profile_id)`` is the §6 A1 enforcement — a retry
  with the same kind updates the kind (no duplicate row), a retry
  with a different kind updates the kind (still no duplicate row).
  Without the constraint, two retries would land two rows and the
  count would double (the §6.1 valódi-sértés próba in the test).

* **Reaction-kind change is update, not insert (§6 A2).** A retry
  with a different ``kind`` against the same ``(post_id, profile_id)``
  row updates the existing row's ``kind`` to the new value and bumps
  ``updated_at`` — the count is unchanged.

* **Allowlist enforcement (§3, §5.3).** The Pydantic / service layer
  rejects anything outside ``{support, celebrate, inspiring, helpful}``
  with ``InvalidReactionKind``; the column itself is plain ``String``
  for the project-wide pattern (ADR 0398 §1).

* **No negative count (§6 A5).** The aggregated count is computed at
  query-time (``COUNT(*)`` over the row), so the property invariant
  is structural — there is no path that yields ``COUNT(*) < 0``.

* **Cascade on post / profile delete (§5.4).** ``ON DELETE CASCADE``
  on both FKs keeps the table consistent if a post is hard-deleted
  later (the §11.5 soft-delete tombstone leaves the row in place;
  the cascade is the safety net for the future retention-policy
  hard-delete).

Importing this module is load-bearing for the migration's
side-effect import: it registers the table with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard)
sees the table as part of the expected schema.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base

# Allowlist of reaction kinds (brief §3). Mirrors the Kör 5 wire
# enum in ``lib/features/community/domain/entities/community_reaction.dart``
# — the two stay in lockstep because the wire decoder at both ends
# collapses unknown values to ``null`` (the A3 cell).
REACTION_KIND_SUPPORT: str = "support"
REACTION_KIND_CELEBRATE: str = "celebrate"
REACTION_KIND_INSPIRING: str = "inspiring"
REACTION_KIND_HELPFUL: str = "helpful"

REACTION_KIND_ALLOWLIST: frozenset[str] = frozenset(
    {
        REACTION_KIND_SUPPORT,
        REACTION_KIND_CELEBRATE,
        REACTION_KIND_INSPIRING,
        REACTION_KIND_HELPFUL,
    }
)


def is_allowed_reaction_kind(value: str) -> bool:
    """True when ``value`` is one of the four MVP kinds (§3)."""
    return value in REACTION_KIND_ALLOWLIST


class CommunityReaction(Base):
    """A single reaction recorded by one viewer on one post.

    The pair ``(post_id, profile_id)`` is unique — a viewer holds at
    most one reaction per post. A change of kind is an UPDATE on the
    existing row, not a new row (the §6 A2 invariant). Removal is a
    DELETE; the count goes down by one.

    The model is intentionally narrow — no ``public_id`` (the row is
    private to the viewer/post pair, never surfaced as a resource).
    """

    __tablename__ = "community_reactions"

    id: Mapped[int] = mapped_column(
        # Same BigInteger / Integer-on-SQLite variant rationale as
        # ``CommunityProfile`` / ``CommunityPost`` (ADR 0396 §1).
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    post_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_posts.id", ondelete="CASCADE"),
        nullable=False,
    )
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Allowlist-validated at the service boundary
    # (``reaction_service.set_reaction``). Plain ``String`` per the
    # project-wide ``visibility`` / ``audience_default`` pattern
    # (ADR 0398 §1).
    kind: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    # The §6 A1 invariant: a retry with the same (post, viewer) does
    # NOT create a second row — the DB rejects the duplicate INSERT
    # and the service layer translates the IntegrityError into an
    # UPDATE (the A2 "kind change is update, not insert" path).
    __table_args__ = (
        UniqueConstraint(
            "post_id",
            "profile_id",
            name="uq_community_reactions_post_profile",
        ),
        # Composite (post_id) backing the count aggregation plan
        # AND the "did viewer react" projection read. The UNIQUE
        # constraint above already covers (post_id, profile_id),
        # but a separate index on (post_id) alone is what the
        # count query's planner shape hits — keeping it explicit
        # so the planner has a stable index regardless of any
        # future refactor of the UNIQUE backing index.
        Index("ix_community_reactions_post", "post_id"),
    )


__all__ = [
    "CommunityReaction",
    "REACTION_KIND_ALLOWLIST",
    "REACTION_KIND_CELEBRATE",
    "REACTION_KIND_HELPFUL",
    "REACTION_KIND_INSPIRING",
    "REACTION_KIND_SUPPORT",
    "is_allowed_reaction_kind",
]
