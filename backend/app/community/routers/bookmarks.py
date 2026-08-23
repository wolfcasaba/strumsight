"""Community bookmarks router (E09-R17, ADR 0408).

The HTTP surface for the private "saved by me" list, plus the
idempotent set / remove endpoints. Per the §5.2 invariant, the
bookmark *count* is NEVER projected onto the public ``PostOut`` —
the bookmark is private to the viewer/post pair and is consumed
only by the Flutter ``BookmarksScreen``.

The router and the service logic live in ONE file (no
``bookmark_service.py``) — the brief's ``allowed_paths`` for this
round is exactly three backend files
(``models/bookmark.py``, ``routers/bookmarks.py``, the migration),
and §8 implementation order puts the service-level logic
immediately after the model, inside the router module. The
companion test file ``tests/community/test_bookmark_service.py``
imports the service-shaped functions and the ``router`` from this
module — same seam the existing ``test_post_service.py`` uses
against ``routers.posts.router``.

The four operational rules (the §6 / §5 invariants — these are the
load-bearing guarantees the tests pin):

* **Server-side viewer identity (§5.1).** ``set_bookmark`` /
  ``remove_bookmark`` / ``list_bookmarks`` take the JWT-resolved
  ``viewer_public_id`` as a parameter — there is no body-side
  override path. The ``(post_id, profile_id)`` UNIQUE constraint is
  the canonical identity anchor.

* **Idempotent set / UNIQUE(post, profile) (§6 A1).** The pair
  ``UNIQUE(post_id, profile_id)`` enforces that a retry with the
  same (post, viewer) lands on the existing row, never a second
  row. The service catches ``IntegrityError`` and re-reads the
  row. The §6.1 valódi-sértés próba drops the constraint and
  asserts that two ``set_bookmark`` calls land two rows (the A1
  cell turns red).

* **Private count (§5.2, A2).** The bookmark count is NEVER
  projected onto ``PostOut`` / the feed card. A2 is enforced
  structurally — this module never returns a count, the schema
  never carries one, and the §6.1 valódi-sértés próba asserts the
  public post response does not contain a bookmark-count field.

* **Tombstone on soft-deleted / moderation-removed post (§6 A3).**
  ``list_bookmarks`` returns a tombstone element when the joined
  post is soft-deleted OR its ``moderation_state != 'visible'``.
  The row is NOT removed (the UNIQUE/pair stays — a future
  retention-policy hard-delete cleans up the bookmark via
  ``ON DELETE CASCADE``). The tombstone is a structured payload
  with a discriminator the Flutter ``BookmarksScreen`` reads to
  render a "this content is no longer available" state — no null
  deref, no crash.

* **Caller-supplied clock (``now: datetime``).** The same
  precedent as ``routers/privacy.py::update_privacy_settings``,
  ``services/post_service.create_post`` and
  ``services/reaction_service.set_reaction`` — the timestamp the
  service uses to stamp ``created_at`` is the caller's, never
  ``datetime.now(timezone.utc)`` inline. The deterministic-
  timestamp discipline keeps the §6.1 valódi-sértés próba and the
  A1 idempotent-retry test free of microsecond drift.

Cursor pagination (§0.0 D4, the brief's D4 decision): the
``list_bookmarks`` cursor is a simple base64-encoded
``(created_at, id)`` keyset — the bookmark list is always
caller-scoped (no adversarial pagination — there is no other-
user surface), so a non-HMAC cursor is sufficient. The encoder
mirrors ``services/comment_service._encode_cursor`` / the
decoder mirrors ``_decode_cursor`` (the Kör 8
``list_blocked`` / Kör 16 ``list_comments`` precedent). A tampered
cursor decodes to ``None`` and the list starts from the top — the
list endpoint never crashes.
"""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import Iterator
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..models.bookmark import CommunityBookmark
from ..models.post import CommunityPost

router = APIRouter(prefix="/community/bookmarks", tags=["community-bookmarks"])


# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class BookmarkPostNotFound(Exception):
    """The bookmark target post is not visible to the caller (or
    does not exist).

    Mirrors the D7 uniform-404 shape — a missing id, a soft-deleted
    post, or a moderation-removed post all collapse to the same
    exception. The §5.3 IDOR guarantee.
    """


