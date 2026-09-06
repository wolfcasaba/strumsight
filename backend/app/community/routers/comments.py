"""HTTP surface for the Community comment domain.

**Miért született (2026-09-05).** A ``services/comment_service.py`` a Kör 12
óta létezik és tesztelt (``backend/tests/community/test_comment_service.py``),
de HTTP-router SOSEM került fölé. A hiány mérhető következménye a
Flutter-oldalon volt: a ``CommunityPostRepository`` négy komment-metódusának
(``comments`` / ``createComment`` / ``updateComment`` / ``deleteComment``)
nem volt mit hívnia, ezért a ``CommentsScreen`` elérhetetlen maradt.

A router SEMMILYEN üzleti szabályt nem hoz — a láthatóság, a mélység-korlát,
a moderációs állapot, az idempotencia és az optimista konkurencia mind a
service-ben él. Ez a modul kizárólag: session-seam, azonosító-feloldás,
kivétel → HTTP-státusz leképezés, és wire-alak.

**Leképezés (a Kör 11 posts-router mintája):**

===============================  ==============================
service kivétel                  HTTP
===============================  ==============================
``CommentPostNotFound``          404 (a create ágon — a poszt alá
                                 írás nem folytatható)
``CommentNotFound``              404
``StaleCommentUpdateError``      409 + a jelenlegi resource_version
``CommentValidationError``       422 + a service indoklása
profil hiánya (``ValueError``)   404 (az onboarding az upstream)
===============================  ==============================

**A LISTA ága szándékosan NEM 404-el.** A ``list_comments`` ismeretlen vagy
a néző elől rejtett posztra ÜRES oldalt ad, nem kivételt — ez a leak-guard,
és a router nem írja felül. Egy 404 itt elárulná, hogy a poszt létezik,
csak nem látható. A ``test_comment_router.py`` A6 cellája ezt kontrollal
együtt méri: az ismeretlen poszt üres, a létező ugyanazon a hívón nem.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..models.comment import CommunityComment
from ..notifications.emitters import notify_post_commented
from ..schemas.comment import (
    COMMENT_PAGE_SIZE_DEFAULT,
    COMMENT_PAGE_SIZE_MAX,
    CommentOut,
    CommentPage,
    CreateCommentRequest,
    PatchCommentRequest,
)
from ..services.comment_service import (
    CommentNotFound,
    CommentPostNotFound,
    CommentValidationError,
    StaleCommentUpdateError,
    create_comment,
    edit_comment_with_resource_version,
    list_comments,
    soft_delete_comment,
)

# A prefix SZÁNDÉKOSAN `/community`, nem `/community/comments`: a lista- és
# létrehozó-útvonal a POSZT alá tartozik (`/community/posts/{id}/comments`),
# a szerkesztés és a törlés viszont magára a kommentre (`/community/
# comments/{id}`). Egy közös komment-prefix az elsőt nem tudná kifejezni.
router = APIRouter(prefix="/community", tags=["community-comments"])


# ---------------------------------------------------------------------------
# Session / clock / azonosító-feloldás seamek — a posts.py mintájával azonos.
# A helperek szándékosan lokálisak: a fában MINDEN community-router a saját
# példányát tartja (posts, feed, bookmarks), és egy közös modul kivezetése a
# meglévő négy router átírását jelentené, ami ezen a körön kívül esik.
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
    """Internal ``community_profiles.id`` for a JWT subject.

    ``ValueError`` when the caller has no community profile — the router
    turns it into 404, because profile creation is the onboarding flow's
    job (Kör 6, ADR 0400), not this surface's.
    """
    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return int(row[0])


def _resolve_author_public_id(db: Session, user_id: int) -> uuid.UUID:
    """The JWT subject's community-profile ``public_id``."""
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return uuid.UUID(str(row[0]))


def _resolve_public_id_by_profile_id(db: Session, profile_id: int) -> uuid.UUID:
    """The ``public_id`` of the profile with the given internal id.

    A szerző azonosítóját a KOMMENT sorából oldjuk fel, nem a hívóéból —
    különben minden komment a nézőnek tulajdonítódna (ugyanaz a hibaosztály,
    amit a posts-router F2 javító köre mért).
    """
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE id = :pid"),
        {"pid": profile_id},
    ).first()
    if row is None:  # pragma: no cover — FK garantálja
        raise ValueError("profile not found")
    return uuid.UUID(str(row[0]))


def _resolve_post_public_id_by_id(db: Session, post_id: int) -> uuid.UUID:
    row = db.execute(
        _sa_text("SELECT public_id FROM community_posts WHERE id = :pid"),
        {"pid": post_id},
    ).first()
    if row is None:  # pragma: no cover — FK garantálja
        raise ValueError("post not found")
    return uuid.UUID(str(row[0]))


def _resolve_comment_public_id_by_id(db: Session, comment_id: int) -> uuid.UUID:
    row = db.execute(
        _sa_text("SELECT public_id FROM community_comments WHERE id = :cid"),
        {"cid": comment_id},
    ).first()
    if row is None:  # pragma: no cover — FK garantálja
        raise ValueError("comment not found")
    return uuid.UUID(str(row[0]))


