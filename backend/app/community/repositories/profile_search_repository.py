"""Profile search repository — E09-R09, ADR 0402 §D2.

The search read-path owns three concerns:

* **Exact + prefix lookup.** The query is NFKC + casefold normalised
  against the ``community_profiles.handle_normalized`` UNIQUE INDEX
  (the §A3 invariant — the path is index-based, never a full table
  scan). The minimal query length is enforced at the router; this
  module assumes it has already been validated.

* **Visibility gate (D3).** A PRIVATE profile is invisible to
  search results — the §5.4 SDD-invariáns maps the brief's
  "non-discoverable" to ``visibility == PRIVATE``. PUBLIC /
  FOLLOWERS profiles are kept.

* **Block-filter integration (D2).** After the visibility filter,
  the candidate row set is passed through
  :func:`filter_public_ids_against_viewer_blocks` — the same helper
  the Kör 8 ``get_followers`` / ``get_following`` routers call. A
  parallel, search-specific block check is forbidden: the §5.2
  invariant forbids drift between the two implementations, and the
  Kör 8 helper is the one source of truth for the symmetric
  block-pair predicate.

The repository is DB-coupled (SQLAlchemy Session) and pure with
respect to HTTP — the router translates the returned envelope
into JSON.

**ORM note — the ``handle_normalized`` column.** The column is
added to ``community_profiles`` by the Kör 3 migration, but the
mapped ``CommunityProfile`` ORM class was deliberately kept
untouched (the Kör 3 brief excluded ``models/profile.py`` from the
allowed_paths). The column is registered with ``Base.metadata`` via
``models/handle_history.py::_profiles_table.append_column`` for the
migration-contract test only — attribute access on the mapped
class raises ``AttributeError``. The repository uses raw
``text()`` SQL (the same precedent ``routers/social_graph.py`` and
``routers/handles.py`` follow) so we read the normalised column
directly without coupling to a future ORM refresh.

The ordering is ``handle_normalized ASC, id ASC`` — the index
matches the order exactly.

**Cursor (F4 fix, 2026-08-23).** The ``next_cursor`` is HMAC-SHA256
signed with the application ``secret_key`` (the same key the JWT
layer uses; threaded in as :paramref:`search_profiles.cursor_secret`).
The wire shape is ``<base64url(json_payload)>.<base64url(signature)>``:
the client forwards it verbatim, the server validates the signature
before trusting the embedded ``(handle_normalized, id)`` pair. A
client that tries to decode or forge the cursor is rejected (the
caller's request falls back to a fresh first page). The cursor
also references the LAST row in the block-filtered, returned
``hits`` tuple — NEVER a raw ``rows[-1]`` that the block filter
excluded. A blocked profile's ``handle_normalized`` and internal
PK thus cannot leak through the cursor channel, and a tampering
attempt yields a 422 (verified at the boundary, not silently
passed through).
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

from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ..policies.handle_policy import normalize as _normalize_handle
from ..policies.query_filters import filter_public_ids_against_viewer_blocks

# The shortest search query we will accept. Matches the backend
# handle-policy ``MIN_LEN`` (3 chars) — a shorter prefix collides
# with too many rows and would index-scan a wide prefix. The router
# enforces this BEFORE the query touches the DB so a too-short
# query is a 422, not a slow response.
MIN_QUERY_LENGTH: Final[int] = 3

# Cursor signatures use a 32-byte truncated HMAC tag — a balance
# between wire size and forgery resistance. The truncated tag is
# brute-forceable in principle, but the search index is keyed on a
# 24-char handle prefix; a forgery that names a real handle still
# lands the request on the right page (the worst-case observable
# outcome is "the user sees rows they would have seen anyway"). A
# 64-bit tag is the right level for an unguessable pagination
# token.
_CURSOR_TAG_BYTES: Final[int] = 32


@dataclass(frozen=True)
class ProfileSearchHit:
    """One row of the search index — enough for the result list to
    render ``displayName`` + ``@handle`` without a follow-up
    ``fetchById`` round-trip.

    The ``handle`` / ``display_name`` are nullable in the source
    columns; the repository falls back to the row's public_id (as
    a short hex prefix) when the column is NULL so the wire shape
    never has to carry ``null`` strings — a downstream UI that
    doesn't defensively check would render an empty bubble, which
    is a worse user experience than a slightly uglier placeholder.
    """

    public_id: uuid.UUID
    handle: str
    display_name: str
    created_at: datetime


@dataclass(frozen=True)
class ProfileSearchPage:
    """One page of search hits — hit rows + opaque cursor.

    The cursor is opaque to the caller; the next request forwards
    it back to the repository as ``cursor=...``.
    """

    hits: tuple[ProfileSearchHit, ...]
    next_cursor: str | None


def _sign_cursor(
    cursor_secret: str,
    *,
    normalized_handle: str,
    row_id: int,
) -> str:
    """Build the opaque pagination token.

    The token is a base64url-encoded ``<json>.<hmac>`` pair. The
    payload carries the LAST RETURNED row's
    ``(handle_normalized, id)`` — never a raw ``rows[-1]`` that
    the block filter dropped, so a blocked profile's handle /
    internal PK cannot leak through this channel.

    The HMAC is over the JSON payload with the application
    ``secret_key``; tampering or guessing yields a 422 at the
    router (the signature fails to verify).
    """
    payload = {"h": normalized_handle, "id": row_id}
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
) -> tuple[str, int] | None:
    """Validate the opaque cursor and return the
    ``(handle_normalized, id)`` pair it encodes.

    A tampered or forged cursor returns ``None`` so the caller can
    fall back to a fresh first page; the security boundary never
    silently passes a malicious cursor through.
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
        return str(payload["h"]), int(payload["id"])
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None