class BookmarkViewerNotFound(Exception):
    """The JWT-resolved viewer has no community profile.

    Same shape as ``post_service.create_post``'s ``ValueError("author
    community profile not found")`` — a 404 is the correct response
    because the viewer IS authenticated but has not completed the
    Community onboarding flow.
    """


# ---------------------------------------------------------------------------
# Pydantic schemas — defined inline (no separate ``schemas/`` file is
# on this round's ``allowed_paths``). The wire shape intentionally
# omits the bookmark *count* (the §5.2 invariant).
# ---------------------------------------------------------------------------


# The bookmark pair is a binary existence predicate; the only state
# the wire surface needs to know is "you saved this post, at this
# timestamp, and the joined post is / is not a tombstone". The
# post-public-id is the join key the Flutter ``BookmarksScreen``
# uses to deep-link back into the post detail.
class BookmarkOut(BaseModel):
    """Outbound shape for a single bookmark in the caller's list.

    The internal ``id`` / ``profile_id`` are deliberately NOT in
    this schema — the wire shape only ever carries public
    identifiers (ADR 0396 §1 invariant). The ``bookmark_id`` is
    the row's internal id (used as the cursor's row_id component),
    so the Flutter screen can drop / re-issue pages without a
    second round-trip.

    The ``is_tombstone`` flag is the A3 surface: a ``True`` row is
    a soft-deleted or moderation-removed post. The Flutter
    ``BookmarksScreen`` renders the corresponding
    "content-no-longer-available" state for that row — the bookmark
    is preserved (the user explicitly asked for it), but the
    content side is gone.
    """

    model_config = ConfigDict(extra="forbid")

    bookmark_id: int = Field(..., description="Internal row id (cursor key).")
    post_public_id: uuid.UUID = Field(
        ..., description="The bookmarked post's public UUID."
    )
    created_at: datetime
    is_tombstone: bool = Field(
        ...,
        description="True when the joined post is soft-deleted or moderation-removed.",
    )


class BookmarkListResponse(BaseModel):
    """The cursor-paginated list response (D4 cursor keyset)."""

    model_config = ConfigDict(extra="forbid")

    items: list[BookmarkOut]
    next_cursor: str | None = None


class BookmarkMutationResponse(BaseModel):
    """The set / remove response (idempotent on either side)."""

    model_config = ConfigDict(extra="forbid")

    status: Literal["ok", "noop"]
    post_public_id: uuid.UUID


# ---------------------------------------------------------------------------
# Cursor pagination helpers — base64 ``(created_at, id)`` keyset, the
# Kör 8 ``list_blocked`` / Kör 16 ``list_comments`` precedent.
# ---------------------------------------------------------------------------


