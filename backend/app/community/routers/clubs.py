"""HTTP surface for the Community club domain.

**Miért született (2026-09-05).** A ``services/club_service.py`` a Kör 24 óta
létezik és tesztelt (``backend/tests/community/test_club_service.py``), és a
``ClubMembershipView`` docstringje ki is mondja: „a future router rounds it
through Pydantic". Az a router SOSEM készült el, ezért a Flutter-oldali
``CommunityClubRepository`` kilenc metódusa végpont nélkül állt, és a három
klub-képernyő elérhetetlen maradt.

A router SEMMILYEN üzleti szabályt nem hoz — a láthatóság, a tagsági és
meghívási limitek, a blokk-viszony, a szerepkör-átmenetek és az idempotencia
mind a service-ben él. Ez a modul: session-seam, azonosító-feloldás, kivétel
→ HTTP-státusz leképezés, és wire-alak.

**Leképezés:**

===============================  ==============================
service kivétel                  HTTP
===============================  ==============================
``ClubNotFound``                 404
``ClubMemberNotFound``           404
``ClubInviteNotFound``           404
``ClubMembershipLimitExceeded``  409
``ClubInviteLimitExceeded``      409
``ClubIdempotencyCollision``     409
``BlockedClubRelationship``      403
``InvalidClubTransition``        409
``OwnerMustTransferFirst``       409
``SelfRoleMutationNotAllowed``   403
profil hiánya (``ValueError``)   404 (az onboarding az upstream)
===============================  ==============================

**A jogosultság a SZERVERÉ.** A router sehol nem dönt szerepkör alapján —
minden művelet az ``actor_profile_id``-t adja át, és a service ítél. Egy
kliens-oldali „ő úgyis moderátor" feltevés jogosultsági rést nyitna.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..feed.club_feed import (
    DEFAULT_PAGE_SIZE as CLUB_FEED_DEFAULT_PAGE_SIZE,
)
from ..feed.club_feed import (
    MAX_PAGE_SIZE as CLUB_FEED_MAX_PAGE_SIZE,
)
from ..feed.club_feed import ClubNotVisible, list_club_feed
from ..models.club import CommunityClub
from ..models.post import CommunityPost
from ..post_projection import SimplePostRow, project_page
from ..routers.feed import _resolve_cursor_secret
from ..schemas.club import (
    CLUB_MEMBER_PAGE_SIZE_MAX,
    CLUB_PAGE_SIZE_DEFAULT,
    CLUB_PAGE_SIZE_MAX,
    ClubMemberOut,
    ClubMemberPage,
    ClubOut,
    ClubPage,
    CreateClubRequest,
    IdempotentRequest,
    TargetProfileRequest,
    UpdateClubRequest,
)
from ..schemas.feed import FeedPage, PinnedPostList
from ..services.club_content_service import list_club_pinned
from ..services.club_service import (
    BlockedClubRelationship,
    ClubIdempotencyCollision,
    ClubInviteLimitExceeded,
    ClubMemberNotFound,
    ClubMembershipLimitExceeded,
    ClubNotFound,
    InvalidClubTransition,
    OwnerMustTransferFirst,
    SelfRoleMutationNotAllowed,
    create_club,
    get_club,
    get_member_role,
    invite,
    leave_club,
    list_club_members,
    list_clubs,
    remove_member,
    request_join,
    transfer_ownership,
    update_club,
)

router = APIRouter(prefix="/community/clubs", tags=["community-clubs"])


# ---------------------------------------------------------------------------
# Seamek — a posts.py / comments.py / notifications.py mintájával azonos.
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


def _resolve_internal_profile_id(db: Session, user_id: int) -> int:
    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return int(row[0])


def _resolve_public_id_by_profile_id(db: Session, profile_id: int) -> uuid.UUID:
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE id = :pid"),
        {"pid": profile_id},
    ).first()
    if row is None:  # pragma: no cover — FK garantálja
        raise ValueError("profile not found")
    return uuid.UUID(str(row[0]))


def _resolve_profile_id_by_public_id(db: Session, public_id: uuid.UUID) -> int:
    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE public_id = :pid"),
        {"pid": str(public_id)},
    ).first()
    if row is None:
        raise ValueError("target profile not found")
    return int(row[0])


def _member_count(db: Session, club_id: int) -> int:
    row = db.execute(
        _sa_text("SELECT COUNT(*) FROM community_club_members WHERE club_id = :cid"),
        {"cid": club_id},
    ).first()
    return int(row[0]) if row is not None else 0


def _club_to_out(
    db: Session, club: CommunityClub, viewer_public_id: uuid.UUID
) -> ClubOut:
    """Wire alak — a néző SAJÁT szerepével együtt.

    A ``my_role`` a service ``get_member_role``-jából jön, nem a routerben
    kitalált szabályból: a szerepkör forrása egy hely.
    """
    return ClubOut(
        public_id=club.public_id,
        name=club.name,
        description=club.description,
        visibility=club.visibility,
        owner_public_id=_resolve_public_id_by_profile_id(db, club.owner_profile_id),
        member_count=_member_count(db, club.id),
        my_role=get_member_role(
            db, club_public_id=club.public_id, profile_public_id=viewer_public_id
        ),
        created_at=club.created_at,
        resource_version=club.updated_at,
    )


def _raise_for_service_error(exc: Exception) -> None:
    """A service kivételeinek EGYETLEN leképezési helye.

    Külön függvény, hogy a tizenegy ág ne másolódjon minden végpontba —
    egy elcsúszott státusz ott némán keletkezne.
    """
    if isinstance(exc, (ClubNotFound, ClubMemberNotFound)):
        raise HTTPException(status_code=404, detail=str(exc) or "not found") from exc
    if isinstance(exc, (BlockedClubRelationship, SelfRoleMutationNotAllowed)):
        raise HTTPException(status_code=403, detail=str(exc) or "forbidden") from exc
    if isinstance(
        exc,
        (
            ClubMembershipLimitExceeded,
            ClubInviteLimitExceeded,
            ClubIdempotencyCollision,
            InvalidClubTransition,
            OwnerMustTransferFirst,
        ),
    ):
        raise HTTPException(status_code=409, detail=str(exc) or "conflict") from exc
    raise exc


_SERVICE_ERRORS = (
    BlockedClubRelationship,
    ClubIdempotencyCollision,
    ClubInviteLimitExceeded,
    ClubMemberNotFound,
    ClubMembershipLimitExceeded,
    ClubNotFound,
    InvalidClubTransition,
    OwnerMustTransferFirst,
    SelfRoleMutationNotAllowed,
)


# ---------------------------------------------------------------------------
# GET / POST /community/clubs
# ---------------------------------------------------------------------------


@router.get("", status_code=status.HTTP_200_OK)
def list_clubs_endpoint(
    request: Request,
    current_user: CurrentUser,
    page_size: int | None = Query(default=None, ge=1),
) -> ClubPage:
    """A néző számára LÁTHATÓ klubok egy oldala.

    A ``next_cursor`` ma mindig ``None``: a ``list_clubs`` service
    ``limit``-alapú. A mező a kliens lapozó-kódja miatt van itt.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        viewer_public_id = _resolve_public_id_by_profile_id(db, viewer_id)
        limit = min(page_size or CLUB_PAGE_SIZE_DEFAULT, CLUB_PAGE_SIZE_MAX)
        clubs = list_clubs(db, viewer_profile_id=viewer_id, limit=limit)
        return ClubPage(
            items=[_club_to_out(db, club, viewer_public_id) for club in clubs],
            next_cursor=None,
        )
    finally:
        next(db_gen, None)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_club_endpoint(
    request: Request,
    current_user: CurrentUser,
    payload: CreateClubRequest,
) -> ClubOut:
    """Új klub — a hívó lesz a tulajdonos."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            owner_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        viewer_public_id = _resolve_public_id_by_profile_id(db, owner_id)
        try:
            club = create_club(
                db,
                owner_profile_id=owner_id,
                name=payload.name,
                description=payload.description,
                visibility=payload.visibility,
                idempotency_key=payload.idempotency_key,
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        except ValueError as exc:
            # A service `ValueError`-ja az érvénytelen `visibility` jelzése.
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        db.commit()
        return _club_to_out(db, club, viewer_public_id)
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# GET / PATCH /community/clubs/{public_id}
# ---------------------------------------------------------------------------


@router.get("/{public_id}", status_code=status.HTTP_200_OK)
def get_club_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> ClubOut:
    """Egy klub részletei, ha a néző láthatja."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        viewer_public_id = _resolve_public_id_by_profile_id(db, viewer_id)
        try:
            club = get_club(db, club_public_id=public_id, viewer_profile_id=viewer_id)
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        return _club_to_out(db, club, viewer_public_id)
    finally:
        next(db_gen, None)


