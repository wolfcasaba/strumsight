"""Club feed read path — E09-R25, ADR 0420 §D2.

The single repository for the ``GET /community/clubs/{id}/feed``
endpoint. The function :func:`list_club_feed` is responsible for
the end-to-end read path: club-membership gating, audience / block /
mute / moderation / deletion filtering, stable ordering, and
HMAC-signed cursor — all reused from the Kör 13
``following_feed.py`` projection (per §5.1, the club feed is a
MEMBERSHIP-anchored view of the shared ``community_posts`` table).

This module owns three concerns:

* **Server-side club membership gate (A1, A6).** The first SQL
  hop resolves the club by ``public_id`` and confirms the viewer
  is a member of that club. A non-member's request fails the
  membership probe and the service raises
  :class:`ClubNotVisible` — the §A1 invariant. The membership
  check is also the §A6 block-side gate's pivot: even when the
  viewer is a member, the page-level block filter drops any row
  whose author is in a block relation with the viewer (mirroring
  the Kör 13 / Kör 8 ``filter_public_ids_against_viewer_blocks``
  helper).

* **Shared post projection (Kör 13 reuse, §5.1).** The candidate
  SELECT is the SAME projection the Kör 13 ``following_feed.py``
  uses — ``(created_at DESC, id DESC)`` ordering, the same
  audience allowlist (``public`` / ``followers``), the same
  moderation / soft-delete filters, the same batched block /
  mute helper. The only difference is the WHERE-clause anchor:
  a single ``club_id = :club_id`` predicate instead of a
  ``profile_id IN (...)`` follow-set probe. Reusing the
  projection is the §5.1 architectural choice — a separate
  ``club_posts`` table would duplicate the moderation / block /
  audience logic (the §5.1 NEM elfogadható gyengítés).

* **Opaque, HMAC-signed cursor (§A7).** The cursor encodes the
  ``(created_at, id, feed_version)`` triple — the last RETURNED
  row's sort key plus a STATIC ``CLUB_FEED_CURSOR_VERSION``
  integer constant. The HMAC key is threaded in from the
  router (``settings.secret_key``); tests pass a fixture-local
  value. The cursor's last row is a KEPT row (a block / mute
  filter did not drop it), so a blocked author's sort-key pair
  cannot leak through the cursor channel (the Kör 13 fix).

The module is DB-coupled (SQLAlchemy ``Session``) and pure with
respect to HTTP — the router translates the returned envelope
into JSON. The cursor's ``secret_key`` is threaded in from the
router (the same ``settings.secret_key`` the JWT layer uses;
tests pass a fixture-local value).
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

from ..models.club import (
    CLUB_ROLE_ALLOWLIST,
    CommunityClub,
    CommunityClubMember,
)
from ..models.post import (
    MODERATION_STATE_VISIBLE,
    CommunityPost,
)
from ..models.profile import CommunityProfile
from ..models.safety_relationships import CommunityMute
from ..policies.query_filters import (
    filter_public_ids_against_viewer_blocks,
)

# ---------------------------------------------------------------------------
# Feed-version constant — mirrors the Kör 13 ``FEED_CURSOR_VERSION``.
# ---------------------------------------------------------------------------

#: Static cursor version — bumping this on a future migration breaks
#: cursor compatibility (old ``next_cursor`` tokens return ``None``)
#: so the client transparently starts at page one again. ADR 0406
#: D5 prescribes an integer; using ``str`` here would silently drift
#: the on-the-wire payload from the architectural decision.
CLUB_FEED_CURSOR_VERSION: Final[int] = 1

#: Default page size — the value the router uses when the client
#: omits ``page_size``. Mirrors the schema default.
DEFAULT_PAGE_SIZE: Final[int] = 25

#: Maximum page size — the absolute cap. Mirrors the schema constant;
#: this module enforces the same clamp on the actual row count
#: fetched (``LIMIT :limit_plus_one``).
MAX_PAGE_SIZE: Final[int] = 50

#: Audience allowlist — the only ``audience`` values that are allowed
#: in the club-feed read path. Mirrors the Kör 13
#: ``FEED_AUDIENCE_ALLOWLIST`` exactly (F4 fix: explicit whitelist,
#: NOT a ``!= 'private'`` denylist, so a future audience value
#: introduced at the Pydantic layer without an explicit migration
#: does NOT silently leak through the SQL filter).
CLUB_FEED_AUDIENCE_ALLOWLIST: Final[tuple[str, ...]] = ("public", "followers")

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
class ClubFeedItemRow:
    """One post row the club-feed repository returns.

    The shape mirrors the Kör 13 :class:`following_feed.FeedItemRow`
    so the same schema layer can render either feed without a
    second dataclass. The ``audience`` is restricted to the
    :data:`CLUB_FEED_AUDIENCE_ALLOWLIST` set; the validation lives
    in :func:`list_club_feed`.
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
class ClubFeedPage:
    """One cursor-paginated page of club-feed items.

    The ``items`` are :class:`ClubFeedItemRow` instances. The
    ``next_cursor`` is ``None`` on the last page; otherwise it is
    the HMAC-signed token the client forwards as the next
    request's ``cursor`` parameter.
    """

    items: tuple[ClubFeedItemRow, ...]
    next_cursor: str | None


