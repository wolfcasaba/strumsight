"""Community router — minimal, dependency-injected surface.

E09-R02, ADR 0396. This router is intentionally tiny:

* it exists so that ``build_community_router`` has something to return when
  ``settings.community_enabled`` is True, and
* it gives the module boundary a real HTTP entry-point that proves the
  DI/seam pattern works end-to-end.

E09-R06, ADR 0400 §2–3, adds the two **authenticated write** endpoints
(``POST /community/profiles/me`` and ``PUT /community/profiles/me``). They
use the project-wide ``CurrentUser`` / ``DbSession`` dependencies from
``app.deps`` (the same pair ``routers/settings.py`` uses); the existing
``ping`` / ``read_profile`` endpoints are untouched and keep their bespoke
``_session_factory`` bridge — the §5.3 / ADR 0400 §6 "MEGLÉVŐ
endpointok változatlanok" rule.

The flag-mogott check is at the *factory* level (``build_community_router``
in ``community/__init__.py``), NOT here — so an operator who forgets the
flag check inside an endpoint cannot accidentally expose a surface: the
router is not even mounted when the flag is off (ADR 0396 §3).
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from ...deps import CurrentUser, DbSession
from ..models.profile import CommunityPrivacySettings, CommunityProfile
from ..schemas.profile import (
    CommunityPrivacySettingsOut,
    CommunityProfileCreate,
    CommunityProfileOut,
    CommunityProfileUpdate,
)
from ..services.identity_service import HandleAlreadyClaimed
from ..services.profile_service import (
    create_profile,
    update_profile,
)

router = APIRouter(prefix="/community", tags=["community"])


@router.get("/ping", status_code=status.HTTP_200_OK)
def ping() -> dict[str, str]:
    """Liveness probe for the Community module.

    Returns ``{"module": "community"}`` when the router is mounted, and
    ``404`` when the router is NOT mounted (``community_enabled=False``),
    because ``build_community_router`` returns ``None`` and the factory
    caller (``backend/tests/community/conftest.py`` here, ``main.py`` in a
    future round) simply does not include the router. That absence is what
    A5 measures — see ``test_profile_schema.py``.
    """
    return {"module": "community"}


def _session_factory(request: Request) -> Session:
    """Bridge ``request.app.state.session_factory`` for DI parity with the
    rest of the backend (``get_db`` reads the same ``state.session_factory``).
    """
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


@router.get(
    "/profiles/{public_id}",
    response_model=CommunityProfileOut,
)
def read_profile(
    public_id: str,
    db: Session = Depends(_session_factory),
) -> CommunityProfile:
    """Read a single community profile by its public UUID.

    The lookup is by ``public_id`` (UUID), NEVER by the internal ``id``
    (BigInteger) — exposing the integer PK as a URL parameter would defeat
    the A2 / §6.1 measure-matrix row 2 ("the response schema exposes the
    internal ``id`` field") guard, and the test in
    ``test_profile_schema.py::test_profile_route_only_looks_up_by_public_id``
    pins that contract.

    The endpoint exists to give the module a real HTTP exercise path; it
    returns ``404`` when the row is missing rather than ``None`` so the
    OpenAPI shape stays honest about the contract.
    """
    import uuid

    try:
        parsed = uuid.UUID(public_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="invalid public_id") from exc

    profile = db.query(CommunityProfile).filter_by(public_id=parsed).one_or_none()
    if profile is None:
        raise HTTPException(status_code=404, detail="profile not found")
    return profile


# ---------------------------------------------------------------------------
# E09-R06 — authenticated write endpoints (ADR 0400 §2–3, brief §2.3)
#
# These two endpoints are the only routes in the file that REQUIRE an
# authenticated user. The ``CurrentUser`` dependency lifts the identity from
# the JWT; the payload's ``user_id`` / ``profile_id`` field (if any) is
# rejected at Pydantic-parse-time by ``extra="forbid"`` (ADR 0400 §5.4,
# A8 measure-matrix "payload can override the CurrentUser" row). The
# pre-``SELECT`` + ``IntegrityError`` belt-and-braces on the create path
# is the §5.3 / A8 "two concurrent create calls both succeed" guard.
# ---------------------------------------------------------------------------


@router.post(
    "/profiles/me",
    status_code=status.HTTP_201_CREATED,
    response_model=CommunityProfileOut,
)
def create_my_profile(
    payload: CommunityProfileCreate,
    current_user: CurrentUser,
    db: DbSession,
) -> dict:
    """Create the caller's community profile.

    Identity is always the ``current_user`` from the auth ladder; the
    payload's body is restricted to the documented fields by
    ``extra="forbid"`` on the schema. The service-layer pre-``SELECT``
    produces a friendly 409 ``profile_exists`` when the caller already
    owns a profile; the DB-level unique index on ``user_id`` is the
    final enforcement for the concurrent-INSERT race (A8
    measure-matrix).
    """
    existing = (
        db.query(CommunityProfile).filter_by(user_id=current_user.id).one_or_none()
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="profile_exists")

    try:
        profile = create_profile(
            db,
            user_id=current_user.id,
            handle=payload.handle,
            display_name=payload.display_name,
            visibility=payload.visibility,
            audience_default=payload.audience_default,
            now=datetime.now(timezone.utc),
        )
    except ValueError as exc:
        # ``handle_policy.validate`` raises ``ValueError`` for a
        # malformed / reserved / blocked handle. 400 — the client can
        # correct the input. The original message is stable, user-safe
        # (no PII, no internal state) per ``handle_policy._classify``.
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except HandleAlreadyClaimed as exc:
        # Final-enforcement path: a concurrent ``INSERT`` slipped past
        # the pre-``SELECT`` and the DB unique index rejected it (or
        # the handle is already taken). 409 — the same shape as the
        # pre-``SELECT`` outcome so the client can branch on
        # ``profile_exists`` vs ``handle_taken`` if it cares.
        raise HTTPException(status_code=409, detail="handle_taken") from exc

    return _serialize_profile(profile, db)


@router.put(
    "/profiles/me",
    response_model=CommunityProfileOut,
)
def update_my_profile(
    payload: CommunityProfileUpdate,
    current_user: CurrentUser,
    db: DbSession,
) -> dict:
    """Update the caller's own community profile (display name only).

    Privacy is intentionally NOT in this payload — the ``privacy.py``
    endpoint (Kör 4, ADR 0398) owns the privacy-row update and is not
    wired into the module in this round (ADR 0400 "Következmények",
    router-mounting-függő). The edit-mode UI therefore does not offer
    a privacy re-selection (brief §5.2 / ADR 0400 §3).

    The row is resolved from ``current_user.id`` — the payload has
    no row identifier, and ``extra="forbid"`` rejects any attempt to
    smuggle one in. This is the §5.4 / A8 measure-matrix "user A can
    write to user B's profile" cell.
    """
    profile = (
        db.query(CommunityProfile).filter_by(user_id=current_user.id).one_or_none()
    )
    if profile is None:
        raise HTTPException(status_code=404, detail="profile_missing")
    updated = update_profile(db, profile, payload.display_name)
    return _serialize_profile(updated, db)


def _serialize_profile(profile: CommunityProfile, db: DbSession) -> dict:
    """Map the ORM row onto the public response shape.

    The response exposes the user-facing handle under the short wire
    key ``handle`` (E09-R06, ADR 0400 §2). The ORM splits the value
    across ``handle_display`` and ``handle_normalized`` (added by the
    Kör 3 migration, Kör 6 does NOT touch the model — see
    ``models/handle_history.py`` for the rationale). Pydantic's
    ``from_attributes=True`` would silently miss the ``handle`` key
    (the ORM has no such attribute), so this function reads the
    ``handle_display`` value via the raw-SQL helper ``assign_handle``
    uses internally — the value was written by the service layer in
    the same transaction we just committed.
    """
    handle_row = db.execute(
        text("SELECT handle_display FROM community_profiles WHERE id = :id"),
        {"id": profile.id},
    ).first()
    handle_display = handle_row[0] if handle_row is not None else None
    return {
        "public_id": profile.public_id,
        "display_name": profile.display_name,
        "created_at": profile.created_at,
        "handle": handle_display,
    }


__all__ = [
    "CommunityPrivacySettings",
    "CommunityPrivacySettingsOut",
    "CommunityProfile",
    "CommunityProfileCreate",
    "CommunityProfileOut",
    "CommunityProfileUpdate",
    "router",
]
