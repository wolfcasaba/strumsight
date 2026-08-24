"""Community challenge invite router — E09-R21, ADR 0415; E09-R22,
ADR 0417.

The HTTP surface for the challenge invite lifecycle AND the
verified-result submission:

* ``POST   /community/challenges/{challenge_public_id}/invites`` —
  create (or recycle) an invite. Server-side inviter (the JWT
  subject). Idempotent on ``idempotency_key`` (§5.3, D4).
  Block-side gate (A3, D3) and rate-limit gate (A4 / §5.3)
  run BEFORE the INSERT.
* ``POST   /community/challenges/invites/{invite_public_id}/accept`` —
  accept a pending invite (invitee-only). The conditional
  UPDATE guards the state graph (D5).
* ``POST   /community/challenges/invites/{invite_public_id}/decline`` —
  decline a pending invite (invitee-only). Same conditional
  UPDATE shape.
* ``DELETE /community/challenges/invites/{invite_public_id}`` —
  cancel an outgoing invite (inviter-only). Same conditional
  UPDATE shape — the D5 race-test cell.
* ``POST   /community/challenges/{challenge_public_id}/results`` —
  submit (or replay) a verified result (E09-R22). Server-side
  decision — the client never carries a ``verified`` / ``rank``
  field. The §6 acceptance-criterion surface (ADR 0417 D7).

There is NO "challenge definition creation" endpoint in this
round (the §0.0 D6 scope-shrink / ADR 0415 §D6): the router
only exposes the invite-lifecycle endpoints and the result
endpoint. The ``community_challenges`` rows are seeded by the
test fixtures or by a future round's admin surface; the
service is still the single chokepoint for all writes.

All authenticated endpoints take ``idempotency_key`` either in
the JSON body (POST endpoints) or as a query parameter
(DELETE endpoints — the Kör 7 ``api_client.dart``'s ``delete()``
does not carry a JSON body, ADR 0401 §1 / §3). The body-side
``inviter_id`` / ``invitee_id`` / ``invite_id`` / ``verified`` /
``rank`` / ``verification_state`` fields are NOT carried by the
Pydantic schemas (``extra='forbid'`` rejects any smuggled value
— the §A2 belt-and-braces invariant).

The router is mounted by the test fixtures directly into a
self-contained ``FastAPI()`` — the production
``build_community_router`` factory stays untouched (the Kör 7–20
pattern; the §3 tilos-zóna discipline).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from typing import Protocol

from fastapi import APIRouter, HTTPException, Query, Request, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..policies.integrity_policy import (
    METRIC_VALUE_MAX,
    METRIC_VALUE_MIN,
)
from ..services.challenge_invite_service import (
    BlockedChallengeRelationship,
    ChallengeInviteNotFound,
    ChallengeInviteRateLimited,
    ChallengeNotFound,
    InvalidChallengeInviteTransition,
    accept_invite,
    cancel_invite,
    create_invite,
    decline_invite,
)
from ..services.challenge_verification_service import (
    ChallengeInviteNotFound as _ResultChallengeInviteNotFound,
)
from ..services.challenge_verification_service import (
    ChallengeNotFound as _ResultChallengeNotFound,
)
from ..services.challenge_verification_service import (
    ChallengeParticipantNotFound as _ChallengeParticipantNotFound,
)
from ..services.challenge_verification_service import (
    submit_result,
)

router = APIRouter(prefix="/community/challenges", tags=["community-challenges"])


# ---------------------------------------------------------------------------
# Session / commit seams — same pattern as the Kör 7–20 routers.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


class _SupportsCommits(Protocol):
    """The HTTP endpoints commit through ``request.app.state`` so the
    test seam can override commit semantics without touching the
    service layer."""

    def __call__(self, db: Session) -> None: ...


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "challenges_commit", _default_commit)
    fn(db)


def _resolve_caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Resolve the caller's community profile public_id from their
    ``users.id`` (the JWT subject).

    Mirrors the Kör 7 ``_caller_profile_public_id`` pattern. The
    router endpoints that take a target profile id (the create
    invite path) read the caller's public_id from this helper;
    the endpoints that take an invite id (accept / decline /
    cancel) read the invitee's / inviter's identity off the
    invite row.
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


def _resolve_profile_public_id_by_internal_id(
    db: Session, internal_id: int
) -> uuid.UUID:
    """Translate an internal ``community_profiles.id`` (PK) to its
    public_id (the wire surface)."""
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE id = :pid"),
        {"pid": internal_id},
    ).first()
    if row is None:
        raise ValueError("profile not found")
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


# ---------------------------------------------------------------------------
# Pydantic schemas — ``extra='forbid'`` rejects any smuggled
# ``inviter_id`` / ``invitee_id`` / ``invite_id`` field (§5.1).
# ---------------------------------------------------------------------------


class CreateChallengeInviteRequest(BaseModel):
    """Body shape for ``POST /community/challenges/{id}/invites``.

    Only the ``invitee_public_id`` and the ``idempotency_key``
    travel on the wire — the ``inviter_public_id`` is the
    JWT subject (server-resolved), never a body field. The
    optional ``expires_in_seconds`` lets the client cap the
    invite window; the default is 14 days (the same horizon
    the Kör 7 follow-request cooldown uses).
    """

    model_config = ConfigDict(extra="forbid")

    invitee_public_id: uuid.UUID
    idempotency_key: str | None = None
    expires_in_seconds: int | None = None


class ChallengeInviteActionRequest(BaseModel):
    """Body shape for ``POST .../accept`` and ``POST .../decline``.

    The endpoints are idempotent on the invite's CURRENT
    state — a retry of an already-accepted invite returns
    200 (the row is already in the target state). The
    ``idempotency_key`` is optional; the natural-key
    identity (the ``invite_public_id`` in the URL) is the
    canonical idempotency surface for these transitions.
    """

    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = None


class ChallengeInviteOut(BaseModel):
    """Wire shape for a single invite row.

    The internal ``id`` is NEVER serialised (the §6.1
    leak-guard). The ``responded_at`` is NULL on a fresh
    ``draft`` / ``sent`` row.
    """

    public_id: uuid.UUID
    challenge_public_id: uuid.UUID
    inviter_public_id: uuid.UUID
    invitee_public_id: uuid.UUID
    state: str
    expires_at: datetime
    created_at: datetime
    updated_at: datetime
    responded_at: datetime | None = None


def _invite_to_out_from_session(db: Session, invite) -> ChallengeInviteOut:
    """Map a ``CommunityChallengeInvite`` ORM row + session to its
    wire shape, resolving the FK public_ids through the
    request-scoped session.

    Mirrors ``_row_to_out`` in ``routers/posts.py`` — every
    public_id on the wire is resolved through a session
    query, never carried on the ORM relationship.
    """
    challenge_pub = _resolve_challenge_public_id_from_session(db, invite)
    inviter_pub = _resolve_profile_public_id_by_internal_id(
        db, invite.inviter_profile_id
    )
    invitee_pub = _resolve_profile_public_id_by_internal_id(
        db, invite.invitee_profile_id
    )
    return ChallengeInviteOut(
        public_id=invite.public_id,
        challenge_public_id=challenge_pub,
        inviter_public_id=inviter_pub,
        invitee_public_id=invitee_pub,
        state=invite.state,
        expires_at=invite.expires_at,
        created_at=invite.created_at,
        updated_at=invite.updated_at,
        responded_at=invite.responded_at,
    )


def _resolve_challenge_public_id_from_session(db: Session, invite) -> uuid.UUID:
    """Resolve the challenge public_id from the request session."""
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_challenges WHERE id = :id"),
        {"id": invite.challenge_id},
    ).first()
    if row is None:
        raise ValueError("invite references a non-existent challenge")
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


# ---------------------------------------------------------------------------
# Default invite-window helper — the 14-day horizon matches the
# Kör 7 follow-request cooldown.
# ---------------------------------------------------------------------------

_DEFAULT_INVITE_WINDOW_DAYS = 14
_MAX_INVITE_WINDOW_DAYS = 90


def _resolve_expires_at(
    *,
    now: datetime,
    expires_in_seconds: int | None,
) -> datetime:
    """Translate the body-side ``expires_in_seconds`` to an
    absolute UTC timestamp.

    The default window is 14 days (the Kör 7 follow-request
    cooldown); the maximum is 90 days — a longer window is
    rejected at the router with 422.
    """
    seconds = (
        expires_in_seconds
        if expires_in_seconds is not None
        else _DEFAULT_INVITE_WINDOW_DAYS * 24 * 60 * 60
    )
    if seconds <= 0:
        raise HTTPException(
            status_code=422,
            detail="expires_in_seconds must be positive",
        )
    if seconds > _MAX_INVITE_WINDOW_DAYS * 24 * 60 * 60:
        raise HTTPException(
            status_code=422,
            detail=(
                f"expires_in_seconds exceeds the {_MAX_INVITE_WINDOW_DAYS}-day "
                "maximum invite window"
            ),
        )
    return now + timedelta(seconds=seconds)


def _now() -> datetime:
    """Server-time helper — mirrors ``routers/posts.datetime_now``.

    Kept as a function (not a module-level constant) so a test
    seam can override ``app.state.clock`` the same way
    ``routers/privacy.py`` does.
    """
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# POST /community/challenges/{challenge_public_id}/invites
# ---------------------------------------------------------------------------


@router.post(
    "/{challenge_public_id}/invites",
    status_code=status.HTTP_201_CREATED,
)
def post_create_invite(
    challenge_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: CreateChallengeInviteRequest,
) -> ChallengeInviteOut:
    """Create (or recycle) a challenge invite.

    The inviter is the JWT subject (D1 server-side identity);
    the invitee and the idempotency key travel on the wire.
    The block-side gate (A3, D3) and the rate-limit gate
    (A4 / §5.3) run BEFORE the INSERT.

    Body shape::

        {
          "invitee_public_id": "<uuid>",
          "idempotency_key": "<string>",
          "expires_in_seconds": <int>   // optional, default 14 days
        }

    The response carries the invite's wire shape (public_id,
    state, expires_at, …). A retry with the same
    ``idempotency_key`` returns the existing row (200) — the
    §A4 idempotency invariant.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                inviter_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            now = _now()
            try:
                expires_at = _resolve_expires_at(
                    now=now,
                    expires_in_seconds=payload.expires_in_seconds,
                )
            except HTTPException:
                db.rollback()
                raise
            try:
                invite = create_invite(
                    db,
                    inviter_public_id=inviter_public_id,
                    invitee_public_id=payload.invitee_public_id,
                    challenge_public_id=challenge_public_id,
                    expires_at=expires_at,
                    idempotency_key=payload.idempotency_key,
                    now=now,
                )
            except BlockedChallengeRelationship as exc:
                db.rollback()
                raise HTTPException(status_code=403, detail=str(exc)) from exc
            except ChallengeInviteRateLimited as exc:
                db.rollback()
                raise HTTPException(status_code=429, detail=str(exc)) from exc
            except ChallengeNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except ValueError as exc:
                db.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/challenges/invites/{invite_public_id}/accept
