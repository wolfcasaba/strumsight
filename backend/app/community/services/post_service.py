"""Community post lifecycle service (E09-R11, ADR 0405).

The service layer for ``CommunityPost`` — owns the four lifecycle
operations: ``create_post`` / ``get_post`` / ``patch_post`` /
``soft_delete_post``. Every method on the service is a pure DB
operation; the HTTP / FastAPI wrapping lives in
``routers.posts``.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the routers and the tests pin):

* **Server-side author identity (§5.1, A1).** ``create_post`` takes
  the JWT-resolved ``author_public_id`` as a parameter — there is no
  body-side override path. The Pydantic ``CreatePostRequest`` does
  not carry an ``author_id`` field at all (``extra='forbid'`` would
  reject any smuggled value even if it did). A test in
  ``test_post_service.py::test_create_forged_author_ignored`` is the
  A1 measure-matrix cell.

* **Idempotent create (§5.2, A2).** ``create_post`` persists a
  unique constraint on ``(profile_id, idempotency_key)``. A retry
  with the same key lands on the existing row (the IntegrityError →
  re-read → return-existing pattern from ``follow_service.follow``).
  Posts without an ``idempotency_key`` are allowed — SQLite's
  UNIQUE-permissive NULL semantics keep the door open. The §6.1
  real-violation probe removes the idempotency check entirely and
  asserts that two creates with the same key produce two rows.

* **Audience + block + moderation gating (§3, §5.3, A3 / A4 / A6).**
  ``get_post`` and ``patch_post`` route through
  ``CommunityAccessPolicy.evaluate_content_access`` (Kör 4) and the
  Kör 8 ``is_blocked_pair`` predicate. Every "viewer may not see
  this" branch — not found, blocked, audience-excluded,
  soft-deleted, moderation-hidden — returns the D7 uniform 404.
  The §D7 invariant is that the response code itself never
  distinguishes "no such id" from "exists, hidden" — the brief
  §5.3 / SDD §28.6 IDOR guarantee.

* **Soft-delete idempotence (§0.0 D12).** A repeat ``DELETE`` on an
  already-deleted post is a successful no-op (the
  ``block``/``unblock`` precedent from ``routers/safety.py`` —
  DELETE is a "target state reached" operation, not a read of the
  IDOR-sensitive existence). PATCH on a deleted post is the D7
  404.

* **Optimistic concurrency (§0.0 D3, A5).** ``patch_post`` compares
  ``payload.resource_version`` (the client's last-seen ``updated_at``)
  with the row's current ``updated_at`` BEFORE the write. A
  mismatch raises ``StalePostUpdateError`` (→ 409 in the router).
  The single ``updated_at`` column is the version token — there is
  no separate ``version`` column (ADR 0398 §6 precedent, brief §0.0
  D3).

* **Injectable cache-invalidation seam (§0.0 D11).** Each mutating
  method accepts an optional ``on_invalidate: Callable[[CachedInvalidationEvent],
  None] | None = None`` parameter. When provided, the service
  emits one ``CachedInvalidationEvent`` AFTER a successful write —
  the privacy.py ``clock``-seam precedent (deterministic test
  injection, default ``None`` in production). A future round that
  adds a real cache layer wires the callback; this round ships the
  seam.

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  ``routers/privacy.py::update_privacy_settings`` — the timestamp
  the service uses to stamp ``created_at`` / ``updated_at`` /
  ``deleted_at`` is the caller's, never ``datetime.now(timezone.utc)``
  inline. The deterministic-timestamp discipline keeps the §6.1
  real-violation probe's two-create comparison free of
  microsecond drift.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.post import (
    MODERATION_STATE_VISIBLE,
    POST_BODY_MAX_LENGTH,
    CommunityPost,
)
from ..models.profile import CommunityProfile
from ..policies.access_policy import (
    CommunityAccessPolicy,
    CommunityAudience,
    relationship_context_from_block_flag,
)
from ..policies.query_filters import is_blocked_pair

# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class PostNotFound(Exception):
    """The post is not visible to this caller.

    This is the D7 uniform 404 — raised on every "no such post FOR
    YOU" branch: not found by id, blocked viewer, audience-
    excluded, soft-deleted, or moderation-removed. The HTTP layer
    cannot distinguish the cases from the exception type alone
    (deliberately — that is the §5.3 IDOR guarantee).
    """


class StalePostUpdateError(Exception):
    """The client's ``resource_version`` does not match the row's
    ``updated_at`` (brief §0.0 D3 / A5).

    Carries the current ``updated_at`` so the router can build a 409
    body that lets the client refresh and retry — same shape as the
    Kör 4 ``StalePrivacyUpdateError``.
    """

    def __init__(self, current_updated_at: datetime) -> None:
        super().__init__(
            f"stale resource_version; current={current_updated_at.isoformat()}"
        )
        self.current_updated_at = current_updated_at


# ---------------------------------------------------------------------------
# Cache-invalidation event (brief §0.0 D11).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class CachedInvalidationEvent:
    """Emitted by the mutating service methods on a successful write.

    The router / cache layer (Kör 13+) wires a real callback; this
    round ships the seam and the test seam. ``post_public_id`` is
    the post's public_id (the wire identity). ``action`` is one of
    ``"create"``, ``"patch"``, ``"delete"``.
    """

    post_public_id: uuid.UUID
    action: str  # "create" | "patch" | "delete"


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read (no native tz-aware column
    type), so a ``DateTime(timezone=True)`` value that came back from
    ``session.get()`` is naive. The migration contract says the
    column stores UTC, so we re-attach ``timezone.utc`` here for
    comparison and serialization. PostgreSQL keeps tzinfo on the
    round-trip; the ``replace`` is then a no-op.
    """
    if value.tzinfo is None:
        return (
            value.replace(tzinfo=datetime.UTC)
            if hasattr(datetime, "UTC")
            else value.replace(tzinfo=_UTC())
        )
    return value