def _encode_cursor(created_at: datetime, row_id: int) -> str:
    """Encode a ``(created_at, row_id)`` cursor as base64 JSON.

    The cursor is opaque to the caller; a tampered cursor decodes
    back to ``None`` and the list restarts from the top — the A1
    invariant the §6.1 measure-matrix relies on (a tampered cursor
    must NOT crash the list endpoint).
    """
    payload = {"created_at": created_at.isoformat(), "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> tuple[datetime, int] | None:
    """Decode a cursor produced by ``_encode_cursor``; bad input → ``None``."""
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        created_at = datetime.fromisoformat(payload["created_at"])
        row_id = int(payload["id"])
        return created_at, row_id
    except (ValueError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    from datetime import timezone

    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read (no native tz-aware column
    type), so a ``DateTime(timezone=True)`` value that came back
    from ``session.get()`` is naive. The migration contract says
    the column stores UTC, so we re-attach ``timezone.utc`` here
    for comparison and serialization.
    """
    if value.tzinfo is None:
        from datetime import timezone as _tz

        return value.replace(tzinfo=_tz.utc)
    return value


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity.

    Identical seam to the existing community routers (the
    self-contained test app in
    ``backend/tests/community/conftest.py`` populates
    ``app.state.session_factory`` so we read the same way the
    production wiring will).
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
    fn = getattr(request.app.state, "bookmarks_commit", _default_commit)
    fn(db)


def _resolve_profile_by_public_id(db: Session, public_id: uuid.UUID):
    """Return the ``CommunityProfile`` row matching ``public_id``, or ``None``.

    Local import keeps the module's import surface tight — the
    profile model is shared with the other community routers.
    """
    from ..models.profile import CommunityProfile

    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _resolve_post_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityPost | None:
    return db.query(CommunityPost).filter_by(public_id=public_id).one_or_none()


def _existing_bookmark(
    db: Session, *, post_id: int, profile_id: int
) -> CommunityBookmark | None:
    """Return the existing live row matching ``(post_id, profile_id)``.

    Soft-deleted posts are NOT excluded here — soft-delete leaves
    the bookmark in place (the §A3 tombstone; the list query is
    responsible for emitting the tombstone element). The check is
    purely on the ``(post_id, profile_id)`` pair.
    """
    return (
        db.query(CommunityBookmark)
        .filter(
            CommunityBookmark.post_id == post_id,
            CommunityBookmark.profile_id == profile_id,
        )
        .one_or_none()
    )


def _post_visible(post: CommunityPost) -> bool:
    """Mirror of the D7 uniform-404 helper (post service shape).

    A post is "visible" when it is NOT soft-deleted AND has a
    visible moderation state. The audience / block check is the
    future post-projection's job — the bookmark service only needs
    to know "does the row exist and is the post itself visible" so
    the bookmark write doesn't end up attached to a tombstone.
    """
    if post.deleted_at is not None:
        return False
    if post.moderation_state != "visible":
        return False
    return True


# ---------------------------------------------------------------------------
# Service surface — the public functions the test file imports.
# ---------------------------------------------------------------------------


# Default page size for the bookmark list. The D4 cursor keyset
# makes the page size a soft cap (the next page is a single
# additional round-trip), so the constant is conservative — the
# Flutter screen renders up to 20 rows on one screenful.
DEFAULT_BOOKMARK_PAGE_SIZE: int = 20

# Hard cap on the requested page size, so a tampered
# ``?limit=1000000`` cannot exhaust the renderer. The cap mirrors
# the Kör 16 comment-list cap.
MAX_BOOKMARK_PAGE_SIZE: int = 50


def set_bookmark(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
    now: datetime,
) -> CommunityBookmark:
    """Set the viewer's bookmark on a post (idempotent, §6 A1).

    Server-side viewer (brief §5.1): ``viewer_public_id`` is the
    JWT-resolved identity. The body-side contract has no
    ``viewer_id`` field; the function does not consult any request
    body for it.

    Idempotent on ``(post_id, profile_id)`` (§6 A1): a retry with
    the same (post, viewer) lands on the existing row, never a
    second row. The UNIQUE constraint is the source of truth for
    idempotency; the service catches ``IntegrityError`` and re-
    reads the row.

    The post must be visible (not soft-deleted, moderation-state =
    visible). A missing / soft-deleted / moderation-removed post
    raises :class:`BookmarkPostNotFound` — the §5.3 D7 uniform
    404.

    ``now`` is the timestamp the row is stamped with — the
    caller-supplied clock precedent (privacy / post / reaction /
    comment service).

    Raises :class:`BookmarkViewerNotFound` when the viewer's
    community profile is missing; :class:`BookmarkPostNotFound`
    when the post is not visible.
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        raise BookmarkViewerNotFound("viewer community profile not found")

    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None or not _post_visible(post):
        raise BookmarkPostNotFound("post not found")

    existing = _existing_bookmark(db, post_id=post.id, profile_id=viewer.id)
    if existing is not None:
        # Same (post, viewer) — no-op. The A1 idempotent retry MUST
        # NOT change row identity; ``created_at`` is preserved, the
        # row is returned unchanged.
        return existing

    row = CommunityBookmark(
        post_id=post.id,
        profile_id=viewer.id,
        created_at=now,
    )
    db.add(row)
    try:
        db.flush()
    except Exception:
        # A concurrent writer landed between the existing-read and
        # the INSERT. Re-read and translate the IntegrityError to a
        # no-op re-read of the existing row (the A1 idempotent
        # retry path).
        db.rollback()
        again = _existing_bookmark(db, post_id=post.id, profile_id=viewer.id)
        if again is None:
            # The error was on a DIFFERENT constraint (most likely
            # the FK on a future column). Re-raise so the caller
            # surfaces a 500.
            raise
        return again
    db.refresh(row)
    return row


def remove_bookmark(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
) -> bool:
    """Remove the viewer's bookmark on a post (idempotent, §6 A3).

    Returns ``True`` when a transition happened (a row was
    deleted), ``False`` when the viewer had no bookmark on this
    post (no-op). The count never goes negative — the DELETE
    removes an existing row, and a second DELETE finds zero rows
    to remove.

    A missing viewer / missing post is a no-op ``False``, not an
    exception — there is nothing to remove; the caller already
    saw the post not visible and we don't want a 404 / no-op
    mismatch (the §5.3 D7 invariant only applies to the WRITE
    surface, not the unbookmark READ+DELETE surface).
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        return False
    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        return False

    existing = _existing_bookmark(db, post_id=post.id, profile_id=viewer.id)
    if existing is None:
        return False
    db.delete(existing)
    db.flush()
    return True


def list_bookmarks(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> BookmarkListResponse:
    """List the viewer's bookmarks with cursor pagination (§0.0 D4).

    The list is ALWAYS caller-scoped (no other-user surface — the
    bookmark is private to the viewer/post pair per §5.2). The
    cursor is a base64 ``(created_at, row_id)`` keyset, ordered
    ``(created_at DESC, id DESC)`` — the Kör 8 ``list_blocked`` /
    Kör 16 ``list_comments`` precedent.

    The §6 A3 tombstone invariant: a soft-deleted or moderation-
    removed post is NOT removed from the list — the bookmark row
    stays (the user explicitly asked to save it), and the row is
    emitted with ``is_tombstone=True`` so the Flutter
    ``BookmarksScreen`` can render the "no longer available"
    state. A hard-delete (the future retention policy) would
    cascade through ``ON DELETE CASCADE`` and the row would drop
    out of the list.

    A tampered cursor decodes to ``None`` and the list starts
    from the top — the A3 invariant (the list never crashes on
    a bad cursor).
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        return BookmarkListResponse(items=[], next_cursor=None)

    page_size = max(1, min(limit, MAX_BOOKMARK_PAGE_SIZE))

    decoded = _decode_cursor(cursor) if cursor else None

    # The cursor keyset is ``(created_at DESC, id DESC)`` keyed on
    # the viewer's profile id. The (profile_id, created_at, id)
    # composite index on the table backs the read — see the model
    # docstring for the planner rationale.
    query = (
        db.query(CommunityBookmark, CommunityPost)
        .outerjoin(CommunityPost, CommunityPost.id == CommunityBookmark.post_id)
        .filter(CommunityBookmark.profile_id == viewer.id)
    )
    if decoded is not None:
        cursor_created_at, cursor_id = decoded
        cursor_created_at = _as_utc(cursor_created_at)
        # ``(created_at, id) DESC`` keyset — the next row has a
        # strictly older created_at OR the same created_at with a
        # strictly smaller id.
        query = query.filter(
            _sa_text(
                "(community_bookmarks.created_at, community_bookmarks.id) < "
                "(:cursor_created_at, :cursor_id)"
            ).bindparams(cursor_created_at=cursor_created_at, cursor_id=cursor_id)
        )

    query = query.order_by(
        CommunityBookmark.created_at.desc(), CommunityBookmark.id.desc()
    ).limit(page_size + 1)

    rows = query.all()
    has_more = len(rows) > page_size
    page_rows = rows[:page_size]

    items: list[BookmarkOut] = []
    last_created_at: datetime | None = None
    last_id: int | None = None
    for bookmark, post in page_rows:
        # A missing post row (the LEFT OUTER JOIN's null branch) is
        # impossible given the FK + ``ON DELETE CASCADE`` — the
        # post row goes with the bookmark row, in the same
        # transaction. The fallback ``is_tombstone=True`` is the
        # safe default for any future FK-shape change.
        is_tombstone = True
        if post is not None:
            is_tombstone = (post.deleted_at is not None) or (
                post.moderation_state != "visible"
            )
        items.append(
            BookmarkOut(
                bookmark_id=bookmark.id,
                post_public_id=post.public_id if post is not None else uuid.UUID(int=0),
                created_at=_as_utc(bookmark.created_at),
                is_tombstone=is_tombstone,
            )
        )
        last_created_at = bookmark.created_at
        last_id = bookmark.id

    next_cursor: str | None = None
    if has_more and last_created_at is not None and last_id is not None:
        next_cursor = _encode_cursor(_as_utc(last_created_at), last_id)

    return BookmarkListResponse(items=items, next_cursor=next_cursor)


# ---------------------------------------------------------------------------
# HTTP endpoints — wire the service surface to FastAPI.
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


def _resolve_viewer_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Return the JWT subject's community profile public_id."""
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
# POST /community/bookmarks/{post_public_id} — set (idempotent)
# ---------------------------------------------------------------------------


@router.post("/{post_public_id}", status_code=status.HTTP_200_OK)
def set_bookmark_endpoint(
    post_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> BookmarkMutationResponse:
    """Save a post to the caller's bookmark list (idempotent on retry).

    The endpoint is the private-save surface: the bookmark row
    exists or it does not, and a retry of this endpoint never
    inflates the underlying row count (the §6 A1 invariant). The
    response's ``status`` field is always ``"ok"`` for a
    successful call (the underlying transition is recorded in the
    response time, not in the body — the bookmark is a binary
    existence predicate).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_public_id = _resolve_viewer_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                set_bookmark(
                    db,
                    viewer_public_id=viewer_public_id,
                    post_public_id=post_public_id,
                    now=_utcnow(),
                )
            except BookmarkViewerNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except BookmarkPostNotFound:
                db.rollback()
                raise HTTPException(status_code=404, detail="post not found") from None
            _commit_via(request, db)
        except HTTPException:
            raise
        return BookmarkMutationResponse(status="ok", post_public_id=post_public_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/bookmarks/{post_public_id} — remove (idempotent)
# ---------------------------------------------------------------------------


@router.delete("/{post_public_id}", status_code=status.HTTP_200_OK)
def remove_bookmark_endpoint(
    post_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> BookmarkMutationResponse:
    """Remove a post from the caller's bookmark list (idempotent on retry).

    Returns ``{"status": "ok", ...}`` on a real transition (a row
    was deleted) and ``{"status": "noop", ...}`` on a no-op (the
    bookmark was already absent). The §6 A3 invariant: a second
    DELETE returns ``noop`` without raising.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_public_id = _resolve_viewer_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            transitioned = remove_bookmark(
                db,
                viewer_public_id=viewer_public_id,
                post_public_id=post_public_id,
            )
            _commit_via(request, db)
        except HTTPException:
            raise
        return BookmarkMutationResponse(
            status="ok" if transitioned else "noop",
            post_public_id=post_public_id,
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/bookmarks — list the caller's bookmarks
# ---------------------------------------------------------------------------


@router.get("", status_code=status.HTTP_200_OK)
def list_bookmarks_endpoint(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = None,
    limit: int = DEFAULT_BOOKMARK_PAGE_SIZE,
) -> BookmarkListResponse:
    """List the caller's saved posts (cursor-paginated, D4 keyset).

    A soft-deleted or moderation-removed post appears with
    ``is_tombstone: true`` so the Flutter ``BookmarksScreen`` can
    render the corresponding "content no longer available" state
    (the §6 A3 invariant). A tampered cursor restarts the list
    from the top — the list never crashes on bad input.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_public_id = _resolve_viewer_public_id(db, current_user.id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            return list_bookmarks(
                db,
                viewer_public_id=viewer_public_id,
                cursor=cursor,
                limit=limit,
            )
        except HTTPException:
            raise
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "BookmarkListResponse",
    "BookmarkMutationResponse",
    "BookmarkOut",
    "BookmarkPostNotFound",
    "BookmarkViewerNotFound",
    "DEFAULT_BOOKMARK_PAGE_SIZE",
    "MAX_BOOKMARK_PAGE_SIZE",
    "list_bookmarks",
    "list_bookmarks_endpoint",
    "remove_bookmark",
    "remove_bookmark_endpoint",
    "router",
    "set_bookmark",
    "set_bookmark_endpoint",
]


# ---------------------------------------------------------------------------
# Re-exports for the §6.1 measure-matrix — the A2 (count not in
# PostOut) cell is enforced at the schema level (``PostOut`` does
# not carry a bookmark count field). The bookmark module never
# imports ``schemas.post.PostOut``; the §5.2 invariant is
# structural — this module returns no count, and the post module
# is on a sibling's allowed_paths. A grep over the diff for
# ``bookmark_count`` / ``bookmarkCount`` is the §6.1 probe.
# ---------------------------------------------------------------------------

_ = Any  # silence "Any imported but unused" on platforms that
# strip type-checking annotations in production builds. The
# annotation is used by the test file's static type-checks.
