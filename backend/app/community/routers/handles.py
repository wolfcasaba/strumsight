"""Handles router — E09-R03, ADR 0397 §5.3, §6.3.

This router exposes the public handle surface — the *only* place a client
learns whether a handle is taken. The §5.3 invariant lives here:

* Single-handle-per-call: there is no batch-availability endpoint, no
  prefix-list endpoint, no "is taken" search. The only handler is
  ``GET /community/handles/availability?handle=<value>`` and it answers
  one question about one handle at a time.
* Rate-limited: a process-local ``RateLimiter`` (same primitive the tutor
  proxy uses — round 120) bounds the request volume per client key.
* No PII: the response is just ``available`` + ``reason`` + the
  normalized form on success. Never the profile id, the display name,
  the email, or any timing oracle.

The router is mounted by the test app through a separate fixture (we
don't have a hook in ``build_community_router`` because the brief
excludes ``backend/app/community/__init__.py`` from this round's allowed
paths — the integration is opt-in per-test).
"""

from __future__ import annotations

from collections.abc import Iterator

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from sqlalchemy.orm import Session

from ...ratelimit import RateLimiter
from ..policies.handle_policy import (
    classify_reason,
    is_blocked,
    is_reserved,
    normalize,
    validate,
)
from ..services.identity_service import (
    CooldownActive,
    HandleAlreadyClaimed,
    assign_handle,
    change_handle,
    commit_with_uniqueness_check,
    is_handle_available,
    lookup_active_profile_id,
    lookup_redirect_target,
)

router = APIRouter(prefix="/community/handles", tags=["community-handles"])

# --- Rate limiters (process-local; ``reset_rate_limiters`` for tests) ------

# 30 availability checks per minute per client key. The brief §5.3 forbids
# batch endpoints; this single-handle-per-call rate limit is the second
# defence, so a client probing many handles is still bounded by the
# limiter even if it spreads across keys (each key still burns one slot).
_AVAILABILITY_MAX = 30
_AVAILABILITY_WINDOW = 60.0

# 5 handle changes per hour per profile. The cooldown is 14 days; this
# tighter bound protects against a single session retrying inside the
# cooldown window — the limiter still rejects each attempt, the cooldown
# is the *contract*.
_CHANGE_MAX = 5
_CHANGE_WINDOW = 3600.0

_availability_limiter = RateLimiter(
    max_attempts=_AVAILABILITY_MAX,
    window_seconds=_AVAILABILITY_WINDOW,
)
_change_limiter = RateLimiter(
    max_attempts=_CHANGE_MAX,
    window_seconds=_CHANGE_WINDOW,
)