def _UTC():
    from datetime import timezone as _tz

    return _tz.utc


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _existing_post_by_idempotency_key(
    db: Session, *, profile_id: int, idempotency_key: str | None
) -> CommunityPost | None:
    """Return the existing row matching ``(profile_id, idempotency_key)``.

    Returns ``None`` if no row matches — including the case where
    the caller's key is ``None`` (the first-call path; subsequent
    calls with the same ``None`` still return ``None`` because the
    column allows multiple NULL rows, which is the §D4 "post WITHOUT
    a key may be created multiple times" invariant).
    """
    if idempotency_key is None:
        return None
    return (
        db.query(CommunityPost)
        .filter(
            CommunityPost.profile_id == profile_id,
            CommunityPost.idempotency_key == idempotency_key,
        )
        .one_or_none()
    )


def _evaluate_visibility(
    db: Session,
    *,
    post: CommunityPost,
    viewer_profile_id: int | None,
) -> None:
    """Raise :class:`PostNotFound` if the viewer may not see ``post``.

    Implements the D7 uniform 404 — blocked, audience-excluded,
    soft-deleted, and moderation-removed all collapse to the same
    exception type. The viewer is the owner when
    ``viewer_profile_id == post.profile_id`` (the §owner short-circuit
    in :class:`CommunityAccessPolicy`).

    A ``viewer_profile_id`` of ``None`` indicates the caller has
    not authenticated / has no community profile — such a viewer can
    only see ``PUBLIC`` posts that are not soft-deleted and not
    moderation-hidden. This is the §8 "anonymous read" branch that
    matches the Kör 2/4 precedent (``CommunityPrivacySettings`` is
    owner-only).
    """
    if post.deleted_at is not None:
        # D7 — soft-deleted posts are uniformly invisible.
        raise PostNotFound("post is not visible")
    if post.moderation_state != MODERATION_STATE_VISIBLE:
        # D7 / D8 — non-visible moderation state is also invisible
        # through the public endpoint.
        raise PostNotFound("post is not visible")

    if viewer_profile_id is None:
        # Anonymous viewer — only PUBLIC posts.
        audience = _audience_from_value(post.audience)
        if audience is not CommunityAudience.PUBLIC:
            raise PostNotFound("post is not visible")
        return

    viewer_is_owner = viewer_profile_id == post.profile_id
    blocked = is_blocked_pair(
        db,
        profile_id_a=viewer_profile_id,
        profile_id_b=post.profile_id,
    )
    # The Kör 11 surface has no follow / club membership yet — the
    # RelationshipContext carries ``is_follower=False`` /
    # ``is_club_member=False`` (the §3 "no club check" invariant;
    # Kör 24 will populate them).
    relationship = relationship_context_from_block_flag(
        blocked=blocked,
        viewer_is_owner=viewer_is_owner,
        is_follower=False,
        is_club_member=False,
    )
    audience = _audience_from_value(post.audience)
    policy = CommunityAccessPolicy()
    if not policy.evaluate_content_access(audience, relationship):
        raise PostNotFound("post is not visible")