def _row_to_out(
    db: Session,
    comment: CommunityComment,
) -> CommentOut:
    """Wire alak egy ORM-sorból, minden azonosítót a SAJÁT forrásából."""
    parent_public_id: uuid.UUID | None = None
    if comment.parent_id is not None:
        parent_public_id = _resolve_comment_public_id_by_id(db, comment.parent_id)
    return CommentOut(
        public_id=comment.public_id,
        post_public_id=_resolve_post_public_id_by_id(db, comment.post_id),
        author_public_id=_resolve_public_id_by_profile_id(
            db, comment.author_profile_id
        ),
        parent_public_id=parent_public_id,
        depth=comment.depth,
        body=comment.body,
        moderation_state=comment.moderation_state,
        created_at=comment.created_at,
        resource_version=comment.updated_at,
        deleted_at=comment.deleted_at,
    )


# ---------------------------------------------------------------------------
# GET /community/posts/{post_public_id}/comments
# ---------------------------------------------------------------------------


@router.get("/posts/{post_public_id}/comments", status_code=status.HTTP_200_OK)
def list_comments_endpoint(
    post_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    # A felső határt a kezelő VÁGJA, nem 422-vel utasítja el — ugyanaz a
    # fail-safe, amit a feed-router dokumentál: egy 5000-es kérés 100-at kap
    # vissza, nem hibát. A `ge=1` alsó határ viszont a FastAPI rétegen áll.
    page_size: int | None = Query(default=None, ge=1),
) -> CommentPage:
    """Egy oldalnyi komment a poszt alatt, a néző láthatósága szerint."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_internal_id = _resolve_internal_profile_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        limit = min(page_size or COMMENT_PAGE_SIZE_DEFAULT, COMMENT_PAGE_SIZE_MAX)
        # A `list_comments` SZÁNDÉKOSAN nem dob ismeretlen posztra: üres
        # oldalt ad. Ez a leak-guard — egy nem létező és egy a néző elől
        # REJTETT poszt megkülönböztethetetlen. A router ezt NEM írja felül
        # 404-re, mert azzal elárulná, hogy a poszt létezik.
        page = list_comments(
            db,
            post_public_id=post_public_id,
            viewer_profile_id=viewer_internal_id,
            cursor=cursor,
            limit=limit,
        )
        return CommentPage(
            items=[_row_to_out(db, row) for row in page.comments],
            next_cursor=page.next_cursor,
        )
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# POST /community/posts/{post_public_id}/comments
# ---------------------------------------------------------------------------


@router.post("/posts/{post_public_id}/comments", status_code=status.HTTP_201_CREATED)
def create_comment_endpoint(
    post_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: CreateCommentRequest,
) -> CommentOut:
    """Új komment a poszt alá (vagy egy szülő-komment alá)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            author_public_id = _resolve_author_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            comment = create_comment(
                db,
                author_public_id=author_public_id,
                post_public_id=post_public_id,
                parent_public_id=payload.parent_public_id,
                body=payload.body,
                now=_utcnow(),
                idempotency_key=payload.idempotency_key,
            )
        except CommentPostNotFound:
            raise HTTPException(status_code=404, detail="post not found") from None
        except CommentValidationError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        # A poszt szerzőjének értesítése. SAVEPOINT-ban fut: ha elhasal, a
        # komment akkor is létrejön — a kibocsátás sosem buktathatja el az
        # elsődleges műveletet.
        notify_post_commented(
            db,
            post_public_id=post_public_id,
            actor_public_id=author_public_id,
            now=_utcnow(),
        )
        db.commit()
        return _row_to_out(db, comment)
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# PATCH /community/comments/{public_id}
# ---------------------------------------------------------------------------


@router.patch("/comments/{public_id}", status_code=status.HTTP_200_OK)
def patch_comment_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: PatchCommentRequest,
) -> CommentOut:
    """Komment szerkesztése — csak a szerző, optimista konkurenciával."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _resolve_author_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            comment = edit_comment_with_resource_version(
                db,
                viewer_public_id=viewer_public_id,
                comment_public_id=public_id,
                body=payload.body,
                resource_version=payload.resource_version,
                now=_utcnow(),
                idempotency_key=payload.idempotency_key,
            )
        except CommentNotFound:
            raise HTTPException(status_code=404, detail="comment not found") from None
        except StaleCommentUpdateError as exc:
            # 409 + a JELENLEGI verzió: a kliens ebből tud újratölteni és
            # újrapróbálni. Egy csupasz 409 nem mondaná meg, mihez képest.
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "stale_resource_version",
                    "current_resource_version": exc.current_updated_at.isoformat(),
                },
            ) from exc
        except CommentValidationError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        db.commit()
        return _row_to_out(db, comment)
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# DELETE /community/comments/{public_id}
# ---------------------------------------------------------------------------


@router.delete("/comments/{public_id}", status_code=status.HTTP_200_OK)
def delete_comment_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> dict[str, bool]:
    """Komment lágy törlése — csak a szerző (a moderátori ág külön surface)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _resolve_author_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            deleted = soft_delete_comment(
                db,
                viewer_public_id=viewer_public_id,
                comment_public_id=public_id,
                now=_utcnow(),
            )
        except CommentNotFound:
            raise HTTPException(status_code=404, detail="comment not found") from None
        db.commit()
        return {"deleted": deleted}
    finally:
        next(db_gen, None)