@router.patch("/{public_id}", status_code=status.HTTP_200_OK)
def update_club_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: UpdateClubRequest,
) -> ClubOut:
    """Klub szerkesztése — a jogosultságot a service ítéli meg."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            actor_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        viewer_public_id = _resolve_public_id_by_profile_id(db, actor_id)
        try:
            club = update_club(
                db,
                actor_profile_id=actor_id,
                club_public_id=public_id,
                description=payload.description,
                visibility=payload.visibility,
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        db.commit()
        return _club_to_out(db, club, viewer_public_id)
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# Tagsági műveletek
# ---------------------------------------------------------------------------


@router.get("/{public_id}/members", status_code=status.HTTP_200_OK)
def list_members_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    page_size: int | None = Query(default=None, ge=1),
) -> ClubMemberPage:
    """A klub tagsági listája, ha a néző láthatja."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        limit = min(page_size or CLUB_MEMBER_PAGE_SIZE_MAX, CLUB_MEMBER_PAGE_SIZE_MAX)
        try:
            views = list_club_members(
                db, club_public_id=public_id, viewer_profile_id=viewer_id, limit=limit
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        return ClubMemberPage(
            items=[
                ClubMemberOut(
                    public_id=view.public_id,
                    club_public_id=view.club_public_id,
                    profile_public_id=view.profile_public_id,
                    role=view.role,
                    joined_at=view.joined_at,
                )
                for view in views
            ],
            next_cursor=None,
        )
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# GET /community/clubs/{public_id}/feed  —  a klub posztfolyama
# ---------------------------------------------------------------------------


@router.get("/{public_id}/feed", status_code=status.HTTP_200_OK)
def club_feed_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    page_size: int | None = Query(default=None, ge=1),
) -> FeedPage:
    """A klub posztfolyama — ugyanaz a wire-alak, mint a következés-feedé.

    A tagsági kapu, a blokk/némítás szűrő és a kurzor aláírása a
    ``list_club_feed`` service-é. A router a KÖZÖS projekciót hívja
    (``post_projection.project_page``), így a klub-feed kártyái ugyanazokat
    a számlálókat és néző-állapotot kapják, mint a következés-feedéi.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_pk = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        cursor_secret = _resolve_cursor_secret(request.app.state.settings)
        effective = page_size or CLUB_FEED_DEFAULT_PAGE_SIZE
        if effective > CLUB_FEED_MAX_PAGE_SIZE:
            effective = CLUB_FEED_MAX_PAGE_SIZE
        try:
            repo_page = list_club_feed(
                db,
                viewer_profile_id=viewer_pk,
                club_public_id=public_id,
                cursor=cursor,
                page_size=effective,
                cursor_secret=cursor_secret,
            )
        except ClubNotVisible as exc:
            raise HTTPException(status_code=404, detail="club not found") from exc
        return FeedPage(
            items=project_page(db, list(repo_page.items), viewer_profile_id=viewer_pk),
            next_cursor=repo_page.next_cursor,
        )
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# GET /community/clubs/{public_id}/pinned
# ---------------------------------------------------------------------------


def _projectable_pinned_rows(db: Session, rows) -> list[SimplePostRow]:
    """A ``PinnedPostRow`` négy mezőjéből + a poszt saját sorából teljes alak.

    A service a KITŰZÉS tényét méri (poszt, szerző, törzs, kitűzés ideje),
    nem a poszt teljes állapotát. A hiányzó mezőket a poszt sorából
    olvassuk ki — egyetlen ``IN``-lekérdezéssel, nem soronként —, hogy a
    kitűzött poszt ugyanazon az úton kapjon számlálót és néző-állapotot,
    mint a feed elemei. A KITŰZÉSI SORREND a service-é marad.
    """
    if not rows:
        return []
    public_ids = [row.post_public_id for row in rows]
    posts = {
        post.public_id: post
        for post in db.query(CommunityPost)
        .filter(CommunityPost.public_id.in_(public_ids))
        .all()
    }
    projectable: list[SimplePostRow] = []
    for row in rows:
        post = posts.get(row.post_public_id)
        if post is None:  # pragma: no cover — FK garantálja
            continue
        projectable.append(
            SimplePostRow(
                post_id=post.id,
                post_public_id=post.public_id,
                author_public_id=row.author_public_id,
                audience=post.audience,
                body=post.body,
                artifact_type=post.artifact_type,
                artifact_schema_version=post.artifact_schema_version,
                artifact_payload=post.artifact_payload,
                moderation_state=post.moderation_state,
                created_at=post.created_at,
                updated_at=post.updated_at,
                deleted_at=post.deleted_at,
            )
        )
    return projectable


@router.get("/{public_id}/pinned", status_code=status.HTTP_200_OK)
def list_pinned_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> PinnedPostList:
    """A klubban kitűzött posztok — a NÉZŐ tagsága szerint.

    A tagsági kapu a service-é (``ClubNotVisible``), nem ezé a
    felületé. A router 404-re fordítja, nem 403-ra: egy 403 elárulná,
    hogy a klub létezik, csak nem látható — ugyanaz a leak-guard, amit
    a komment-lista üres oldala és a reakció-törlés visz.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_pk = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            rows = list_club_pinned(
                db, viewer_profile_id=viewer_pk, club_public_id=public_id
            )
        except ClubNotVisible as exc:
            raise HTTPException(status_code=404, detail="club not found") from exc
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
            raise
        return PinnedPostList(
            items=project_page(
                db,
                _projectable_pinned_rows(db, list(rows)),
                viewer_profile_id=viewer_pk,
            )
        )
    finally:
        next(db_gen, None)