def _audience_from_value(value: str) -> CommunityAudience:
    """Translate a string ``audience`` column to the enum.

    Defensive — the DB layer does not constrain the value set
    (project-wide ``visibility`` pattern, ADR 0398 §1). An
    unexpected value falls through to ``PRIVATE`` so the policy
    short-circuits to "not visible" (the safe default; same
    fallback as ``follow_service._is_private``).
    """
    try:
        return CommunityAudience(value)
    except ValueError:
        return CommunityAudience.PRIVATE


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def create_post(
    db: Session,
    *,
    author_public_id: uuid.UUID,
    audience: CommunityAudience,
    body: str,
    idempotency_key: str | None,
    club_id: int | None = None,
    artifact: dict[str, Any] | None = None,
    now: datetime,
    on_invalidate: Callable[[CachedInvalidationEvent], None] | None = None,
) -> CommunityPost:
    """Create (or recycle) a post.

    Server-side author (brief §5.1): the ``author_public_id`` comes
    from the JWT, not the request body. Idempotent on
    ``(profile_id, idempotency_key)``: a retry returns the existing
    row without raising (brief §5.2 / §0.0 D4).

    The artifact, when supplied, is the Pydantic-roundtripped
    dict from ``schemas.post._validate_artifact`` — the service
    re-parses it to mirror ``.type`` and ``.schema_version`` into
    the typed sibling columns (brief §0.0 D10). An explicit
    ``artifact=None`` means "no artifact on this post".

    ``now`` is the timestamp the row is stamped with (the Kör 4
    privacy-row precedent — caller-supplied for deterministic
    tests).

    Raises :class:`ValueError` when the author's community profile
    is missing (no JWT-resolvable profile → the onboarding flow is
    upstream).
    """
    if len(body) > POST_BODY_MAX_LENGTH:
        # Defensive — the Pydantic layer should already have
        # rejected this. Duplicating the guard here keeps the
        # service callable directly from non-router code paths.
        raise ValueError(f"body exceeds {POST_BODY_MAX_LENGTH} characters")
    author = _resolve_profile_by_public_id(db, author_public_id)
    if author is None:
        raise ValueError("author community profile not found")

    existing = _existing_post_by_idempotency_key(
        db, profile_id=author.id, idempotency_key=idempotency_key
    )
    if existing is not None:
        # Idempotent retry — return the existing row. The cache-
        # invalidation event is NOT re-emitted (a retry is a no-op
        # from the cache's perspective; the row is unchanged).
        return existing

    artifact_type: str | None = None
    artifact_schema_version: int | None = None
    artifact_payload: dict[str, Any] | None = None
    if artifact is not None:
        # Re-parse the validated artifact to read the typed fields.
        # parse_share_artifact would raise ValidationError on a bad
        # payload, but the value has already been through the
        # schema layer; this is a defensive round-trip.
        from ..schemas.artifacts import parse_share_artifact

        envelope = parse_share_artifact(artifact)
        concrete = envelope.artifact
        artifact_type = concrete.type  # type: ignore[attr-defined]
        # ``schema_version`` is ``StrictInt`` in Pydantic — cast to
        # plain int for the DB column (Integer, not BigInteger).
        artifact_schema_version = int(concrete.schema_version)  # type: ignore[attr-defined]
        artifact_payload = envelope.model_dump(mode="json")

    post = CommunityPost(
        profile_id=author.id,
        audience=audience.value,
        club_id=club_id,
        body=body,
        artifact_type=artifact_type,
        artifact_schema_version=artifact_schema_version,
        artifact_payload=artifact_payload,
        moderation_state=MODERATION_STATE_VISIBLE,
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
    )
    db.add(post)
    try:
        db.flush()
    except IntegrityError:
        # Race: a concurrent writer landed between the
        # idempotency-key read and our INSERT. Re-read and return
        # the winner's row.
        db.rollback()
        again = _existing_post_by_idempotency_key(
            db, profile_id=author.id, idempotency_key=idempotency_key
        )
        if again is not None:
            return again
        # The IntegrityError was on a DIFFERENT constraint (most
        # likely the CHECK on a future column). Re-raise so the
        # caller surfaces a 500 — the A2 measure-matrix is about
        # the idempotency key specifically, not unrelated
        # constraints.
        raise

    if on_invalidate is not None:
        on_invalidate(
            CachedInvalidationEvent(post_public_id=post.public_id, action="create")
        )
    return post


