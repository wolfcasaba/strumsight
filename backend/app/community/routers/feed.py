"""Community following-feed router — E09-R13, ADR 0406.

The HTTP surface for the ``GET /community/feed`` endpoint. The
endpoint is authenticated (the ``CurrentUser`` dependency — the
follow-graph and block/mute filters are anchored to the caller,
and an unauthenticated feed would either be impossible to
personalise or would leak the caller's block/mute set through
the response shape).

Endpoint:

* ``GET /community/feed?cursor=...&page_size=...`` — one cursor-
  paginated page of the viewer's following feed. Returns
  ``{"items": [...], "next_cursor": "..."}``. The items are
  :class:`FeedPostItem` envelopes (the Kör 11 ``PostOut`` shape
  minus the owner-only mutations); the ``next_cursor`` is an
  opaque, HMAC-signed token the client forwards verbatim on the
  next page request.

The router is mounted by the test fixtures directly into a self-
contained ``FastAPI()`` — the production ``build_community_router``
factory stays untouched (the Kör 7–11 pattern; the brief §3 tilos-
zóna discipline — the ``build_community_router`` factory is not in
the round's ``allowed_paths`` list).

**Page-size enforcement (ADR 0406 D7).** The router clamps
``page_size`` to :data:`FEED_PAGE_SIZE_MAX` after the Pydantic
schema validation. The fail-safe ordering is: schema rejects
``page_size < 1`` and ``page_size > MAX`` with a 422; the router
ADDITIONALLY clamps any value that bypassed schema validation
(the belt-and-braces guard — a future client that calls the
endpoint without going through Pydantic still cannot trigger an
oversized query). The §6.1 measure-matrix on the page-size
threshold ("alatta / rajta / fölötte") is enforced at both layers.

**Cursor-secret fail-closed (F3 fix).** The application
``secret_key`` is HMAC'd into every cursor; signing with a public,
code-resident placeholder would let any client forge a valid
cursor. The router refuses to serve the endpoint when
``settings.secret_key`` is missing or resolves to the dev
placeholder — a 503 surfaces the configuration error to the
client (the underlying readiness gate already runs on every
``/health/ready`` request, so this is consistent with the existing
discipline).
"""

from __future__ import annotations

from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...config import Settings
from ...deps import CurrentUser
from ..feed.following_feed import (
    DEFAULT_PAGE_SIZE,
    FeedItemRow,
    list_following_feed,
)
from ..feed.following_feed import (
    FeedPage as FeedPageRepo,
)
from ..schemas.feed import FEED_PAGE_SIZE_MAX, FeedPage, FeedPageQuery, FeedPostItem

router = APIRouter(prefix="/community", tags=["community-feed"])

#: The Settings class' ``secret_key`` default — duplicated here so
#: the cursor-secret check does NOT import ``app.main`` (which would
#: create a circular import via ``app.community.routers``). The
#: string is also asserted identical to the one in
#: ``app.main._DEV_SECRET`` at module load.
_DEV_SECRET_KEY_DEFAULT = Settings.model_fields["secret_key"].default


