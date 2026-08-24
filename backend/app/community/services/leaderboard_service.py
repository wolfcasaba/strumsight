"""Community leaderboard service (E09-R23, ADR 0418).

The verified-only leaderboard projection — one read service, one
opt-in service, and one rank helper. The leaderboard is rebuilt
on every request (no materialized projection): the read service
queries the Kör 22 ``community_challenge_results`` table filtered
to ``verification_state='verified'``, sorted by the §D3 / §D4
tie-break keys, and walks the page via the §D4 cursor.

Design contract (the §5 / §0.0 invariants — these are the load-
bearing guarantees the router and the tests pin):

* **Verified-only projection (A1, §5.1).** The WHERE clause is
  ``verification_state = 'verified'`` — ``pending`` /
  ``unverified`` / ``rejected`` / ``review`` rows are NEVER in
  the leaderboard. The §6.1 valódi-sértés próba
  (brief §6.1, L254) drops the filter and asserts the A1 cell
  turns red.

* **Opt-in filter (A3, §5.3, D2).** Profiles WITHOUT a
  ``community_leaderboard_opt_ins`` row are excluded from the
  public leaderboard. There is no implicit-default "everyone is
  in" — a missing row means opt-out.

* **Tie-breaker (A2, §D4).** The sort key is
  ``(metric_value DESC, submitted_at ASC, id ASC)`` — the
  project-wide ``(created_at, id)`` cursor mirror, with
  ``metric_value DESC`` as the primary.

* **Friends-scope follow-graph filter (A4, §D4).** For
  ``type='friends'`` challenges, the projection is FURTHER
  filtered to participants the viewer has an active follow edge
  to (``community_follows.follower_profile_id = viewer``).
  ``club`` / ``dailyCommunity`` / ``periodicGlobal`` /
  ``personalBest`` types have no follow-graph filter (the
  challenge's own participant list is the source — the §D4
  precedent).

* **Cursor pagination (A5, §D4).** The opaque cursor encodes
  ``(metric_value, submitted_at, id)`` of the last row of the
  previous page. The next-page predicate is the lexicographic
  ``>`` over the same triple. The L109 measurement warns
  against single-row tie-break fixtures; the §A5 test asserts
  multi-page stability.

* **One source of truth — no materialized projection.** The D5
  path runs a query-time projection; the
  ``rebuild_leaderboard()`` helper is exported for the §A6 test
  (which mutates a verified row in-DB and asserts the next
  read reflects the new state) but production callers never
  invoke it.

* **Caller-supplied clock (``now: datetime``).** Same precedent
  as Kör 22 — the timestamp the service uses is the caller's,
  never ``datetime.now(timezone.utc)`` inline.

* **No commit.** The router layer owns the commit
  (``routers/leaderboards.py::_commit_via``); the service
  flushes only.

The service does NOT modify the Kör 22
``challenge_verification_service.py`` (tilos zóna). The
verified-receipt row is read-only here.
"""

from __future__ import annotations

import base64
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.challenge import (
    CHALLENGE_TYPE_FRIENDS,
    CommunityChallenge,
    CommunityChallengeParticipant,
)
from ..models.challenge_result import (
    CHALLENGE_RESULT_STATE_VERIFIED,
    CommunityChallengeResult,
)
from ..models.leaderboard import CommunityLeaderboardOptIn
from ..models.profile import CommunityProfile
from ..models.social_graph import CommunityFollow


# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class ChallengeNotFound(Exception):
    """The challenge is not visible to the caller (D7 uniform 404)."""


# ---------------------------------------------------------------------------
# Wire-string vocabulary — opt-in toggle, mirror of the Kör 4
# ``visibility`` wire-string pattern (ADR 0398 §1). A plain
# ``String`` allows future values (``opted_in``, ``opted_out``)
# without a migration; the row's PRESENCE is the actual
# authoritative signal (D2).
# ---------------------------------------------------------------------------

