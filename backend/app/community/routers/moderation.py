"""Community moderation router — E09-R27, ADR 0425.

The first site-wide admin / moderator endpoint surface in the
backend. Every endpoint here requires the caller's
``users.id`` to appear in :class:`CommunityModerator` — a normal
JWT user with no moderator grant gets 403 (the A1 measure-matrix
cell).

Endpoints:

* ``GET    /community/moderation/cases`` — list open cases for
  the queue (priority-ordered).
* ``GET    /community/moderation/cases/{public_id}`` — fetch a
  single case plus its action history.
* ``POST   /community/moderation/cases/{public_id}/decisions`` —
  apply a moderator decision (the ONLY path to ``removed`` /
  ``author_only``).
* ``POST   /community/moderation/cases/{public_id}/appeals`` —
  submit an appeal against a case (any logged-in user).
* ``POST   /community/moderation/cases/{public_id}/appeals/resolve`` —
  resolve an appeal (moderator-only, verdict ``upheld`` /
  ``overturned``).

The router is mounted by the test fixtures directly into a
self-contained ``FastAPI()`` — the production
``build_community_router`` factory stays untouched per the §0.0
STOP-feltétel 1 (no ``backend/app/main.py`` changes this round).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..models.moderation import (
    MODERATION_CASE_STATES,
    CommunityModerationCase,
)
from ..moderation.case_service import (
    AppealAlreadySubmitted,
    AutomationCannotEnforce,
    InvalidAppealVerdict,
    InvalidStateTransition,
    ModerationActionSummary,
    ModerationCaseSummary,
    NoOpenAppeal,
    NotAModerator,
    apply_moderator_decision,
    get_case_by_public_id,
    is_moderator,
    list_case_actions,
    list_open_cases,
    record_automation_signal,
    resolve_appeal,
    submit_appeal,
)

router = APIRouter(prefix="/community/moderation", tags=["community-moderation"])


# ---------------------------------------------------------------------------
# Session factory seam — same pattern as routers/safety.py / reports.py.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "moderation_commit", _default_commit)
    fn(db)


# ---------------------------------------------------------------------------
# The §5.1 retaliation-risk invariant from ADR 0422 applies
# symmetrically here: the response shape MUST NOT include the
# reporter identity. The helper below enforces it.
# ---------------------------------------------------------------------------


def _case_summary(case: CommunityModerationCase) -> dict[str, object]:
    """Build the §6 A7 wire shape for a case row.

    The dataclass :class:`ModerationCaseSummary` is the type-safe
    envelope; this helper converts it to the JSON dict the router
    returns. The dataclass has NO ``reporter_profile_id`` field
    (the structural invariant) — a future maintainer who tries to
    add one will fail the A7 test.
    """
    summary = ModerationCaseSummary(
        case_public_id=case.public_id,
        target_type=case.target_type,
        target_id=case.target_id,
        state=case.state,
        appeal_state=case.appeal_state,
        priority_score=case.priority_score,
        is_open=case.is_open,
        opened_at=case.opened_at,
        updated_at=case.updated_at,
    )
    return {
        "case_public_id": str(summary.case_public_id),
        "target_type": summary.target_type,
        "target_id": summary.target_id,
        "state": summary.state,
        "appeal_state": summary.appeal_state,
        "priority_score": summary.priority_score,
        "is_open": summary.is_open,
        "opened_at": summary.opened_at.isoformat(),
        "updated_at": summary.updated_at.isoformat(),
    }


def _action_summary(action, case_public_id: uuid.UUID) -> dict[str, object]:
    """Build the §6 A7 wire shape for an action audit row.

    The ``actor_user_id`` field is the user who CARRIED OUT the
    moderation action (a moderator), NOT the reporter. The reporter
    identity (Kör 26 ``CommunityReport``) is never joined in here.

    ``case_public_id`` is passed in by the caller because
    :class:`CommunityModerationAction` deliberately has no
    ``relationship()`` back to the case row (no extra join — the
    audit row carries the case's ``id`` as a plain FK only).
    """
    summary = ModerationActionSummary(
        action_public_id=action.public_id,
        case_public_id=case_public_id,
        action_type=action.action_type,
        from_state=action.from_state,
        to_state=action.to_state,
        actor_type=action.actor_type,
        actor_user_id=action.actor_user_id,
        reason=action.reason,
        created_at=action.created_at,
    )
    return {
        "action_public_id": str(summary.action_public_id),
        "case_public_id": str(summary.case_public_id),
        "action_type": summary.action_type,
        "from_state": summary.from_state,
        "to_state": summary.to_state,
        "actor_type": summary.actor_type,
        "actor_user_id": summary.actor_user_id,
        "reason": summary.reason,
        "created_at": summary.created_at.isoformat(),
    }


# ---------------------------------------------------------------------------
# The §6 A1 helper — every endpoint requires the caller to be a
# moderator. Returns the user's internal ``id`` (the
# ``CommunityModerator`` table joins on ``users.id``).
# ---------------------------------------------------------------------------


def _require_moderator(db: Session, current_user) -> int:
    """Raise 403 when ``current_user.id`` is not in
    :class:`CommunityModerator`.

    The :class:`CurrentUser` is the standard ``User`` row the
    :func:`get_current_user` dependency yields. The A1
    measure-matrix cell exploits this — a JWT user with no
    moderator grant is rejected here, regardless of the endpoint.
    """
    if not is_moderator(db, current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="moderator role required",
        )
    return current_user.id


# ---------------------------------------------------------------------------
# GET /community/moderation/cases
# ---------------------------------------------------------------------------


@router.get(
    "/cases",
    status_code=status.HTTP_200_OK,
)
def get_cases(
    request: Request,
    current_user: CurrentUser,
) -> dict[str, object]:
    """Return the open-case queue (priority-ordered).

    The response is the §6 A7 sanitized envelope — the case rows
    carry ``target_*`` / ``state`` / ``appeal_state`` /
    ``priority_score``, NEVER any reporter identity.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        moderator_id = _require_moderator(db, current_user)
        _ = moderator_id  # silence unused — the check is the side-effect
        cases = list_open_cases(db)
        return {
            "cases": [_case_summary(case) for case in cases],
            "count": len(cases),
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/moderation/cases/{public_id}
# ---------------------------------------------------------------------------


@router.get(
    "/cases/{case_public_id}",
    status_code=status.HTTP_200_OK,
)
def get_case(
    case_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> dict[str, object]:
    """Return a single case plus its action history.

    The action rows carry the moderator's ``actor_user_id`` (the
    user who carried out the action), NOT any reporter identity.
    The ``CommunityReport`` rows the case was opened against are
    NEVER joined in.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        moderator_id = _require_moderator(db, current_user)
        _ = moderator_id
        case = get_case_by_public_id(db, case_public_id)
        if case is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"case {case_public_id} not found",
            )
        actions = list_case_actions(db, case)
        return {
            "case": _case_summary(case),
            "actions": [_action_summary(a, case.public_id) for a in actions],
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/moderation/cases/{public_id}/decisions
# ---------------------------------------------------------------------------


@router.post(
    "/cases/{case_public_id}/decisions",
    status_code=status.HTTP_200_OK,
)
def post_decision(
    case_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Apply a moderator decision — the ONLY path to
    ``removed`` / ``author_only``.

    Body shape::

        {"to_state": "<one of MODERATION_CASE_STATES>",
         "reason": "<non-empty string>"}

    The ``to_state`` is verified against the
    :data:`case_service.ALLOWED_TRANSITIONS` graph inside
    :func:`apply_moderator_decision`. Invalid transitions return
    422; non-moderator callers return 403.
    """
    to_state_raw = payload.get("to_state")
    if not isinstance(to_state_raw, str) or to_state_raw not in MODERATION_CASE_STATES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"to_state must be one of {sorted(MODERATION_CASE_STATES)}",
        )

    reason_raw = payload.get("reason")
    if not isinstance(reason_raw, str) or not reason_raw.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="reason required",
        )

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            moderator_user_id = _require_moderator(db, current_user)
            case = get_case_by_public_id(db, case_public_id)
            if case is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"case {case_public_id} not found",
                )
            from datetime import datetime, timezone

            now = datetime.now(timezone.utc)
            case = apply_moderator_decision(
                db,
                case,
                to_state=to_state_raw,
                moderator_user_id=moderator_user_id,
                reason=reason_raw,
                now=now,
            )
            _commit_via(request, db)
        except NotAModerator as exc:
            db.rollback()
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except InvalidStateTransition as exc:
            db.rollback()
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        return _case_summary(case)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/moderation/cases/{public_id}/appeals
# ---------------------------------------------------------------------------


