"""SQLAlchemy ORM model for Community post bookmarks (E09-R17, ADR 0408).

Adds the private "saved by me" surface on top of the Kör 11
``community_posts`` table — one row per ``(post, viewer)`` pair. The
bookmark is a binary existence predicate: the row exists (the viewer
saved the post), or it does not. There is no kind / category /
annotation column — the bookmark is the wire primitive the Flutter
``BookmarksScreen`` consumes; the §5.2 invariant pins the count to
PRIVATE — the SDK never projects a bookmark count onto the public
``PostOut`` shape.

The schema follows the project-wide ``public UUID + bigint PK`` pattern
(ADR 0396 §1) but does NOT carry a ``public_id`` column: the
bookmark is private to the viewer/post pair and is never surfaced as
a wire resource. The wire projection (Flutter ``BookmarksScreen``)
only ever needs the internal ``id`` (for cursor pagination), the
``post_id`` (the joined post row), the ``profile_id`` (the owner),
and the ``created_at`` (the cursor key).

* ``id`` — BigInteger internal PK, variant to Integer on SQLite for
  autoincrement portability (same seam used by Kör 5–16 migrations).
* ``post_id`` — FK to ``community_posts.id`` with
  ``ondelete='CASCADE'`` so a post hard-delete (the future retention
  policy) cleans up its bookmarks in the same transaction.
  Soft-delete leaves the row in place — the bookmark-list query is
  responsible for emitting a tombstone element (D3 / §5.2).
* ``profile_id`` — FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'`` so a profile deletion removes its
  bookmarks in the same transaction (the Kör 15 / Kör 7 precedent).
* ``created_at`` — ``DateTime(timezone=True)`` — the cursor key
  (D4, ``(created_at DESC, id DESC)`` pagination).
* ``UNIQUE(post_id, profile_id)`` — the §6 A1 idempotency invariant.
  A retry with the same pair hits the existing row; a second
  bookmark by the same viewer on the same post never lands. The
  composite ``(profile_id, created_at, id)`` index backs the
  caller's own bookmark list pagination (the cursor keyset).

Importing this module is load-bearing for the migration's side-
effect import: it registers the table with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract
guard) sees the table as part of the expected schema. The migration
body uses raw ``sa.Column`` calls — the schema is the migration-
source-of-truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityBookmark(Base):
    """A single bookmark recorded by one viewer on one post.

    The pair ``(post_id, profile_id)`` is unique — a viewer holds at
    most one bookmark per post. The bookmark is private to the
    viewer/post pair and is never projected onto the public
    ``PostOut`` (brief §5.2). The ``CommunityBookmark`` is the
    Kör 15 ``CommunityReaction`` layout sans ``kind``: an
    idempotent pair existence, no allowlist.
    """

    __tablename__ = "community_bookmarks"

    id: Mapped[int] = mapped_column(
        # Same BigInteger / Integer-on-SQLite variant rationale as
        # ``CommunityReaction`` / ``CommunityPost`` (ADR 0396 §1).
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
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    # The §6 A1 invariant: a retry with the same (post, viewer) does
    # NOT create a second row — the DB rejects the duplicate INSERT
    # and the service layer translates the IntegrityError into a
    # no-op re-read of the existing row.
    __table_args__ = (
        UniqueConstraint(
            "post_id",
            "profile_id",
            name="uq_community_bookmarks_post_profile",
        ),
        # The caller's own bookmark list is keyed by
        # ``(profile_id, created_at, id)`` — the D4 cursor keyset.
        # The UNIQUE constraint above already provides index
        # coverage on (post_id, profile_id), but the list query
        # reads on (profile_id, created_at, id), which is the
        # composite we declare here. Keeping it explicit so the
        # planner has a stable shape regardless of any future
        # refactor of the UNIQUE backing index.
        Index(
            "ix_community_bookmarks_profile_created",
            "profile_id",
            "created_at",
            "id",
        ),
    )


__all__ = ["CommunityBookmark"]