# ---------------------------------------------------------------------------
# Cursor signing / verification — HMAC-SHA256, the Kör 13 pattern.
# ---------------------------------------------------------------------------


def _sign_cursor(
    cursor_secret: str,
    *,
    created_at: datetime,
    post_id: int,
    feed_version: int = CLUB_FEED_CURSOR_VERSION,
) -> str:
    """Build the opaque pagination token.

    The payload encodes ``(created_at, post_id, feed_version)`` —
    the last RETURNED row's sort key plus a static version marker.
    The wire shape is ``<base64url(json)>.<base64url(hmac)>``; the
    client forwards it verbatim and the repository validates the
    signature before trusting the embedded sort key (the §A7
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
        if version != CLUB_FEED_CURSOR_VERSION:
            # A future migration bumping CLUB_FEED_CURSOR_VERSION turns
            # legacy cursors into a fresh first page automatically
            # — the §A7 forward-compat seam.
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
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class ClubNotVisible(Exception):
    """The club is not visible to this caller.

    Raised on every "not visible FOR YOU" branch: the club does
    not exist by ``public_id``; the club is soft-deleted; or the
    viewer is not a member of the club. The HTTP layer cannot
    distinguish the cases from the exception type alone — that
    is the §A1 / D7 uniform 404 IDOR guarantee (a non-member
    cannot distinguish "exists, hidden" from "no such club").
    """


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _resolve_visible_club_for_member(
    db: Session,
    *,
    club_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> CommunityClub:
    """Return the club row if it exists, is not soft-deleted, AND the
    viewer is a member.

    Raises :class:`ClubNotVisible` on every "not visible" branch
    (the §A1 uniform 404 invariant). The membership probe uses a
    single SELECT against ``community_club_members`` —
    ``profile_id = viewer AND club_id = club.id`` — so a viewer
    who is NOT a member of the club pays the cost of one extra
    round-trip to be rejected at the boundary.

    Note: the owner of a ``public`` or ``discoverable`` club is
    expected to also be a member row (the Kör 24
    ``create_club`` path inserts the owner with role ``owner``
    immediately). For ``private`` clubs, only members can see the
    feed — which is exactly the §A1 / §A6 invariant.
    """
    club = (
        db.query(CommunityClub)
        .filter_by(public_id=club_public_id, deleted_at=None)
        .one_or_none()
    )
    if club is None:
        raise ClubNotVisible("club not found")

    is_member = (
        db.query(CommunityClubMember.id)
        .filter(
            CommunityClubMember.club_id == club.id,
            CommunityClubMember.profile_id == viewer_profile_id,
        )
        .limit(1)
        .first()
    )
    if is_member is None:
        raise ClubNotVisible("club not found")

    return club


# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------


def list_club_feed(
    db: Session,
    *,
    viewer_profile_id: int,
    club_public_id: uuid.UUID,
    cursor: str | None,
    page_size: int,
    cursor_secret: str,
) -> ClubFeedPage:
    """Return one cursor-paginated page of the viewer's club feed.

    Parameters
    ----------
    db:
        The SQLAlchemy session. Owning it lets the router wrap
        the call in a single, short-lived transaction.
    viewer_profile_id:
        The internal PK of the caller. The membership probe and
        the block / mute filters are anchored to this id; the
        endpoint cannot be served without it.
    club_public_id:
        The public UUID of the club whose feed the caller is
        reading. The membership probe is anchored to this id; a
        non-member raises :class:`ClubNotVisible` (the §A1
        IDOR guarantee).
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
    ClubFeedPage
        The ``items`` are :class:`ClubFeedItemRow` instances,
        ordered ``(created_at DESC, id DESC)``. The
        ``next_cursor`` is ``None`` when there are no more
        rows; it is the HMAC-signed position of the LAST
        RETURNED item — never a filtered-out row, so a
        blocked / muted author's ``created_at`` / ``id`` pair
        cannot leak through the cursor channel.
    """
    if page_size < 1:
        # Defensive — the router / schema already enforce this.
        page_size = 1
    if page_size > MAX_PAGE_SIZE:
        page_size = MAX_PAGE_SIZE

    # Resolve the club + viewer membership (A1 gate). A
    # non-member's request fails this probe and the service raises
    # ClubNotVisible — the §A1 invariant.
    club = _resolve_visible_club_for_member(
        db,
        club_public_id=club_public_id,
        viewer_profile_id=viewer_profile_id,
    )

    # Decode the cursor once — ``None`` means "fresh first page".
    decoded_cursor: tuple[datetime, int] | None = None
    if cursor is not None:
        decoded_cursor = _verify_cursor(cursor_secret, cursor)
        # A malformed / forged cursor falls back to a fresh first
        # page (the security boundary never silently passes a
        # malicious cursor through — the §A7 invariant).

    # Step 1: the candidate SELECT — posts whose ``club_id`` matches
    # the club's internal id, ordered by the (created_at, id) index,
    # with moderation / deletion / audience filters applied. This
    # is the SAME projection the Kör 13 ``list_following_feed``
    # uses, with the WHERE-clause anchored on ``club_id`` instead
    # of a materialised follow-set IN list (the §5.1 reuse).
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
            CommunityPost.club_id == club.id,
            CommunityPost.deleted_at.is_(None),
            CommunityPost.moderation_state == MODERATION_STATE_VISIBLE,
            # Audience allowlist (F4 fix): explicit whitelist, NOT a
            # ``!= 'private'`` denylist. A future audience value
            # introduced at the Pydantic layer without an explicit
            # migration does NOT silently leak through the SQL
            # filter. The Kör 13 / Kör 11 access policy mirrors
            # this set.
            CommunityPost.audience.in_(CLUB_FEED_AUDIENCE_ALLOWLIST),
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
        return ClubFeedPage(items=(), next_cursor=None)

    # The block-filter (Kör 8 symmetric helper). The candidate
    # ``profile_id`` set is small (page-sized), so the page-level
    # filter is one round-trip against the viewer's block table —
    # NOT an N+1 ``is_blocked_pair`` call per row. Mirrors the Kör
    # 13 ``list_following_feed`` exactly (the §A6 invariant).
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
    # build our own batched set here — the §D3 explicit
    # instruction, mirrored from the Kör 13 feed.
    muted_author_pks: set[int] = set()
    if candidate_profile_ids:
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
        ClubFeedItemRow(
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

    return ClubFeedPage(items=items, next_cursor=next_cursor)


__all__ = [
    "CLUB_FEED_AUDIENCE_ALLOWLIST",
    "CLUB_FEED_CURSOR_VERSION",
    "DEFAULT_PAGE_SIZE",
    "ClubFeedItemRow",
    "ClubFeedPage",
    "ClubNotVisible",
    "MAX_PAGE_SIZE",
    "list_club_feed",
]


# Re-export of the allowed-role set — the router layer uses it for
# the §A3 "pin/moderation permission check" branch. Re-exported here
# (and NOT in the permission matrix module) to keep the matrix
# closed to additions this round — the matrix file is NOT on the
# round's ``allowed_paths`` and a future round will own a formal
# ``ClubAction.PIN_POST`` extension.
CLUB_PIN_AUTHORIZED_ROLES: Final[frozenset[str]] = CLUB_ROLE_ALLOWLIST
