"""SQLAlchemy ORM model for Community comments (E09-R16, ADR 0407).

Adds the comment layer on top of the Kör 11 ``community_posts`` table —
one row per comment (top-level or one-level reply), soft-delete, two-value
moderation field, optimistic-concurrency via ``updated_at``.

The schema follows the project-wide ``public UUID + bigint PK`` pattern
(ADR 0396 §1) and reuses every existing convention:

* ``id`` is BigInteger internally; the SQLite variant flips to Integer
  so in-memory test engines autoincrement reliably (the same
  ``BigInteger().with_variant(Integer, 'sqlite')`` seam used by
  ``CommunityPost`` / ``CommunityProfile`` / etc.).

* ``public_id`` is ``Uuid(as_uuid=True)``, ``unique=True``,
  ``index=True``, default ``uuid.uuid4``. The wire shape only ever
  carries this — the internal ``id`` is the join surface.

* ``post_id`` is the FK to ``community_posts.id`` with
  ``ondelete='CASCADE'`` so a post hard-delete (the future retention
  policy) cleans up its comments in the same transaction. Soft-delete
  leaves the rows in place — the list query is responsible for
  filtering (the Kör 11 §D7 uniform-404 invariant at the post level
  prevents soft-deleted posts from being visible to viewers in the
  first place).

* ``author_profile_id`` is the FK to ``community_profiles.id`` with
  ``ondelete='CASCADE'`` so a profile deletion removes its comments in
  the same transaction (the Kör 5 follow-graph precedent).

* ``parent_id`` is a self-referencing FK to ``community_comments.id``,
  ``nullable=True`` for a top-level comment (depth 0) and set to the
  parent row's id for a reply. The depth limit (max 1, see ADR 0407
  §D4) is enforced at the service layer via the ``depth`` column, not
  via a recursive query — the migration's column-pair is the source
  of truth.

* ``depth`` is a plain ``Integer`` (NOT NULL, default 0). Top-level
  comments are ``depth=0``; a reply has ``depth = parent.depth + 1``.
  The service layer rejects ``create_comment`` when the parent
  ``depth >= 1`` so no row with ``depth >= 2`` ever lands (the §6.1
  valódi-sértés próba removes this guard and asserts the A1 cell
  goes red).

* ``body`` is ``String(1000)`` matching the wire shape's max length
  (the §14.2 documented comment body limit). The Pydantic layer
  re-validates the same bound.

* ``moderation_state`` is a plain ``String`` with
  ``server_default='visible'`` (brief §0.0 D5 — the Kör 11 two-value
  pattern, NOT the Dart ``ModerationState`` five-state enum). The
  active moderation workflow is Kör 26/27 scope; this round only
  consumes the field, never writes a value other than the default.

* ``created_at`` / ``updated_at`` are ``DateTime(timezone=True)``.
  ``updated_at`` doubles as the resource-version token (ADR 0398 §6
  precedent; ADR 0407 §D1 — NO separate ``version`` column).
  ``onupdate=_utcnow`` is the bump trigger; the service layer passes a
  caller-supplied ``now`` to the column write for deterministic
  timestamp tests.

* ``deleted_at`` is the soft-delete tombstone (D7 uniform-404
  invariant at the row level).

Importing this module is load-bearing for the migration's side-effect
import: it registers the table with ``Base.metadata`` so ``alembic
compare_metadata`` (the round-12 migration-contract guard) sees the
table as part of the expected schema.
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


# Comment body length cap, mirrored in the Pydantic / schema layer.
# Brief §6.1 cell A8 measures the HTML-rejection path; the wire shape
# keeps the documented Kör 14 ``kCommunityCommentBodyMaxLength``
# value (1000) in lockstep with the Flutter side.
COMMENT_BODY_MAX_LENGTH: int = 1000

# Two-value moderation field (ADR 0407 §D5). Mirrors
# ``post.MODERATION_STATE_VISIBLE`` / ``REMOVED`` — but the constants
# live in this module too because ``schemas/post.py`` is NOT on the
# ``allowed_paths`` (per ADR 0407 §D3 / §D5 — the post module's
# private symbols cannot be imported). Re-declaring the same two
# strings is intentional, not duplication-of-evil: the Kör 11
# contract is two-value by design and this module's moderation
# surface is part of the same contract.
MODERATION_STATE_VISIBLE: str = "visible"
MODERATION_STATE_REMOVED: str = "removed"


class CommunityComment(Base):
    """A single comment on a Community post.

    Lifecycle is owned by ``services.comment_service``; the model here
    is the persisted shape. The row carries ``depth`` so the service
    can enforce the §6.1 max-depth invariant with a single parent
    lookup — no recursive SQL needed.
    """

    __tablename__ = "community_comments"

    id: Mapped[int] = mapped_column(
        # Same BigInteger / Integer-on-SQLite variant rationale as
        # ``CommunityPost`` (ADR 0396 §1).
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
    post_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_posts.id", ondelete="CASCADE"),
        nullable=False,
    )
    author_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Self-FK — nullable for top-level (depth 0) comments. The
    # service rejects ``create_comment`` when the parent already has
    # ``depth >= 1`` so a row with ``depth >= 2`` never lands.
    parent_id: Mapped[int | None] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_comments.id", ondelete="CASCADE"),
        nullable=True,
    )
    # Explicit depth column (ADR 0407 §D4). NOT NULL, default 0.
    # Top-level comment = 0; reply = parent.depth + 1.
    depth: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )
    body: Mapped[str] = mapped_column(
        String(length=COMMENT_BODY_MAX_LENGTH),
        nullable=False,
    )
    moderation_state: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default=MODERATION_STATE_VISIBLE,
        server_default=MODERATION_STATE_VISIBLE,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # ``updated_at`` doubles as the resource-version token (ADR 0407
    # §D1 — NO separate ``version`` column, the Kör 4 / Kör 11
    # ``updated_at``-as-version precedent).
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Two composite indexes back the comment list pagination:
    # * ``(post_id, parent_id, created_at, id)`` — the per-post list
    #   paginator. Top-level comments come first (parent_id IS NULL),
    #   then replies, ordered by (created_at DESC, id DESC) per ADR
    #   0407 §D6.
    # * ``(post_id, created_at, id)`` — the unfiltered fallback when
    #   the parent_id filter isn't pushed down (the §0.0 "every
    #   query path through the same index" preference).
    __table_args__ = (
        Index(
            "ix_community_comments_post_parent_created",
            "post_id",
            "parent_id",
            "created_at",
            "id",
        ),
        Index(
            "ix_community_comments_post_created",
            "post_id",
            "created_at",
            "id",
        ),
    )


__all__ = [
    "COMMENT_BODY_MAX_LENGTH",
    "CommunityComment",
    "MODERATION_STATE_REMOVED",
    "MODERATION_STATE_VISIBLE",
]
