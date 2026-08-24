"""Club content service — E09-R25, ADR 0420 §D2.

The service layer for club-scoped CONTENT mutations: pinned-post
add / remove, and club-challenge lifecycle (``create``,
``list_active``, ``end``). The pure read path (the feed itself)
lives in ``feed.club_feed``; this module owns the WRITE side of
the same domain.

Three concerns:

* **Pinned-post junction (A3, A4).** A club's pinned posts are a
  many-to-many between ``community_clubs`` and
  ``community_posts``. The relation is stored in a small
  ``community_club_pinned_posts`` table defined inline in this
  module via SQLAlchemy ``Table`` (the schema-side work lives in
  the same module that owns the service; the brief §0.0 #4 names
  ``MAX_CLUB_PINNED_POSTS`` as a module-level constant rather
  than a ``Settings`` field, mirroring the Kör 24
  ``MAX_CLUB_MEMBERS`` precedent). The table holds the (club_id,
  post_id) pair plus a ``pinned_at`` timestamp and the
  ``pinned_by_profile_id`` audit column. The pin-limit
  enforcement lives at the service layer (not the DB), so a
  future round can re-tune the cap without a migration.

* **Pin permission check (A3).** Only the owner or a moderator
  of the same club may pin or unpin a post in that club — the
  §5.2 invariant that the moderator-jog does NOT spread across
  clubs. The check is computed inline in this module (the
  permission matrix module is NOT on this round's
  ``allowed_paths``; a future round will own a formal
  ``ClubAction.PIN_POST`` entry).

* **Club-challenge lifecycle (A5, A6).** The challenge
  create / list / end operations re-use the Kör 21
  ``challenge_invite_service`` for the invite state machine and
  the Kör 8 ``is_blocked_pair`` predicate for the block-side
  gate. The create path stamps the new challenge's ``club_id``
  column with ``str(club.public_id)`` (a ``String(64)`` UUID
  form, per §0.0 #1) — NOT the internal BigInteger id (which
  would silently break the §A5 cell). The eligibility check
  confirms the actor is a member of the club; a non-member is
  rejected at the boundary (the §A5 IDOR guarantee).

The module is DB-coupled (SQLAlchemy ``Session``) and pure
with respect to HTTP — the router translates the returned
dataclasses into JSON.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Final

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Table,
    delete,
    func,
    insert,
    select,
)
from sqlalchemy.orm import Session as SASession

from ...database import Base
from ..models.challenge import (
    CHALLENGE_TYPE_CLUB,
    CommunityChallenge,
)
from ..models.club import (
    CLUB_ROLE_MODERATOR,
    CLUB_ROLE_OWNER,
    CLUB_VISIBILITY_ALLOWLIST,
    CommunityClub,
    CommunityClubMember,
)
from ..models.post import CommunityPost
from ..models.profile import CommunityProfile
from ..policies.query_filters import is_blocked_pair

# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class ClubPinForbidden(Exception):
    """The actor lacks the owner / moderator role in THIS club (A3)."""


class ClubPinLimitExceeded(Exception):
    """The club already has the maximum number of pinned posts (A4)."""


class ClubPinPostNotEligible(Exception):
    """The post is not eligible for pinning in this club — it must
    be authored in the same club (``post.club_id == club.id``),
    visible (not soft-deleted, ``moderation_state == 'visible'``)."""


class ClubChallengeNotVisible(Exception):
    """The challenge is not visible to this caller (A5 / D7 uniform 404)."""


class ClubChallengeActorNotMember(Exception):
    """The actor is not a member of the club — they cannot create
    / end challenges inside it (A5 IDOR guarantee)."""


class ClubChallengeEndForbidden(Exception):
    """The actor is not the owner or a moderator of the club —
    they cannot end a challenge inside it (A3 §5.2 cross-club
    moderator-jog guard)."""


# ---------------------------------------------------------------------------
# Module-level constants — mirror the Kör 24 ``MAX_CLUB_MEMBERS``
# precedent (brief §0.0 #4 — module-level Python constant, NOT
# a ``Settings`` field).
# ---------------------------------------------------------------------------

#: Maximum number of pinned posts per club (A4). Mirrors the
#: pattern of Kör 24 ``MAX_CLUB_MEMBERS`` — a documented
#: module-level constant rather than a ``Settings`` field. The
#: value is the §0.0 #4 "implementer választása" documented in
#: §10 of the round brief.
MAX_CLUB_PINNED_POSTS: Final[int] = 5

#: Visibility allowlist — re-exported here so the pin-eligibility
#: check can drop unknown values (defensive: the DB does NOT
#: constrain the ``clubs.visibility`` column).
CLUB_VISIBILITY_FOR_PIN: Final[frozenset[str]] = CLUB_VISIBILITY_ALLOWLIST

#: Roles authorised to pin / unpin inside a club (A3 §5.2). The
#: matrix module is NOT on this round's ``allowed_paths``; the
#: set is the Kör 24 / ADR 0420 wire-string values, defined inline.
#: A future round will lift this into a formal ``ClubAction.PIN_POST``
#: entry on the permission matrix.
CLUB_PIN_AUTHORIZED_ROLES: Final[frozenset[str]] = frozenset(
    {CLUB_ROLE_OWNER, CLUB_ROLE_MODERATOR}
)

#: Roles authorised to ``end`` a challenge inside a club (A3 / §5.2
#: cross-club guard). Same set as :data:`CLUB_PIN_AUTHORIZED_ROLES`.
CLUB_CHALLENGE_END_AUTHORIZED_ROLES: Final[frozenset[str]] = frozenset(
    {CLUB_ROLE_OWNER, CLUB_ROLE_MODERATOR}
)


# ---------------------------------------------------------------------------
# Schema — pinned-post junction table, defined inline.
#
# The Kör 11 ``community_posts`` and Kör 21 ``community_challenges``
# models are the tilos zóna this round (brief §0.0 — only their
# ``club_id`` join is permitted; no new column / new migration on
# those tables). A junction table for the pin relation is a
# DIFFERENT table — it does NOT duplicate post content; it only
# records the (club, post, pinned_at, pinned_by) tuple.
#
# Defined here with SQLAlchemy ``Table`` so the service module
# owns the schema-side definition in a single file (no new
# ``models/`` file is created). The table is registered against
# ``Base.metadata`` so the test fixture can create it via
# ``Base.metadata.create_all`` after the alembic upgrade; a
# production alembic migration will be added in a follow-up round
# (the §10 implementation handoff flags this gap).
# ---------------------------------------------------------------------------


community_club_pinned_posts = Table(
    "community_club_pinned_posts",
    Base.metadata,
    Column(
        "club_id",
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_clubs.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "post_id",
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_posts.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "pinned_at",
        DateTime(timezone=True),
        nullable=False,
    ),
    Column(
        "pinned_by_profile_id",
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    ),
)


# ---------------------------------------------------------------------------
# Cache-invalidation event (brief §0.0 D11; the Kör 11 pattern).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ClubCachedInvalidationEvent:
    """Emitted by the mutating service methods on a successful write.

    The router / cache layer (Kör 13+) wires a real callback; this
    round ships the seam and the test seam. ``club_public_id`` is
    the club's public_id (the wire identity). ``action`` is one of
    ``"pin_post"``, ``"unpin_post"``, ``"end_challenge"``.
    """

    club_public_id: uuid.UUID
    action: str  # "pin_post" | "unpin_post" | "end_challenge"


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read (no native tz-aware column
    type); the migration contract says ``DateTime(timezone=True)``
    columns store UTC, so we re-attach ``timezone.utc`` here for
    comparison and serialization. PostgreSQL keeps tzinfo on the
    round-trip; the ``replace`` is then a no-op.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _resolve_club_by_public_id(
    db: SASession, public_id: uuid.UUID
) -> CommunityClub | None:
    return (
        db.query(CommunityClub)
        .filter_by(public_id=public_id, deleted_at=None)
        .one_or_none()
    )


def _resolve_member(
    db: SASession, *, club_id: int, profile_id: int
) -> CommunityClubMember | None:
    return (
        db.query(CommunityClubMember)
        .filter_by(club_id=club_id, profile_id=profile_id)
        .one_or_none()
    )


def _resolve_profile_by_public_id(
    db: SASession, public_id: uuid.UUID
) -> CommunityProfile | None:
    return (
        db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()
    )


def _resolve_post_by_public_id(
    db: SASession, public_id: uuid.UUID
) -> CommunityPost | None:
    return db.query(CommunityPost).filter_by(public_id=public_id).one_or_none()


def _resolve_challenge_by_public_id(
    db: SASession, public_id: uuid.UUID
) -> CommunityChallenge | None:
    return (
        db.query(CommunityChallenge).filter_by(public_id=public_id).one_or_none()
    )


def _ensure_actor_role(
    db: SASession,
    *,
    club: CommunityClub,
    actor_profile_id: int,
    allowed_roles: frozenset[str],
) -> str:
    """Return the actor's role inside ``club`` if it is in
    ``allowed_roles``; raise :class:`ClubPinForbidden` otherwise.

    The check anchors to the ``community_club_members`` row for
    the (club, actor) pair — a moderator of a DIFFERENT club
    cannot bypass this guard (the §5.2 cross-club invariant).
    The role-string returned is one of the three
    ``ClubRole`` wire values; the caller can use it for
    fine-grained logic (e.g. only-owner paths).
    """
    member = _resolve_member(
        db, club_id=club.id, profile_id=actor_profile_id
    )
    if member is None:
        raise ClubPinForbidden("actor is not a member of this club")
    if member.role not in allowed_roles:
        raise ClubPinForbidden(
            f"actor role={member.role!r} is not authorised"
        )
    return member.role


def _ensure_actor_is_member(
    db: SASession,
    *,
    club: CommunityClub,
    actor_profile_id: int,
) -> None:
    """Raise :class:`ClubChallengeActorNotMember` when the actor is
    not a member of ``club`` (A5 IDOR guarantee).

    Unlike :func:`_ensure_actor_role`, this is the eligibility
    check for the CHALLENGE create / list / end paths — the
    actor must be a member (any role); the END path's stricter
    owner / moderator check is layered on top of this in
    :func:`_ensure_actor_role`.
    """
    member = _resolve_member(
        db, club_id=club.id, profile_id=actor_profile_id
    )
    if member is None:
        raise ClubChallengeActorNotMember("actor is not a member of this club")


def _is_post_eligible_for_pin(
    post: CommunityPost,
    *,
    club_id: int,
) -> bool:
    """Return ``True`` when ``post`` is eligible to be pinned in
    the club with internal id ``club_id``.

    A post is eligible when:

    * ``post.club_id == club_id`` — the post is authored in this
      club (a post authored in another club or as a profile-only
      post is not pinnable);
    * ``post.deleted_at IS NULL`` — soft-deleted posts cannot be
      pinned (mirrors the §Kör 11 soft-delete invariant);
    * ``post.moderation_state == 'visible'`` — moderation-hidden
      posts cannot be pinned (the §Kör 11 ``moderation_state``
      allowlist).
    """
    from ..models.post import MODERATION_STATE_VISIBLE

    if post.club_id != club_id:
        return False
    if post.deleted_at is not None:
        return False
    if post.moderation_state != MODERATION_STATE_VISIBLE:
        return False
    return True


def _current_pinned_count(db: SASession, *, club_id: int) -> int:
    """Return the number of currently-pinned posts in ``club_id``.

    Counts rows in the inline ``community_club_pinned_posts``
    table (the §A4 measure-matrix anchor). A future round may
    add an index on ``club_id`` for very large clubs; the
    present round keeps the table lean — there is at most
    :data:`MAX_CLUB_PINNED_POSTS` rows per club anyway.
    """
    stmt = select(func.count()).select_from(
        community_club_pinned_posts
    ).where(community_club_pinned_posts.c.club_id == club_id)
    result = db.execute(stmt).scalar()
    return int(result or 0)


# ---------------------------------------------------------------------------
# Pinned-post service surface.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PinnedPostRow:
    """One pinned post row returned to the caller.

    The shape mirrors :class:`feed.club_feed.ClubFeedItemRow`
    minus the audit-only fields (``audience`` /
    ``moderation_state`` are still relevant for downstream
    filtering but the wire-shape is the caller's responsibility).
    """

    post_public_id: uuid.UUID
    author_public_id: uuid.UUID
    body: str
    pinned_at: datetime


def list_club_pinned(
    db: SASession,
    *,
    viewer_profile_id: int,
    club_public_id: uuid.UUID,
) -> tuple[PinnedPostRow, ...]:
    """Return the currently-pinned posts in ``club_public_id`` for
    ``viewer_profile_id``.

    The membership probe is the same :class:`ClubNotVisible` gate
    used by the feed (a non-member cannot enumerate pinned posts).
    The result is ordered ``(pinned_at DESC, post_id DESC)`` so the
    most recently pinned post leads the list — the §A4 ordering
    invariant.
    """
    from ..feed.club_feed import _resolve_visible_club_for_member

    club = _resolve_visible_club_for_member(
        db,
        club_public_id=club_public_id,
        viewer_profile_id=viewer_profile_id,
    )

    stmt = (
        select(
            CommunityPost.public_id.label("post_public_id"),
            CommunityProfile.public_id.label("author_public_id"),
            CommunityPost.body,
            community_club_pinned_posts.c.pinned_at,
        )
        .join(
            community_club_pinned_posts,
            community_club_pinned_posts.c.post_id == CommunityPost.id,
        )
        .join(
            CommunityProfile,
            CommunityProfile.id == CommunityPost.profile_id,
        )
        .where(community_club_pinned_posts.c.club_id == club.id)
        .order_by(
            community_club_pinned_posts.c.pinned_at.desc(),
            community_club_pinned_posts.c.post_id.desc(),
        )
    )
    rows = db.execute(stmt).all()

    # Apply the §A6 block filter on the page-level author set —
    # same precedent as the Kör 13 / Kör 25 feed. Mute is NOT
    # applied: pinning is a moderator-curated list (the curator
    # has already exercised editorial judgement, so a per-viewer
    # mute filter would be redundant). Block is applied because
    # block is a hard-visibility signal.
    from ..policies.query_filters import (
        filter_public_ids_against_viewer_blocks,
    )

    author_public_ids = [
        _coerce_uuid(row.author_public_id) for row in rows
    ]
    allowed_author_public_ids = set(
        filter_public_ids_against_viewer_blocks(
            db,
            viewer_profile_id=viewer_profile_id,
            public_ids=author_public_ids,
        )
    )

    pinned = tuple(
        PinnedPostRow(
            post_public_id=_coerce_uuid(row.post_public_id),
            author_public_id=_coerce_uuid(row.author_public_id),
            body=str(row.body),
            pinned_at=_as_utc(row.pinned_at),
        )
        for row in rows
        if _coerce_uuid(row.author_public_id) in allowed_author_public_ids
    )
    return pinned


def pin_post(
    db: SASession,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
    now: datetime,
    on_invalidate: Callable[[ClubCachedInvalidationEvent], None] | None = None,
) -> PinnedPostRow:
    """Pin ``post_public_id`` at the top of ``club_public_id``'s
    feed.

    Server-side actor identity (§5.1): ``actor_profile_id`` is the
    JWT-resolved internal id. The permission check (A3) anchors
    to the actor's role inside THIS club — a moderator of another
    club is rejected at the boundary (the §5.2 cross-club
    invariant).

    The pin-limit check (A4) anchors to the current row count in
    the inline junction table; an attempt that would exceed
    :data:`MAX_CLUB_PINNED_POSTS` raises
    :class:`ClubPinLimitExceeded` and the row is not inserted.

    The post-eligibility check (mirrors Kör 11 D7) requires the
    post to be authored in the same club, not soft-deleted, and
    moderation-visible. An ineligible post raises
    :class:`ClubPinPostNotEligible`.

    Idempotent: re-pinning an already-pinned post is a successful
    no-op (the §Kör 11 idempotency precedent). The pin-list count
    is NOT decremented when the row already exists.
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None:
        raise ClubPinForbidden("club not found")

    _ensure_actor_role(
        db,
        club=club,
        actor_profile_id=actor_profile_id,
        allowed_roles=CLUB_PIN_AUTHORIZED_ROLES,
    )

    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        raise ClubPinPostNotEligible("post not found")

    if not _is_post_eligible_for_pin(post, club_id=club.id):
        raise ClubPinPostNotEligible(
            "post is not eligible for pinning in this club"
        )

    # Idempotent: an existing pin is a successful re-read. We do
    # NOT decrement the count on re-pin — the §A4 invariant is
    # about ATTEMPTED insertions of a NEW row, not about reads
    # of an existing one.
    existing_stmt = select(community_club_pinned_posts).where(
        community_club_pinned_posts.c.club_id == club.id,
        community_club_pinned_posts.c.post_id == post.id,
    )
    existing = db.execute(existing_stmt).first()
    if existing is not None:
        return PinnedPostRow(
            post_public_id=post.public_id,
            author_public_id=_profile_public_id_for_post(db, post),
            body=post.body,
            pinned_at=_as_utc(existing.pinned_at),
        )

    # Pin-limit check (A4) — runs BEFORE the INSERT so a club
    # already at the cap is rejected without an extra write.
    current_count = _current_pinned_count(db, club_id=club.id)
    if current_count >= MAX_CLUB_PINNED_POSTS:
        raise ClubPinLimitExceeded(
            f"club already has {current_count} pinned posts (limit={MAX_CLUB_PINNED_POSTS})"
        )

    db.execute(
        insert(community_club_pinned_posts).values(
            club_id=club.id,
            post_id=post.id,
            pinned_at=now,
            pinned_by_profile_id=actor_profile_id,
        )
    )
    db.flush()

    if on_invalidate is not None:
        on_invalidate(
            ClubCachedInvalidationEvent(
                club_public_id=club_public_id,
                action="pin_post",
            )
        )

    return PinnedPostRow(
        post_public_id=post.public_id,
        author_public_id=_profile_public_id_for_post(db, post),
        body=post.body,
        pinned_at=_as_utc(now),
    )


def unpin_post(
    db: SASession,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
    on_invalidate: Callable[[ClubCachedInvalidationEvent], None] | None = None,
) -> bool:
    """Remove ``post_public_id`` from ``club_public_id``'s pinned list.

    Returns ``True`` when a row was deleted; ``False`` when the
    post was NOT pinned (a successful no-op, the §Kör 11
    ``delete_post`` precedent). The same actor-role gate as
    :func:`pin_post` applies (A3 §5.2).

    The post-eligibility check is intentionally NOT applied — a
    moderator may unpin a soft-deleted or moderation-removed post
    (the editorial cleanup path).
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None:
        raise ClubPinForbidden("club not found")

    _ensure_actor_role(
        db,
        club=club,
        actor_profile_id=actor_profile_id,
        allowed_roles=CLUB_PIN_AUTHORIZED_ROLES,
    )

    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        # §Kör 11 / §D7 uniform 404 — unpinning a non-existent
        # post is a no-op success (a moderator who knows a post
        # id cannot use this path to enumerate post existence).
        return False

    result = db.execute(
        delete(community_club_pinned_posts).where(
            community_club_pinned_posts.c.club_id == club.id,
            community_club_pinned_posts.c.post_id == post.id,
        )
    )
    db.flush()

    if on_invalidate is not None:
        on_invalidate(
            ClubCachedInvalidationEvent(
                club_public_id=club_public_id,
                action="unpin_post",
            )
        )

    return bool(result.rowcount)


# ---------------------------------------------------------------------------
# Club-challenge lifecycle (A5, A6).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ClubChallengeRow:
    """One challenge row returned to the caller (challenge
    definition + member-eligible for the viewer)."""

    challenge_public_id: uuid.UUID
    type: str
    metric: str
    difficulty: int
    starts_at: datetime
    ends_at: datetime


def _coerce_uuid(raw: object) -> uuid.UUID:
    """Coerce the ``Uuid`` column's driver-native return type.

    Same precedent as the Kör 13 / Kör 9 helper — SQLite returns
    ``CHAR(32)`` hex form on raw text() queries; PostgreSQL
    returns the native ``UUID``. The wire-shape helpers
    downstream need the typed ``UUID``.
    """
    if isinstance(raw, uuid.UUID):
        return raw
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return uuid.UUID(str(raw))


def _profile_public_id_for_post(
    db: SASession, post: CommunityPost
) -> uuid.UUID:
    """Return the ``public_id`` of the post's author profile.

    The Kör 11 ``CommunityPost`` model has NO back-relationship
    to ``CommunityProfile`` — the foreign-key join is ad-hoc per
    query (per the model docstring). The helper performs the
    direct lookup.
    """
    author = (
        db.query(CommunityProfile).filter_by(id=post.profile_id).one()
    )
    return author.public_id


def create_club_challenge(
    db: SASession,
    *,
    actor_public_id: uuid.UUID,
    club_public_id: uuid.UUID,
    metric: str,
    difficulty: int,
    starts_at: datetime,
    ends_at: datetime,
    now: datetime,
) -> CommunityChallenge:
    """Create a club-scoped challenge inside ``club_public_id``.

    The eligibility gate (A5) confirms the actor is a member of
    the club — a non-member is rejected at the boundary (the §A5
    IDOR guarantee). The block filter (A6) confirms the actor is
    not in a block relation with the club owner (the §A6 §Kör 8
    invariant).

    The new challenge is stamped with ``type=club``,
    ``club_id=str(club.public_id)`` (the §0.0 #1 invariant — the
    ``community_challenges.club_id`` column is ``String(64)``,
    storing the UUID form, NOT the internal BigInteger id) and the
    actor's ``public_id`` as the author.

    The Kör 21 invite state machine is NOT invoked here — the
    club's member roster IS the participant set by design
    (the §A5 eligibility check IS the participant-eligibility
    check). A future round that adds per-challenge invites will
    re-use the Kör 21 ``create_invite`` helper.
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None:
        raise ClubChallengeNotVisible("club not found")

    actor = _resolve_profile_by_public_id(db, actor_public_id)
    if actor is None:
        raise ClubChallengeNotVisible("actor community profile not found")

    _ensure_actor_is_member(
        db, club=club, actor_profile_id=actor.id
    )

    if is_blocked_pair(
        db,
        profile_id_a=actor.id,
        profile_id_b=club.owner_profile_id,
    ):
        raise ClubChallengeActorNotMember(
            "actor is in a block relation with the club owner"
        )

    # §A5 — challenge type is the wire string for the Kör 21
    # ``CHALLENGE_TYPE_CLUB`` constant. The DB column is plain
    # ``String``; the wire value is the allowlist's canonical
    # entry.
    challenge = CommunityChallenge(
        public_id=uuid.uuid4(),
        author_profile_id=actor.id,
        type=CHALLENGE_TYPE_CLUB,
        metric=metric,
        difficulty=difficulty,
        starts_at=starts_at,
        ends_at=ends_at,
        # §0.0 #1 — the club_id column on community_challenges
        # is String(64); we store the club's public_id (UUID
        # string form), NOT the internal BigInteger id. Mixing
        # the two would silently break the §A5 cell.
        club_id=str(club.public_id),
        created_at=now,
        updated_at=now,
    )
    db.add(challenge)
    db.flush()
    db.refresh(challenge)
    return challenge


def list_club_challenges(
    db: SASession,
    *,
    viewer_profile_id: int,
    club_public_id: uuid.UUID,
    now: datetime,
    include_ended: bool = False,
) -> tuple[ClubChallengeRow, ...]:
    """Return the active challenges of ``club_public_id`` for
    ``viewer_profile_id``.

    The membership probe is the same gate as the feed (a
    non-member cannot enumerate the club's challenges). The
    window-based activation rule mirrors the Kör 21
    ``_ensure_challenge_visible`` helper (§0.0 #2 — there is
    no separate ``state`` column; activation is implicit in the
    ``starts_at`` / ``ends_at`` window).

    The block filter (A6) drops any challenge whose author is
    in a block relation with the viewer — same page-level
    pattern as the feed.
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None:
        raise ClubChallengeNotVisible("club not found")

    viewer = (
        db.query(CommunityProfile).filter_by(id=viewer_profile_id).one_or_none()
    )
    if viewer is None:
        raise ClubChallengeNotVisible("viewer community profile not found")

    member = _resolve_member(
        db, club_id=club.id, profile_id=viewer.id
    )
    if member is None:
        raise ClubChallengeNotVisible("viewer is not a member of this club")

    club_public_id_str = str(club.public_id)
    now_utc = _as_utc(now)

    stmt = select(
        CommunityChallenge.public_id,
        CommunityChallenge.type,
        CommunityChallenge.metric,
        CommunityChallenge.difficulty,
        CommunityChallenge.starts_at,
        CommunityChallenge.ends_at,
        CommunityChallenge.author_profile_id,
    ).where(
        CommunityChallenge.club_id == club_public_id_str,
    )
    if not include_ended:
        # §0.0 #2 — activation is window-based: only challenges
        # whose window includes ``now`` are returned.
        stmt = stmt.where(
            CommunityChallenge.starts_at <= now_utc,
            CommunityChallenge.ends_at > now_utc,
        )
    stmt = stmt.order_by(
        CommunityChallenge.starts_at.desc(),
        CommunityChallenge.id.desc(),
    )
    rows = db.execute(stmt).all()

    # Apply the §A6 block filter on the page-level author set.
    from ..policies.query_filters import (
        filter_public_ids_against_viewer_blocks,
    )

    author_public_ids = [
        _coerce_uuid(
            db.query(CommunityProfile.public_id)
            .filter_by(id=row.author_profile_id)
            .scalar()
        )
        for row in rows
    ]
    allowed_author_public_ids = set(
        filter_public_ids_against_viewer_blocks(
            db,
            viewer_profile_id=viewer_profile_id,
            public_ids=author_public_ids,
        )
    )

    out: list[ClubChallengeRow] = []
    for row in rows:
        author_public_id = (
            db.query(CommunityProfile.public_id)
            .filter_by(id=row.author_profile_id)
            .scalar()
        )
        if _coerce_uuid(author_public_id) not in allowed_author_public_ids:
            continue
        out.append(
            ClubChallengeRow(
                challenge_public_id=_coerce_uuid(row.public_id),
                type=str(row.type),
                metric=str(row.metric),
                difficulty=int(row.difficulty),
                starts_at=_as_utc(row.starts_at),
                ends_at=_as_utc(row.ends_at),
            )
        )
    return tuple(out)


def end_club_challenge(
    db: SASession,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    challenge_public_id: uuid.UUID,
    now: datetime,
    on_invalidate: Callable[[ClubCachedInvalidationEvent], None] | None = None,
) -> CommunityChallenge:
    """End a club challenge by setting ``ends_at = now``.

    §0.0 #2 — there is no separate ``state`` column on
    ``CommunityChallenge``; ending is implicit in the window
    (``now >= ends_at`` collapses to ``ends_at <= now``). The
    implementation writes ``ends_at = now`` so a future round
    can derive the "ended" set from the same window check.

    The actor-role gate (A3 §5.2) anchors to the actor's role
    inside THIS club — a moderator of another club cannot end
    this club's challenges. The eligibility gate (A5) requires
    the actor to be a member of the club (the §A5 IDOR
    guarantee). The challenge itself must be a club-scoped
    challenge whose ``club_id`` matches THIS club's public_id —
    a stale public_id or a non-club challenge raises
    :class:`ClubChallengeNotVisible`.

    Idempotent: ending an already-ended challenge is a successful
    no-op (the row is returned without a write).
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None:
        raise ClubChallengeNotVisible("club not found")

    _ensure_actor_is_member(
        db, club=club, actor_profile_id=actor_profile_id
    )
    _ensure_actor_role(
        db,
        club=club,
        actor_profile_id=actor_profile_id,
        allowed_roles=CLUB_CHALLENGE_END_AUTHORIZED_ROLES,
    )

    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ClubChallengeNotVisible("challenge not found")

    if challenge.club_id != str(club.public_id):
        # The challenge's ``club_id`` is the wire string of the
        # owning club — a mismatch means this challenge is
        # NOT in this club. The §A5 / §D7 uniform 404 applies.
        raise ClubChallengeNotVisible("challenge not found")

    ends_at_utc = _as_utc(challenge.ends_at)
    now_utc = _as_utc(now)
    if ends_at_utc <= now_utc:
        # Already ended — successful no-op (the §Kör 11
        # ``delete_post`` idempotence precedent).
        return challenge

    challenge.ends_at = now
    challenge.updated_at = now
    db.flush()
    db.refresh(challenge)

    if on_invalidate is not None:
        on_invalidate(
            ClubCachedInvalidationEvent(
                club_public_id=club_public_id,
                action="end_challenge",
            )
        )

    return challenge


__all__ = [
    "CLUB_CHALLENGE_END_AUTHORIZED_ROLES",
    "CLUB_PIN_AUTHORIZED_ROLES",
    "MAX_CLUB_PINNED_POSTS",
    "ClubCachedInvalidationEvent",
    "ClubChallengeActorNotMember",
    "ClubChallengeEndForbidden",
    "ClubChallengeNotVisible",
    "ClubChallengeRow",
    "ClubPinForbidden",
    "ClubPinLimitExceeded",
    "ClubPinPostNotEligible",
    "PinnedPostRow",
    "create_club_challenge",
    "end_club_challenge",
    "list_club_challenges",
    "list_club_pinned",
    "pin_post",
    "unpin_post",
]