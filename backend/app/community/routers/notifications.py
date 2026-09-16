"""HTTP surface for the Community notification inbox.

**Miért született (2026-09-05).** A ``notifications/notification_service.py``
a Kör 20 óta létezik és tesztelt, de HTTP-router SOSEM került fölé. A hiány a
Flutter-oldalon látszott: a ``CommunityNotificationRepository`` öt metódusa
(``inboxPage`` / ``markRead`` / ``markAllReadUpTo`` / ``preferences`` /
``updatePreference``) végpont nélkül állt, ezért a
``CommunityNotificationsScreen`` elérhetetlen maradt.

A router SEMMILYEN üzleti szabályt nem hoz — az összevonás, a dedup, a
láthatóság és az idempotencia a service-ben él. Ez a modul: session-seam,
azonosító-feloldás, kivétel → státusz leképezés, wire-alak.

**Leképezés:**

=================================  ==============================
service kivétel                    HTTP
=================================  ==============================
``NotificationProfileNotFound``    404 (az onboarding az upstream)
``ValueError`` (érvénytelen szint) 422 + a service indoklása
=================================  ==============================

**Ismeretlen értesítés-azonosító NEM 404.** A ``mark_read`` sehol nem dob
``NotificationNotFound``-ot (grep-pel mérve): ismeretlen id-re ``False``-t
ad, a router pedig ``200 {"changed": false}``-ot. Két oka van, és mindkettő
szándékos: (1) a művelet idempotens — egy retry nem hibaág, (2) egy 404
elárulná, hogy az azonosító létezik-e, ami ugyanaz a szivárgás, amit a
komment-lista üres oldala zár. Az ``except NotificationNotFound`` ág ezért
NINCS a routerben: halott kód lenne.

**Az inbox MINDIG a hívó sajátja.** A címzettet a JWT-ből oldjuk fel, és a
service is a ``recipient_public_id``-ra szűr — nincs olyan útvonal, amin
valaki más inboxát lehetne kérni. Ez nem hozzáférés-ellenőrzés, hanem a
felület alakja: a paraméter nem is létezik.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..models.notification import CommunityNotification
from ..notifications.notification_service import (
    NotificationProfileNotFound,
    get_preferences,
    get_unread_count,
    list_inbox,
    mark_all_read_up_to,
    mark_read,
    set_preference,
)
from ..schemas.notification import (
    NOTIFICATION_PAGE_SIZE_DEFAULT,
    NOTIFICATION_PAGE_SIZE_MAX,
    MarkReadRequest,
    NotificationInboxPageOut,
    NotificationOut,
    NotificationPreferencesOut,
    SetPreferenceRequest,
)

router = APIRouter(prefix="/community/notifications", tags=["community-notifications"])


# ---------------------------------------------------------------------------
# Seamek — a posts.py / comments.py mintájával azonos.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _resolve_recipient_public_id(db: Session, user_id: int) -> uuid.UUID:
    """A hívó community-profiljának ``public_id``-ja.

    ``ValueError`` ⇒ 404: a profil létrehozása az onboarding dolga
    (Kör 6, ADR 0400), nem ezé a felületé.
    """
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return uuid.UUID(str(row[0]))


def _resolve_public_id_by_profile_id(db: Session, profile_id: int) -> uuid.UUID:
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE id = :pid"),
        {"pid": profile_id},
    ).first()
    if row is None:  # pragma: no cover — FK garantálja
        raise ValueError("profile not found")
    return uuid.UUID(str(row[0]))


def _row_to_out(db: Session, row: CommunityNotification) -> NotificationOut:
    """Wire alak — a belső id és a recipient_profile_id SOSEM megy ki."""
    actor_public_id: uuid.UUID | None = None
    if row.actor_profile_id is not None:
        actor_public_id = _resolve_public_id_by_profile_id(db, row.actor_profile_id)
    return NotificationOut(
        public_id=row.public_id,
        actor_public_id=actor_public_id,
        type=row.type,
        title_key=row.title_key,
        body_key=row.body_key,
        entity_type=row.entity_type,
        entity_id=row.entity_id,
        aggregate_count=row.aggregate_count,
        is_read=row.is_read,
        read_at=row.read_at,
        created_at=row.created_at,
    )


# ---------------------------------------------------------------------------
# GET /community/notifications
# ---------------------------------------------------------------------------


@router.get("", status_code=status.HTTP_200_OK)
def list_inbox_endpoint(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    page_size: int | None = Query(default=None, ge=1),
) -> NotificationInboxPageOut:
    """A hívó SAJÁT inboxának egy oldala + a teljes olvasatlan-szám."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            recipient = _resolve_recipient_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        limit = min(
            page_size or NOTIFICATION_PAGE_SIZE_DEFAULT, NOTIFICATION_PAGE_SIZE_MAX
        )
        try:
            page = list_inbox(
                db, recipient_public_id=recipient, cursor=cursor, limit=limit
            )
            unread = get_unread_count(db, recipient_public_id=recipient)
        except NotificationProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return NotificationInboxPageOut(
            items=[_row_to_out(db, row) for row in page.notifications],
            next_cursor=page.next_cursor,
            unread_count=unread,
        )
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# POST /community/notifications/{public_id}/read
# ---------------------------------------------------------------------------