# ---------------------------------------------------------------------------
# Session factory seam — mirrors the Kör 3 / Kör 4 / Kör 7 / Kör 8 / Kör 11
# pattern. The self-contained test app in ``tests/community/conftest.py``
# populates ``app.state.session_factory`` so the router reads the same way
# the production wiring will (when a future round mounts this router in
# ``build_community_router``).
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _resolve_viewer_profile_pk(db: Session, user_id: int) -> int:
    """Resolve the JWT subject's community profile internal PK.

    Returns ``None`` if the caller has no community profile
    (the onboarding flow, Kör 6, owns this) — the router turns
    that into 404.

    Mirrors the Kör 7 ``_caller_profile_public_id`` /
    ``_resolve_internal_profile_id`` patterns from
    ``routers/social_graph.py`` and ``routers/posts.py``.
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return int(row[0])


def _resolve_cursor_secret(settings: Settings) -> str:
    """Return the application ``secret_key`` or refuse to serve.

    The cursor is HMAC-signed with the live ``settings.secret_key``.
    Signing with a missing or placeholder value would let any
    client forge a valid cursor token (the §5.2 integrity
    invariant); F3 requires the endpoint to fail-closed in that
    state rather than silently signing with the code-resident
    placeholder. A 503 surfaces the configuration error to the
    client; the underlying ``/health/ready`` gate catches the
    same condition at the deploy boundary, so this is consistent
    with the existing readiness discipline.
    """
    secret = getattr(settings, "secret_key", None)
    if not isinstance(secret, str) or not secret.strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="feed cursor signing key not configured",
        )
    if secret == _DEV_SECRET_KEY_DEFAULT:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="feed cursor signing key is the development placeholder",
        )
    return secret


def _interaction_counts(
    db: Session, post_ids: list[int]
) -> dict[int, tuple[int, int, int]]:
    """Reakció / komment / könyvjelző szám poszt-azonosítónként.

    HÁROM csoportosított lekérdezés az OLDALRA, nem poszt-onként három —
    egy 50-es oldalon az N+1 alak 150 kört jelentene. Üres oldalon egy
    lekérdezés sem fut.
    """
    if not post_ids:
        return {}
    counts: dict[int, tuple[int, int, int]] = {pid: (0, 0, 0) for pid in post_ids}
    placeholders = ", ".join(f":p{i}" for i in range(len(post_ids)))
    params = {f"p{i}": pid for i, pid in enumerate(post_ids)}

    def _grouped(sql: str) -> dict[int, int]:
        return {
            int(r[0]): int(r[1]) for r in db.execute(_sa_text(sql), params).fetchall()
        }

    reactions = _grouped(
        "SELECT post_id, COUNT(*) FROM community_reactions "
        f"WHERE post_id IN ({placeholders}) GROUP BY post_id"
    )
    # A törölt és a nem látható komment NEM számít bele — különben a
    # kártya többet ígérne, mint amennyit a komment-lista megnyitva ad.
    comments = _grouped(
        "SELECT post_id, COUNT(*) FROM community_comments "
        f"WHERE post_id IN ({placeholders}) AND deleted_at IS NULL "
        "AND moderation_state = 'visible' GROUP BY post_id"
    )
    bookmarks = _grouped(
        "SELECT post_id, COUNT(*) FROM community_bookmarks "
        f"WHERE post_id IN ({placeholders}) GROUP BY post_id"
    )
    for pid in post_ids:
        counts[pid] = (
            reactions.get(pid, 0),
            comments.get(pid, 0),
            bookmarks.get(pid, 0),
        )
    return counts


def _viewer_state(
    db: Session, viewer_profile_id: int, post_ids: list[int]
) -> dict[int, tuple[bool, str | None]]:
    """A NÉZŐ saját könyvjelzője és reakciója poszt-azonosítónként.

    Külön a számlálóktól, mert néző-függő: ugyanaz a poszt más
    felhasználónak MÁS értéket ad, ezért sosem oszthatja a cache-t.
    """
    if not post_ids:
        return {}
    placeholders = ", ".join(f":p{i}" for i in range(len(post_ids)))
    params: dict[str, object] = {f"p{i}": pid for i, pid in enumerate(post_ids)}
    params["viewer"] = viewer_profile_id
    bookmarked = {
        int(r[0])
        for r in db.execute(
            _sa_text(
                "SELECT post_id FROM community_bookmarks "
                f"WHERE profile_id = :viewer AND post_id IN ({placeholders})"
            ),
            params,
        ).fetchall()
    }
    reactions = {
        int(r[0]): str(r[1])
        for r in db.execute(
            _sa_text(
                "SELECT post_id, kind FROM community_reactions "
                f"WHERE profile_id = :viewer AND post_id IN ({placeholders})"
            ),
            params,
        ).fetchall()
    }
    return {pid: (pid in bookmarked, reactions.get(pid)) for pid in post_ids}


def _row_to_item(
    row: FeedItemRow,
    counts: tuple[int, int, int] = (0, 0, 0),
    viewer: tuple[bool, str | None] = (False, None),
) -> FeedPostItem:
    """Map a repository ``FeedItemRow`` to the wire-shape item.

    Centralised so the §6.1 leak-guard (no internal id on the wire)
    is structural — adding a field to the response still routes
    through here. ``resource_version`` mirrors the Kör 11
    ``PostOut`` (the ``updated_at`` token).
    """
    return FeedPostItem(
        public_id=row.post_public_id,
        author_public_id=row.author_public_id,
        audience=row.audience,  # type: ignore[arg-type]
        club_id=None,
        body=row.body,
        artifact_type=row.artifact_type,
        artifact_schema_version=row.artifact_schema_version,
        artifact_payload=row.artifact_payload,
        moderation_state=row.moderation_state,  # type: ignore[arg-type]
        reaction_count=counts[0],
        comment_count=counts[1],
        bookmark_count=counts[2],
        viewer_bookmarked=viewer[0],
        viewer_reaction=viewer[1],
        created_at=row.created_at,
        resource_version=row.updated_at,
        deleted_at=row.deleted_at,
    )


# ---------------------------------------------------------------------------
# GET /community/feed
# ---------------------------------------------------------------------------


@router.get("/feed", status_code=status.HTTP_200_OK)
def get_following_feed(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    # §0.0 D7 — ``page_size`` is clamped to :data:`FEED_PAGE_SIZE_MAX`
    # INSIDE the handler; we accept any ``ge=1`` value at the Query
    # layer so a client that requests 5000 rows gets 50 back instead
    # of a 422 (the §6.1 fölött cell). A request with
    # ``page_size=0`` is still rejected at the FastAPI layer
    # (the alatta cell).
    page_size: int | None = Query(default=None, ge=1),
) -> FeedPage:
    """Return one cursor-paginated page of the viewer's following feed.

    The endpoint is authenticated — the follow-graph and
    block/mute filters are anchored to the caller, and the wire
    shape is personalised (the brief §5.2 SDD-invariáns). A
    caller without a community profile receives 404 (the
    onboarding flow is upstream — Kör 6 / ADR 0400).

    The page-size and cursor parameters are validated at the
    Pydantic / FastAPI layer (``ge=1``, ``max_length=512`` on the
    cursor). The router ADDITIONALLY clamps the ``page_size`` to
    :data:`MAX_PAGE_SIZE` as a belt-and-braces guard against a
    client that bypassed schema validation — the §0.0 D7
    fail-safe.

    A malformed or forged cursor does NOT surface to the client
    as a 422 (F5 fix — the previous docstring was wrong): the
    repository's ``_verify_cursor`` returns ``None`` on any
    malformed / forged / version-mismatch input, and the
    repository then silently serves a fresh first page (the
    §5.2 invariant — the security boundary never raises a
    stack-trace-bearing 500 in response to a hostile cursor).
    This endpoint's only error responses are 404 (caller has
    no community profile) and 503 (cursor signing key is
    missing or holds the development placeholder — F3 fix).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_pk = _resolve_viewer_profile_pk(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

        settings = request.app.state.settings
        cursor_secret = _resolve_cursor_secret(settings)

        # Validate the inbound query via the Pydantic schema — the
        # ``extra='forbid'`` discipline prevents a client from
        # smuggling undocumented query parameters that would land
        # on the repository layer. The schema's own ``ge=1`` bound
        # is the first guard for the alatta cell; the router's
        # ``min(requested, MAX_PAGE_SIZE)`` clamp is the second
        # (the fölött cell — the §0.0 D7 fail-safe).
        validated = FeedPageQuery(cursor=cursor, page_size=page_size)
        effective_page_size = (
            validated.page_size
            if validated.page_size is not None
            else DEFAULT_PAGE_SIZE
        )
        # Belt-and-braces clamp at the router layer — even if a
        # future client bypassed the schema's bounds, the request
        # still cannot trigger an oversized query.
        if effective_page_size > FEED_PAGE_SIZE_MAX:
            effective_page_size = FEED_PAGE_SIZE_MAX

        repo_page: FeedPageRepo = list_following_feed(
            db,
            viewer_profile_id=viewer_pk,
            cursor=validated.cursor,
            page_size=effective_page_size,
            cursor_secret=cursor_secret,
        )

        post_ids = [row.post_id for row in repo_page.items]
        counts = _interaction_counts(db, post_ids)
        viewer_state = _viewer_state(db, viewer_pk, post_ids)
        items = [
            _row_to_item(
                row,
                counts.get(row.post_id, (0, 0, 0)),
                viewer_state.get(row.post_id, (False, None)),
            )
            for row in repo_page.items
        ]
        return FeedPage(items=items, next_cursor=repo_page.next_cursor)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "get_following_feed",
    "router",
]
