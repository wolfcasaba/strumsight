"""SQLAlchemy ORM models for Community clubs (E09-R24, ADR 0420).

The first concrete schema for the ``CommunityClub`` domain entity (the
Kör 5 / ADR 0399 entity has been wire-side for three rounds; this
round gives it a persisted shape).

Three tables:

* ``CommunityClub`` — one row per club definition (name, description,
  visibility, owner).
* ``CommunityClubMember`` — one row per (club, profile) join with the
  role (owner / moderator / member). The DB-level UNIQUE on
  ``(club_id, profile_id)`` is the A3 (duplicate-join) enforcement.
* ``CommunityClubInvite`` — one row per invite edge (club, inviter,
  invitee, status). Idempotent on
  ``(club_id, inviter_profile_id, invitee_profile_id,
  idempotency_key)``.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Wire-string vocabulary.** The ``role`` column on the member row
  is a plain ``String`` carrying one of the three ``ClubRole`` wire
  values (``owner`` / ``moderator`` / ``member``); the ``visibility``
  column on the club row carries one of the three ``ClubVisibility``
  wire values (``private`` / ``discoverable`` / ``public``). A DB-level
  CHECK lists the known values as a defensive safety net; the
  service / migration-authority is the canonical allowlist.

* **Idempotency (A3, D5).** ``community_club_members`` has a UNIQUE
  on ``(club_id, profile_id)`` — the §A3 duplicate-join enforcement.
  ``community_club_invites`` has a UNIQUE on
  ``(club_id, inviter_profile_id, invitee_profile_id,
  idempotency_key)`` — the §D4 idempotency surface (mirrors the Kör 21
  invite precedent).

* **Cascade on profile delete.** A profile hard-delete cleans up its
  membership / invite / ownership rows in the same transaction
  (mirrors the project-wide ``community_follows`` /
  ``community_challenge_invites`` precedent).

* **Migration is STRICTLY ADDITIVE.** No existing column / constraint
  / index on any prior table is touched (the Kör 11
  ``community_posts.club_id`` and Kör 21 ``community_challenges.club_id``
  columns stay as-is — the Kör 25 FK work is a future round).

* **Internal ``id: BigInteger`` PK + ``public_id: Uuid`` external
  identifier.** The project-wide convention (ADR 0396 §1, D1) — the
  wire surface carries the UUID only, the internal bigint is the join
  surface.

Importing this module is load-bearing for the migration's
side-effect import: it registers the tables with ``Base.metadata``
so ``alembic compare_metadata`` (the round-12 migration-contract
guard) sees the tables as part of the expected schema.
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
# Wire-string vocabulary — mirrors the Kör 5 / ADR 0399 enum in
# ``lib/features/community/domain/entities/community_club.dart``.
# The 3 role values and 3 visibility values are byte-identical to the
# Dart ``ClubRole`` / ``ClubVisibility`` enum values. The Flutter
# wire-decoders collapse unknown values to ``null`` (the Kör 5
# §3 invariant), so the backend can add new values without a breaking
# change.
# ---------------------------------------------------------------------------

CLUB_ROLE_OWNER: str = "owner"
CLUB_ROLE_MODERATOR: str = "moderator"
CLUB_ROLE_MEMBER: str = "member"

CLUB_ROLE_ALLOWLIST: frozenset[str] = frozenset(
    {CLUB_ROLE_OWNER, CLUB_ROLE_MODERATOR, CLUB_ROLE_MEMBER}
)

CLUB_VISIBILITY_PRIVATE: str = "private"
CLUB_VISIBILITY_DISCOVERABLE: str = "discoverable"
CLUB_VISIBILITY_PUBLIC: str = "public"

CLUB_VISIBILITY_ALLOWLIST: frozenset[str] = frozenset(
    {
        CLUB_VISIBILITY_PRIVATE,
        CLUB_VISIBILITY_DISCOVERABLE,
        CLUB_VISIBILITY_PUBLIC,
    }
)

# Maximum documented size of a club roster (D3) — mirrors the
# Flutter ``kCommunityClubsMaxMembers`` constant in
# ``community_club.dart`` (Kör 5, ADR 0399). The membership-limit
# cell in the §6.1 threshold matrix binds to this number.
MAX_CLUB_MEMBERS: int = 500

# Invite-side rate-limit budget: max 50 pending invites per club at
# any time. This is an INFORMATIVE value (the brief §6.1 only pins
# the membership-limit threshold), picked so that a single club
# cannot broadcast-spam invites — the Kör 21 challenge-invite
# precedent uses 30 invites/minute for the same reason (the
# §5.3 balance between a usable invite cadence and an enumeration
# / spam loop).
MAX_CLUB_PENDING_INVITES: int = 50


def is_allowed_club_role(value: str) -> bool:
    """True when ``value`` is one of the 3 ``ClubRole`` wire values."""
    return value in CLUB_ROLE_ALLOWLIST


def is_allowed_club_visibility(value: str) -> bool:
    """True when ``value`` is one of the 3 ``ClubVisibility`` wire values."""
    return value in CLUB_VISIBILITY_ALLOWLIST


# ---------------------------------------------------------------------------
# CommunityClub — one row per club definition.
# ---------------------------------------------------------------------------


class CommunityClub(Base):
    """A topic-centric small Community (E09-R24, ADR 0420).

    Lifecycle is owned by ``services.club_service`` — the create / read /
    leave / remove / role-change / ownership-transfer operations. The
    schema follows the project-wide ``public UUID + bigint PK`` pair
    (ADR 0396 §1, ADR 0420 D1).

    ``visibility`` is one of the three ``ClubVisibility`` wire values;
    the Kör 24 service maps the wire value to the access branch
    (``private`` → pending-request flow, ``discoverable`` / ``public``
    → direct-membership flow per D6).

    ``description`` mirrors the Flutter-side
    ``community_club.dart`` Pydantic/Factories validation rule
    (≤ 2000 chars, see ``clubs.description_max_length``).
    """

    __tablename__ = "community_clubs"

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
    # Name is short (≤ 60 chars in the Flutter factory) — the DB
    # cap mirrors the request-layer cap so the DB-level guard is a
    # defensive bound, not the primary validator.
    name: Mapped[str] = mapped_column(String(length=60), nullable=False)
    description: Mapped[str] = mapped_column(
        String(length=2000),
        nullable=False,
        default="",
        server_default="",
    )
    visibility: Mapped[str] = mapped_column(
        String(length=16),
        nullable=False,
        default=CLUB_VISIBILITY_PRIVATE,
        server_default=CLUB_VISIBILITY_PRIVATE,
    )
    # Owner profile FK — the A1 invariant's last-resort guard. The
    # service layer ALSO refuses to leave / remove the owner without
    # a transfer step; the DB-level CASCADE on profile delete cleans
    # up the club row when the owner profile is hard-deleted.
    owner_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
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
    # Soft-delete tombstone — mirrors the Kör 11 / Kör 21
    # ``deleted_at`` precedent. The Kör 24 service treats any row
    # with ``deleted_at IS NOT NULL`` as a uniform 404.
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_clubs_public_id",
        ),
        # DB-level safety net for the wire vocabulary (the service
        # is the canonical allowlist; the CHECK is a defensive
        # backstop).
        CheckConstraint(
            "visibility IN ('private','discoverable','public')",
            name="ck_community_clubs_visibility_known",
        ),
        # The list index — the active-clubs feed orders by
        # ``(created_at DESC, id DESC)`` and filters by visibility.
        Index(
            "ix_community_clubs_visibility_created",
            "visibility",
            "created_at",
            "id",
        ),
        # The owner-lookup index — used by the
        # ``leave_club`` ownership-transfer step.
        Index(
            "ix_community_clubs_owner",
            "owner_profile_id",
        ),
    )


# ---------------------------------------------------------------------------
# CommunityClubMember — one row per (club, profile) join.
# ---------------------------------------------------------------------------


class CommunityClubMember(Base):
    """A membership row for a single (club, profile) pair.

    One row per pair (the DB-level UNIQUE prevents duplicate joins).
    The ``role`` column is the wire-string form of the Kör 5
    ``ClubRole`` enum — ``owner`` / ``moderator`` / ``member``.

    Membership lifecycle (D5, D6): ``request_join`` adds a row with
    role ``member`` for ``discoverable`` / ``public`` clubs
    (immediate acceptance), or a pending request row for ``private``
    clubs. ``leave_club`` removes the row. ``transfer_ownership``
    flips the old owner's role to ``member`` and the new owner's
    role to ``owner`` (the A8 / D4 contract).
    """

    __tablename__ = "community_club_members"

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
    club_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_clubs.id", ondelete="CASCADE"),
        nullable=False,
    )
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(
        String(length=16),
        nullable=False,
        default=CLUB_ROLE_MEMBER,
        server_default=CLUB_ROLE_MEMBER,
    )
    joined_at: Mapped[datetime] = mapped_column(
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
            name="uq_community_club_members_public_id",
        ),
        # §A3 / D5 — duplicate-join enforcement at the DB layer.
        UniqueConstraint(
            "club_id",
            "profile_id",
            name="uq_community_club_members_pair",
        ),
        CheckConstraint(
            "role IN ('owner','moderator','member')",
            name="ck_community_club_members_role_known",
        ),
        # The member-list query orders by
        # ``(joined_at ASC, id ASC)`` per the Kör 11 / Kör 16 cursor
        # pattern.
        Index(
            "ix_community_club_members_club_joined",
            "club_id",
            "joined_at",
            "id",
        ),
        # The per-profile clubs-list index.
        Index(
            "ix_community_club_members_profile",
            "profile_id",
            "joined_at",
            "id",
        ),
    )


# ---------------------------------------------------------------------------
# CommunityClubInvite — one row per invite edge.
# ---------------------------------------------------------------------------


class CommunityClubInvite(Base):
    """An invite row for a single (club, inviter, invitee) triple.

    Mirrors the Kör 21 ``community_challenge_invites`` shape — wire-
    string ``status`` + server-authoritative ``expires_at`` +
    ``idempotency_key`` UNIQUE. The Kör 24 ``invite`` lifecycle is
    invite-only (no accept / decline / cancel — the Kör 24 service
    does not model invitee-side state transitions yet).
    """

    __tablename__ = "community_club_invites"

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
    club_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_clubs.id", ondelete="CASCADE"),
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
    # Wire-string status. Kör 24 only models ``pending`` and
    # ``accepted`` (the lifecycle is invite-only for this round);
    # ``cancelled`` / ``declined`` / ``expired`` are reserved for
    # future rounds.
    status: Mapped[str] = mapped_column(
        String(length=16),
        nullable=False,
        default="pending",
        server_default="pending",
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    # Idempotency surface — the Kör 21 pattern.
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
    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_club_invites_public_id",
        ),
        # §D4 / D5 — idempotency surface, the Kör 21 pattern.
        UniqueConstraint(
            "club_id",
            "inviter_profile_id",
            "invitee_profile_id",
            "idempotency_key",
            name="uq_community_club_invites_idempotency",
        ),
        # NOTE: no self-pair CHECK here. The Kör 24 ``request_join``
        # path for a ``private`` club creates a row where
        # ``inviter_profile_id == invitee_profile_id`` (the actor
        # requests to join their own club — see ADR 0420 D6). The
        # service layer rejects self-invites on the ``invite`` path
        # (the non-join-request call) by raising ``ValueError`` —
        # see ``club_service.invite``.
        CheckConstraint(
            "status IN ('pending','accepted','cancelled','declined','expired')",
            name="ck_community_club_invites_status_known",
        ),
        # Per-club pending-invites index.
        Index(
            "ix_community_club_invites_club_status",
            "club_id",
            "status",
            "created_at",
            "id",
        ),
        # Per-invitee inbox.
        Index(
            "ix_community_club_invites_invitee_status",
            "invitee_profile_id",
            "status",
            "created_at",
            "id",
        ),
        # The idempotency probe.
        Index(
            "ix_community_club_invites_idempotency_key",
            "club_id",
            "inviter_profile_id",
            "idempotency_key",
        ),
    )


__all__ = [
    "CLUB_ROLE_ALLOWLIST",
    "CLUB_ROLE_MEMBER",
    "CLUB_ROLE_MODERATOR",
    "CLUB_ROLE_OWNER",
    "CLUB_VISIBILITY_ALLOWLIST",
    "CLUB_VISIBILITY_DISCOVERABLE",
    "CLUB_VISIBILITY_PRIVATE",
    "CLUB_VISIBILITY_PUBLIC",
    "MAX_CLUB_MEMBERS",
    "MAX_CLUB_PENDING_INVITES",
    "CommunityClub",
    "CommunityClubInvite",
    "CommunityClubMember",
    "is_allowed_club_role",
    "is_allowed_club_visibility",
]
