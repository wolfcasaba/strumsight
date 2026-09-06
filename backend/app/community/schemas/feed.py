"""Pydantic schemas for the Community following feed (E09-R13, ADR 0406).

The wire shape for ``GET /community/feed``. Two design choices govern
the module:

* **Server-side page-size validation (ADR 0406 D7).** The
  :class:`FeedPageQuery` schema enforces ``page_size >= 1`` and
  delegates the upper bound to the router-side clamp (``min(
  requested, FEED_PAGE_SIZE_MAX)``). A client that asks for
  5000 rows receives 50 (the maximum), never a 422 and never
  an oversized query. The §6.1 measure-matrix on the page-size
  threshold ("alatta / rajta / fölötte") is enforced at the
  FastAPI Query layer (minimum), the schema layer (minimum +
  ``extra='forbid'``), and the router (clamp-to-maximum).

* **Cursor is opaque.** The :class:`FeedPage` response carries a
  ``next_cursor`` string the client forwards verbatim on the next
  page request. The wire shape carries no metadata a client could
  decode — the cursor is an HMAC-signed, versioned token (see
  ``feed.following_feed``). A tampered or forged cursor returns
  ``None`` and the repository falls back to a fresh first page;
  the wire shape never reveals why.

The response model mirrors the Kör 11 :class:`PostOut` shape so
the Flutter feed UI can reuse the same post-rendering pipeline
(Kör 14+). The ``resource_version`` token is included on every
item so the optimistic-concurrency contract (brief §0.0 D3) is
preserved — a tap-through to the post detail screen can PATCH
with the feed-supplied token without an extra round-trip.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from ..models.post import POST_BODY_MAX_LENGTH
from ..policies.access_policy import CommunityAudience

# ---------------------------------------------------------------------------
# Page-size thresholds (ADR 0406 §5.3 / §0.0 D7).
# ---------------------------------------------------------------------------

#: Default page size — the value the client gets when it omits the
#: query parameter.
FEED_PAGE_SIZE_DEFAULT: int = 25

#: Maximum page size — the absolute cap the server enforces. Mirrors
#: the Kör 7 / Kör 8 social-graph endpoints (``_FOLLOW_LIST_MAX_LIMIT
#: = 200``); the feed uses a smaller cap because each row carries a
#: full post body (up to ``POST_BODY_MAX_LENGTH`` chars) and the
#: blocking/mute filter adds a separate query per page request.
FEED_PAGE_SIZE_MAX: int = 50


class FeedPageQuery(BaseModel):
    """Inbound shape for ``GET /community/feed``.

    The schema is intentionally minimal — a client passes ``page_size``
    (validated against the documented thresholds) and ``cursor`` (a
    previously-returned opaque token). ``page_size`` is bound at the
    Pydantic layer; the router additionally clamps the value to
    :data:`FEED_PAGE_SIZE_MAX` as a belt-and-braces guard against a
    client that bypasses schema validation (the §0.0 D7 fail-safe).

    The ``extra='forbid'`` discipline matches the Kör 11 post schema:
    a client cannot smuggle a hidden filter or sort parameter
    through the query string and accidentally trigger an
    undocumented query path.
    """

    model_config = ConfigDict(extra="forbid")

    #: Page-size request. ``None`` ⇒ use the default
    #: (:data:`FEED_PAGE_SIZE_DEFAULT`); an integer is validated
    #: against the ``ge=1`` minimum. The upper bound is NOT
    #: enforced at the schema layer — a request above
    #: :data:`FEED_PAGE_SIZE_MAX` is silently clamped to the
    #: maximum by the router (the §6.1 fölött cell — the §0.0
    #: D7 fail-safe; the server never returns a 422 for an
    #: oversized request).
    page_size: int | None = Field(default=None, ge=1)

    #: Opaque continuation token from the previous page, or ``None``
    #: on the first page. The token's content is opaque to the
    #: caller — the schema only validates its presence as a string.
    cursor: str | None = Field(default=None, max_length=512)


class FeedPostItem(BaseModel):
    """One row of the feed response.

    Mirrors the Kör 11 :class:`PostOut` shape so the Flutter feed
    UI (Kör 14+) can reuse the existing post-rendering pipeline.
    The author is the ``author_public_id`` (the wire identity), not
    the internal ``profile_id`` — the §6.1 leak-guard lives here.
    """

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    author_public_id: uuid.UUID
    audience: CommunityAudience
    club_id: int | None = None
    #: Capped at :data:`POST_BODY_MAX_LENGTH` to match the column
    #: length on the wire (the Kör 11 DB constraint is a defensive
    #: bound; this is the primary validation). The Flutter side
    #: truncates previews at a smaller visual length.
    body: str = Field(..., max_length=POST_BODY_MAX_LENGTH)
    artifact_type: str | None = None
    artifact_schema_version: int | None = None
    artifact_payload: dict[str, Any] | None = None
    moderation_state: Literal["visible", "removed"]
    #: Interakció-számlálók. 2026-09-05-ig HIÁNYOZTAK a wire-alakból,
    #: miközben a Flutter feed-kártya (`feed_card_registry.dart:211,219,223`
    #: és `reaction_bar.dart:87`) KIÍRJA őket — a kliens tehát minden
    #: poszton nullát mutatott volna. A projekt saját elve
    #: (`UNKNOWN > CONFIDENTLY WRONG`) tiltja ezt: egy „0 reakció" felirat
    #: nem hiányzó adat, hanem egy magabiztos állítás, ami hamis.
    reaction_count: int = 0
    comment_count: int = 0
    bookmark_count: int = 0
    #: A NÉZŐ saját viszonya a poszthoz — a UI ebből rajzolja a
    #: könyvjelző- és reakció-gomb állapotát. Néző-függő, ezért SOSEM
    #: cache-elhető a poszttal együtt más néző számára.
    viewer_bookmarked: bool = False
    viewer_reaction: str | None = None
    created_at: datetime
    #: The Kör 11 ``updated_at`` resource-version token (ADR 0398 §6
    #: precedent). Echoed back on PATCH for optimistic concurrency.
    resource_version: datetime
    deleted_at: datetime | None = None


class FeedPage(BaseModel):
    """The outbound shape for one cursor-paginated feed page.

    ``items`` is the list of visible, audience-/block-/mute-/moderation-
    /deletion-passed posts the viewer may see. ``next_cursor`` is
    ``None`` when the page is the last one (the repository fetched
    exactly ``page_size`` rows or fewer); otherwise it is the opaque
    HMAC-signed token the client forwards as the next request's
    ``cursor`` parameter.
    """

    model_config = ConfigDict(extra="forbid")

    items: list[FeedPostItem]
    next_cursor: str | None = None


class PinnedPostList(BaseModel):
    """A klubban kitűzött posztok — TELJES elemekkel.

    Az elem ugyanaz a :class:`FeedPostItem`, amit a feed ad: számlálóstul,
    néző-állapotostul. Egy szűkebb, négymezős alak kényszerítené a klienst,
    hogy nullákat rajzoljon a kitűzött poszt alá, miközben a feedben
    ugyanaz a poszt a valódi számokat mutatja — ugyanaz a „magabiztos hamis
    állítás", amit a feed-számlálók bevezetése zárt.

    NINCS ``next_cursor``: a kitűzhető posztok száma klubonként korlátos
    (a ``club_content_service`` pin-limit őre tartja be), tehát a lista
    definíció szerint egyoldalas. Egy mindig ``None`` kurzor-mező azt
    sugallná, hogy van lapozás.
    """

    model_config = ConfigDict(extra="forbid")

    items: list[FeedPostItem]


__all__ = [
    "FEED_PAGE_SIZE_DEFAULT",
    "FEED_PAGE_SIZE_MAX",
    "FeedPage",
    "FeedPageQuery",
    "FeedPostItem",
    "PinnedPostList",
]
