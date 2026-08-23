"""SQLAlchemy ORM model for Community notification inbox (E09-R20, ADR 0414).

The first-version inbox table — one row per ``CommunityNotificationItem``
in the Flutter inbox. The wire surface (``CommunityNotificationItem``
+ ``CommunityNotificationRepository``) is M2-5 / ADR 0399 territory
and is **unchanged** by this round; this model is the persisted
shape behind it.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Server-side recipient identity (§5.1).** ``recipient_profile_id``
  is the FK to ``community_profiles`` with CASCADE — a profile
  hard-delete (the future retention-policy delete) cleans its inbox
  in the same transaction.

* **Nullable actor (§5.2).** ``actor_profile_id`` is also a FK to
  ``community_profiles`` with CASCADE, but NULLABLE for system
  events: a moderation-decision, a security alert — events where
  no user triggered the notification. The A4 block-pair filter is
  skipped on system events (no actor → no block relationship
  possible).

* **A2 burst-aggregation key.** The ``(entity_type, entity_id)``
  pair is the aggregation key the service uses to merge five
  reactions inside the 15-minute window into a single inbox item
  with ``aggregate_count = 5``. The composite index
  ``(recipient_profile_id, entity_type, entity_id, created_at)``
  backs the lookup. The pair is NULLABLE — a system event with no
  entity to point at leaves them NULL (the "purely informational"
  notification class, the Kör 5 entity precedent).

* **A7 dedup key.** ``dedup_key`` is a nullable string UNIQUE-
  constrained per ``(recipient_profile_id, dedup_key)``. A retry
  with the same ``dedup_key`` is rejected by the DB; the service
  catches ``IntegrityError`` and re-reads the existing row
  (the ``reaction_service.set_reaction`` pattern). A NULL
  ``dedup_key`` is non-conflicting in SQL UNIQUE — system events
  and the burst-aggregation path opt out of dedup by leaving it
  NULL.

* **Read state (A3 race).** ``is_read`` (Boolean) + ``read_at``
  (DateTime). The mark-read service bumps both atomically inside
  a single UPDATE — the §6 / §6.1 measure-matrix pins consistency
  under two concurrent mark-read calls from two devices.

* **Localization keys (A1 redaction).** ``title_key`` and
  ``body_key`` are stored ON the row — the push payload MUST NOT
  carry localized text (ADR 0414 §D1 — the push is a refresh
  trigger, the localised body lives in the ARB catalogues the
  client reads on receipt of the inbox row). The column shape
  (KEY not TEXT) is what makes redaction structurally possible.

* **public UUID + bigint PK.** The project-wide pattern
  (ADR 0396 §1). ``public_id`` is the wire surface, the internal
  ``id`` is the join surface. SQLite drops the BigInteger to
  Integer via the standard variant so in-memory test engines
  autoincrement reliably.

Importing this module is load-bearing for the migration's
side-effect import: it registers the table with ``Base.metadata``
so ``alembic compare_metadata`` (the round-12 migration-contract
guard) sees the table as part of the expected schema.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
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


# Notification kind allowlist (brief §0.0, §3). Mirrors the Kör 5
# ``CommunityNotificationKind`` wire enum in
# ``lib/features/community/domain/entities/notification_item.dart``
# — the two stay in lockstep because the wire decoder at both ends
# collapses unknown values to ``null`` (the A3 cell, the §17.3
# invariant). The 10 wire values:
NOTIFICATION_TYPE_FOLLOW_REQUEST: str = "follow_request"
NOTIFICATION_TYPE_FOLLOW_ACCEPTED: str = "follow_accepted"
NOTIFICATION_TYPE_REACTION_SUMMARY: str = "reaction_summary"
NOTIFICATION_TYPE_COMMENT: str = "comment"
NOTIFICATION_TYPE_MENTION: str = "mention"
NOTIFICATION_TYPE_CHALLENGE_INVITE: str = "challenge_invite"
NOTIFICATION_TYPE_CHALLENGE_COMPLETED: str = "challenge_completed"
NOTIFICATION_TYPE_CLUB_INVITE: str = "club_invite"
NOTIFICATION_TYPE_MODERATION_DECISION: str = "moderation_decision"
NOTIFICATION_TYPE_SECURITY_ALERT: str = "security_alert"

NOTIFICATION_TYPE_ALLOWLIST: frozenset[str] = frozenset(
    {
        NOTIFICATION_TYPE_FOLLOW_REQUEST,
        NOTIFICATION_TYPE_FOLLOW_ACCEPTED,
        NOTIFICATION_TYPE_REACTION_SUMMARY,
        NOTIFICATION_TYPE_COMMENT,
        NOTIFICATION_TYPE_MENTION,
        NOTIFICATION_TYPE_CHALLENGE_INVITE,
        NOTIFICATION_TYPE_CHALLENGE_COMPLETED,
        NOTIFICATION_TYPE_CLUB_INVITE,
        NOTIFICATION_TYPE_MODERATION_DECISION,
        NOTIFICATION_TYPE_SECURITY_ALERT,
    }
)


def is_allowed_notification_type(value: str) -> bool:
    """True when ``value`` is one of the 10 wire kinds (§3)."""
    return value in NOTIFICATION_TYPE_ALLOWLIST


# Burst-aggregation window: 15 minutes sliding (ADR 0414 §D3). The
# window is exposed as a module constant so a future round can tune
# it from a single location without grepping the service module.
REACTION_BURST_WINDOW_SECONDS: int = 15 * 60


class CommunityNotification(Base):
    """A single inbox row in the Community notification feed.

    Lifecycle is owned by
    ``services.notification_service.notification_service``. The model
    is the persisted shape; the service layer emits the push-payload
    and aggregates bursts.

    The row carries ``aggregate_count`` so the A2 burst-aggregation
    cell can land five reactions in 15 minutes as a single inbox
    item, with the count tracking how many reactions the user has
    not yet seen inside the window.
    """

    __tablename__ = "community_notifications"

    id: Mapped[int] = mapped_column(
        # Same BigInteger / Integer-on-SQLite variant rationale as
        # ``CommunityPost`` / ``CommunityProfile`` (ADR 0396 §1).
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
    recipient_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    actor_profile_id: Mapped[int | None] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=True,
    )
    # Allowlist-validated at the service boundary
    # (``notification_service.create_notification``). Plain ``String``
    # per the project-wide ``visibility`` / ``audience_default`` /
    # ``kind`` pattern (ADR 0398 §1).
    type: Mapped[str] = mapped_column(String, nullable=False)
    # Localization KEYS, not localized text. The push payload NEVER
    # carries localized text (A1 — redaction is structural because
    # the column doesn't exist for the payload to leak).
    title_key: Mapped[str] = mapped_column(String, nullable=False)
    body_key: Mapped[str | None] = mapped_column(String, nullable=True)
    # The A2 burst-aggregation key. Both columns are NULLABLE — a
    # system event with no entity to point at leaves them NULL.
    entity_type: Mapped[str | None] = mapped_column(String, nullable=True)
    entity_id: Mapped[str | None] = mapped_column(
        String(length=64), nullable=True
    )
    # The A2 burst-aggregation count. NOT NULL, default 1; the
    # service increments instead of inserting for a new event
    # inside the 15-minute window.
    aggregate_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )
    # Read state. ``is_read`` is the hot-path index column;
    # ``read_at`` is the audit stamp.
    is_read: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="0"
    )
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # A7 dedup key. UNIQUE per (recipient, dedup_key); a NULL
    # dedup_key is non-conflicting in SQL UNIQUE.
    dedup_key: Mapped[str | None] = mapped_column(
        String(length=128), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # ``updated_at`` doubles as the burst-aggregation refresh
    # stamp (a new event in the window advances both the count
    # and the stamp) and the mark-read stamp (a successful
    # mark-read bumps it).
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )

    # The §5 / §0.0 invariants are encoded as constraints:
    #
    # * ``UNIQUE(public_id)`` — the wire surface is unique per
    #   row.
    # * ``UNIQUE(recipient_profile_id, dedup_key)`` — A7
    #   idempotency. NULLs do not collide in SQL UNIQUE, so
    #   system events and the burst-aggregation path leave the
    #   column NULL.
    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_notifications_public_id",
        ),
        UniqueConstraint(
            "recipient_profile_id",
            "dedup_key",
            name="uq_community_notifications_recipient_dedup",
        ),
        # Backing index for the inbox list pagination
        # (``ORDER BY created_at DESC, id DESC`` for a single
        # recipient). Same shape as the Kör 16
        # ``ix_community_comments_post_created`` composite.
        Index(
            "ix_community_notifications_recipient_created",
            "recipient_profile_id",
            "created_at",
            "id",
        ),
        # Backing index for the unread-count aggregate
        # (``WHERE recipient_profile_id = ? AND is_read = 0``).
        # The composite is hot on every inbox open.
        Index(
            "ix_community_notifications_recipient_unread",
            "recipient_profile_id",
            "is_read",
        ),
        # Backing index for the A2 burst-aggregation lookup
        # (``WHERE recipient_profile_id = ? AND entity_type = ?
        # AND entity_id = ?`` + the time-window filter). The
        # ``recipient_profile_id`` leading column lets the
        # planner use the same access path as the inbox list.
        Index(
            "ix_community_notifications_recipient_entity",
            "recipient_profile_id",
            "entity_type",
            "entity_id",
            "created_at",
        ),
    )


__all__ = [
    "CommunityNotification",
    "NOTIFICATION_TYPE_ALLOWLIST",
    "NOTIFICATION_TYPE_CHALLENGE_COMPLETED",
    "NOTIFICATION_TYPE_CHALLENGE_INVITE",
    "NOTIFICATION_TYPE_CLUB_INVITE",
    "NOTIFICATION_TYPE_COMMENT",
    "NOTIFICATION_TYPE_FOLLOW_ACCEPTED",
    "NOTIFICATION_TYPE_FOLLOW_REQUEST",
    "NOTIFICATION_TYPE_MENTION",
    "NOTIFICATION_TYPE_MODERATION_DECISION",
    "NOTIFICATION_TYPE_REACTION_SUMMARY",
    "NOTIFICATION_TYPE_SECURITY_ALERT",
    "REACTION_BURST_WINDOW_SECONDS",
    "is_allowed_notification_type",
]
