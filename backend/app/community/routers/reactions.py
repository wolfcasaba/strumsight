"""HTTP surface for the Community reaction domain.

**Miért született (2026-09-05).** A ``services/reaction_service.py`` a Kör 15
óta létezik és tesztelt, és a saját docstringje ki is mondja: „the wire
router is **not** in this round's ``allowed_paths`` (§0.0 D2 scope-shrink)".
Az a router SOSEM készült el. A hiány mérhető következménye a Flutter-oldalon
volt: a ``CommunityPostRepository.setReaction`` és a ``ReactionBar`` widget
végpont nélkül állt, ezért a reagálás a feed-kártyán nem volt bekötve.

A router SEMMILYEN üzleti szabályt nem hoz — az allowlist, az idempotencia, a
fajta-váltás UPDATE-szemantikája, a láthatóság és a cache-invalidációs esemény
mind a service-ben él. Ez a modul: session-seam, azonosító-feloldás,
kivétel → státusz leképezés, wire-alak.

**Leképezés:**

===============================  ==============================
service kivétel                  HTTP
===============================  ==============================
``ReactionViewerNotFound``       404 (az onboarding az upstream)
``ReactionPostNotFound``         404 (D7 egységes 404 — a nem
                                 létező, a törölt és a moderált
                                 poszt megkülönböztethetetlen)
``InvalidReactionKind``          422 + a service indoklása, ami
                                 FELSOROLJA a megengedett fajtákat
===============================  ==============================

**A DELETE ismeretlen posztra NEM 404.** A ``remove_reaction`` hiányzó posztra
``False``-t ad, nem kivételt — nincs mit eltávolítani, és egy 404 elárulná,
hogy a poszt létezik-e. Ugyanaz a leak-guard, amit a komment-lista üres oldala
és az értesítés-``mark_read`` ``{"changed": false}``-ja visz. A router ezt nem
írja felül.

**A válasz a művelet UTÁNI állapot.** Nem nyugta: a néző saját reakciója és a
teljes számláló. A séma docstringje mondja meg, miért — a fajta-váltás UPDATE,
tehát a számláló nem változik, és egy kliensoldali „+1 / -1" logika itt
tévedne.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..schemas.reaction import ReactionStateOut, SetReactionRequest
from ..services.reaction_service import (
    InvalidReactionKind,
    ReactionPostNotFound,
    ReactionViewerNotFound,
    get_reaction_count,
    get_viewer_reaction,
    remove_reaction,
    set_reaction,
)

router = APIRouter(prefix="/community", tags=["community-reactions"])


# ---------------------------------------------------------------------------
# Seamek — a bookmarks.py / comments.py mintájával azonos.
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


def _resolve_viewer_public_id(db: Session, user_id: int) -> uuid.UUID:
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
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


def _state_after(
    db: Session, *, viewer_public_id: uuid.UUID, post_public_id: uuid.UUID
) -> ReactionStateOut:
    """A poszt reakció-állapota a néző szemszögéből, a commit UTÁN.

    A két értéket a SERVICE olvasó felülete adja (``get_viewer_reaction`` /
    ``get_reaction_count``) — a router nem számol, nem növel és nem
    következtet. Így a válasz akkor is a valóságot mutatja, ha közben egy
    másik hívó is reagált.
    """
    return ReactionStateOut(
        post_public_id=post_public_id,
        viewer_reaction=get_viewer_reaction(
            db, viewer_public_id=viewer_public_id, post_public_id=post_public_id
        ),
        reaction_count=get_reaction_count(db, post_public_id=post_public_id),
    )


# ---------------------------------------------------------------------------
# PUT /community/posts/{post_public_id}/reaction
# ---------------------------------------------------------------------------


@router.put("/posts/{post_public_id}/reaction", status_code=status.HTTP_200_OK)
def set_reaction_endpoint(
    post_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: SetReactionRequest,
) -> ReactionStateOut:
    """A néző reakciójának beállítása vagy megváltoztatása.

    ``PUT``, nem ``POST``: a művelet idempotens a ``(poszt, néző)`` páron —
    ugyanazzal a fajtával ismételve ugyanaz az állapot áll elő, és a
    számláló nem nő. A fajta-váltás UPDATE ugyanazon a soron.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _resolve_viewer_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            set_reaction(
                db,
                viewer_public_id=viewer_public_id,
                post_public_id=post_public_id,
                kind=payload.kind,
                now=_utcnow(),
                idempotency_key=payload.idempotency_key,
            )
        except ReactionViewerNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ReactionPostNotFound:
            db.rollback()
            raise HTTPException(status_code=404, detail="post not found") from None
        except InvalidReactionKind as exc:
            # A service üzenete FELSOROLJA a megengedett fajtákat — a kliens
            # így a hibából megtudja, mi lett volna érvényes. Ezért nem
            # írjuk felül egy általános „invalid kind" szöveggel.
            db.rollback()
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        db.commit()
        return _state_after(
            db, viewer_public_id=viewer_public_id, post_public_id=post_public_id
        )
    finally:
        next(db_gen, None)


# ---------------------------------------------------------------------------
# DELETE /community/posts/{post_public_id}/reaction
# ---------------------------------------------------------------------------


@router.delete("/posts/{post_public_id}/reaction", status_code=status.HTTP_200_OK)
def remove_reaction_endpoint(
    post_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> ReactionStateOut:
    """A néző reakciójának eltávolítása (idempotens).

    Egy második hívás nem hibaág: nincs mit eltávolítani, a válasz ugyanaz
    az állapot. Ismeretlen poszt szintén nem 404 — l. a modul docstringjét.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _resolve_viewer_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        try:
            remove_reaction(
                db,
                viewer_public_id=viewer_public_id,
                post_public_id=post_public_id,
                now=_utcnow(),
            )
        except ReactionViewerNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        db.commit()
        return _state_after(
            db, viewer_public_id=viewer_public_id, post_public_id=post_public_id
        )
    finally:
        next(db_gen, None)


__all__ = [
    "ReactionStateOut",
    "SetReactionRequest",
    "remove_reaction_endpoint",
    "router",
    "set_reaction_endpoint",
]
