"""Community posts router (E09-R11, ADR 0405).

The HTTP surface for the post lifecycle:

* ``POST   /community/posts`` — create a post. Server-side author
  (the JWT subject). Idempotent on ``idempotency_key``.
* ``GET    /community/posts/{public_id}`` — read a post through the
  audience + block + moderation gate (uniform 404 on every "not
  visible" branch — brief §5.3, §0.0 D7).
* ``PATCH  /community/posts/{public_id}`` — owner-only update with
  optimistic-concurrency check on ``resource_version`` (brief §0.0
  D3, ADR 0398 §6 precedent).
* ``DELETE /community/posts/{public_id}`` — owner-only soft delete.
  Idempotent on a soft-deleted post (D12).

All four endpoints take a JWT (the ``CurrentUser`` dependency). The
author of a create is the JWT subject, NEVER a body-side field
(§5.1 / A1). The router is mounted by the test fixtures directly
into a self-contained ``FastAPI()`` — the production
``build_community_router`` factory stays untouched (the Kör 7–8
pattern; the §3 tilos-zóna discipline).

The cache-invalidation seam (``on_invalidate``) is wired through
``app.state.posts_on_invalidate`` when present; the default is
``None`` — Kör 13+ will bind the real cache layer (brief §0.0 D11).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import ValidationError as PydanticValidationError
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..schemas.post import CreatePostRequest, PatchPostRequest, PostOut
from ..services.post_service import (
    CachedInvalidationEvent,
    PostNotFound,
    StalePostUpdateError,
    create_post,
    get_post,
    patch_post,
    soft_delete_post,
)

router = APIRouter(prefix="/community/posts", tags=["community-posts"])


# ---------------------------------------------------------------------------
# Session / commit / clock / invalidation seams — same pattern as the
# Kör 5/8 routers (routers/social_graph.py, routers/safety.py,
# routers/privacy.py).
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity.

    Identical seam to the existing community routers — the
    self-contained test app in ``backend/tests/community/conftest.py``
    populates ``app.state.session_factory`` so we read the same way
    the production wiring will (when a future round mounts this
    router in ``build_community_router``).
    """
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "posts_commit", _default_commit)
    fn(db)


def _on_invalidate(request: Request):
    """Return the ``on_invalidate`` callable the service will call.

    Defaults to ``None`` — the cache-invalidation seam is wired
    only when ``app.state.posts_on_invalidate`` is set (Kör 13+).
    A test fixture injects a spy here for the D11 cell.
    """
    return getattr(request.app.state, "posts_on_invalidate", None)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


def _resolve_internal_profile_id(db: Session, user_id: int) -> int:
    """Return the internal ``community_profiles.id`` for a JWT subject.

    Raises ``ValueError`` (the router catches and returns 404) when
    the user has no community profile — the onboarding flow owns
    profile creation (Kör 6, ADR 0400).
    """
    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return int(row[0])


def _resolve_author_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Return the JWT subject's community profile public_id.

    Mirrors the Kör 7 ``_caller_profile_public_id`` pattern, but
    here we need the public_id (the create service takes it; the
    delete service takes the internal id). Both calls share the
    same SQL — kept as separate helpers for type clarity.
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


def _row_to_out(post, author_public_id: uuid.UUID) -> PostOut:
    """Map a ``CommunityPost`` ORM row + author public_id to ``PostOut``.

    Centralised so the §6.1 leak-guard (no internal id on the wire)
    is structural — adding a field to the response still routes
    through here.
    """
    return PostOut(
        public_id=post.public_id,
        author_public_id=author_public_id,
        audience=post.audience,  # type: ignore[arg-type]
        club_id=post.club_id,
        body=post.body,
        artifact_type=post.artifact_type,
        artifact_schema_version=post.artifact_schema_version,
        artifact_payload=post.artifact_payload,
        moderation_state=post.moderation_state,  # type: ignore[arg-type]
        created_at=post.created_at,
        resource_version=post.updated_at,
        deleted_at=post.deleted_at,
    )


# ---------------------------------------------------------------------------
# POST /community/posts
# ---------------------------------------------------------------------------


