"""Challenge READ queries — the server side of the Flutter
``listChallenges`` / ``fetchDefinition`` / ``fetchMyParticipation``
repository methods.

The Kör 21 / Kör 22 services own every WRITE on the challenge tables
(``challenge_invite_service`` — the invite state machine, and
``challenge_verification_service`` — the result decision chain). This
module is read-only: it never mutates a row, never commits, and only
composes the visibility rule the two write services already imply.

Visibility (the "public ones + the ones the caller participates in"
rule):

* ``dailyCommunity`` / ``periodicGlobal`` challenges are the public
  surface — every signed-in profile may read them;
* the caller's OWN challenges (``author_profile_id``) are always
  visible;
* a challenge the caller has a participant row on (accepted invite)
  is visible;
* a challenge the caller holds an invite for (any state — a declined
  invite still lets the caller read what they declined) is visible;
* a ``club`` challenge is visible to the members of that club
  (``community_challenges.club_id`` carries the club public id as a
  string — both the dashed and the 32-hex spelling are matched, the
  column is a reserved free-form ``String(64)``);
* the block-side gate (A6, the Kör 8 ``is_blocked_pair`` helper) drops
  every challenge whose author is in a block relationship with the
  viewer — the same row-level filter ``club_service.list_clubs``
  applies to the club owner.

Pagination is the project-wide ``(created_at DESC, id DESC)`` walk
with an opaque base64-JSON cursor (the Kör 23 leaderboard pattern). A
malformed cursor restarts from the top rather than 500-ing (the Kör 21
/ Kör 11 rule).
"""

from __future__ import annotations