# ---------------------------------------------------------------------------


@router.post(
    "/invites/{invite_public_id}/accept",
    status_code=status.HTTP_200_OK,
)
def post_accept_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ChallengeInviteActionRequest | None = None,
) -> ChallengeInviteOut:
    """Accept a pending invite (invitee-only).

    Body shape is optional (the natural-key identity is the
    invite_public_id in the URL). The conditional UPDATE
    guards the state graph (D5) — a terminal-state invite
    raises :class:`InvalidChallengeInviteTransition` and the
    router returns 409.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                invitee_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                invite = accept_invite(
                    db,
                    invitee_public_id=invitee_public_id,
                    invite_public_id=invite_public_id,
                    now=_now(),
                )
            except ChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except BlockedChallengeRelationship as exc:
                db.rollback()
                raise HTTPException(status_code=403, detail=str(exc)) from exc
            except InvalidChallengeInviteTransition as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "invalid_invite_transition",
                        "current_state": exc.current_state,
                    },
                ) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/challenges/invites/{invite_public_id}/decline
# ---------------------------------------------------------------------------


@router.post(
    "/invites/{invite_public_id}/decline",
    status_code=status.HTTP_200_OK,
)
def post_decline_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ChallengeInviteActionRequest | None = None,
) -> ChallengeInviteOut:
    """Decline a pending invite (invitee-only)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                invitee_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                invite = decline_invite(
                    db,
                    invitee_public_id=invitee_public_id,
                    invite_public_id=invite_public_id,
                    now=_now(),
                )
            except ChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except InvalidChallengeInviteTransition as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "invalid_invite_transition",
                        "current_state": exc.current_state,
                    },
                ) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/challenges/invites/{invite_public_id}   (cancel)
