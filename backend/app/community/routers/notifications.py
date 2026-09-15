"""Community notification inbox router (E09-R20 service, ADR 0414 §D3;
HTTP surface landed in the 2026-09-15 production-wiring round).

The five endpoints the Flutter ``HttpCommunityNotificationRepository``
(``lib/features/community/data/repositories/notification_repository_impl.dart``)
is coded against, field-for-field:

* ``GET  /community/notifications?limit=&cursor=`` — one cursor page
  of the caller's inbox (``notification_service.list_inbox``): the
  A4 blocked-actor filter and the A5 deleted-entity suppression
  (``related_content_id = null``) are applied by the service.
* ``POST /community/notifications/{public_id}/read`` — mark one row
  read (``mark_read``). Idempotent on the ``(recipient,
  notification)`` natural key; a retry answers ``{"status": "noop"}``.
* ``POST /community/notifications/read-all`` — mark every unread row
  up to ``up_to_public_id`` (``mark_all_read_up_to``).
* ``GET  /community/notifications/preferences`` — the bare
  ``{category: level}`` map (``get_preferences``).
* ``PUT  /community/notifications/preferences/{category}`` — set one
  category's level (``set_preference``); the response is the updated
  bare map.

Every endpoint takes a JWT (``CurrentUser``). The recipient is ALWAYS
the JWT subject (§5.1) — no body-side recipient field exists, and a
notification owned by another profile is a silent ``noop`` on the
write side (the service's IDOR guard) and invisible on the read side.
A caller with no community profile gets the uniform 404 the sibling
routers use (``"caller has no community profile"``).

The session / commit / clock / invalidation seams mirror
``routers/posts.py`` (``app.state.session_factory``,
``app.state.notifications_commit``,
``app.state.notifications_on_invalidate``).

Route registration order matters inside this prefix: the literal
``/preferences`` and ``/read-all`` segments are registered before the
``/{public_id}/read`` collector — they differ in segment count so
Starlette cannot confuse them today, but the ADR 0497 D3 rule (literal
before param) is kept so a future single-segment param route cannot
shadow them.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..notifications import notification_service
from ..notifications.notification_service import NotificationProfileNotFound
from ..schemas.notification import (
    NOTIFICATION_PAGE_SIZE_DEFAULT,
    NOTIFICATION_PAGE_SIZE_MAX,
    MarkAllReadOut,
    MarkAllReadRequest,
    MarkReadOut,
    MarkReadRequest,
    NotificationOut,
    NotificationPage,
    PreferenceUpdateRequest,
)

router = APIRouter(prefix="/community/notifications", tags=["community-notifications"])

_PROFILE_MISSING = "caller has no community profile"


# ---------------------------------------------------------------------------
# Session / commit / clock / invalidation seams — the routers/posts.py
# pattern.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "notifications_commit", _default_commit)
    fn(db)


def _on_invalidate(request: Request):
    """The ``on_invalidate`` callable the service will call — ``None``
    unless a test / a future cache layer sets
    ``app.state.notifications_on_invalidate``."""
    return getattr(request.app.state, "notifications_on_invalidate", None)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """SQLite drops tzinfo on read; the column contract is UTC."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


def _resolve_caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
    """``users.id`` (JWT subject) → ``community_profiles.public_id``.

    Raises ``ValueError`` (the router turns it into the uniform 404)
    when the caller has not completed Community onboarding.
    """
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError(_PROFILE_MISSING)
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