@router.post("/{public_id}/read", status_code=status.HTTP_200_OK)
def mark_read_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: MarkReadRequest | None = None,
) -> dict[str, bool]:
    """Egy értesítés olvasottra állítása.

    A válasz ``changed`` mezője megmondja, TÉNYLEGESEN változott-e az
    állapot. Egy már olvasott — VAGY egy nem létező — értesítés jelölése
    egyaránt ``200 {"changed": false}``: idempotens, és nem árulja el, hogy
    az azonosító létezik-e (l. a modul docstringjét).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            recipient = _resolve_recipient_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            changed = mark_read(
                db,
                recipient_public_id=recipient,
                notification_public_id=public_id,
                now=_utcnow(),
                idempotency_key=(payload.idempotency_key if payload else None),
            )
        except NotificationProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        db.commit()
        return {"changed": changed}
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# POST /community/notifications/{public_id}/read-up-to
# ---------------------------------------------------------------------------


@router.post("/{public_id}/read-up-to", status_code=status.HTTP_200_OK)
def mark_all_read_up_to_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: MarkReadRequest | None = None,
) -> dict[str, int]:
    """Minden értesítés olvasottra állítása a megadottig BEZÁRÓLAG.

    A válasz ``marked`` mezője a TÉNYLEGESEN átbillentett sorok száma —
    a kliens ebből tudja frissíteni a jelvényt anélkül, hogy újralapozna.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            recipient = _resolve_recipient_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            marked = mark_all_read_up_to(
                db,
                recipient_public_id=recipient,
                up_to_id=public_id,
                now=_utcnow(),
                idempotency_key=(payload.idempotency_key if payload else None),
            )
        except NotificationProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        db.commit()
        return {"marked": marked}
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# GET / PUT /community/notifications/preferences
# ---------------------------------------------------------------------------


@router.get("/preferences", status_code=status.HTTP_200_OK)
def get_preferences_endpoint(
    request: Request,
    current_user: CurrentUser,
) -> NotificationPreferencesOut:
    """A hívó értesítés-beállításai (kategória → szint)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            recipient = _resolve_recipient_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            prefs = get_preferences(db, recipient_public_id=recipient)
        except NotificationProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return NotificationPreferencesOut(preferences=prefs)
    finally:
        next(db_gen, None)


@router.put("/preferences", status_code=status.HTTP_200_OK)
def set_preference_endpoint(
    request: Request,
    current_user: CurrentUser,
    payload: SetPreferenceRequest,
) -> NotificationPreferencesOut:
    """Egyetlen kategória szintjének állítása.

    Az érvényes szintek halmazát a SERVICE ismeri (``inApp`` / ``push`` /
    ``disabled``); a séma csak hosszt korlátoz, hogy az érvényesség EGY
    helyen dőljön el. Érvénytelen szint ⇒ 422 a service indoklásával.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            recipient = _resolve_recipient_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            set_preference(
                db,
                recipient_public_id=recipient,
                category=payload.category,
                level=payload.level,
            )
        except NotificationProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            # A service `ValueError`-ja az ÉRVÉNYTELEN SZINT jelzése. A
            # profil-hiányt fölötte már elkaptuk, tehát itt nem keveredhet
            # a kettő.
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        db.commit()
        return NotificationPreferencesOut(
            preferences=get_preferences(db, recipient_public_id=recipient)
        )
    finally:
        next(db_gen, None)