def get_post(
    db: Session,
    *,
    post_public_id: uuid.UUID,
    viewer_profile_id: int | None,
) -> CommunityPost:
    """Return the post if the viewer may see it; otherwise D7 404.

    The function never raises to distinguish "no such id" from
    "exists, but not visible" — the §5.3 IDOR invariant.

    ``viewer_profile_id`` is the internal bigint PK (the same
    surface the Kör 8 ``is_blocked_pair`` operates on). Passing
    ``None`` models an anonymous viewer (only PUBLIC posts visible,
    and only when not soft-deleted / moderation-removed).
    """
    post = db.query(CommunityPost).filter_by(public_id=post_public_id).one_or_none()
    if post is None:
        raise PostNotFound("post not found")
    _evaluate_visibility(db, post=post, viewer_profile_id=viewer_profile_id)
    return post


def patch_post(
    db: Session,
    *,
    post_public_id: uuid.UUID,
    viewer_profile_id: int,
    payload: dict[str, Any],
    now: datetime,
    on_invalidate: Callable[[CachedInvalidationEvent], None] | None = None,
) -> CommunityPost:
    """Apply a partial update to the post.

    The caller is the router, after it has already verified the
    JWT and resolved the internal profile PK. ``payload`` is the
    Pydantic-parsed ``PatchPostRequest.model_dump()`` so the schema
    layer has already validated ``extra='forbid'``, HTML, mentions,
    and the artifact discriminator.

    Optimistic concurrency (brief §0.0 D3 / A5): the caller's
    ``resource_version`` (a ``datetime``) must match the row's
    current ``updated_at`` — otherwise :class:`StalePostUpdateError`
    is raised and the router returns 409. ``updated_at`` is then
    bumped to ``now``.

    Visibility (brief §5.3, D7): the post must exist AND the
    viewer must pass the audience / block / moderation gate —
    otherwise :class:`PostNotFound` is raised and the router
    returns 404 (the uniform IDOR-safe shape).

    The ``artifact`` field uses Pydantic's ``model_fields_set``
    semantic: a value of ``None`` set explicitly clears the
    post's artifact; an absent field leaves the existing value
    intact. The router is responsible for passing the right
    payload-shape; this service treats both as "write what the
    payload says" — the only field with explicit clear semantics
    is ``artifact`` because a Pydantic ``None`` is a valid
    no-artifact state and indistinguishable from "not in payload"
    without ``model_fields_set``.
    """
    post = db.query(CommunityPost).filter_by(public_id=post_public_id).one_or_none()
    if post is None:
        raise PostNotFound("post not found")
    # Visibility check BEFORE the optimistic-concurrency check: a
    # non-owner / non-visible viewer must not learn whether their
    # resource_version token is "stale" (that would leak the row's
    # update timing — a side channel the §5.3 IDOR guarantee
    # forecloses).
    _evaluate_visibility(db, post=post, viewer_profile_id=viewer_profile_id)

    # Optimistic concurrency (A5).
    if _as_utc(payload["resource_version"]) != _as_utc(post.updated_at):
        raise StalePostUpdateError(_as_utc(post.updated_at))

    if "audience" in payload and payload["audience"] is not None:
        audience_value = payload["audience"]
        post.audience = (
            audience_value.value
            if isinstance(audience_value, CommunityAudience)
            else str(audience_value)
        )
    if "body" in payload and payload["body"] is not None:
        post.body = payload["body"]
    if "artifact" in payload:
        # ``artifact`` carries the explicit-clear semantic: ``None``
        # clears, a dict re-parses and persists.
        if payload["artifact"] is None:
            post.artifact_type = None
            post.artifact_schema_version = None
            post.artifact_payload = None
        else:
            from ..schemas.artifacts import parse_share_artifact

            envelope = parse_share_artifact(payload["artifact"])
            concrete = envelope.artifact
            post.artifact_type = concrete.type  # type: ignore[attr-defined]
            post.artifact_schema_version = int(concrete.schema_version)  # type: ignore[attr-defined]
            post.artifact_payload = envelope.model_dump(mode="json")

    post.updated_at = now
    db.flush()
    db.refresh(post)

    if on_invalidate is not None:
        on_invalidate(
            CachedInvalidationEvent(post_public_id=post.public_id, action="patch")
        )
    return post