@router.post("/{public_id}/join", status_code=status.HTTP_200_OK)
def request_join_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: IdempotentRequest | None = None,
) -> dict[str, str]:
    """Csatlakozási kérelem.

    A válasz ``outcome`` mezője megmondja, MI történt: nyílt klubnál azonnali
    tagság (``joined``), zártnál függő kérelem (``requested``). A kettő
    összemosása azt a hibaosztályt szülné, amit a projekt az „optimista
    jelölés" alatt mér.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            actor_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            member, invite_row = request_join(
                db,
                actor_profile_id=actor_id,
                club_public_id=public_id,
                idempotency_key=(payload.idempotency_key if payload else None),
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        db.commit()
        if member is not None:
            return {"outcome": "joined"}
        if invite_row is not None:
            return {"outcome": "requested"}
        return {"outcome": "unchanged"}
    finally:
        next(db_gen, None)


@router.post("/{public_id}/leave", status_code=status.HTTP_200_OK)
def leave_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: IdempotentRequest | None = None,
) -> dict[str, bool]:
    """Kilépés a klubból."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            actor_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            leave_club(
                db,
                actor_profile_id=actor_id,
                club_public_id=public_id,
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        db.commit()
        return {"left": True}
    finally:
        next(db_gen, None)


@router.post("/{public_id}/invites", status_code=status.HTTP_201_CREATED)
def invite_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: TargetProfileRequest,
) -> dict[str, str]:
    """Meghívás — a jogosultságot a service ítéli meg."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            actor_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            invite_row = invite(
                db,
                actor_profile_id=actor_id,
                club_public_id=public_id,
                invitee_profile_public_id=payload.target_public_id,
                idempotency_key=payload.idempotency_key,
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        db.commit()
        return {"invite_public_id": str(invite_row.public_id)}
    finally:
        next(db_gen, None)


@router.delete("/{public_id}/members/{target_public_id}", status_code=200)
def remove_member_endpoint(
    public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> dict[str, bool]:
    """Tag eltávolítása — a jogosultságot a service ítéli meg."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            actor_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            remove_member(
                db,
                actor_profile_id=actor_id,
                club_public_id=public_id,
                target_profile_public_id=target_public_id,
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        db.commit()
        return {"removed": True}
    finally:
        next(db_gen, None)


@router.post("/{public_id}/owner", status_code=status.HTTP_200_OK)
def transfer_ownership_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: TargetProfileRequest,
) -> ClubOut:
    """Tulajdonos-átadás — a jogosultságot a service ítéli meg."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            actor_id = _resolve_internal_profile_id(db, current_user.id)
            new_owner_id = _resolve_profile_id_by_public_id(
                db, payload.target_public_id
            )
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        viewer_public_id = _resolve_public_id_by_profile_id(db, actor_id)
        try:
            club = transfer_ownership(
                db,
                actor_profile_id=actor_id,
                club_public_id=public_id,
                new_owner_profile_id=new_owner_id,
                now=_utcnow(),
            )
        except _SERVICE_ERRORS as exc:
            _raise_for_service_error(exc)
        db.commit()
        return _club_to_out(db, club, viewer_public_id)
    finally:
        next(db_gen, None)