import base64
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from ..models.challenge import (
    CHALLENGE_INVITE_STATE_ACTIVE,
    CHALLENGE_INVITE_STATE_COMPLETED,
    CHALLENGE_TYPE_CLUB,
    CHALLENGE_TYPE_DAILY_COMMUNITY,
    CHALLENGE_TYPE_PERIODIC_GLOBAL,
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from ..models.club import CommunityClub, CommunityClubMember
from ..models.profile import CommunityProfile
from ..policies.query_filters import is_blocked_pair

#: The challenge types every signed-in profile may read.
PUBLIC_CHALLENGE_TYPES: frozenset[str] = frozenset(
    {CHALLENGE_TYPE_DAILY_COMMUNITY, CHALLENGE_TYPE_PERIODIC_GLOBAL}
)


class ChallengeNotVisible(Exception):
    """The challenge does not exist OR the caller may not see it —
    a uniform 404 at the router (the D7 "no existence oracle" rule)."""


def _as_utc(value: datetime) -> datetime:
    """SQLite drops tzinfo on read — re-attach UTC for comparisons."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


# ---------------------------------------------------------------------------
# Cursor — base64 JSON over ``(created_at, id)``.
# ---------------------------------------------------------------------------


def encode_challenge_cursor(*, created_at: datetime, row_id: int) -> str:
    payload = {"created_at": _as_utc(created_at).isoformat(), "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def decode_challenge_cursor(cursor: str) -> tuple[datetime, int] | None:
    """``(created_at, id)`` or ``None`` on a malformed token."""
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        created_at = datetime.fromisoformat(payload["created_at"])
        row_id = int(payload["id"])
        return created_at, row_id
    except (ValueError, KeyError, TypeError, json.JSONDecodeError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------------------
# Public dataclasses — the router wraps these in Pydantic.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ChallengeView:
    public_id: uuid.UUID
    author_public_id: uuid.UUID
    type: str
    metric: str
    difficulty: int
    starts_at: datetime
    ends_at: datetime
    version: int
    club_id: str | None
    participant_count: int
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class ChallengePageView:
    items: tuple[ChallengeView, ...]
    next_cursor: str | None


@dataclass(frozen=True)
class ParticipationView:
    participant_public_id: uuid.UUID
    challenge_public_id: uuid.UUID
    invite_state: str
    best_metric_value: int | None
    joined_at: datetime | None
    invite_public_id: uuid.UUID | None


# ---------------------------------------------------------------------------
# Visibility predicate.
# ---------------------------------------------------------------------------


def _viewer_club_id_spellings(db: Session, *, viewer_profile_id: int) -> list[str]:
    """Every string spelling of the viewer's club public ids that a
    ``community_challenges.club_id`` value could carry."""
    rows = db.execute(
        select(CommunityClub.public_id)
        .join(CommunityClubMember, CommunityClubMember.club_id == CommunityClub.id)
        .where(
            CommunityClubMember.profile_id == viewer_profile_id,
            CommunityClub.deleted_at.is_(None),
        )
    ).all()
    spellings: list[str] = []
    for (public_id,) in rows:
        value = (
            public_id if isinstance(public_id, uuid.UUID) else uuid.UUID(str(public_id))
        )
        spellings.append(str(value))
        spellings.append(value.hex)
    return spellings


def _visibility_predicate(db: Session, *, viewer_profile_id: int):
    participant_subq = select(CommunityChallengeParticipant.challenge_id).where(
        CommunityChallengeParticipant.participant_profile_id == viewer_profile_id
    )
    invite_subq = select(CommunityChallengeInvite.challenge_id).where(
        CommunityChallengeInvite.invitee_profile_id == viewer_profile_id
    )
    clauses = [
        CommunityChallenge.type.in_(sorted(PUBLIC_CHALLENGE_TYPES)),
        CommunityChallenge.author_profile_id == viewer_profile_id,
        CommunityChallenge.id.in_(participant_subq),
        CommunityChallenge.id.in_(invite_subq),
    ]
    club_spellings = _viewer_club_id_spellings(db, viewer_profile_id=viewer_profile_id)
    if club_spellings:
        clauses.append(
            and_(
                CommunityChallenge.type == CHALLENGE_TYPE_CLUB,
                CommunityChallenge.club_id.in_(club_spellings),
            )
        )
    return or_(*clauses)


def _window_predicate(window: str | None, *, now: datetime):
    if window == "active":
        return and_(
            CommunityChallenge.starts_at <= now, CommunityChallenge.ends_at > now
        )
    if window == "upcoming":
        return CommunityChallenge.starts_at > now
    if window == "ended":
        return CommunityChallenge.ends_at <= now
    return None


def _participant_counts(db: Session, challenge_ids: list[int]) -> dict[int, int]:
    if not challenge_ids:
        return {}
    rows = db.execute(
        select(
            CommunityChallengeParticipant.challenge_id,
            func.count(CommunityChallengeParticipant.id),
        )
        .where(CommunityChallengeParticipant.challenge_id.in_(challenge_ids))
        .group_by(CommunityChallengeParticipant.challenge_id)
    ).all()
    return {row[0]: int(row[1]) for row in rows}


def _author_public_ids(db: Session, author_ids: list[int]) -> dict[int, uuid.UUID]:
    if not author_ids:
        return {}
    rows = db.execute(
        select(CommunityProfile.id, CommunityProfile.public_id).where(
            CommunityProfile.id.in_(author_ids)
        )
    ).all()
    return {row[0]: row[1] for row in rows}


def _to_view(
    challenge: CommunityChallenge,
    *,
    author_public_id: uuid.UUID,
    participant_count: int,
) -> ChallengeView:
    return ChallengeView(
        public_id=challenge.public_id,
        author_public_id=author_public_id,
        type=challenge.type,
        metric=challenge.metric,
        difficulty=challenge.difficulty,
        starts_at=_as_utc(challenge.starts_at),
        ends_at=_as_utc(challenge.ends_at),
        version=challenge.version,
        club_id=challenge.club_id,
        participant_count=participant_count,
        created_at=_as_utc(challenge.created_at),
        updated_at=_as_utc(challenge.updated_at),
    )


# ---------------------------------------------------------------------------
# Service surface.
# ---------------------------------------------------------------------------


def list_visible_challenges(
    db: Session,
    *,
    viewer_profile_id: int,
    limit: int,
    cursor: str | None,
    now: datetime,
    window: str | None = None,
    club_id: str | None = None,
    challenge_type: str | None = None,
) -> ChallengePageView:
    """One cursor page of the challenges the viewer may see.

    ``limit + 1`` rows are fetched so ``next_cursor`` is emitted only
    when a further page exists. The block-side gate runs in Python on
    the fetched slice (author ↔ viewer pairs, deduplicated); the cursor
    always advances over the RAW slice so a page of blocked authors
    can never stall the walk.
    """
    stmt = (
        select(CommunityChallenge)
        .where(_visibility_predicate(db, viewer_profile_id=viewer_profile_id))
        .order_by(CommunityChallenge.created_at.desc(), CommunityChallenge.id.desc())
        .limit(limit + 1)
    )
    window_clause = _window_predicate(window, now=now)
    if window_clause is not None:
        stmt = stmt.where(window_clause)
    if club_id:
        stmt = stmt.where(CommunityChallenge.club_id == club_id)
    if challenge_type:
        stmt = stmt.where(CommunityChallenge.type == challenge_type)
    if cursor is not None:
        decoded = decode_challenge_cursor(cursor)
        if decoded is not None:
            c_created_at, c_id = decoded
            stmt = stmt.where(
                or_(
                    CommunityChallenge.created_at < c_created_at,
                    and_(
                        CommunityChallenge.created_at == c_created_at,
                        CommunityChallenge.id < c_id,
                    ),
                )
            )

    rows = list(db.execute(stmt).scalars().all())
    has_more = len(rows) > limit
    page_rows = rows[:limit]

    next_cursor: str | None = None
    if has_more and page_rows:
        last = page_rows[-1]
        next_cursor = encode_challenge_cursor(
            created_at=last.created_at, row_id=last.id
        )

    author_ids = sorted({row.author_profile_id for row in page_rows})
    blocked_authors = {
        pid
        for pid in author_ids
        if pid != viewer_profile_id
        and is_blocked_pair(db, profile_id_a=viewer_profile_id, profile_id_b=pid)
    }
    visible_rows = [
        row for row in page_rows if row.author_profile_id not in blocked_authors
    ]

    counts = _participant_counts(db, [row.id for row in visible_rows])
    authors = _author_public_ids(db, [row.author_profile_id for row in visible_rows])
    items = tuple(
        _to_view(
            row,
            author_public_id=authors[row.author_profile_id],
            participant_count=counts.get(row.id, 0),
        )
        for row in visible_rows
        if row.author_profile_id in authors
    )
    return ChallengePageView(items=items, next_cursor=next_cursor)


def _resolve_visible_challenge(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> CommunityChallenge:
    challenge = db.execute(
        select(CommunityChallenge).where(
            CommunityChallenge.public_id == challenge_public_id,
            _visibility_predicate(db, viewer_profile_id=viewer_profile_id),
        )
    ).scalar_one_or_none()
    if challenge is None:
        raise ChallengeNotVisible("challenge not found")
    if challenge.author_profile_id != viewer_profile_id and is_blocked_pair(
        db,
        profile_id_a=viewer_profile_id,
        profile_id_b=challenge.author_profile_id,
    ):
        raise ChallengeNotVisible("challenge not found")
    return challenge


def get_visible_challenge(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> ChallengeView:
    """One challenge definition, visibility-gated (uniform 404)."""
    challenge = _resolve_visible_challenge(
        db,
        challenge_public_id=challenge_public_id,
        viewer_profile_id=viewer_profile_id,
    )
    authors = _author_public_ids(db, [challenge.author_profile_id])
    counts = _participant_counts(db, [challenge.id])
    return _to_view(
        challenge,
        author_public_id=authors[challenge.author_profile_id],
        participant_count=counts.get(challenge.id, 0),
    )


def get_my_participation(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_id: int,
    now: datetime,
) -> ParticipationView | None:
    """The caller's own participation summary, or ``None`` when the
    caller has neither a participant row nor an invite.

    Raises :class:`ChallengeNotVisible` when the challenge itself is
    not readable by the caller (uniform 404) — a ``None`` answer is a
    200 with ``participant: null`` on a challenge they CAN read.
    """
    challenge = _resolve_visible_challenge(
        db,
        challenge_public_id=challenge_public_id,
        viewer_profile_id=viewer_profile_id,
    )
    viewer_public_id = db.execute(
        select(CommunityProfile.public_id).where(
            CommunityProfile.id == viewer_profile_id
        )
    ).scalar_one()

    participant = db.execute(
        select(CommunityChallengeParticipant).where(
            CommunityChallengeParticipant.challenge_id == challenge.id,
            CommunityChallengeParticipant.participant_profile_id == viewer_profile_id,
        )
    ).scalar_one_or_none()

    # The most recent invite addressed to the caller, if any.
    invite = db.execute(
        select(CommunityChallengeInvite)
        .where(
            CommunityChallengeInvite.challenge_id == challenge.id,
            CommunityChallengeInvite.invitee_profile_id == viewer_profile_id,
        )
        .order_by(
            CommunityChallengeInvite.updated_at.desc(),
            CommunityChallengeInvite.id.desc(),
        )
        .limit(1)
    ).scalar_one_or_none()

    if participant is not None:
        state = (
            CHALLENGE_INVITE_STATE_ACTIVE
            if _as_utc(challenge.ends_at) > _as_utc(now)
            else CHALLENGE_INVITE_STATE_COMPLETED
        )
        return ParticipationView(
            participant_public_id=viewer_public_id,
            challenge_public_id=challenge.public_id,
            invite_state=state,
            best_metric_value=participant.best_metric_value,
            joined_at=_as_utc(participant.joined_at),
            invite_public_id=invite.public_id if invite is not None else None,
        )
    if invite is not None:
        return ParticipationView(
            participant_public_id=viewer_public_id,
            challenge_public_id=challenge.public_id,
            invite_state=invite.state,
            best_metric_value=None,
            joined_at=None,
            invite_public_id=invite.public_id,
        )
    return None


__all__ = [
    "PUBLIC_CHALLENGE_TYPES",
    "ChallengeNotVisible",
    "ChallengePageView",
    "ChallengeView",
    "ParticipationView",
    "decode_challenge_cursor",
    "encode_challenge_cursor",
    "get_my_participation",
    "get_visible_challenge",
    "list_visible_challenges",
]
