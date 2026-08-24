"""Community report router — E09-R26, ADR 0422 §5.1.

The single POST endpoint that backs the Flutter ``report_content_sheet``.
The router's wire shape is the §5.1 sanitized envelope
(``build_sanitized_response``); the reporter's identity NEVER reaches
the response body.

Endpoints:

* ``POST /community/reports`` — submit a report. Body shape::

      {
        "idempotency_key": "<string>",
        "target_type": "post" | "comment",
        "target_id": "<UUID string>",
        "category": "<one of REPORT_CATEGORIES>",
        "extra_metadata": { ... } | null   # only honored for
                                            # copyright / privacy
      }

  Response (200, §5.1 sanitized)::

      {
        "report_public_id": "<UUID>",
        "target_type": "post",
        "target_id": "<UUID>",
        "category": "spam",
        "created_at": "<ISO-8601>",
        "deduplicated": false
      }

  Error map:

  * 400 — ``idempotency_key`` missing, ``target_type`` /
    ``target_id`` / ``category`` missing or wrong type.
  * 404 — caller has no community profile (mirror of the safety
    router's pattern).
  * 422 — ``category`` is empty or unknown (§6 A5).
  * 429 — caller exceeded the §6 A6 hourly cap.

The router is mounted by the test fixtures directly into a
self-contained ``FastAPI()`` — the production
``build_community_router`` factory stays untouched per the §0.0 STOP
feltétel 1.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..models.report import CommunityReport
from ..services.report_service import (
    InvalidCategory,
    InvalidExtraMetadata,
    RateLimitExceeded,
    build_sanitized_response,
    submit_report,
)

router = APIRouter(prefix="/community", tags=["community-reports"])


# ---------------------------------------------------------------------------
# Session factory seam — same pattern as routers/safety.py.
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
    fn = getattr(request.app.state, "reports_commit", _default_commit)
    fn(db)


# ---------------------------------------------------------------------------
# Resolve the caller's community profile public_id (mirrors safety.py).
# ---------------------------------------------------------------------------


def _caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
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


# ---------------------------------------------------------------------------
# POST /community/reports
# ---------------------------------------------------------------------------


_ALLOWED_TARGET_TYPES = frozenset({"post", "comment"})


@router.post(
    "/reports",
    status_code=status.HTTP_200_OK,
)
def post_report(
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Submit a user report (§5.1 sanitized response).

    The body is intentionally untyped (a plain dict) to mirror the
    safety router's pattern — the service layer's dataclass is the
    type-safe core, the router just unpacks and validates.

    The §5.1 invariant is enforced by the service layer's
    :func:`build_sanitized_response` — the router never adds a
    ``reporter_public_id`` field to the response.
    """
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    target_type = payload.get("target_type")
    if not isinstance(target_type, str) or target_type not in _ALLOWED_TARGET_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"target_type must be one of {sorted(_ALLOWED_TARGET_TYPES)}",
        )

    target_id = payload.get("target_id")
    if not isinstance(target_id, str) or not target_id:
        raise HTTPException(status_code=400, detail="target_id required")

    # F1 — the ``target_id`` must be a parseable UUID. A malformed
    # ``target_id`` (``"not-a-uuid"``) would otherwise reach the
    # service layer's :func:`target_exists` and raise ``ValueError``
    # inside ``uuid.UUID(target_id)`` — the router's blanket
    # ``except ValueError`` would map that to a 404 with the
    # "reporter profile not found" semantics, which is wrong (the
    # failure is a malformed client input, not a missing target).
    try:
        uuid.UUID(target_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail="target_id must be a valid UUID",
        ) from exc

    # ``category`` may be any string here — the service layer rejects
    # unknown values with the §6 A5 contract. Surfacing the failure
    # as 422 (the HTTP "Unprocessable Entity" status) matches the
    # FastAPI convention for semantic validation failures.
    category = payload.get("category")
    if not isinstance(category, str):
        raise HTTPException(status_code=400, detail="category required")

    extra_metadata_raw = payload.get("extra_metadata")
    extra_metadata: dict[str, object] | None = None
    if extra_metadata_raw is not None:
        if not isinstance(extra_metadata_raw, dict):
            raise HTTPException(
                status_code=400,
                detail="extra_metadata must be an object",
            )
        extra_metadata = {str(k): v for k, v in extra_metadata_raw.items()}

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            reporter_public_id = _caller_profile_public_id(db, current_user.id)
            result = submit_report(
                db,
                reporter_public_id=reporter_public_id,
                target_type=target_type,
                target_id=target_id,
                category=category,
                extra_metadata=extra_metadata,
            )
            # The response is built from the row BEFORE commit so the
            # §5.1 sanitization helper can verify the wire shape. The
            # ORM row is still attached to the session at this point.
            row = (
                db.query(CommunityReport)
                .filter_by(public_id=result.report_public_id)
                .one()
            )
            response = build_sanitized_response(row, deduplicated=result.deduplicated)
            _commit_via(request, db)
        except InvalidCategory as exc:
            db.rollback()
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        except InvalidExtraMetadata as exc:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except RateLimitExceeded as exc:
            db.rollback()
            raise HTTPException(status_code=429, detail=str(exc)) from exc
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return response
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "post_report",
    "router",
]