def reset_rate_limiters() -> None:
    """Clear both rate limiters — exposed for the test fixture."""
    _availability_limiter.reset()
    _change_limiter.reset()


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _client_key(request: Request) -> str:
    """Best-effort client key for rate limiting.

    The endpoint is intentionally behind the Community enable flag, so
    authenticated identity is not yet available (Kör 6 is the auth
    surface). Until then we key by the first ``X-Forwarded-For`` value
    when present, falling back to the FastAPI ``client`` tuple. This is
    not a security boundary — the *real* defence against enumeration is
    the single-handle-per-call endpoint shape, not the IP heuristic.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client is not None:
        return request.client.host
    return "unknown"


# --------------------------------------------------------------------------
# GET /community/handles/availability?handle=...
# --------------------------------------------------------------------------


@router.get("/availability", status_code=status.HTTP_200_OK)
def check_availability(
    request: Request,
    handle: str = Query(..., min_length=1, max_length=64),
) -> dict[str, object]:
    """Check whether a single handle is available.

    The response is intentionally minimal:

    * ``available: true`` + ``normalized`` on success.
    * ``available: false`` + ``reason`` (one of ``invalid``,
      ``reserved``, ``blocked``, ``taken``, ``rate_limited``).

    The endpoint never echoes the existing owner's profile, the email,
    or the registration timestamp — the §6 A3 invariant.
    """
    if not _availability_limiter.allow(_client_key(request)):
        return {"available": False, "reason": "rate_limited"}

    normalized = normalize(handle)
    reason = classify_reason(normalized)
    if reason is not None:
        return {"available": False, "reason": _reason_code(normalized, reason)}

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        if is_handle_available(db, normalized):
            return {"available": True, "normalized": normalized}
        return {"available": False, "reason": "taken"}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


def _reason_code(normalized: str, _classify_reason: str) -> str:
    """Map a policy reason string to a stable wire-level code."""
    if is_reserved(normalized):
        return "reserved"
    if is_blocked(normalized):
        return "blocked"
    return "invalid"


# --------------------------------------------------------------------------
# GET /community/handles/{handle}   (active OR redirect target)
# --------------------------------------------------------------------------


@router.get("/{handle:str}", status_code=status.HTTP_200_OK)
def resolve_handle(
    handle: str,
    request: Request,
) -> dict[str, object]:
    """Resolve a handle to a profile, with redirect support for old handles
    that are still inside the ``HANDLE_REDIRECT_WINDOW``.

    The response only exposes the *public* UUID of the owner. The internal
    ``id`` is never returned (the Kör 2 A2 contract holds here too).
    """
    normalized = normalize(handle)
    if classify_reason(normalized) is not None:
        raise HTTPException(status_code=404, detail="handle not found")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        active = lookup_active_profile_id(db, normalized)
        if active is not None:
            return {
                "handle": normalized,
                "public_id": _public_id_for(db, active),
            }
        redirect = lookup_redirect_target(db, normalized)
        if redirect is not None:
            return {
                "handle": normalized,
                "public_id": _public_id_for(db, redirect),
                "redirect": True,
            }
        raise HTTPException(status_code=404, detail="handle not found")
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


def _public_id_for(db: Session, profile_id: int) -> str:
    """Look up the public UUID for a profile (DB read by id)."""
    row = db.execute(
        # The handle columns live on community_profiles but are not in the
        # ORM mapped class (the Kör 2 model was kept untouched this
        # round — see the brief's allowed_paths). Raw SQL is honest about
        # the surface we're touching.
        "SELECT public_id FROM community_profiles WHERE id = :id",
        {"id": profile_id},
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="profile missing")
    return str(row[0])


# --------------------------------------------------------------------------
# POST /community/handles/claim    (initial handle assignment)
# --------------------------------------------------------------------------


@router.post("/claim", status_code=status.HTTP_201_CREATED)
def claim_handle(
    request: Request,
    response: Response,
    payload: dict[str, object],
) -> dict[str, object]:
    """Assign the initial handle to a profile.

    The DB-level unique index is the enforcement (§5.1). The application
    layer surfaces ``409 taken`` instead of letting callers discover it
    through a 500.

    Body shape::

        {"profile_id": <int>, "handle": "<raw>"}

    The ``profile_id`` is the internal ``community_profiles.id`` (this is
    an internal endpoint, not yet exposed to the mobile client — the
    Kör 6 onboarding surface will use ``public_id``).
    """
    profile_id = payload.get("profile_id")
    handle = payload.get("handle")
    if not isinstance(profile_id, int) or not isinstance(handle, str):
        raise HTTPException(status_code=400, detail="invalid payload")
    try:
        normalized = validate(handle)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if not _change_limiter.allow(_client_key(request)):
        raise HTTPException(status_code=429, detail="rate limited")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        assign_handle(db, profile_id, handle, normalized)
        try:
            commit_with_uniqueness_check(db)
        except HandleAlreadyClaimed:
            raise HTTPException(status_code=409, detail="handle taken") from None
        return {"profile_id": profile_id, "handle": normalized, "available": True}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# --------------------------------------------------------------------------
# POST /community/handles/change   (handle change with cooldown)
# --------------------------------------------------------------------------


@router.post("/change", status_code=status.HTTP_200_OK)
def change_profile_handle(
    request: Request,
    payload: dict[str, object],
) -> dict[str, object]:
    """Change a profile's handle with cooldown enforcement (§5.4, A6).

    Body shape::

        {"profile_id": <int>, "handle": "<raw>"}

    The cooldown is the *contract* — 14 days since the last change. The
    rate limit is a tighter secondary bound (5 attempts per hour) that
    protects against a stuck client retrying inside the cooldown window.
    """
    profile_id = payload.get("profile_id")
    handle = payload.get("handle")
    if not isinstance(profile_id, int) or not isinstance(handle, str):
        raise HTTPException(status_code=400, detail="invalid payload")
    try:
        normalized = validate(handle)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if not _change_limiter.allow(_client_key(request)):
        raise HTTPException(status_code=429, detail="rate limited")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            change_handle(db, profile_id, handle, normalized)
        except CooldownActive as exc:
            raise HTTPException(status_code=429, detail=str(exc)) from exc
        try:
            commit_with_uniqueness_check(db)
        except HandleAlreadyClaimed:
            raise HTTPException(status_code=409, detail="handle taken") from None
        return {"profile_id": profile_id, "handle": normalized, "available": True}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "router",
    "reset_rate_limiters",
]