LEADERBOARD_OPT_IN_OPTED_IN: str = "opted_in"
LEADERBOARD_OPT_IN_OPTED_OUT: str = "opted_out"


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _resolve_challenge_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityChallenge | None:
    return db.query(CommunityChallenge).filter_by(public_id=public_id).one_or_none()


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


# ---------------------------------------------------------------------------
# Cursor pagination — opaque (metric_value, submitted_at, id) triple,
# base64-encoded JSON (the Kör 11 / Kör 21 / Kör 7 cursor pattern).
#
# The sort key is ``(metric_value DESC, submitted_at ASC, id ASC)``.
# A paginated walk advances forward in that order — the next-page
# predicate is the lexicographic ``>`` over the same triple:
#
#   metric_value < cursor.metric_value   OR
#   metric_value = cursor.metric_value
#     AND submitted_at > cursor.submitted_at   OR
#   metric_value = cursor.metric_value
#     AND submitted_at = cursor.submitted_at
#     AND id > cursor.id
#
# SQLAlchemy's ``tuple_(...) < tuple_(...)`` / ``>```` are
# dialect-portable (PostgreSQL row-value compare; SQLite emulates
# it via the ``(a < b) OR (a = b AND c < d)`` rewrite).
# ---------------------------------------------------------------------------