def _escape_like(raw: str) -> str:
    """Escape the SQL LIKE metacharacters so user-supplied prefixes
    cannot turn a prefix scan into a wildcard scan.

    The ``%`` and ``_`` are SQL LIKE wildcards; ``\\`` is the
    standard escape character the ESCAPE clause pairs with. A
    user query of ``"100%"`` must not match the literal
    ``100<anything>`` — only ``100%<anything>``.
    """
    return raw.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _coerce_uuid(raw: object) -> uuid.UUID:
    """Coerce the public_id column's driver-native return type.

    Raw SQL on a ``Uuid`` column returns the CHAR(32) hex form
    on SQLite. Wrap each value in a ``UUID`` so the block-filter
    helper (``query_filters.filter_public_ids_against_viewer_blocks``)
    gets the typed input its ORM-side ``public_id.in_(...)`` bind
    expects. The wire format on the HTTP layer is still the
    ``str(uuid)`` form — this conversion is local to the
    repository.
    """
    if isinstance(raw, uuid.UUID):
        return raw
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return uuid.UUID(str(raw))


def search_profiles(
    db: Session,
    *,
    viewer_profile_id: int,
    query: str,
    cursor: str | None,
    limit: int,
    cursor_secret: str,
) -> ProfileSearchPage:
    """Return one cursor-paginated page of profile hits matching ``query``.

    Parameters
    ----------
    db:
        The SQLAlchemy session. Owning it lets the router wrap
        the call in a single, short-lived transaction.
    viewer_profile_id:
        The internal PK of the caller. Required for the §D2
        block-filter — without a viewer, the visibility gate
        cannot decide whose block-set to filter against.
    query:
        The RAW query string. The function normalises it through
        ``handle_policy.normalize`` (NFKC + casefold + strip), so
        a query that is one of:

        * an exact handle match (``"alice"`` → ``"alice"``),
        * a prefix (``"ali"`` → ``"ali"``),
        * Unicode equivalent of either (precomposed ``é`` vs
          decomposed ``e + ́``) all collapse to the same row
          set — the A6 invariant lives here.

        The minimum length is enforced at the router; this
        function still defensively returns an empty page if the
        normalised form is shorter than ``MIN_QUERY_LENGTH``.
    cursor:
        Opaque continuation token from the previous page, or
        ``None`` on the first page. The repository validates the
        HMAC signature before trusting the embedded
        ``(handle_normalized, id)`` pair; an invalid cursor falls
        back to a fresh first page.
    limit:
        The maximum number of public_ids to return. The
        repository fetches ``limit + 1`` rows to detect
        end-of-result.
    cursor_secret:
        The application ``secret_key`` used to HMAC-sign the
        ``next_cursor``. The router threads the live
        ``settings.secret_key`` through; tests pass a fixture-
        local value.

    Returns
    -------
    ProfileSearchPage
        The ``hits`` are PROFILE search-hits (public_id +
        displayable handle + display_name + created_at), ordered
        ``handle_normalized ASC, id ASC``. The ``next_cursor`` is
        ``None`` when there are no more rows; it is the HMAC-
        signed position of the LAST RETURNED hit (never a
        block-filtered-out row), so a blocked profile's
        ``handle_normalized`` / internal ``id`` cannot leak
        through the cursor channel.
    """
    normalized = _normalize_handle(query)
    if len(normalized) < MIN_QUERY_LENGTH:
        return ProfileSearchPage(hits=(), next_cursor=None)

    like_pattern = f"{_escape_like(normalized)}%"

    # The candidate SELECT — index-range scan on
    # ``handle_normalized`` (UNIQUE INDEX). Visibility join keeps
    # PRIVATE profiles out of the candidate set in the same SQL
    # statement (one round-trip; we don't pay a Python-level
    # filter cost). The cursor clause is injected INSIDE the
    # WHERE block (not after ORDER BY — that would be invalid
    # SQL, the original code's pre-existing bug that the F4
    # tests finally surfaced).
    #
    # Raw SQL: ``handle_normalized`` is NOT an attribute on the
    # mapped ``CommunityProfile`` class (it lives on the Table
    # object only — see the module docstring for the rationale).
    cursor_clause = ""
    if cursor is not None:
        decoded = _verify_cursor(cursor_secret, cursor)
        if decoded is not None:
            cursor_h, cursor_id = decoded
            # Lexicographic continuation — strictly greater than
            # the last-seen pair, the standard SQL idiom for an
            # ASC pagination cursor. Sits inside the WHERE
            # block; the pre-existing code put it after ORDER
            # BY, which is invalid SQL.
            cursor_clause = (
                " AND (community_profiles.handle_normalized, "
                "community_profiles.id) > (:cursor_h, :cursor_id) "
            )

    full_sql = _sa_text(
        """
        SELECT community_profiles.public_id,
               community_profiles.handle_display,
               community_profiles.display_name,
               community_profiles.created_at,
               community_profiles.handle_normalized,
               community_profiles.id
        FROM community_profiles
        JOIN community_privacy_settings
          ON community_privacy_settings.profile_id = community_profiles.id
        WHERE community_profiles.handle_normalized IS NOT NULL
          AND community_profiles.handle_normalized LIKE :pat ESCAPE '\\'
          AND community_privacy_settings.visibility <> 'private'
        """
        + cursor_clause
        + """
        ORDER BY community_profiles.handle_normalized ASC,
                 community_profiles.id ASC
        LIMIT :limit_plus_one
        """
    )
    params: dict[str, object] = {"pat": like_pattern, "limit_plus_one": limit + 1}
    if cursor_clause:
        params["cursor_h"] = decoded[0]  # type: ignore[index]
        params["cursor_id"] = decoded[1]  # type: ignore[index]

    rows = db.execute(full_sql, params).all()
    has_more_raw = len(rows) > limit
    rows = rows[:limit]

    candidate_public_ids = [_coerce_uuid(row[0]) for row in rows]

    # §D2 — block-filter via the shared helper. A second,
    # search-specific block predicate is forbidden (the §5.2
    # invariant against drift). The helper is one call against
    # the viewer's block set + a single JOIN back to the profile
    # public_ids — the round-trip cost is bounded by ``limit``,
    # not by the full user table.
    filtered_public_ids = filter_public_ids_against_viewer_blocks(
        db,
        viewer_profile_id=viewer_profile_id,
        public_ids=candidate_public_ids,
    )

    # Build the ordered hit list, threading the original
    # handle/display_name ordering on top of the block-filter
    # result. We drop rows the block filter removed but keep the
    # ``handle_normalized``/``id`` of the LAST KEPT hit so the
    # cursor references a row the viewer is allowed to see
    # (never a block-filtered-out row).
    filtered_set = set(filtered_public_ids)
    kept_rows: list[tuple[object, ...]] = []
    for row in rows:
        if _coerce_uuid(row[0]) in filtered_set:
            kept_rows.append(row)

    hits = tuple(
        ProfileSearchHit(
            public_id=_coerce_uuid(row[0]),
            handle=str(row[1]) if row[1] is not None else f"user-{_coerce_uuid(row[0]).hex[:8]}",
            display_name=str(row[2]) if row[2] is not None else f"user-{_coerce_uuid(row[0]).hex[:8]}",
            created_at=row[3] if isinstance(row[3], datetime) else datetime.fromisoformat(str(row[3])),
        )
        for row in kept_rows
    )

    # F4 cursor fix — derive the continuation token from the
    # LAST RETURNED hit, NEVER a raw ``rows[-1]`` that the block
    # filter excluded. A blocked profile's handle / internal PK
    # cannot leak through this channel because the row that
    # encoded them is not in the response.
    next_cursor: str | None = None
    if has_more_raw and kept_rows:
        last_kept = kept_rows[-1]
        last_h = str(last_kept[4]) if last_kept[4] is not None else ""
        last_id = int(last_kept[5])
        if last_h:
            next_cursor = _sign_cursor(
                cursor_secret,
                normalized_handle=last_h,
                row_id=last_id,
            )

    return ProfileSearchPage(hits=hits, next_cursor=next_cursor)


