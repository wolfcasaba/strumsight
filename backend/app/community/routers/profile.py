"""Community router — minimal, dependency-injected read surface.

E09-R02, ADR 0396. This router is intentionally tiny:

* it exists so that ``build_community_router`` has something to return when
  ``settings.community_enabled`` is True, and
* it gives the module boundary a real HTTP entry-point that proves the
  DI/seam pattern works end-to-end.

The full CRUD surface — explicit onboarding (Kör 6), posts, follows,
leaderboards — is out of scope for this round (ADR 0396 §3 and the brief
§5.2). What lives here is a minimal, flag-mogott read/stub endpoint that
the module's tests can exercise (A3, A5).

The flag-mogott check is at the *factory* level (``build_community_router``
in ``community/__init__.py``), NOT here — so an operator who forgets the
flag check inside an endpoint cannot accidentally expose a surface: the
router is not even mounted when the flag is off (ADR 0396 §3).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.orm import Session

from ..models.profile import CommunityPrivacySettings, CommunityProfile
from ..schemas.profile import CommunityPrivacySettingsOut, CommunityProfileOut

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
        from fastapi import HTTPException

        raise HTTPException(status_code=400, detail="invalid public_id") from exc

    profile = db.query(CommunityProfile).filter_by(public_id=parsed).one_or_none()
    if profile is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="profile not found")
    return profile


__all__ = [
    "CommunityPrivacySettings",
    "CommunityProfile",
    "CommunityProfileOut",
    "CommunityPrivacySettingsOut",
    "router",
]