@router.post(
    "/cases/{case_public_id}/appeals",
    status_code=status.HTTP_200_OK,
)
def post_appeal(
    case_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Submit an appeal against a case.

    A5 — the appeal is one-per-case. A second submission returns
    409.

    Any authenticated user can submit an appeal (the appeal is
    the target's right of reply; the moderator identity is NOT
    required here). The Kör 26 reporter identity is NEVER
    reflected in the response — the case row has no reporter FK
    (D2 / D7) and the appeal row carries only the submitter's
    internal ``users.id`` as ``actor_user_id`` in the action
    audit.
    """
    reason_raw = payload.get("reason")
    if not isinstance(reason_raw, str) or not reason_raw.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="reason required",
        )

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            case = get_case_by_public_id(db, case_public_id)
            if case is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"case {case_public_id} not found",
                )
            from datetime import datetime, timezone

            now = datetime.now(timezone.utc)
            case = submit_appeal(
                db,
                case,
                submitted_by_user_id=current_user.id,
                reason=reason_raw,
                now=now,
            )
            _commit_via(request, db)
        except AppealAlreadySubmitted as exc:
            db.rollback()
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        return _case_summary(case)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/moderation/cases/{public_id}/appeals/resolve
# ---------------------------------------------------------------------------


@router.post(
    "/cases/{case_public_id}/appeals/resolve",
    status_code=status.HTTP_200_OK,
)
def post_resolve_appeal(
    case_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Resolve an appeal — moderator-only.

    Body shape::

        {"verdict": "upheld" | "overturned",
         "reason": "<non-empty string>"}

    ``upheld`` reverts the case to ``visible``. ``overturned``
    keeps the case closed. The "independent reviewer" rule from
    ADR 0425 §D6 lives in the runbook; every action row carries
    the resolver's ``users.id`` so the rule is auditable.
    """
    verdict_raw = payload.get("verdict")
    if verdict_raw not in {"upheld", "overturned"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="verdict must be 'upheld' or 'overturned'",
        )

    reason_raw = payload.get("reason")
    if not isinstance(reason_raw, str) or not reason_raw.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="reason required",
        )

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            resolver_user_id = _require_moderator(db, current_user)
            case = get_case_by_public_id(db, case_public_id)
            if case is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"case {case_public_id} not found",
                )
            from datetime import datetime, timezone

            now = datetime.now(timezone.utc)
            case = resolve_appeal(
                db,
                case,
                resolver_user_id=resolver_user_id,
                verdict=verdict_raw,
                reason=reason_raw,
                now=now,
            )
            _commit_via(request, db)
        except NotAModerator as exc:
            db.rollback()
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except InvalidAppealVerdict as exc:
            db.rollback()
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        except NoOpenAppeal as exc:
            db.rollback()
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        return _case_summary(case)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# Internal / admin-side helper — the automation-signal intake.
#
# This endpoint is here so a future wiring round can call it from a
# cron / scheduler. The A4 measure-matrix test monkey-patches
# :func:`record_automation_signal` to bypass the
# :data:`case_service.AUTOMATION_ALLOWED_TO_STATES` allowlist and
# asserts that the resulting ``removed``-transition raises
# :class:`AutomationCannotEnforce`. The endpoint itself is moderator-
# only — automation NEVER holds a JWT.
# ---------------------------------------------------------------------------