def _encode_leaderboard_cursor(
    *, metric_value: int, submitted_at: datetime, row_id: int
) -> str:
    payload = {
        "metric_value": metric_value,
        "submitted_at": submitted_at.isoformat(),
        "id": row_id,
    }
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_leaderboard_cursor(
    cursor: str,
) -> tuple[int, datetime, int] | None:
    """Return ``(metric_value, submitted_at, id)`` or ``None`` on a
    malformed cursor. The malformed case is the caller's signal to
    start over from the top (the Kör 21 / Kör 11 pattern).
    """
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        metric_value = int(payload["metric_value"])
        submitted_at = datetime.fromisoformat(payload["submitted_at"])
        row_id = int(payload["id"])
        return metric_value, submitted_at, row_id
    except (ValueError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------------------
# Public dataclasses — the router layer wraps these in Pydantic
# response models.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class LeaderboardEntry:
    """A single row of the verified-only leaderboard.

    The internal ``id`` is NEVER serialized (the §6.1 leak-guard).
    The ``rank`` is the dense rank assigned AT READ TIME — it is
    the row's position in the projection (1-based, gaps when an
    excluded profile would have sat in between).

    ``display_name`` is ``None`` for a profile that has not set
    one yet (the Kör 4 onboarding path is nullable). The Flutter
    screen falls back to ``@handle`` in that case.

    ``verified_badge`` is a constant ``True`` — every row in the
    projection is verified by construction (A1). The field exists
    so the wire shape is forward-compatible with a future round
    that distinguishes "verified" from "moderator-pinned".
    """

    public_id: uuid.UUID
    rank: int
    display_name: str | None
    handle: str | None
    metric_value: int
    submitted_at: datetime
    verified_badge: bool = True


@dataclass(frozen=True)
class LeaderboardPage:
    """A single page of leaderboard entries.

    ``next_cursor`` is opaque to the caller; the Flutter
    repository sends it back verbatim in the next request.
    ``None`` means "no more pages".
    """

    entries: tuple[LeaderboardEntry, ...]
    next_cursor: str | None


# ---------------------------------------------------------------------------
# Base-query builder — kept private; the read service composes it
# for both the page and the own-rank helper.
# ---------------------------------------------------------------------------


def _build_base_query(
    *,
    challenge_id: int,
    viewer_profile_internal_id: int,
    friends_scope: bool,
) -> Any:
    """Build the verified-only leaderboard query.

    Joins ``community_challenge_results → community_challenge_
    participants → community_profiles`` and applies:

    * §A1 / §5.1 — ``verification_state = 'verified'``
    * §A3 / §D2 — ``EXISTS community_leaderboard_opt_ins``
      (the opt-in check; rows without an opt-in are excluded)
    * §A4 / §D4 — for ``type='friends'``, the follow-graph
      filter (``follower = viewer``)
    * the ``challenge_id`` predicate (per-challenge leaderboard)
    """
    opt_in_exists = (
        select(CommunityLeaderboardOptIn.id)
        .where(CommunityLeaderboardOptIn.profile_id == CommunityProfile.id)
        .exists()
    )

    stmt = (
        select(
            CommunityProfile.public_id,
            CommunityProfile.display_name,
            CommunityProfile.handle,
            CommunityChallengeResult.metric_value,
            CommunityChallengeResult.submitted_at,
            CommunityChallengeResult.id,
            CommunityChallengeResult.participant_id,
        )
        .join(
            CommunityChallengeParticipant,
            CommunityChallengeParticipant.id
            == CommunityChallengeResult.participant_id,
        )
        .join(
            CommunityProfile,
            CommunityProfile.id
            == CommunityChallengeParticipant.participant_profile_id,
        )
        .where(
            CommunityChallengeResult.verification_state
            == CHALLENGE_RESULT_STATE_VERIFIED,
            opt_in_exists,
            CommunityChallengeParticipant.challenge_id == challenge_id,
        )
    )

    if friends_scope:
        friends_exists = (
            select(CommunityFollow.id)
            .where(
                and_(
                    CommunityFollow.follower_profile_id
                    == viewer_profile_internal_id,
                    CommunityFollow.followed_profile_id == CommunityProfile.id,
                )
            )
            .exists()
        )
        stmt = stmt.where(friends_exists)

    return stmt


def _next_page_predicate(
    *, metric_value: int, submitted_at: datetime, row_id: int
):
    """Build the next-page WHERE clause for a cursor at
    ``(metric_value, submitted_at, row_id)``.

    Returns the lexicographic-``>`` predicate — the row must be
    STRICTLY after the cursor in the (DESC, ASC, ASC) order.
    """
    return or_(
        CommunityChallengeResult.metric_value < metric_value,
        and_(
            CommunityChallengeResult.metric_value == metric_value,
            CommunityChallengeResult.submitted_at > submitted_at,
        ),
        and_(
            CommunityChallengeResult.metric_value == metric_value,
            CommunityChallengeResult.submitted_at == submitted_at,
            CommunityChallengeResult.id > row_id,
        ),
    )


def _strictly_precedes_predicate(
    *, metric_value: int, submitted_at: datetime, row_id: int
):
    """Build the "strictly precedes" predicate — for rank
    computation. The row must be STRICTLY before
    ``(metric_value, submitted_at, row_id)`` in the (DESC, ASC,
    ASC) order.
    """
    return or_(
        CommunityChallengeResult.metric_value > metric_value,
        and_(
            CommunityChallengeResult.metric_value == metric_value,
            CommunityChallengeResult.submitted_at < submitted_at,
        ),
        and_(
            CommunityChallengeResult.metric_value == metric_value,
            CommunityChallengeResult.submitted_at == submitted_at,
            CommunityChallengeResult.id < row_id,
        ),
    )


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def get_leaderboard_page(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> LeaderboardPage:
    """Return one page of the leaderboard for ``challenge_public_id``.

    The challenge's ``type`` field (§D4) decides whether the
    follow-graph filter applies: ``friends`` ⇒ yes; every other
    type ⇒ no. The viewer must NOT be filtered by opt-in — a
    viewer can read the leaderboard WITHOUT being opted-in
    themselves (the §A3 invariant is "I am NOT shown in public
    scope"; it is NOT "I cannot read the board").

    A malformed cursor starts the read from the top — the Kör 21
    / Kör 11 convention.

    Raises :class:`ChallengeNotFound` when the challenge / viewer
    profile is missing — the router layer translates to 404 (D7).
    """
    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ChallengeNotFound("challenge not found")
    viewer_profile = _resolve_profile_by_public_id(db, viewer_profile_public_id)
    if viewer_profile is None:
        raise ChallengeNotFound("viewer has no community profile")

    friends_scope = challenge.type == CHALLENGE_TYPE_FRIENDS
    stmt = _build_base_query(
        challenge_id=challenge.id,
        viewer_profile_internal_id=viewer_profile.id,
        friends_scope=friends_scope,
    )
    # §D3 / §D4 sort key — leaderboard order.
    stmt = stmt.order_by(
        CommunityChallengeResult.metric_value.desc(),
        CommunityChallengeResult.submitted_at.asc(),
        CommunityChallengeResult.id.asc(),
    )
    # One extra to detect "more".
    stmt = stmt.limit(limit + 1)

    if cursor is not None:
        decoded = _decode_leaderboard_cursor(cursor)
        if decoded is not None:
            cur_metric, cur_submitted, cur_id = decoded
            stmt = stmt.where(
                _next_page_predicate(
                    metric_value=cur_metric,
                    submitted_at=cur_submitted,
                    row_id=cur_id,
                )
            )

    rows = db.execute(stmt).all()
    has_more = len(rows) > limit
    rows = rows[:limit]

    # The absolute rank of the first row on this page — the
    # cumulative count of rows STRICTLY PRECEDING it in the same
    # projection.
    rank_offset = 0
    if cursor is not None and rows:
        decoded = _decode_leaderboard_cursor(cursor)
        if decoded is not None:
            cur_metric, cur_submitted, cur_id = decoded
            count_stmt = _build_base_query(
                challenge_id=challenge.id,
                viewer_profile_internal_id=viewer_profile.id,
                friends_scope=friends_scope,
            ).where(
                _strictly_precedes_predicate(
                    metric_value=cur_metric,
                    submitted_at=cur_submitted,
                    row_id=cur_id,
                )
            )
            rank_offset = db.execute(
                select(func.count()).select_from(count_stmt.subquery())
            ).scalar_one()

    entries: list[LeaderboardEntry] = []
    for index, row in enumerate(rows):
        public_id_value, display_name_value, handle_value, metric_value, submitted_at, row_id, _participant_id = row
        entries.append(
            LeaderboardEntry(
                public_id=public_id_value,
                rank=rank_offset + index + 1,
                display_name=display_name_value,
                handle=handle_value,
                metric_value=metric_value,
                submitted_at=submitted_at,
            )
        )

    next_cursor: str | None = None
    if has_more and rows:
        last = rows[-1]
        _public_id, _display_name, _handle, metric_value, submitted_at, row_id, _participant_id = last
        next_cursor = _encode_leaderboard_cursor(
            metric_value=metric_value,
            submitted_at=submitted_at,
            row_id=row_id,
        )

    return LeaderboardPage(entries=tuple(entries), next_cursor=next_cursor)


def get_own_rank(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_public_id: uuid.UUID,
) -> LeaderboardEntry | None:
    """Return the viewer's own leaderboard entry, or ``None`` if
    the viewer is not in the projection.

    The viewer is excluded from their own rank when EITHER:

    * they have not opted in (§A3), OR
    * they have no verified result for this challenge.

    A viewer who opted in but has a pending / rejected result
    still gets ``None`` — the projection is verified-only (A1).
    The Flutter-bekötés is a future round (ADR 0418 D6 / Kontextus
    6.); the service returns the wire shape now.
    """
    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ChallengeNotFound("challenge not found")
    viewer_profile = _resolve_profile_by_public_id(db, viewer_profile_public_id)
    if viewer_profile is None:
        raise ChallengeNotFound("viewer has no community profile")

    friends_scope = challenge.type == CHALLENGE_TYPE_FRIENDS
    stmt = _build_base_query(
        challenge_id=challenge.id,
        viewer_profile_internal_id=viewer_profile.id,
        friends_scope=friends_scope,
    ).where(CommunityProfile.public_id == viewer_profile_public_id)

    row = db.execute(stmt.limit(1)).first()
    if row is None:
        return None
    public_id_value, display_name_value, handle_value, metric_value, submitted_at, row_id, _participant_id = row

    # Absolute rank — count rows STRICTLY PRECEDING this row.
    rank_count_stmt = _build_base_query(
        challenge_id=challenge.id,
        viewer_profile_internal_id=viewer_profile.id,
        friends_scope=friends_scope,
    ).where(
        _strictly_precedes_predicate(
            metric_value=metric_value,
            submitted_at=submitted_at,
            row_id=row_id,
        )
    )
    rank = db.execute(
        select(func.count()).select_from(rank_count_stmt.subquery())
    ).scalar_one() + 1

    return LeaderboardEntry(
        public_id=public_id_value,
        rank=rank,
        display_name=display_name_value,
        handle=handle_value,
        metric_value=metric_value,
        submitted_at=submitted_at,
    )


def set_opt_in(
    db: Session,
    *,
    profile_id: int,
    opted_in: bool,
    now: datetime,
) -> str:
    """Toggle the caller's leaderboard opt-in.

    Returns the wire-string state (``"opted_in"`` /
    ``"opted_out"``) that lands in the response. The PRESENCE of
    a row in ``community_leaderboard_opt_ins`` is the actual
    authoritative signal (D2) — the returned wire-string is just
    the echo for the client.

    Idempotent: a second call with the same ``opted_in`` returns
    the same wire-string WITHOUT raising.
    """
    existing = (
        db.query(CommunityLeaderboardOptIn)
        .filter_by(profile_id=profile_id)
        .one_or_none()
    )

    if opted_in:
        if existing is not None:
            return LEADERBOARD_OPT_IN_OPTED_IN
        row = CommunityLeaderboardOptIn(
            profile_id=profile_id,
            opted_in_at=now,
        )
        db.add(row)
        try:
            db.flush()
        except IntegrityError:
            # A concurrent writer won the race — re-read and
            # return idempotently (the §D2 one-row-per-profile
            # UNIQUE caught it).
            db.rollback()
            again = (
                db.query(CommunityLeaderboardOptIn)
                .filter_by(profile_id=profile_id)
                .one_or_none()
            )
            if again is not None:
                return LEADERBOARD_OPT_IN_OPTED_IN
            raise
        return LEADERBOARD_OPT_IN_OPTED_IN

    if existing is None:
        return LEADERBOARD_OPT_IN_OPTED_OUT
    db.delete(existing)
    db.flush()
    return LEADERBOARD_OPT_IN_OPTED_OUT


def rebuild_leaderboard(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
) -> int:
    """No-op rebuild helper for the §A6 disqualification test.

    The leaderboard is query-time (no materialized projection),
    so a "rebuild" is a no-op in production. The function exists
    so the §A6 test can call something that triggers a re-read
    AFTER it mutates a verified result row directly in the DB
    (the §D5 test-szintű DB-mutáció). Returns the number of
    verified rows that the projection WOULD return — the §A6
    test asserts the count changes deterministically after the
    mutation.
    """
    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ChallengeNotFound("challenge not found")
    count_stmt = (
        select(func.count(CommunityChallengeResult.id))
        .join(
            CommunityChallengeParticipant,
            CommunityChallengeParticipant.id
            == CommunityChallengeResult.participant_id,
        )
        .where(
            CommunityChallengeResult.verification_state
            == CHALLENGE_RESULT_STATE_VERIFIED,
            CommunityChallengeParticipant.challenge_id == challenge.id,
        )
    )
    return db.execute(count_stmt).scalar_one()


__all__ = [
    "ChallengeNotFound",
    "LEADERBOARD_OPT_IN_OPTED_IN",
    "LEADERBOARD_OPT_IN_OPTED_OUT",
    "LeaderboardEntry",
    "LeaderboardPage",
    "get_leaderboard_page",
    "get_own_rank",
    "rebuild_leaderboard",
    "set_opt_in",
]