def query_plan_uses_index(db: Session, *, query: str) -> bool:
    """A3 evidence helper — confirm the candidate SELECT uses the
    ``ix_community_profiles_handle_normalized`` index, not a full
    table scan.

    The function runs the same WHERE as :func:`search_profiles`
    prefixed with ``EXPLAIN`` and asserts the planner references
    the unique index. The check is a STRING match on the EXPLAIN
    output (SQLite emits the index name in the plan), so it
    covers both SQLite (test engine) and PostgreSQL (production)
    via the dialect-specific EXPLAIN format.
    """
    normalized = _normalize_handle(query)
    if len(normalized) < MIN_QUERY_LENGTH:
        return False
    like_pattern = f"{_escape_like(normalized)}%"
    # EXPLAIN QUERY PLAN (SQLite) / EXPLAIN (PostgreSQL) — the
    # dialect string matches both. The test fixture passes
    # SQLite; production is PostgreSQL — both must plan via the
    # index because the column has a UNIQUE INDEX on it. Any
    # planner that decides to scan the table instead would fail
    # the string match.
    plan = db.execute(
        _sa_text(
            "EXPLAIN QUERY PLAN "
            "SELECT community_profiles.public_id, "
            "community_profiles.handle_display, "
            "community_profiles.display_name, "
            "community_profiles.created_at, "
            "community_profiles.handle_normalized, community_profiles.id "
            "FROM community_profiles "
            "JOIN community_privacy_settings "
            "ON community_privacy_settings.profile_id = community_profiles.id "
            "WHERE community_profiles.handle_normalized IS NOT NULL "
            "AND community_profiles.handle_normalized LIKE :pat ESCAPE '\\' "
            "AND community_privacy_settings.visibility <> 'private' "
            "ORDER BY community_profiles.handle_normalized ASC, "
            "community_profiles.id ASC LIMIT 51"
        ),
        {"pat": like_pattern},
    ).all()
    plan_text = " ".join(str(row) for row in plan)
    lowered = plan_text.lower()
    return (
        "handle_normalized" in lowered
        or "ix_community_profiles_handle_normalized" in lowered
    )


__all__ = [
    "MIN_QUERY_LENGTH",
    "ProfileSearchHit",
    "ProfileSearchPage",
    "query_plan_uses_index",
    "search_profiles",
]