@router.post(
    "/cases/{case_public_id}/automation-signals",
    status_code=status.HTTP_200_OK,
)
def post_automation_signal(
    case_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Record an automation signal against a case.

    Body shape::

        {"confidence": 0.0..1.0,
         "provider": "<string>",
         "provider_version": "<string>"}

    The destination state is computed inside
    :func:`case_service.record_automation_signal` from the
    confidence — there is no ``to_state`` field in the body.
    This endpoint is moderator-only as a defense-in-depth measure:
    the automation NEVER holds a JWT.
    """
    confidence_raw = payload.get("confidence")
    if not isinstance(confidence_raw, (int, float)) or not (
        0.0 <= confidence_raw <= 1.0
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="confidence must be a number in [0.0, 1.0]",
        )

    provider_raw = payload.get("provider")
    if not isinstance(provider_raw, str) or not provider_raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="provider required",
        )

    provider_version_raw = payload.get("provider_version")
    if not isinstance(provider_version_raw, str) or not provider_version_raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="provider_version required",
        )

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            moderator_user_id = _require_moderator(db, current_user)
            _ = moderator_user_id
            case = get_case_by_public_id(db, case_public_id)
            if case is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"case {case_public_id} not found",
                )
            from datetime import datetime, timezone

            now = datetime.now(timezone.utc)
            case = record_automation_signal(
                db,
                case,
                confidence=float(confidence_raw),
                provider=provider_raw,
                provider_version=provider_version_raw,
                now=now,
            )
            _commit_via(request, db)
        except AutomationCannotEnforce as exc:
            db.rollback()
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        except InvalidStateTransition as exc:
            db.rollback()
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return _case_summary(case)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# Re-export the helper so tests can call it directly.
__all__ = [
    "get_case",
    "get_cases",
    "post_appeal",
    "post_automation_signal",
    "post_decision",
    "post_resolve_appeal",
    "router",
]