def soft_delete_post(
    db: Session,
    *,
    post_public_id: uuid.UUID,
    viewer_profile_id: int,
    now: datetime,
    on_invalidate: Callable[[CachedInvalidationEvent], None] | None = None,
) -> bool:
    """Soft-delete the post. Returns ``True`` when a transition
    happened, ``False`` when the post was already deleted (D12).

    Idempotent on a soft-deleted post: a repeat DELETE is a
    successful no-op (the ``block``/``unblock`` precedent). The
    audit-vs-D7 tension here is resolved by the §0.0 D12 note:
    DELETE is "target state reached", not a read, so it does
    NOT need the uniform 404 treatment — but it DOES need the
    owner check (a non-owner cannot delete someone else's post
    and learn the deletion state from a 404-vs-200 split).

    Non-owner / non-existent post → :class:`PostNotFound` (D7).
    Soft-deleted post → returns ``False`` silently, no event
    (D12 idempotent no-op).

    Cache invalidation is emitted only on the actual transition
    (i.e. when ``True`` is returned).
    """
    post = db.query(CommunityPost).filter_by(public_id=post_public_id).one_or_none()
    if post is None:
        raise PostNotFound("post not found")
    # Owner-only delete: a non-owner must NOT learn whether the
    # post exists (the §5.3 IDOR guarantee applies to DELETE too
    # — a 200-vs-404 split on someone else's id would leak the
    # existence + ownership boundary).
    if post.profile_id != viewer_profile_id:
        raise PostNotFound("post not found")

    if post.deleted_at is not None:
        # Already soft-deleted — D12 idempotent no-op. No event.
        return False

    post.deleted_at = now
    post.updated_at = now
    db.flush()
    db.refresh(post)

    if on_invalidate is not None:
        on_invalidate(
            CachedInvalidationEvent(post_public_id=post.public_id, action="delete")
        )
    return True


__all__ = [
    "CachedInvalidationEvent",
    "PostNotFound",
    "StalePostUpdateError",
    "create_post",
    "get_post",
    "patch_post",
    "soft_delete_post",
]