# ---------------------------------------------------------------------------


@router.delete(
    "/invites/{invite_public_id}",
    status_code=status.HTTP_200_OK,
)
def delete_cancel_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> ChallengeInviteOut:
    """Cancel an outgoing invite (inviter-only).

    The idempotency key rides the URL on DELETE — the
    Kör 7 ``api_client.dart`` ``delete()`` transport carries
    no JSON body (ADR 0401 §1).

    The D5 race-test cell (concurrent accept + cancel from
    two devices) lands here: the conditional UPDATE accepts
    only ``draft`` / ``sent`` source states, so when the
    accept branch wins, the cancel branch sees ``rowcount ==
    0`` and the router returns 409. The test asserts that
    exactly one branch succeeds and the other raises
    deterministically.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                inviter_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                invite = cancel_invite(
                    db,
                    inviter_public_id=inviter_public_id,
                    invite_public_id=invite_public_id,
                    now=_now(),
                )
            except ChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except InvalidChallengeInviteTransition as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "invalid_invite_transition",
                        "current_state": exc.current_state,
                    },
                ) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# E09-R22 — verified-result submission (ADR 0417 D7).
#
# Inline Pydantic request / response models — same shape as the
# Kör 21 invite router (the §0.0 D6 Kör 21 consistency rule).
# ``extra='forbid'`` is the FIRST line of defense against
# client-issued ``verified`` / ``rank`` fields (§A2 §5.1); the
# service-level ``assert_no_client_issued_trust_state`` is the
# SECOND (the §6.1 belt-and-braces probe).
# ---------------------------------------------------------------------------


class SubmitChallengeResultRequest(BaseModel):
    """Body shape for ``POST /community/challenges/{id}/results``.

    Only the ``metric_value`` / ``source_event_id`` /
    ``idempotency_key`` travel on the wire — the
    ``verification_state`` / ``verified`` / ``rank`` /
    ``decision_at`` fields are server-computed (D1, §5.1). The
    ``extra='forbid'`` rejects any smuggled trust state.
    """

    model_config = ConfigDict(extra="forbid")

    # Wire-level bound (F1 MAJOR fix — E09-R22 review). The
    # Pydantic ``Field`` rejects values outside the domain
    # ``[METRIC_VALUE_MIN, METRIC_VALUE_MAX]`` BEFORE the
    # decision chain runs, so the service's INSERT never
    # receives an unrepresentable value (e.g. ``10**19``,
    # which SQLite would round-trip as ``OverflowError``
    # rather than ``IntegrityError``). This keeps the §A8
    # audit invariant: even absurdly large payloads are
    # caught by a deterministic wire-level rejection
    # instead of bubbling up as an HTTP 500.
    metric_value: int = Field(
        ge=METRIC_VALUE_MIN,
        le=METRIC_VALUE_MAX,
    )
    source_event_id: str = Field(min_length=1, max_length=128)
    idempotency_key: str | None = Field(default=None, max_length=128)
    # The version the client submitted (the Kör 5 wire entity
    # carries ``version`` — the A5 measure-matrix asserts the
    # service rejects when the client's version differs from
    # the server's). A null/missing field defaults to the
    # server-fetched version on a fresh submission, but the
    # server explicitly rejects mismatches when the field is
    # supplied (the §A5 path).
    submitted_version: int | None = Field(default=None)


class ChallengeResultOut(BaseModel):
    """Wire shape for a single ``CommunityChallengeResult`` row.

    The internal ``id`` is NEVER serialised (the §6.1 leak-
    guard). The ``verification_state`` is the server's
    authoritative decision; the ``reason_code`` is the
    §A8 audit trail (a terminal-state row's structured reason).
    """

    public_id: uuid.UUID
    challenge_public_id: uuid.UUID
    participant_public_id: uuid.UUID
    source_event_id: str
    idempotency_key: str | None
    metric_value: int
    verification_state: str
    reason_code: str | None
    nonce_expires_at: datetime
    submitted_at: datetime
    decided_at: datetime | None


def _resolve_participant_public_id_from_session(db: Session, result_row) -> uuid.UUID:
    """Resolve the actor's community profile public_id from the
    request session, walking ``result → participant → profile``.

    The ``result_row`` is a :class:`CommunityChallengeResult` ORM
    row; its ``participant_id`` is the FK to
    :class:`CommunityChallengeParticipant`, whose
    ``participant_profile_id`` is the FK to
    :class:`CommunityProfile` (whose ``public_id`` is the
    wire-public actor identity).
    """
    from sqlalchemy import text as _sa_text

    profile_row = db.execute(
        _sa_text(
            "SELECT profile.public_id "
            "FROM community_challenge_results r "
            "JOIN community_challenge_participants cp "
            "ON cp.id = r.participant_id "
            "JOIN community_profiles profile "
            "ON profile.id = cp.participant_profile_id "
            "WHERE r.id = :rid"
        ),
        {"rid": result_row.id},
    ).first()
    if profile_row is None:
        raise ValueError("result references a non-existent participant profile")
    raw = profile_row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


def _result_to_out_from_session(db: Session, result_row) -> ChallengeResultOut:
    """Map a ``CommunityChallengeResult`` ORM row + session to its
    wire shape, resolving the FK public_ids through the
    request-scoped session.

    Mirrors ``_invite_to_out_from_session``.
    """
    from sqlalchemy import text as _sa_text

    challenge_pub_row = db.execute(
        _sa_text("SELECT public_id FROM community_challenges WHERE id = :id"),
        {"id": _resolve_challenge_internal_id_from_result(db, result_row)},
    ).first()
    if challenge_pub_row is None:
        raise ValueError("result references a non-existent challenge")
    challenge_pub_raw = challenge_pub_row[0]
    challenge_pub = (
        uuid.UUID(hex=challenge_pub_raw)
        if isinstance(challenge_pub_raw, str)
        else challenge_pub_raw
    )

    participant_pub = _resolve_participant_public_id_from_session(db, result_row)
    return ChallengeResultOut(
        public_id=result_row.public_id,
        challenge_public_id=challenge_pub,
        participant_public_id=participant_pub,
        source_event_id=result_row.source_event_id,
        idempotency_key=result_row.idempotency_key,
        metric_value=result_row.metric_value,
        verification_state=result_row.verification_state,
        reason_code=result_row.reason_code,
        nonce_expires_at=result_row.nonce_expires_at,
        submitted_at=result_row.submitted_at,
        decided_at=result_row.decided_at,
    )


def _resolve_challenge_internal_id_from_result(db: Session, result_row) -> int:
    """Translate ``result_row`` → ``community_challenges.id`` via the
    participant row."""
    from sqlalchemy import text as _sa_text

    challenge_id_row = db.execute(
        _sa_text(
            "SELECT challenge_id FROM community_challenge_participants WHERE id = :pid"
        ),
        {"pid": result_row.participant_id},
    ).first()
    if challenge_id_row is None:
        raise ValueError("result references a non-existent participant row")
    return challenge_id_row[0]


# ---------------------------------------------------------------------------
# POST /community/challenges/{challenge_public_id}/results
# ---------------------------------------------------------------------------


@router.post(
    "/{challenge_public_id}/results",
    status_code=status.HTTP_200_OK,
)
async def post_submit_result(
    challenge_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: SubmitChallengeResultRequest,
) -> ChallengeResultOut:
    """Submit (or replay) a verified challenge result.

    Body shape::

        {
          "metric_value": <int, 0..1_000_000>,
          "source_event_id": "<string, 1..128>",
          "idempotency_key": "<string, 1..128>" or null,
          "submitted_version": <int> | null   // A5 measure-matrix
        }

    The response carries the result's wire shape (public_id,
    ``verification_state`` computed server-side, ``reason_code``
    structured audit). Replays of the same ``source_event_id``
    hit the §A1 idempotency surface — the row is returned as-is
    regardless of the new request.

    The endpoint NEVER accepts a client-issued ``verified`` /
    ``rank`` / ``verification_state`` field — the Pydantic
    ``extra='forbid'`` rejects it at the body level (§A2 first
    defense), the service-level
    :func:`assert_no_client_issued_trust_state` rejects it
    at the service level (§A2 second defense).

    F3 MINOR fix (E09-R22 review): the ``submitted_keys``
    forwarded to the service-level trust-state assertion are
    derived from the ACTUAL incoming body keys (read via
    ``request.json()`` BEFORE Pydantic strips extras), not a
    hardcoded set derived from the Pydantic schema. With
    ``extra='forbid'`` in production the two coincide; but
    the raw-body approach keeps the §A2 second line of
    defense load-bearing even if a future refactor relaxes
    the Pydantic config to ``extra='allow'`` — the
    service-level assertion would then correctly see the
    forged ``verified`` / ``rank`` keys.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                actor_public_id = _resolve_caller_profile_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc

            # The service needs the ACTOR PROFILE internal_id, not
            # the public_id — resolve it through the same session
            # so the lookup is request-bound. The column is
            # stored as 32-char hex (no dashes) in SQLite — the
            # helper above returns a ``uuid.UUID`` object whose
            # ``.hex`` matches the stored format.
            from sqlalchemy import text as _sa_text

            actor_row = db.execute(
                _sa_text("SELECT id FROM community_profiles WHERE public_id = :pid"),
                {"pid": actor_public_id.hex},
            ).first()
            if actor_row is None:
                raise HTTPException(
                    status_code=404, detail="caller has no community profile"
                )
            actor_profile_id = actor_row[0]

            # F3 — capture the ACTUAL incoming request-body keys
            # so the service-level trust-state assertion sees
            # what the client sent, not a curated subset.
            # Starlette caches the body after the first read, so
            # ``request.json()`` here reads the SAME bytes
            # Pydantic just validated. If a future refactor
            # changes ``extra='forbid'`` to ``extra='allow'`` /
            # ``'ignore'``, this set then correctly includes the
            # forged fields — keeping the §A2 second line of
            # defense load-bearing.
            try:
                raw_body = await request.json()
            except Exception:
                raw_body = {}
            if not isinstance(raw_body, dict):
                raw_body = {}
            submitted_keys: set[str] = set(raw_body.keys())
            try:
                result = submit_result(
                    db,
                    actor_profile_id=actor_profile_id,
                    challenge_public_id=challenge_public_id,
                    submitted_version=payload.submitted_version
                    if payload.submitted_version is not None
                    else 0,
                    source_event_id=payload.source_event_id,
                    metric_value=payload.metric_value,
                    idempotency_key=payload.idempotency_key,
                    submitted_payload_keys=submitted_keys,
                    now=_now(),
                )
            except _ResultChallengeNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except _ChallengeParticipantNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except _ResultChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _result_to_out_from_session(db, result)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "router",
]