def _caller_or_404(db: Session, user_id: int) -> uuid.UUID:
    try:
        return _resolve_caller_profile_public_id(db, user_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


def _row_to_out(db: Session, row) -> NotificationOut:
    """Map a ``CommunityNotification`` ORM row to the wire shape.

    Centralised so the no-internal-id guarantee is structural; the A5
    deep-link suppression is delegated to the service
    (``get_related_content_id``).
    """
    return NotificationOut(
        public_id=row.public_id,
        type=row.type,
        title_key=row.title_key,
        body_key=row.body_key,
        related_content_id=notification_service.get_related_content_id(
            db, notification=row
        ),
        is_read=bool(row.is_read),
        created_at=_as_utc(row.created_at),
    )


# ---------------------------------------------------------------------------
# GET /community/notifications
# ---------------------------------------------------------------------------


@router.get("", status_code=status.HTTP_200_OK)
def get_notifications(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    limit: int = Query(
        default=NOTIFICATION_PAGE_SIZE_DEFAULT, ge=1, le=NOTIFICATION_PAGE_SIZE_MAX
    ),
) -> NotificationPage:
    """One cursor page of the caller's inbox, newest first.

    Response: ``{"items": [NotificationOut...], "next_cursor":
    "..."|null}``. A malformed cursor restarts from the top (never a
    500).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        recipient_public_id = _caller_or_404(db, current_user.id)
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient_public_id,
            cursor=cursor,
            limit=limit,
        )
        return NotificationPage(
            items=[_row_to_out(db, row) for row in page.notifications],
            next_cursor=page.next_cursor,
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/notifications/preferences
# ---------------------------------------------------------------------------


@router.get("/preferences", status_code=status.HTTP_200_OK)
def get_preferences(
    request: Request,
    current_user: CurrentUser,
) -> dict[str, str]:
    """The caller's per-category preference map — a BARE
    ``{category: "inApp"|"push"|"disabled"}`` object, one entry per
    notification kind (unset categories read ``inApp``)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        recipient_public_id = _caller_or_404(db, current_user.id)
        return notification_service.get_preferences(
            db, recipient_public_id=recipient_public_id
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# PUT /community/notifications/preferences/{category}
# ---------------------------------------------------------------------------


@router.put("/preferences/{category}", status_code=status.HTTP_200_OK)
def put_preference(
    category: str,
    request: Request,
    current_user: CurrentUser,
    payload: PreferenceUpdateRequest,
) -> dict[str, str]:
    """Set one category's level; answers the updated bare map.

    ``level`` outside ``inApp`` / ``push`` / ``disabled`` is a 422
    (schema-level, and the service's own ``ValueError`` is mapped to
    422 as a second line). Naturally idempotent — the
    ``idempotency_key`` is accepted for wire parity and unused.
    """
    if not category or len(category) > 64:
        raise HTTPException(status_code=422, detail="invalid preference category")
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        recipient_public_id = _caller_or_404(db, current_user.id)
        try:
            notification_service.set_preference(
                db,
                recipient_public_id=recipient_public_id,
                category=category,
                level=payload.level,
            )
        except NotificationProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=_PROFILE_MISSING) from exc
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        return notification_service.get_preferences(
            db, recipient_public_id=recipient_public_id
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/notifications/read-all
# ---------------------------------------------------------------------------


@router.post("/read-all", status_code=status.HTTP_200_OK)
def post_read_all(
    request: Request,
    current_user: CurrentUser,
    payload: MarkAllReadRequest,
) -> MarkAllReadOut:
    """Mark every unread row up to (and including) ``up_to_public_id``.

    ``{"status": "read", "count": n}`` when at least one row
    transitioned; ``{"status": "noop", "count": 0}`` when nothing was
    unread in range OR the cutoff is not one of the caller's rows (the
    service's IDOR-safe no-op — never a 404 that would confirm another
    user's notification exists).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        recipient_public_id = _caller_or_404(db, current_user.id)
        try:
            count = notification_service.mark_all_read_up_to(
                db,
                recipient_public_id=recipient_public_id,
                up_to_id=payload.up_to_public_id,
                now=_now(),
                on_invalidate=_on_invalidate(request),
                idempotency_key=payload.idempotency_key,
            )
        except NotificationProfileNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=_PROFILE_MISSING) from exc
        if count:
            _commit_via(request, db)
        return MarkAllReadOut(status="read" if count else "noop", count=count)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/notifications/{public_id}/read
# ---------------------------------------------------------------------------


@router.post("/{public_id}/read", status_code=status.HTTP_200_OK)
def post_mark_read(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: MarkReadRequest | None = None,
) -> MarkReadOut:
    """Mark one row read.

    ``{"status": "read"}`` on the transition, ``{"status": "noop"}`` on
    an already-read row, an unknown id, or another user's row (the
    service's IDOR guard is a silent no-op — ADR 0414 §D4). The body
    is optional so a bare retry without a key still succeeds.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        recipient_public_id = _caller_or_404(db, current_user.id)
        try:
            transitioned = notification_service.mark_read(
                db,
                recipient_public_id=recipient_public_id,
                notification_public_id=public_id,
                now=_now(),
                on_invalidate=_on_invalidate(request),
                idempotency_key=payload.idempotency_key if payload else None,
            )
        except NotificationProfileNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=_PROFILE_MISSING) from exc
        if transitioned:
            _commit_via(request, db)
        return MarkReadOut(status="read" if transitioned else "noop")
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "get_notifications",
    "get_preferences",
    "post_mark_read",
    "post_read_all",
    "put_preference",
    "router",
]
