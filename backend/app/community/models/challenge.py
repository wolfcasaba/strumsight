"""SQLAlchemy ORM models for Community challenges (E09-R21, ADR 0415).

The first-version challenge schema — three tables:

* ``CommunityChallenge`` — one row per challenge definition
  (author, type, metric, difficulty, server-authoritative
  ``starts_at`` / ``ends_at`` window).
* ``CommunityChallengeParticipant`` — one row per accepted
  participant (the (challenge, profile) join with the personal
  best metric).
* ``CommunityChallengeInvite`` — one row per invite edge
  (the (challenge, inviter, invitee) row with the
  ``ChallengeInviteState`` wire-string and the idempotency key).

Design contract (the §5 / §0.0 invariants — these are the load-
bearing guarantees the service and the tests pin):

* **Server-side author identity (§5.1).** ``author_profile_id``
  is the FK to ``community_profiles`` with CASCADE — a profile
  hard-delete (the future retention-policy delete) cleans its
  challenges in the same transaction.

* **Wire-string type (D1).** ``type`` is a plain ``String``
  (ADR 0398 §1 project-wide pattern); the value set is enforced
  at the service boundary (``is_allowed_challenge_type`` mirrors
  the Kör 20 ``is_allowed_notification_type`` pattern). The DB
  does NOT constrain it — leaving the column unconstrained means
  a future round can add a new wire value without a migration,
  and the §6.1 valódi-sértés próba (which drops the allowlist
  check) can land two rows of unknown type without a DB-level
  CHECK tripping first.

* **Club affinity reserved (D7).** ``club_id`` is a nullable
  string column with NO ForeignKey — the ``community_clubs``
  table is Kör 24 scope. The column exists so the Kör 24
  club integration does not require a schema change.

* **Server-authoritative window (A7, §5.2).** ``starts_at`` /
  ``ends_at`` are ``DateTime(timezone=True)``. The expiry check
  is server-time, never client-time.

* **Idempotency (A4, D4).** ``community_challenge_invites`` has
  a composite UNIQUE on
  ``(challenge_id, inviter_profile_id, invitee_profile_id,
  idempotency_key)``. A retry with the same key hits the
  existing row (the service catches ``IntegrityError`` and
  re-reads). NULL keys are non-conflicting in SQL UNIQUE.

* **State graph (D1, D5).** ``state`` is the wire-string form
  of the Kör 5 ``ChallengeInviteState`` enum. The service
  guards the transition graph with a conditional UPDATE
  (``WHERE state IN (:megengedett_forrás_állapotok)`` +
  rowcount-check). The DB-level CHECK is a defensive safety
  net that lists the nine known wire values; it does NOT
  encode the transition graph — that lives at the service
  layer (a future round could add a CHECK constraint on
  ``responded_at`` being non-NULL for terminal states, but
  the A1 / A5 measure-matrix depends on the service-level
  conditional UPDATE being the enforcement).

* **Cursor pagination.** The invites list query orders by
  ``(created_at DESC, id DESC)`` per the project-wide
  cursor pattern (Kör 11 / Kör 16). The composite index
  ``(challenge_id, state, created_at, id)`` backs both the
  per-challenge invite list and the per-viewer inbox join.

Importing this module is load-bearing for the migration's
side-effect import: it registers the tables with
``Base.metadata`` so ``alembic compare_metadata`` (the round-12
migration-contract guard) sees the tables as part of the
expected schema.
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


# ---------------------------------------------------------------------------
# Wire-string vocabulary — mirrors the Kör 5 enum in
# ``lib/features/community/domain/entities/community_challenge.dart``.
# The 9 invite-state values and the 5 challenge-type values are
# byte-identical to the Dart ``ChallengeInviteState`` /
# ``ChallengeType`` enum values. The Flutter wire-decoders
# collapse unknown values to ``null`` (the A3 measure-matrix cell),
# so the backend can add new values without a breaking change.
# ---------------------------------------------------------------------------

CHALLENGE_INVITE_STATE_DRAFT: str = "draft"
CHALLENGE_INVITE_STATE_SENT: str = "sent"
CHALLENGE_INVITE_STATE_ACCEPTED: str = "accepted"
CHALLENGE_INVITE_STATE_DECLINED: str = "declined"
CHALLENGE_INVITE_STATE_EXPIRED: str = "expired"
CHALLENGE_INVITE_STATE_CANCELLED: str = "cancelled"
CHALLENGE_INVITE_STATE_ACTIVE: str = "active"
CHALLENGE_INVITE_STATE_COMPLETED: str = "completed"
CHALLENGE_INVITE_STATE_FORFEITED: str = "forfeited"

CHALLENGE_INVITE_STATE_ALLOWLIST: frozenset[str] = frozenset(
    {
        CHALLENGE_INVITE_STATE_DRAFT,
        CHALLENGE_INVITE_STATE_SENT,
        CHALLENGE_INVITE_STATE_ACCEPTED,
        CHALLENGE_INVITE_STATE_DECLINED,
        CHALLENGE_INVITE_STATE_EXPIRED,
        CHALLENGE_INVITE_STATE_CANCELLED,
        CHALLENGE_INVITE_STATE_ACTIVE,
        CHALLENGE_INVITE_STATE_COMPLETED,
        CHALLENGE_INVITE_STATE_FORFEITED,
    }
)

CHALLENGE_TYPE_FRIENDS: str = "friends"
CHALLENGE_TYPE_CLUB: str = "club"
CHALLENGE_TYPE_DAILY_COMMUNITY: str = "dailyCommunity"
CHALLENGE_TYPE_PERIODIC_GLOBAL: str = "periodicGlobal"
CHALLENGE_TYPE_PERSONAL_BEST: str = "personalBest"

CHALLENGE_TYPE_ALLOWLIST: frozenset[str] = frozenset(
    {
        CHALLENGE_TYPE_FRIENDS,
        CHALLENGE_TYPE_CLUB,
        CHALLENGE_TYPE_DAILY_COMMUNITY,
        CHALLENGE_TYPE_PERIODIC_GLOBAL,
        CHALLENGE_TYPE_PERSONAL_BEST,
    }
)


def is_allowed_challenge_type(value: str) -> bool:
    """True when ``value`` is one of the 5 wire types (D1)."""
    return value in CHALLENGE_TYPE_ALLOWLIST


def is_allowed_invite_state(value: str) -> bool:
    """True when ``value`` is one of the 9 wire states (D1)."""
    return value in CHALLENGE_INVITE_STATE_ALLOWLIST


# Source-states allowed for each transition. The graph is
# §5.1 (D5):
#
#   draft → sent
#   sent → accepted | declined | expired | cancelled
#   accepted → active | completed | forfeited | expired
#
# ``cancelled`` is the inviter-initiated branch (the
# ``cancel_invite`` endpoint), ``declined`` the
# invitee-initiated branch, ``expired`` is the server-driven
# window check (A2 / §5.2), and ``accepted`` is the
# invitee-initiated accept (the only state from which
# ``active`` / ``completed`` / ``forfeited`` can be reached).
INVITE_SOURCE_STATES_FOR_ACCEPT: frozenset[str] = frozenset(
    {CHALLENGE_INVITE_STATE_DRAFT, CHALLENGE_INVITE_STATE_SENT}
)
INVITE_SOURCE_STATES_FOR_DECLINE: frozenset[str] = frozenset(
    {CHALLENGE_INVITE_STATE_DRAFT, CHALLENGE_INVITE_STATE_SENT}
)
INVITE_SOURCE_STATES_FOR_CANCEL: frozenset[str] = frozenset(
    {CHALLENGE_INVITE_STATE_DRAFT, CHALLENGE_INVITE_STATE_SENT}
)
# Terminal states are NEVER a valid source — once an invite
# reaches a terminal state, it cannot transition further. The
# A1 measure-matrix relies on this: a ``declined`` invite
# cannot be flipped back to ``accepted``.
INVITE_TERMINAL_STATES: frozenset[str] = frozenset(
    {
        CHALLENGE_INVITE_STATE_DECLINED,
        CHALLENGE_INVITE_STATE_EXPIRED,
        CHALLENGE_INVITE_STATE_CANCELLED,
        CHALLENGE_INVITE_STATE_COMPLETED,
        CHALLENGE_INVITE_STATE_FORFEITED,
    }
)


# ---------------------------------------------------------------------------
# CommunityChallenge — one row per challenge definition.
# ---------------------------------------------------------------------------


class CommunityChallenge(Base):
    """A single challenge definition.

    Lifecycle is owned by ``services.challenge_invite_service`` (the
    invite state machine) and (future) the Kör 22 results service.
    This model is the persisted shape behind the Kör 5
    ``CommunityChallengeDefinition`` wire entity.

    The window (``starts_at`` / ``ends_at``) is the server-
    authoritative contract — the client refuses to submit results
    outside this window, and the server's expiry check is the
    security boundary (A7 / §5.2).

    The ``club_id`` column is reserved for the Kör 24 club
    integration (D7); the column exists today so the Kör 24
    schema does not need a migration.
    """

    __tablename__ = "community_challenges"

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
    author_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Wire-string type from the Kör 5 ``ChallengeType`` enum.
    type: Mapped[str] = mapped_column(String(length=32), nullable=False)
    # Free-form metric label (e.g. "score", "durationSeconds");
    # defined enum is Kör 15+ scope.
    metric: Mapped[str] = mapped_column(String(length=64), nullable=False)
    difficulty: Mapped[int] = mapped_column(Integer, nullable=False)
    # Server-authoritative window — A7 / §5.2.
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # Schema version — bumped when the wire shape evolves
    # beyond v1 (mirrors the post's ``artifact_schema_version``
    # precedent).
    version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )
    # Reserved for Kör 24 club integration (D7) — nullable,
    # no FK.
    club_id: Mapped[str | None] = mapped_column(String(length=64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_challenges_public_id",
        ),
        CheckConstraint(
            "ends_at > starts_at",
            name="ck_community_challenges_window_positive",
        ),
        # The active-window list query (challenges where
        # ``starts_at <= now <= ends_at``); the leading
        # ``type`` column is for the Kör 24 club filter.
        Index(
            "ix_community_challenges_type_starts",
            "type",
            "starts_at",
            "id",
        ),
        # The author's own challenges list.
        Index(
            "ix_community_challenges_author_created",
            "author_profile_id",
            "created_at",
            "id",
        ),
    )


# ---------------------------------------------------------------------------
# CommunityChallengeParticipant — one row per (challenge, profile) join.
# ---------------------------------------------------------------------------


class CommunityChallengeParticipant(Base):
    """A participant row for a single challenge.

    Created by the ``accept_invite`` service path; one row per
    ``(challenge_id, participant_profile_id)`` pair (the DB-level
    UNIQUE prevents duplicate joins). The personal-best
    ``best_metric_value`` is the Kör 22 results surface — NULL
    until the participant submits a verified result.
    """

    __tablename__ = "community_challenge_participants"

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
    challenge_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_challenges.id", ondelete="CASCADE"),
        nullable=False,
    )
    participant_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Personal best metric — the Kör 22 surface. NULL until
    # the participant has submitted a verified result.
    best_metric_value: Mapped[int | None] = mapped_column(Integer, nullable=True)
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_challenge_participants_public_id",
        ),
        # One participant row per (challenge, profile) pair.
        UniqueConstraint(
            "challenge_id",
            "participant_profile_id",
            name="uq_community_challenge_participants_pair",
        ),
        Index(
            "ix_community_challenge_participants_challenge",
            "challenge_id",
            "joined_at",
            "id",
        ),
        Index(
            "ix_community_challenge_participants_profile",
            "participant_profile_id",
            "joined_at",
            "id",
        ),
    )


# ---------------------------------------------------------------------------
# CommunityChallengeInvite — one row per (challenge, invitee) invite edge.
# ---------------------------------------------------------------------------


class CommunityChallengeInvite(Base):
    """A single invite row for a single (challenge, invitee) pair.

    The state machine is owned by
    ``services.challenge_invite_service`` — every transition is
    a single conditional UPDATE that the service guards with a
    rowcount check (ADR 0415 D5). The DB column is plain
    ``String`` with a CHECK on the nine known values (a
    defensive safety net, not the transition-graph
    enforcer).
    """

    __tablename__ = "community_challenge_invites"

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
    challenge_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_challenges.id", ondelete="CASCADE"),
        nullable=False,
    )
    inviter_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    invitee_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Wire-string state from the Kör 5 ``ChallengeInviteState``
    # enum.
    state: Mapped[str] = mapped_column(String(length=16), nullable=False)
    # Server-authoritative expiry — the invite window. The
    # accept path checks ``expires_at > now`` (A2 / §5.2
    # server-time check).
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    # Idempotency surface (A4, D4). A retry with the same
    # key hits the existing row. NULL keys are
    # non-conflicting in SQL UNIQUE.
    idempotency_key: Mapped[str | None] = mapped_column(
        String(length=128), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )
    # Last-transition stamp — the ``accepted`` /
    # ``declined`` / ``cancelled`` / ``expired`` transition
    # lands here. NULL on a fresh ``draft`` or ``sent`` row.
    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_challenge_invites_public_id",
        ),
        # §5.3 / A4 idempotency invariant — the composite
        # key includes the (challenge, inviter, invitee)
        # tuple so the same idempotency_key value on
        # DIFFERENT invites does not collide. Mirrors the
        # Kör 11 ``uq_community_posts_profile_idempotency``
        # precedent, extended with the per-invitee
        # dimension.
        UniqueConstraint(
            "challenge_id",
            "inviter_profile_id",
            "invitee_profile_id",
            "idempotency_key",
            name="uq_community_challenge_invites_idempotency",
        ),
        # Self-pair rejection at the DB layer (mirrors the
        # ``ck_community_blocks_no_self_block`` precedent).
        CheckConstraint(
            "inviter_profile_id != invitee_profile_id",
            name="ck_community_challenge_invites_no_self_invite",
        ),
        # DB-level safety net that lists the nine known
        # wire values. The service still guards the
        # transition graph with a conditional UPDATE — a
        # future round could add a CHECK on
        # ``responded_at`` being non-NULL for terminal
        # states, but the A1 / A5 measure-matrix depends on
        # the service-level conditional UPDATE being the
        # enforcement.
        CheckConstraint(
            "state IN ("
            "'draft','sent','accepted','declined',"
            "'expired','cancelled','active',"
            "'completed','forfeited'"
            ")",
            name="ck_community_challenge_invites_state_known",
        ),
        # The per-challenge invite list (the Kör 21
        # ``GET /community/challenges/{id}/invites``
        # endpoint).
        Index(
            "ix_community_challenge_invites_challenge_state",
            "challenge_id",
            "state",
            "created_at",
            "id",
        ),
        # The per-invitee inbox (the recipient's pending
        # invites). The leading ``state`` column lets the
        # ``WHERE invitee_profile_id = ? AND state =
        # 'sent'`` lookup hit the index directly.
        Index(
            "ix_community_challenge_invites_invitee_state",
            "invitee_profile_id",
            "state",
            "created_at",
            "id",
        ),
        # The idempotency probe — the Kör 11
        # ``ix_community_posts_idempotency_key``
        # precedent.
        Index(
            "ix_community_challenge_invites_idempotency_key",
            "challenge_id",
            "inviter_profile_id",
            "idempotency_key",
        ),
    )


__all__ = [
    "CHALLENGE_INVITE_STATE_ALLOWLIST",
    "CHALLENGE_INVITE_STATE_FORFEITED",
    "CHALLENGE_INVITE_STATE_COMPLETED",
    "CHALLENGE_INVITE_STATE_ACTIVE",
    "CHALLENGE_INVITE_STATE_CANCELLED",
    "CHALLENGE_INVITE_STATE_DECLINED",
    "CHALLENGE_INVITE_STATE_DRAFT",
    "CHALLENGE_INVITE_STATE_EXPIRED",
    "CHALLENGE_INVITE_STATE_SENT",
    "CHALLENGE_TYPE_ALLOWLIST",
    "CHALLENGE_TYPE_CLUB",
    "CHALLENGE_TYPE_DAILY_COMMUNITY",
    "CHALLENGE_TYPE_FRIENDS",
    "CHALLENGE_TYPE_PERIODIC_GLOBAL",
    "CHALLENGE_TYPE_PERSONAL_BEST",
    "CommunityChallenge",
    "CommunityChallengeInvite",
    "CommunityChallengeParticipant",
    "INVITE_SOURCE_STATES_FOR_ACCEPT",
    "INVITE_SOURCE_STATES_FOR_CANCEL",
    "INVITE_SOURCE_STATES_FOR_DECLINE",
    "INVITE_TERMINAL_STATES",
    "is_allowed_challenge_type",
    "is_allowed_invite_state",
]
