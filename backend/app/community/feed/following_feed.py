"""Following-feed read path — E09-R13, ADR 0406.

The single repository for the ``GET /community/feed`` endpoint. The
function :func:`list_following_feed` is responsible for the
end-to-end read path: follow-graph resolution, audience/block/mute/
moderation/deletion filtering, stable ordering, HMAC-signed cursor,
and batched profile projection.

This module owns four concerns (ADR 0406 §5):

* **Chronological, explainable ordering (§5.1).** The sort is
  exactly ``(created_at DESC, id DESC)`` — no engagement signal
  feeds the order. The §6.1 A1 cell is realised by removing any
  secondary sort key and asserting the ordering is still
  deterministic and stable.

* **Multi-axis filtering (§5.3, ADR 0406 §D3).** A row is
  included in the viewer's feed if ALL of:

  - the row's author ``profile_id`` is in the viewer's
    ``community_follows.followed_profile_id`` set (the follow
    set is materialised first as a small ``IN (list)`` predicate;
    ADR 0406 D2 — the planner then picks the
    ``ix_community_posts_created_id (created_at, id)`` index for
    the global sort, and the profile filter is applied as the
    planner walks the index);
  - the row's ``audience`` is in the canonical allowlist
    ``{'public', 'followers'}`` — explicit whitelist, NOT a
    ``!= 'private'`` denylist (F4 fix: a future audience value
    introduced at the Pydantic layer without an explicit
    migration would otherwise slip through a denylist filter);
  - the row's author is NOT in a block relation with the viewer
    (the Kör 8 ``filter_public_ids_against_viewer_blocks`` helper,
    extended to a single ``profile_id IN (...)`` predicate so
    the page-sized batch can be filtered in one round-trip);
  - the viewer is NOT the ``muter`` of a mute edge pointing at
    the author (asymmetric — the Kör 8 mute is one-directional;
    no shared helper exists, so this module builds its own
    ``muter_profile_id = viewer`` predicate on
    ``community_mutes`` — ADR 0406 §D3 explicit instruction);
  - ``moderation_state == 'visible'`` (Kör 11 invariant);
  - ``deleted_at IS NULL`` (Kör 11 soft-delete invariant).

  Each filter is a separate SQL predicate. The §6.1 measure-matrix
  flips ONE filter off per cell (the corresponding cell turns
  red) — the architecture supports a real-violation probe.

* **Opaque, HMAC-signed cursor (§5.2).** The cursor encodes the
  ``(created_at, id, feed_version)`` triple — the last returned
  row's sort key plus a STATIC ``FEED_CURSOR_VERSION`` integer
  constant (ADR 0406 D5: an ``int``, not a string). The payload
  is HMAC-SHA256-signed with the application ``secret_key``
  (same key the Kör 9 ``profile_search_repository`` uses). A
  client that tampers with the cursor sees the server fall back
  to a fresh first page (the security boundary never silently
  passes a malicious cursor through). The ``feed_version`` lets
  a future migration break cursor compatibility by bumping the
  constant — old cursors return ``None`` and the client starts
  at page one again.

* **Batched profile projection (no N+1, §5.3).** The follow set
  is fetched in one query, the candidate rows in a second query
  that joins posts to ``community_profiles`` (``author_public_id``
  resolution), and the block / mute filters run as in-Python set
  predicates on the page-sized candidate set. The
  ``community_blocks`` symmetric block-helper
  (``filter_public_ids_against_viewer_blocks``) is called with
  the candidate ``profile_id`` set — a single batched read
  rather than per-row ``is_blocked_pair`` calls.

The module is DB-coupled (SQLAlchemy ``Session``) and pure
with respect to HTTP — the router translates the returned
envelope into JSON. The cursor's ``secret_key`` is threaded in
from the router (the same ``settings.secret_key`` the JWT layer
uses; tests pass a fixture-local value).
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Final

from sqlalchemy import select, tuple_
from sqlalchemy.orm import Session

from ..models.post import (
    MODERATION_STATE_VISIBLE,
    CommunityPost,
)
from ..models.profile import CommunityProfile
from ..models.social_graph import CommunityFollow
from ..policies.query_filters import (
    filter_public_ids_against_viewer_blocks,
)

# ---------------------------------------------------------------------------
# Feed-version constant (ADR 0406 D5).
# ---------------------------------------------------------------------------

#: Static cursor version — bumping this on a future migration breaks
#: cursor compatibility (old ``next_cursor`` tokens return ``None``)
#: so the client transparently starts at page one again. ADR 0406 D5
#: prescribes an integer; using ``str`` here would silently drift the
#: on-the-wire payload from the architectural decision.
FEED_CURSOR_VERSION: Final[int] = 1

#: Default page size — the value the router uses when the client
#: omits ``page_size``. Mirrors the schema default.
DEFAULT_PAGE_SIZE: Final[int] = 25

#: Maximum page size — the absolute cap. Mirrors the schema constant;
#: this module enforces the same clamp on the actual row count
#: fetched (``LIMIT :limit_plus_one``).
MAX_PAGE_SIZE: Final[int] = 50

#: Audience allowlist — the only ``audience`` values that are allowed
#: in the following-feed read path (F4 fix: explicit whitelist, NOT a
#: ``!= 'private'`` denylist, so a future audience value introduced at
#: the Pydantic layer without an explicit migration does NOT silently
#: leak through the SQL filter).
FEED_AUDIENCE_ALLOWLIST: Final[tuple[str, ...]] = ("public", "followers")

#: Cursor HMAC tag length. Same trade-off as the Kör 9
#: ``profile_search_repository`` — a 32-byte truncated tag is
#: brute-forceable in principle, but a forgery that names a real
#: ``(created_at, id)`` pair still lands the request on the right
#: page (the worst-case observable outcome is "the user sees rows
#: they would have seen anyway").
_CURSOR_TAG_BYTES: Final[int] = 32


# ---------------------------------------------------------------------------
# Public dataclasses — the wire shape lives in ``schemas/feed.py``,
# but the repository carries an internal, DB-coupling-friendly view.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class FeedItemRow:
    """One post row the repository returns.

    The author ``profile_id`` and ``public_id`` are both surfaced —
    the router needs the public_id for the wire shape, and the
    internal ``id`` is kept here for the cursor's sort-key
    composition. The repository is the single source of truth for
    the ``(profile_id, public_id)`` mapping for a candidate row;
    downstream code (the schema) consumes only the public_id.
    """

    post_id: int
    post_public_id: uuid.UUID
    profile_id: int
    author_public_id: uuid.UUID
    audience: str
    body: str
    artifact_type: str | None
    artifact_schema_version: int | None
    artifact_payload: dict[str, object] | None
    moderation_state: str
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


@dataclass(frozen=True)
class FeedPage:
    """One cursor-paginated page of feed items.

    The ``items`` are :class:`FeedItemRow` — the schema layer maps
    each row to a :class:`FeedPostItem`. ``next_cursor`` is
    ``None`` on the last page; otherwise it is the HMAC-signed
    token the client forwards as the next request's ``cursor``
    parameter.
    """

    items: tuple[FeedItemRow, ...]
    next_cursor: str | None


# ---------------------------------------------------------------------------
# Cursor signing / verification — HMAC-SHA256, the Kör 9 pattern.
# ---------------------------------------------------------------------------


def _sign_cursor(
    cursor_secret: str,
    *,
    created_at: datetime,
    post_id: int,
    feed_version: int = FEED_CURSOR_VERSION,
) -> str:
    """Build the opaque pagination token.

    The payload encodes ``(created_at, post_id, feed_version)`` —
    the last RETURNED row's sort key plus a static version marker.
    The wire shape is ``<base64url(json)>.<base64url(hmac)>``; the
    client forwards it verbatim and the repository validates the
    signature before trusting the embedded sort key (the §5.2
    integrity guarantee). A client that decodes or forges the
    cursor is rejected at the boundary.
    """
    payload = {
        "c": _serialize_datetime(created_at),
        "i": int(post_id),
        "v": int(feed_version),
    }
    payload_bytes = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    signature = hmac.new(
        cursor_secret.encode("utf-8"), payload_bytes, hashlib.sha256
    ).digest()[:_CURSOR_TAG_BYTES]
    return (
        base64.urlsafe_b64encode(payload_bytes).decode("ascii")
        + "."
        + base64.urlsafe_b64encode(signature).decode("ascii")
    )


def _verify_cursor(
    cursor_secret: str,
    cursor: str,
) -> tuple[datetime, int] | None:
    """Validate the opaque cursor and return ``(created_at, post_id)``.

    Returns ``None`` on any malformed / forged / version-mismatch
    input — the caller's policy is to fall back to a fresh first
    page. The signature is constant-time compared.
    """
    if "." not in cursor:
        return None
    payload_b64, signature_b64 = cursor.rsplit(".", 1)
    try:
        payload_bytes = base64.urlsafe_b64decode(payload_b64.encode("ascii"))
        signature = base64.urlsafe_b64decode(signature_b64.encode("ascii"))
    except (ValueError, TypeError):
        return None
    expected = hmac.new(
        cursor_secret.encode("utf-8"), payload_bytes, hashlib.sha256
    ).digest()[:_CURSOR_TAG_BYTES]
    if not hmac.compare_digest(signature, expected):
        return None
    try:
        payload = json.loads(payload_bytes.decode("utf-8"))
        version = int(payload["v"])
        if version != FEED_CURSOR_VERSION:
            # A future migration bumping FEED_CURSOR_VERSION turns
            # legacy cursors into a fresh first page automatically
            # — the §5.2 forward-compat seam.
            return None
        created_at = _deserialize_datetime(str(payload["c"]))
        post_id = int(payload["i"])
        return created_at, post_id
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None


def _serialize_datetime(value: datetime) -> str:
    """Serialize a ``datetime`` to the cursor's ISO-8601 string form.

    Naive ``datetime`` objects get the ``+00:00`` suffix so the
    cursor string is unambiguous across SQLite / PostgreSQL
    round-trips (SQLite drops tzinfo on read; the cursor is
    timezone-agnostic at parse time).
    """
    from datetime import timezone

    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _deserialize_datetime(raw: str) -> datetime:
    """Inverse of :func:`_serialize_datetime`."""
    parsed = datetime.fromisoformat(raw)
    if parsed.tzinfo is None:
        from datetime import timezone

        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _coerce_uuid(raw: object) -> uuid.UUID:
    """Coerce the ``Uuid`` column's driver-native return type.

    Same precedent as the Kör 9 ``profile_search_repository``
    helper — SQLite returns ``CHAR(32)`` hex form on raw text()
    queries; PostgreSQL returns the native ``UUID``. The
    wire-shape helpers downstream need the typed ``UUID``.
    """
    if isinstance(raw, uuid.UUID):
        return raw
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return uuid.UUID(str(raw))


# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------


def list_following_feed(
    db: Session,
    *,
    viewer_profile_id: int,
    cursor: str | None,
    page_size: int,
    cursor_secret: str,
) -> FeedPage:
    """Return one cursor-paginated page of the viewer's following feed.

    Parameters
    ----------
    db:
        The SQLAlchemy session. Owning it lets the router wrap
        the call in a single, short-lived transaction.
    viewer_profile_id:
        The internal PK of the caller. The follow-graph and
        block/mute filters are anchored to this id; the
        endpoint cannot be served without it.
    cursor:
        Opaque continuation token from the previous page, or
        ``None`` on the first page. The repository validates
        the HMAC signature (and the ``feed_version`` marker)
        before trusting the embedded ``(created_at, post_id)``
        pair; an invalid cursor falls back to a fresh first
        page (the security boundary never silently passes a
        malicious cursor through).
    page_size:
        The maximum number of posts to return. The router
        clamps the wire value to :data:`MAX_PAGE_SIZE` before
        calling the repository; the repository fetches
        ``page_size + 1`` rows to detect end-of-result.
    cursor_secret:
        The application ``secret_key`` used to HMAC-sign the
        ``next_cursor``. The router threads the live
        ``settings.secret_key`` through; tests pass a fixture-
        local value.

    Returns
    -------
    FeedPage
        The ``items`` are :class:`FeedItemRow` instances,
        ordered ``(created_at DESC, id DESC)``. The
        ``next_cursor`` is ``None`` when there are no more
        rows; it is the HMAC-signed position of the LAST
        RETURNED item — never a filtered-out row, so a
        blocked / muted / audience-excluded author's
        ``created_at`` / ``id`` pair cannot leak through the
        cursor channel.
    """
    if page_size < 1:
        # Defensive — the router / schema already enforce this.
        page_size = 1
    if page_size > MAX_PAGE_SIZE:
        page_size = MAX_PAGE_SIZE

    # Decode the cursor once — ``None`` means "fresh first page".
    decoded_cursor: tuple[datetime, int] | None = None
    if cursor is not None:
        decoded_cursor = _verify_cursor(cursor_secret, cursor)
        # A malformed / forged cursor falls back to a fresh first
        # page (the security boundary never silently passes a
        # malicious cursor through — the §5.2 invariant).

    # Step 1: materialise the viewer's follow-graph target set into a
    # small ``IN (...)`` predicate. The Kör 11 query shape joined the
    # follow table directly, which forced the SQLite planner into a
    # nested-loop profile-id lookup followed by a USE TEMP B-TREE FOR
    # ORDER BY — the (created_at, id) index could never lead the
    # sort. With the follow set materialised first, the second
    # SELECT runs ``WHERE profile_id IN (...) ORDER BY created_at
    # DESC, id DESC LIMIT :n`` and the planner walks the
    # ``ix_community_posts_created_id`` index directly, applying the
    # IN-list as a per-row filter (ADR 0406 D2; F1 review fix).
    followed_profile_ids = (
        db.execute(
            select(CommunityFollow.followed_profile_id).where(
                CommunityFollow.follower_profile_id == viewer_profile_id,
            )
        )
        .scalars()
        .all()
    )

    if not followed_profile_ids:
        return FeedPage(items=(), next_cursor=None)

    # Step 2: the candidate SELECT — posts whose author is in the
    # viewer's accepted follow-graph, ordered by the (created_at, id)
    # index, with moderation / deletion / audience filters applied.
    candidate_sql = (
        select(
            CommunityPost.id,
            CommunityPost.public_id,
            CommunityPost.profile_id,
            CommunityProfile.public_id.label("author_public_id"),
            CommunityPost.audience,
            CommunityPost.body,
            CommunityPost.artifact_type,
            CommunityPost.artifact_schema_version,
            CommunityPost.artifact_payload,
            CommunityPost.moderation_state,
            CommunityPost.created_at,
            CommunityPost.updated_at,
            CommunityPost.deleted_at,
        )
        .join(
            CommunityProfile,
            CommunityProfile.id == CommunityPost.profile_id,
        )
        .where(
            CommunityPost.profile_id.in_(followed_profile_ids),
            CommunityPost.deleted_at.is_(None),
            CommunityPost.moderation_state == MODERATION_STATE_VISIBLE,
            # Audience allowlist (F4 fix): explicit whitelist, NOT a
            # ``!= 'private'`` denylist. A future audience value
            # introduced at the Pydantic layer without an explicit
            # migration does NOT silently leak through the SQL
            # filter. The Kör 11 access policy mirrors this set.
            CommunityPost.audience.in_(FEED_AUDIENCE_ALLOWLIST),
        )
        .order_by(
            CommunityPost.created_at.desc(),
            CommunityPost.id.desc(),
        )
        .limit(page_size + 1)
    )

    if decoded_cursor is not None:
        # Append the cursor WHERE clause as a SQLAlchemy row
        # tuple comparator — DB-portable, no dialect-specific
        # row-constructor syntax. The bind values come from the
        # verified cursor (the HMAC guard runs first).
        candidate_sql = candidate_sql.where(
            tuple_(CommunityPost.created_at, CommunityPost.id)
            < tuple_(decoded_cursor[0], decoded_cursor[1])
        )

    candidate_rows = db.execute(candidate_sql).all()
    has_more_raw = len(candidate_rows) > page_size
    candidate_rows = candidate_rows[:page_size]

    if not candidate_rows:
        return FeedPage(items=(), next_cursor=None)

    # The block-filter (Kör 8 symmetric helper). The candidate
    # ``profile_id`` set is small (page-sized), so the page-level
    # filter is one round-trip against the viewer's block table —
    # NOT an N+1 ``is_blocked_pair`` call per row.
    candidate_profile_ids = [int(row.profile_id) for row in candidate_rows]
    candidate_author_public_ids = [
        _coerce_uuid(row.author_public_id) for row in candidate_rows
    ]
    filtered_author_public_ids = set(
        filter_public_ids_against_viewer_blocks(
            db,
            viewer_profile_id=viewer_profile_id,
            public_ids=candidate_author_public_ids,
        )
    )

    # The mute-filter is ASYMMETRIC (the viewer→author edge only).
    # The Kör 8 mute helper is a single-pair predicate, so we
    # build our own batched set here — the §D3 explicit instruction.
    muted_author_pks: set[int] = set()
    if candidate_profile_ids:
        from ..models.safety_relationships import CommunityMute

        mute_stmt = select(CommunityMute.muted_profile_id).where(
            CommunityMute.muter_profile_id == viewer_profile_id,
            CommunityMute.muted_profile_id.in_(candidate_profile_ids),
        )
        muted_author_pks = {int(row[0]) for row in db.execute(mute_stmt).all()}

    # Stitch the four predicates together: only rows whose author
    # passes the block filter AND is not in the muted set survive.
    # The list is ordered; we preserve the SQL ordering by iterating
    # in the original order and dropping in-place.
    kept_rows: list[tuple[object, ...]] = []
    for row in candidate_rows:
        author_public_id = _coerce_uuid(row.author_public_id)
        if author_public_id not in filtered_author_public_ids:
            continue
        if int(row.profile_id) in muted_author_pks:
            continue
        kept_rows.append(row)

    items = tuple(
        FeedItemRow(
            post_id=int(row.id),
            post_public_id=_coerce_uuid(row.public_id),
            profile_id=int(row.profile_id),
            author_public_id=_coerce_uuid(row.author_public_id),
            audience=str(row.audience),
            body=str(row.body),
            artifact_type=row.artifact_type,
            artifact_schema_version=(
                int(row.artifact_schema_version)
                if row.artifact_schema_version is not None
                else None
            ),
            artifact_payload=row.artifact_payload,
            moderation_state=str(row.moderation_state),
            created_at=(
                row.created_at
                if isinstance(row.created_at, datetime)
                else datetime.fromisoformat(str(row.created_at))
            ),
            updated_at=(
                row.updated_at
                if isinstance(row.updated_at, datetime)
                else datetime.fromisoformat(str(row.updated_at))
            ),
            deleted_at=(
                row.deleted_at
                if isinstance(row.deleted_at, datetime)
                else (
                    datetime.fromisoformat(str(row.deleted_at))
                    if row.deleted_at is not None
                    else None
                )
            ),
        )
        for row in kept_rows
    )

    # The cursor encodes the LAST KEPT row's (created_at, post_id),
    # NOT a raw ``rows[-1]`` that the block / mute filter excluded.
    # A blocked / muted author's sort-key pair cannot leak through
    # the cursor channel because the row that encoded them is not
    # in the response — same fix the Kör 9 review applied to the
    # search repository.
    next_cursor: str | None = None
    if has_more_raw and kept_rows:
        last_kept = kept_rows[-1]
        last_at = (
            last_kept.created_at
            if isinstance(last_kept.created_at, datetime)
            else datetime.fromisoformat(str(last_kept.created_at))
        )
        last_id = int(last_kept.id)
        next_cursor = _sign_cursor(cursor_secret, created_at=last_at, post_id=last_id)

    return FeedPage(items=items, next_cursor=next_cursor)


# ---------------------------------------------------------------------------
# Explain-plan baseline (A7 measure-matrix).
# ---------------------------------------------------------------------------


def query_plan_uses_feed_index(db: Session, *, viewer_profile_id: int) -> bool:
    """A7 evidence helper — confirm the candidate SELECT uses the
    new ``ix_community_posts_created_id`` index for the sort,
    not a sequential scan AND not a TEMP B-TREE sort.

    The function runs the same WHERE / ORDER BY as
    :func:`list_following_feed` prefixed with ``EXPLAIN`` and
    asserts the planner:

    1. walks ``community_posts`` via the
       ``ix_community_posts_created_id`` index (the F1 fix —
       a generic "SEARCH ... USING INDEX" substring match is too
       permissive; the planner may pick ANY index, including one
       introduced by a future migration, and still satisfy the
       old matcher. The exact name is what the §6.1 valódi-sértés
       próba asserts is MISSING when the index is dropped);
    2. does NOT emit ``USE TEMP B-TREE FOR ORDER BY`` — the new
       index is supposed to give the planner the rows in sort
       order, so a TEMP B-TREE is evidence that the index is not
       actually leading the sort (the Kör 11 join shape had this
       exact failure mode; the F1 refactor moves the query to a
       materialised ``profile_id IN (...)`` shape precisely so
       the planner can drive off the new index).

    The check is a STRING match on the EXPLAIN output (SQLite
    emits the index name in the plan), so it covers both SQLite
    (test engine) and PostgreSQL (production) via the
    dialect-specific EXPLAIN format.
    """
    from sqlalchemy import text as _sa_text

    plan = db.execute(
        _sa_text(
            "EXPLAIN QUERY PLAN "
            "SELECT community_posts.id, community_posts.public_id, "
            "       community_posts.profile_id, "
            "       community_posts.audience, "
            "       community_posts.body, "
            "       community_posts.artifact_type, "
            "       community_posts.artifact_schema_version, "
            "       community_posts.artifact_payload, "
            "       community_posts.moderation_state, "
            "       community_posts.created_at, "
            "       community_posts.updated_at, "
            "       community_posts.deleted_at "
            "FROM community_posts "
            "WHERE community_posts.profile_id IN ("
            "  SELECT community_follows.followed_profile_id "
            "  FROM community_follows "
            "  WHERE community_follows.follower_profile_id = :viewer"
            ") "
            "  AND community_posts.deleted_at IS NULL "
            "  AND community_posts.moderation_state = :visible "
            "  AND community_posts.audience IN ('public', 'followers') "
            "ORDER BY community_posts.created_at DESC, community_posts.id DESC "
            "LIMIT 51"
        ),
        {"viewer": viewer_profile_id, "visible": MODERATION_STATE_VISIBLE},
    ).all()
    plan_text = " ".join(str(row) for row in plan)
    lowered = plan_text.lower()

    # 1. The plan must explicitly name ``ix_community_posts_created_id``
    # on the SEARCH / SCAN line for community_posts. A generic "USING
    # INDEX" matcher would pass on the Kör 11 index too — the §6.1
    # measure-matrix wants THIS index, not "any index".
    posts_index_used = "ix_community_posts_created_id" in lowered

    # 2. The plan must NOT do a final TEMP B-TREE sort. A tmp btree
    # is the planner's escape hatch when the chosen access path does
    # NOT yield the rows in the requested sort order — the new
    # composite index exists precisely to avoid this fallback.
    no_temp_sort = "use temp b-tree for order by" not in lowered

    # 3. The follow subquery must use an index on community_follows
    # for the follower_profile_id lookup (the Kör 7 follow-graph
    # composite index). A sequential scan of the follows table is a
    # different N+1 vector (Kör 8) and must also turn the A7 cell
    # red.
    follows_index_used = (
        ("search community_follows using" in lowered)
        or ("scan community_follows using" in lowered)
        or ("community_follows" in lowered and "index" in lowered)
    )

    result = posts_index_used and no_temp_sort and follows_index_used
    if not result:
        # Debug aid — the §6.1 valódi-sértés próba relies on this
        # helper; surfacing the actual plan here makes a regression
        # easy to diagnose (``posts_index_used`` alone is not enough
        # — the temp-sort signal is what tells you the index is not
        # actually driving the sort).
        import sys as _sys

        _sys.stderr.write(
            "\n[query_plan_uses_feed_index] plan did NOT use feed index:\n"
            f"  posts_index_used={posts_index_used}\n"
            f"  no_temp_sort={no_temp_sort}\n"
            f"  follows_index_used={follows_index_used}\n"
            f"  plan={plan_text!r}\n"
        )
        _sys.stderr.flush()
    return result


# ---------------------------------------------------------------------------
# Re-export of Kör 8 helpers that the router may want to surface
# (the §D2 "single source of truth for the symmetric block predicate"
# invariant — the feed MUST go through ``filter_public_ids_against_viewer_blocks``,
# not a parallel implementation).
# ---------------------------------------------------------------------------


__all__ = [
    "DEFAULT_PAGE_SIZE",
    "FEED_AUDIENCE_ALLOWLIST",
    "FEED_CURSOR_VERSION",
    "FeedItemRow",
    "FeedPage",
    "MAX_PAGE_SIZE",
    "list_following_feed",
    "query_plan_uses_feed_index",
]