@router.post("", status_code=status.HTTP_201_CREATED)
def post_post(
    request: Request,
    current_user: CurrentUser,
    payload: CreatePostRequest,
) -> PostOut:
    """Create a post (idempotent on ``idempotency_key``).

    Author = JWT subject (brief §5.1). A forged ``author_id`` in the
    body is rejected at parse time by ``ConfigDict(extra='forbid')``
    on ``CreatePostRequest`` and never reaches the service.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                author_public_id = _resolve_author_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                post = create_post(
                    db,
                    author_public_id=author_public_id,
                    audience=payload.audience,
                    body=payload.body,
                    idempotency_key=payload.idempotency_key,
                    club_id=payload.club_id,
                    artifact=payload.artifact,
                    now=datetime_now(),
                    on_invalidate=_on_invalidate(request),
                )
            except ValueError as exc:
                # Author has no community profile / body too long /
                # a service-layer invariant violation.
                db.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            except PydanticValidationError as exc:
                # ``parse_share_artifact`` re-raised inside the
                # service layer (defensive round-trip).
                db.rollback()
                raise HTTPException(status_code=422, detail=exc.errors()) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _row_to_out(post, author_public_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/posts/{public_id}
# ---------------------------------------------------------------------------


@router.get("/{public_id}", status_code=status.HTTP_200_OK)
def get_post_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> PostOut:
    """Return the post if the viewer may see it (D7 uniform 404)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_internal_id = _resolve_internal_profile_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                viewer_public_id = _resolve_author_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                post = get_post(
                    db,
                    post_public_id=public_id,
                    viewer_profile_id=viewer_internal_id,
                )
            except PostNotFound:
                raise HTTPException(status_code=404, detail="post not found") from None
            return _row_to_out(post, viewer_public_id)
        except HTTPException:
            raise
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# PATCH /community/posts/{public_id}
# ---------------------------------------------------------------------------


@router.patch("/{public_id}", status_code=status.HTTP_200_OK)
def patch_post_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: PatchPostRequest,
) -> PostOut:
    """Update a post (owner-only; optimistic concurrency on
    ``resource_version``)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_internal_id = _resolve_internal_profile_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                viewer_public_id = _resolve_author_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            payload_dict = payload.model_dump(exclude_unset=True)
            # ``resource_version`` is required; keep it in the dict so
            # the service can compare it. ``exclude_unset`` keeps the
            # "absent field = leave alone" semantic for the rest.
            payload_dict["resource_version"] = payload.resource_version
            try:
                post = patch_post(
                    db,
                    post_public_id=public_id,
                    viewer_profile_id=viewer_internal_id,
                    payload=payload_dict,
                    now=datetime_now(),
                    on_invalidate=_on_invalidate(request),
                )
            except PostNotFound:
                raise HTTPException(status_code=404, detail="post not found") from None
            except StalePostUpdateError as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "stale_resource_version",
                        "current_resource_version": (
                            exc.current_updated_at.isoformat()
                        ),
                    },
                ) from exc
            except ValueError as exc:
                db.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _row_to_out(post, viewer_public_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/posts/{public_id}
# ---------------------------------------------------------------------------


@router.delete("/{public_id}", status_code=status.HTTP_200_OK)
def delete_post_endpoint(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> dict[str, object]:
    """Soft-delete a post (owner-only; idempotent on already-deleted).

    Returns ``{"status": "deleted"}`` on the actual transition and
    ``{"status": "noop"}`` on an idempotent retry (D12). Both are
    HTTP 200; the §0.0 D7 uniform 404 applies only when the post
    is missing OR the viewer is not the owner.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_internal_id = _resolve_internal_profile_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                post = soft_delete_post(
                    db,
                    post_public_id=public_id,
                    viewer_profile_id=viewer_internal_id,
                    now=datetime_now(),
                    on_invalidate=_on_invalidate(request),
                )
            except PostNotFound:
                raise HTTPException(status_code=404, detail="post not found") from None
            _commit_via(request, db)
        except HTTPException:
            raise
        return {
            "status": "deleted" if post else "noop",
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# Local clock helper — keeps the timestamp source in one place.
# ---------------------------------------------------------------------------


def datetime_now():
    """Return the current UTC-aware ``datetime``.

    Kept as a function (not a module-level constant) so a test
    seam can override ``app.state.clock`` the same way
    ``routers/privacy.py`` does.
    """
    from datetime import datetime, timezone

    return datetime.now(timezone.utc)


__all__ = [
    "delete_post_endpoint",
    "get_post_endpoint",
    "patch_post_endpoint",
    "post_post",
    "router",
]
