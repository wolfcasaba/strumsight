"""Community social-graph router — E09-R07, ADR 0401 §3, §5, §7; E09-R08, ADR 0402 §D2.

This router exposes the follow / follow-request / follower-removal
HTTP endpoints AND the block-first filtering that E09-R08 wires into
``get_followers`` / ``get_following`` (the §D2 invariant). It is
mounted in the test app through a separate fixture (the brief §0.0 5.
pont — the ``build_community_router`` factory in
``community/__init__.py`` is in the §3 tilos zóna, so this round ships
its own mount point in the test conftest).

Endpoints:

* ``POST /community/profiles/{public_id}/follow`` — public target
  ⇒ immediate follow; private target ⇒ pending request. Returns
  ``{"request_id": ..., "status": "following" | "requested"}``.
  Idempotent at the state-machine level (retry is success).
* ``POST /community/follow-requests/{request_id}/accept`` — accept
  a pending request (target-only). Returns the same shape as
  follow.
* ``POST /community/follow-requests/{request_id}/decline`` — decline
  a pending request (target-only).
* ``DELETE /community/profiles/{public_id}/follow`` — unfollow
  (active edge DELETE) OR cancel a pending request (UPDATE row to
  ``cancelled``). Idempotent no-op if neither exists. Returns
  ``{"outcome": "unfollowed" | "cancelled" | "noop"}``.
* ``DELETE /community/profiles/{public_id}/followers/{follower_id}`` —
  remove a follower. Idempotent no-op if not a follower.
* ``GET /community/profiles/{public_id}/followers?cursor=...&limit=...`` —
  cursor-paginated followers list. **E09-R08 block-first**: a
  block between the caller and the profile owner returns ``403``;
  otherwise blocked profiles are filtered from the page.
* ``GET /community/profiles/{public_id}/following?cursor=...&limit=...`` —
  cursor-paginated following list. Same E09-R08 block-first filter.

All authenticated endpoints take an ``idempotency_key`` either in
the JSON body (POST endpoints) or as a query parameter (DELETE
endpoints — the Kör 5 ``api_client.dart``'s ``delete()`` does not
carry a JSON body, ADR 0401 §1 / §3).

The two GET endpoints translate the Kör 7 ``list_followers`` /
``list_following`` return value (which is a tuple of follow-edge
public_ids, the row's own ``public_id``) into the documented
follower / followed PROFILE public_ids so the wire shape matches
the documented contract and the E09-R08 block-filter can resolve
each id back to a ``community_profiles`` row. The response
envelope (``public_ids`` / ``next_cursor``) is unchanged.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Protocol

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..models.profile import CommunityProfile
from ..models.social_graph import CommunityFollow
from ..notifications.emitters import (
    notify_follow_accepted_by_request,
    notify_follow_request,
)
from ..policies.query_filters import (
    filter_public_ids_against_viewer_blocks,
    is_blocked_pair,
)
from ..services.follow_service import (
    FollowAlreadyExists,
    FollowRequestNotFound,
    SelfFollowNotAllowed,
    accept_follow_request,
    decline_follow_request,
    follow,
    list_followers,
    list_following,
    remove_follower,
    unfollow,
)

router = APIRouter(prefix="/community", tags=["community-social-graph"])


# ---------------------------------------------------------------------------
# Session factory seam — mirrors the Kör 3 / Kör 4 pattern.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


class _SupportsCommits(Protocol):
    """The HTTP endpoints commit through ``request.app.state`` so the
    test seam can override commit semantics without touching the
    service layer (the §6.1 valódi-sértés próba uses this)."""

    def __call__(self, db: Session) -> None: ...


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "follow_commit", _default_commit)
    fn(db)


# ---------------------------------------------------------------------------
# POST /community/profiles/{public_id}/follow
# ---------------------------------------------------------------------------


def _notification_now() -> datetime:
    """Az értesítés időbélyege.

    Külön függvény, hogy a két kibocsátási pont ugyanazt az órát olvassa,
    és a teszt egy helyen tudja rögzíteni.
    """
    return datetime.now(timezone.utc)


@router.post(
    "/profiles/{public_id}/follow",
    status_code=status.HTTP_200_OK,
)
def post_follow(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Create (or recycle) a follow edge or a follow request.

    Body shape::

        {"idempotency_key": "<string>"}

    The response carries ``request_id`` (the public_id of the new
    row) and ``status`` (``"following"`` for an active edge,
    ``"requested"`` for a pending request).
    """
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            follower_public_id = _caller_profile_public_id(db, current_user.id)
            result = follow(
                db,
                follower_public_id=follower_public_id,
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            if result.status == "requested":
                # Csak a KÉRELEM szül értesítést. Egy nyílt profil közvetlen
                # követésére nincs megengedett értesítés-típus: a
                # `follow_accepted` az ELLENKEZŐ irányt jelenti („elfogadták
                # a kérelmedet"), és arra felhasználva a címzett azt hinné,
                # hogy az ő kérelmét fogadták el. A hiány dokumentált —
                # egy `follow_started` típus felvétele külön kör.
                notify_follow_request(
                    db,
                    target_public_id=public_id,
                    actor_public_id=follower_public_id,
                    now=_notification_now(),
                )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except SelfFollowNotAllowed as exc:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except FollowAlreadyExists:
            # Rare race path: the service layer raised
            # ``FollowAlreadyExists`` because the IntegrityError→re-read
            # path in ``follow()`` could not find the would-be-winner
            # row to return (§6 / ADR 0401 §6 — the documented rare
            # outcome of a concurrent INSERT that lands between the
            # rollback and the re-read). The truthful response is the
            # same one we would return on a successful, idempotent
            # retry: the caller is already following / has a pending
            # request for this target. Treated as success (the §F4
            # fix — previously a nyers 500-as ``str(exc)``).
            db.rollback()
            return {
                "request_id": str(public_id),
                "status": "following",
            }
        return {
            "request_id": str(result.request_id),
            "status": result.status,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/follow-requests/{request_id}/accept
# ---------------------------------------------------------------------------


@router.post(
    "/follow-requests/{request_id}/accept",
    status_code=status.HTTP_200_OK,
)
def post_accept_follow_request(
    request_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Accept an incoming follow request (target-only)."""
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            acceptor_public_id = _caller_profile_public_id(db, current_user.id)
            result = accept_follow_request(
                db,
                request_public_id=request_id,
                target_public_id=acceptor_public_id,
                idempotency_key=idempotency_key,
            )
            # A kérelmező értesítése — enélkül sosem tudná meg, hogy
            # elfogadták: a felületen nincs olyan lista, ami a saját
            # kimenő kérelmei állapotát mutatná.
            notify_follow_accepted_by_request(
                db,
                request_public_id=request_id,
                actor_public_id=acceptor_public_id,
                now=_notification_now(),
            )
            _commit_via(request, db)
        except FollowRequestNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {
            "request_id": str(result.request_id),
            "status": result.status,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/follow-requests/{request_id}/decline
# ---------------------------------------------------------------------------


@router.post(
    "/follow-requests/{request_id}/decline",
    status_code=status.HTTP_200_OK,
)
def post_decline_follow_request(
    request_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Decline an incoming follow request (target-only)."""
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            decline_follow_request(
                db,
                request_public_id=request_id,
                target_public_id=_caller_profile_public_id(db, current_user.id),
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except FollowRequestNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"status": "declined"}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/profiles/{public_id}/follow   (unfollow OR cancel)
# ---------------------------------------------------------------------------


@router.delete(
    "/profiles/{public_id}/follow",
    status_code=status.HTTP_200_OK,
)
def delete_follow(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> dict[str, object]:
    """Unfollow a profile OR cancel a pending outgoing request.

    The function dispatches by the §3 three-branch contract: active
    edge → ``"unfollowed"``; pending request → ``"cancelled"``;
    otherwise → ``"noop"``. The response carries the chosen branch
    so the Flutter controller can decide whether the optimistic UI
    needs to roll back.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            outcome = unfollow(
                db,
                follower_public_id=_caller_profile_public_id(db, current_user.id),
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"outcome": outcome}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/profiles/{public_id}/followers/{follower_id}
# ---------------------------------------------------------------------------


@router.delete(
    "/profiles/{public_id}/followers/{follower_id}",
    status_code=status.HTTP_200_OK,
)
def delete_follower(
    public_id: uuid.UUID,
    follower_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> dict[str, object]:
    """Remove a follower — the owner expels an unwanted follower.

    Only the OWNER may call this on their own profile id. The
    ownership check is at the application layer (the JWT-resolved
    profile MUST match the path ``{public_id}``).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            caller_public_id = _caller_profile_public_id(db, current_user.id)
            if caller_public_id != public_id:
                # 403 — the caller is not the owner. The path is
                # the resource; the JWT is the proof. A mismatch
                # is an authorization failure, not a missing row.
                raise HTTPException(
                    status_code=403,
                    detail="only the profile owner may remove followers",
                )
            remove_follower(
                db,
                owner_public_id=public_id,
                follower_public_id=follower_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"status": "removed"}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/profiles/{public_id}/followers
# GET /community/profiles/{public_id}/following
# ---------------------------------------------------------------------------


_FOLLOW_LIST_DEFAULT_LIMIT = 50
_FOLLOW_LIST_MAX_LIMIT = 200


def _follower_page(
    db: Session,
    *,
    owner_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> tuple[list[uuid.UUID], str | None]:
    """Return the cursor-paginated FOLLOWERS page as PROFILE public_ids.

    Wraps :func:`follow_service.list_followers` and translates the
    edge-level public_ids the service returns into the
    corresponding follower's profile public_id (via a JOIN on
    ``community_profiles`` keyed on ``follower_profile_id``). The
    cursor is forwarded verbatim.

    Same shape contract as the wire — list of public_ids plus a
    next_cursor — but the values are the documented profile
    public_ids, not the Kör 7 edge public_ids.
    """
    page = list_followers(
        db, profile_public_id=owner_public_id, cursor=cursor, limit=limit
    )
    if not page.public_ids:
        return [], page.next_cursor
    rows = (
        db.query(CommunityFollow.public_id, CommunityFollow.follower_profile_id)
        .filter(CommunityFollow.public_id.in_(list(page.public_ids)))
        .all()
    )
    edge_to_follower_pk = {row[0]: row[1] for row in rows}
    profile_public_ids = _translate_edge_public_ids_to_profile_public_ids(
        db, edge_public_ids_to_profile_pk=edge_to_follower_pk
    )
    # Preserve order — the service page is ordered; we map
    # edge-by-edge so the (created_at DESC, id DESC) ordering is
    # preserved.
    return profile_public_ids, page.next_cursor


def _following_page(
    db: Session,
    *,
    owner_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> tuple[list[uuid.UUID], str | None]:
    """Same as :func:`_follower_page` but for the following list.

    Translates ``CommunityFollow.public_id`` to the FOLLOWED
    profile's public_id (JOIN on ``followed_profile_id``).
    """
    page = list_following(
        db, profile_public_id=owner_public_id, cursor=cursor, limit=limit
    )
    if not page.public_ids:
        return [], page.next_cursor
    rows = (
        db.query(CommunityFollow.public_id, CommunityFollow.followed_profile_id)
        .filter(CommunityFollow.public_id.in_(list(page.public_ids)))
        .all()
    )
    edge_to_followed_pk = {row[0]: row[1] for row in rows}
    profile_public_ids = _translate_edge_public_ids_to_profile_public_ids(
        db, edge_public_ids_to_profile_pk=edge_to_followed_pk
    )
    return profile_public_ids, page.next_cursor


@router.get(
    "/profiles/{public_id}/followers",
    status_code=status.HTTP_200_OK,
)
def get_followers(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None),
    limit: int = Query(
        default=_FOLLOW_LIST_DEFAULT_LIMIT,
        ge=1,
        le=_FOLLOW_LIST_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Return one cursor-paginated page of followers.

    Authenticated — the JWT must be present and valid (the §F2
    fix; the visibility filter that decides WHICH rows the caller
    is allowed to see remains Kör 8 / Kör 13 scope, but
    authentication is the router's own invariant — every other
    endpoint in this router enforces it, and a GET without auth
    is a hole regardless of what the body says).

    **E09-R08 block-first (ADR 0402 §D2):**

    1. If the caller and the profile owner are connected by a
       block edge in either direction, the endpoint returns
       ``403`` instead of the page. This is the block-first
       invariant — a blocked viewer must not even learn the size
       or the first row of the page.
    2. Otherwise, every row in the page whose owner is connected
       to the caller by a block edge is dropped. The drop is
       silent — the page is just shorter. The cursor is forwarded
       verbatim so the caller never sees the dropped rows.

    The check is symmetric: it does not matter who initiated the
    block.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _caller_profile_public_id(db, current_user.id)
        except ValueError:
            raise HTTPException(status_code=404, detail="caller profile not found")
        owner_id = _community_profile_pk(db, public_id)
        if owner_id is None:
            raise HTTPException(status_code=404, detail="profile not found")
        viewer_id = _community_profile_pk(db, viewer_public_id)
        if viewer_id is None:
            raise HTTPException(status_code=404, detail="caller profile not found")
        if is_blocked_pair(db, profile_id_a=viewer_id, profile_id_b=owner_id):
            # §D2: 403 BEFORE the page is materialised — the caller
            # learns nothing about the blocked peer's social graph.
            raise HTTPException(status_code=403, detail="blocked")
        profile_public_ids, next_cursor = _follower_page(
            db, owner_public_id=public_id, cursor=cursor, limit=limit
        )
        filtered_ids = filter_public_ids_against_viewer_blocks(
            db,
            viewer_profile_id=viewer_id,
            public_ids=profile_public_ids,
        )
        return {
            "public_ids": [str(value) for value in filtered_ids],
            "next_cursor": next_cursor,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.get(
    "/profiles/{public_id}/following",
    status_code=status.HTTP_200_OK,
)
def get_following(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None),
    limit: int = Query(
        default=_FOLLOW_LIST_DEFAULT_LIMIT,
        ge=1,
        le=_FOLLOW_LIST_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Return one cursor-paginated page of profiles the user follows.

    Authenticated — see the docstring on ``get_followers`` for the
    rationale (the §F2 fix: auth at the router layer; visibility
    filtering at the policy layer, Kör 8 / Kör 13).

    E09-R08 block-first: same §D2 invariant as ``get_followers`` —
    caller↔owner block → ``403``; otherwise blocked profiles are
    filtered from the page.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _caller_profile_public_id(db, current_user.id)
        except ValueError:
            raise HTTPException(status_code=404, detail="caller profile not found")
        owner_id = _community_profile_pk(db, public_id)
        if owner_id is None:
            raise HTTPException(status_code=404, detail="profile not found")
        viewer_id = _community_profile_pk(db, viewer_public_id)
        if viewer_id is None:
            raise HTTPException(status_code=404, detail="caller profile not found")
        if is_blocked_pair(db, profile_id_a=viewer_id, profile_id_b=owner_id):
            raise HTTPException(status_code=403, detail="blocked")
        profile_public_ids, next_cursor = _following_page(
            db, owner_public_id=public_id, cursor=cursor, limit=limit
        )
        filtered_ids = filter_public_ids_against_viewer_blocks(
            db,
            viewer_profile_id=viewer_id,
            public_ids=profile_public_ids,
        )
        return {
            "public_ids": [str(value) for value in filtered_ids],
            "next_cursor": next_cursor,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Resolve the caller's community profile public_id from their
    ``users.id`` (the JWT subject).

    Raises 404 when the user has no Community profile — the
    community onboarding flow (Kör 6, ADR 0400) owns this; the
    follow endpoints assume a profile exists.
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    raw = row[0]
    if isinstance(raw, str):
        # SQLite returns CHAR(32) UUID columns as plain strings
        # through raw text() queries. Wrap the hex form as a UUID
        # so the rest of the service layer sees the type it expects.
        return uuid.UUID(hex=raw)
    return raw


def _translate_edge_public_ids_to_profile_public_ids(
    db: Session,
    *,
    edge_public_ids_to_profile_pk: dict[uuid.UUID, int],
) -> list[uuid.UUID]:
    """Map a list of ``CommunityFollow.public_id`` (edge) values to
    the corresponding PROFILE public_ids on the OTHER end of each
    edge.

    The Kör 7 ``list_followers`` / ``list_following`` services
    return ``CommunityFollow.public_id`` — the edge's own UUID —
    not the follower's / followed profile's public_id. The wire
    contract (and the Dart ``_decodePage``) treats them as
    profile public_ids, so the routers translate before the
    response. The helper is shared between ``get_followers`` and
    ``get_following`` — the column that points to the
    "other party's" profile is the FK carried in
    ``edge_public_ids_to_profile_pk``.

    Returns the input list's PROFILE public_ids in the same order.
    Unknown edge public_ids (an internal mismatch — should not
    happen because the page came from the same engine) are
    silently dropped.
    """
    pk_to_profile_public_id: dict[int, uuid.UUID] = {}
    pks = list(set(edge_public_ids_to_profile_pk.values()))
    if pks:
        rows = (
            db.query(CommunityProfile.id, CommunityProfile.public_id)
            .filter(CommunityProfile.id.in_(pks))
            .all()
        )
        pk_to_profile_public_id = {row[0]: row[1] for row in rows}
    out: list[uuid.UUID] = []
    for edge_id in edge_public_ids_to_profile_pk:
        profile_pk = edge_public_ids_to_profile_pk[edge_id]
        profile_pid = pk_to_profile_public_id.get(profile_pk)
        if profile_pid is not None:
            out.append(profile_pid)
    return out


def _community_profile_pk(db: Session, public_id: uuid.UUID) -> int | None:
    """Resolve the internal bigint PK for a community profile public_id.

    Returns ``None`` for unknown public_ids (the caller distinguishes
    that case from "caller has no profile" so the routers can return
    404 vs 403 correctly). The block-filter helpers
    (``query_filters.is_blocked_pair`` / ``filter_public_ids_*``)
    operate on internal ids (the schema's PK), so the routers must
    bridge the path-param public_id to the internal id once per
    request.

    The ``community_profiles.public_id`` column is declared
    ``Uuid(as_uuid=True)`` and serialises to ``CHAR(32)`` (hex form,
    no hyphens) on SQLite — same precedent as
    ``community_privacy_settings``'s raw-insert helper in the test
    fixtures. The query binds the hex form to match.
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE public_id = :pid"),
        {"pid": public_id.hex},
    ).first()
    if row is None:
        return None
    raw = row[0]
    return int(raw)


__all__ = [
    "delete_follow",
    "delete_follower",
    "get_followers",
    "get_following",
    "post_accept_follow_request",
    "post_decline_follow_request",
    "post_follow",
    "router",
]
