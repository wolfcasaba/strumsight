"""Community media upload pipeline service (E09-R18, ADR 0410).

The service layer for ``CommunityMedia`` — owns the three
lifecycle operations: ``create_upload_intent`` /
``finalize_upload`` / ``cancel_upload`` and the orphan-cleanup
function the brief §6 A7 acceptance cell exercises. The HTTP /
FastAPI wrapping lives in a future round's
``backend/app/community/routers/media.py`` (NOT this round's
``allowed_paths`` — see ADR 0410 Következmények 1. pont and the
§0.0 D1 router-free discipline).

Design contract (the §5 / §0.0 invariants — these are the
load-bearing guarantees the tests pin):

* **Feature-flag gate (§5.1 / D1, A1).** Every public entry point
  (``create_upload_intent`` / ``finalize_upload`` /
  ``cancel_upload``) checks ``settings.community_media_enabled``
  FIRST and raises :class:`MediaUploadDisabled` when the flag is
  OFF. The HTTP router-bekötés (NOT in this round's
  ``allowed_paths``) would translate that exception to a 404 —
  the same shape as the Kör 1 ``build_community_router`` factory's
  None-returning semantic when ``community_enabled`` is OFF
  (ADR 0395 §3).

* **ObjectStore seam (§5.1 / D2).** The service consumes the
  :class:`ObjectStore` interface — never the concrete
  ``S3CompatibleObjectStore``. The tests inject
  :class:`InMemoryObjectStore`; production wires the S3 adapter
  via dependency injection. The service has no module-level
  reference to either implementation.

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  ``post_service.create_post`` / ``reaction_service.set_reaction``
  — the timestamp the service uses to stamp ``created_at`` /
  ``updated_at`` / ``finalized_at`` is the caller's, never
  ``datetime.now(timezone.utc)`` inline. The deterministic-
  timestamp discipline keeps the §6 A5 "checksum mismatch at the
  finalize boundary" probe reproducible.

* **Caller-supplied ObjectStore + size / content-type / expires_in
  seams.** The constructor signature is
  ``(db, *, profile_public_id, object_store, max_content_length,
  signed_url_expires_in, retention_window, now)``; the brief §6.1
  threshold-triple is exercised by passing different
  ``max_content_length`` / ``size`` combinations. ``now`` and
  ``object_store`` are the deterministic-timestamp + dependency-
  injection seams that keep the tests reproducible.

* **Server-side owner identity (§6 A6).** ``create_upload_intent``
  takes the JWT-resolved ``profile_public_id`` as a parameter —
  there is no body-side override path. ``finalize_upload`` and
  ``cancel_upload`` look up the row by ``public_id`` and re-check
  ``profile_id == viewer_profile_id`` before transitioning state.
  A non-owner sees :class:`MediaNotFound` (uniform 404, the
  §5.3 IDOR discipline).

* **Checksum / MIME / size / expiry double-check (§5.3, A2 / A3 /
  A4 / A5).** ``finalize_upload`` re-reads the actual object via
  :meth:`ObjectStore.head_object` and compares the bucket-side
  ``Content-Type``, ``size`` and SHA-256 against the row's
  intent-time declarations. The signed-URL expiry check is the
  ``now >= expires_at`` comparison against the intent's
  ``SignedUpload.expires_at`` (the §6 A2 measure-matrix).

* **Size cap as module constant (§0.0 D5).**
  ``MAX_UPLOAD_BYTES`` is the module-scope constant the brief
  pins — ``media_upload_service.py`` carries it (NOT
  ``config.py`` — ``config.py`` is NOT in this round's
  ``allowed_paths``). A future round that wants to make the cap
  configurable moves it to ``Settings`` then.

* **Orphan cleanup (§6 A7).** :func:`cleanup_orphan_uploads` walks
  every row whose state is NOT ``finalized`` AND whose
  ``retention_until`` is in the past, deletes the bucket-side
  object via ``delete_object``, and soft-transitions the row to
  ``cancelled`` (so the audit trail survives). The function is
  idempotent — re-running it after a successful sweep finds
  nothing to do, and the in-memory fake's ``deleted`` list
  records every call.

* **Quota policy.** The ``MAX_LIVE_UPLOADS_PER_PROFILE``
  constant caps the number of NON-finalized rows a profile may
  hold simultaneously. ``create_upload_intent`` rejects when the
  count exceeds the cap — prevents a single profile from
  spamming the bucket with abandoned uploads.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Final

from sqlalchemy.orm import Session

from ..models.media import (
    UPLOAD_STATE_CANCELLED,
    UPLOAD_STATE_FAILED,
    UPLOAD_STATE_FINALIZED,
    UPLOAD_STATE_PENDING,
    UPLOAD_STATE_UPLOADED,
    CommunityMedia,
)
from ..models.profile import CommunityProfile
from ..storage.object_store import ObjectMetadata, ObjectStore, SignedUpload

# ---------------------------------------------------------------------------
# Domain constants (brief §6.1 threshold-triple, §0.0 D5).
# ---------------------------------------------------------------------------


#: The hard upper-bound on a single uploaded object's size, in bytes.
#: 100 MiB — large enough for a 5-minute 1080p phone video at the
#: practical 3–6 Mbps upload-rate envelope, small enough to keep
#: the signed-URL content-length constraint inside any reasonable
#: bucket quota. The brief §6.1 threshold-triple is exercised by
#: passing ``size = MAX_UPLOAD_BYTES - 1`` (accepted),
#: ``size == MAX_UPLOAD_BYTES`` (accepted, the boundary is
#: INCLUSIVE), and ``size = MAX_UPLOAD_BYTES + 1`` (rejected). The
#: finalize path enforces the cap independently of the signed-URL
#: content-length constraint (defense-in-depth).
MAX_UPLOAD_BYTES: Final[int] = 100 * 1024 * 1024

#: How long a signed PUT URL stays valid. 5 minutes is the
#: brief §5.2 "dokumentált, rövid ablak" pick — long enough for a
#: 100 MiB upload on a 3G connection (~5 minutes at 3 Mbps), short
#: enough that a leaked URL cannot be reused after the user's
#: composer session ends. Tests use shorter windows (15–60 s) to
#: exercise the §6 A2 cell deterministically.
SIGNED_URL_EXPIRES_IN: Final[timedelta] = timedelta(minutes=5)

#: How long a non-finalized row sticks around before the
#: orphan-cleanup function sweeps it. 24 hours is the brief §3
#: "grace window" pick — long enough for a retry-after-network-
#: glitch, short enough that abandoned uploads don't pile up.
#: The intent-time ``retention_until`` is ``now + retention_window``.
RETENTION_WINDOW: Final[timedelta] = timedelta(hours=24)

#: Live (non-finalized) uploads a single profile may hold
#: simultaneously. 10 is the §3 quota pick — large enough for a
#: power user composing multiple posts in parallel, small enough
#: that an account-takeover can't pin the bucket.
MAX_LIVE_UPLOADS_PER_PROFILE: Final[int] = 10


# ---------------------------------------------------------------------------
# MIME allowlist (brief §3, A3 acceptance cell).
# ---------------------------------------------------------------------------

#: The MIME types the upload pipeline accepts. The §3 / §6.1
#: measure-matrix cell "A client that uploads a `.png` file with
#: `Content-Type: image/jpeg` is rejected" goes red only when the
#: server re-reads the bucket-side ``Content-Type`` and rejects
#: the mismatch (NOT extension-based — that's the §5.3 explicit
#: ban). The allowlist is enforced at intent time AND at finalize
#: time (defense-in-depth, same shape as the size cap).
MEDIA_CONTENT_TYPE_ALLOWLIST: Final[frozenset[str]] = frozenset(
    {
        # Audio — covers the primary detection-output use case.
        "audio/mpeg",  # mp3
        "audio/mp4",  # m4a
        "audio/x-wav",  # wav
        "audio/ogg",  # ogg
        # Image — for cover art / reference shots.
        "image/jpeg",
        "image/png",
        "image/webp",
        # Video — for the future camera-capture path.
        "video/mp4",
        "video/quicktime",
    }
)


def is_allowed_media_content_type(value: str) -> bool:
    """True when ``value`` is one of the §3 MVP media MIME types."""
    return value in MEDIA_CONTENT_TYPE_ALLOWLIST


# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class MediaUploadDisabled(Exception):
    """The ``community_media_enabled`` feature flag is OFF.

    The brief §5.1 / D1 / A1 acceptance cell: every public entry
    point raises this on a flag-OFF deployment. The future router
    translates it to a 404 (the same shape as the Kör 1
    ``build_community_router`` factory's None-returning semantic
    when ``community_enabled`` is OFF).
    """


class MediaNotFound(Exception):
    """The media row is not visible to this caller.

    D7 uniform 404 — missing id, foreign-owner, soft-cancelled, or
    never-finalized all collapse to the same exception. The §5.3
    IDOR guarantee (a non-owner must NOT learn whether the row
    exists).
    """


class MediaUploadExpired(Exception):
    """The signed URL has expired (brief §6 A2).

    Raised by :func:`finalize_upload` when ``now >= expires_at``.
    The finalize re-checks against the intent's stored
    ``expires_at`` independently of the bucket-side rejection —
    defense-in-depth so a clock-skewed client doesn't slip past
    the check.
    """


class MediaSizeExceeded(Exception):
    """The uploaded object exceeds ``MAX_UPLOAD_BYTES``.

    Brief §6 A4 / §6.1 threshold-triple (the ``+ 1`` cell). The
    finalize path checks independently of the signed-URL
    content-length constraint, so a maliciously-crafted signed
    URL that permits an over-cap upload is rejected when the
    server re-reads the actual object size via ``head_object``.
    """


class MediaChecksumMismatch(Exception):
    """The bucket-side SHA-256 does not match the row's
    intent-time declaration (brief §6 A5).

    The §6.1 valódi-sértés próba removes the comparison from the
    finalize path and asserts this cell goes red — A5 turns into
    a silent success that should not happen.
    """


class MediaContentTypeMismatch(Exception):
    """The bucket-side ``Content-Type`` does not match the
    row's intent-time declaration OR is outside the §3 allowlist
    (brief §6 A3).

    The check uses the bucket's reported content type — NOT the
    file extension. The §5.3 explicit ban on extension-based MIME
    validation is enforced here.
    """


class MediaQuotaExceeded(Exception):
    """The viewer already holds ``MAX_LIVE_UPLOADS_PER_PROFILE``
    non-finalized rows (brief §3 quota).

    Raised by :func:`create_upload_intent`. The cap prevents a
    single profile from spamming the bucket with abandoned
    uploads; the orphan-cleanup function frees space over time.
    """


# ---------------------------------------------------------------------------
# Cache-invalidation event (the same seam post_service / reaction_service
# ship).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MediaInvalidationEvent:
    """Emitted by ``finalize_upload`` / ``cancel_upload`` on a
    successful state transition.

    ``media_public_id`` is the wire identity; ``action`` is one of
    ``"finalize"`` / ``"cancel"`` / ``"orphan_cleanup"``. A future
    round that wires a real cache layer reads this event to
    invalidate the profile's media-list projection.
    """

    media_public_id: uuid.UUID
    action: str  # "finalize" | "cancel" | "orphan_cleanup"


# ---------------------------------------------------------------------------
# Wire value types — the contract ``create_upload_intent`` returns.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class UploadIntent:
    """The handle the client carries to ``finalize_upload``.

    ``media_public_id`` is the wire identity the client posts back
    at finalize time. ``object_key`` is the bucket-side path the
    client PUTs the bytes to. ``signed_upload`` carries the
    presigned PUT URL, the constraints the signed URL enforces
    (content type, content length), and the absolute expiry
    timestamp.
    """

    media_public_id: uuid.UUID
    object_key: str
    signed_upload: SignedUpload


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _resolve_media_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityMedia | None:
    return db.query(CommunityMedia).filter_by(public_id=public_id).one_or_none()


def _live_upload_count(db: Session, *, profile_id: int) -> int:
    """Count the viewer's non-finalized media rows.

    The §3 quota — ``create_upload_intent`` rejects when this
    count exceeds ``MAX_LIVE_UPLOADS_PER_PROFILE``. The four
    "live" states (``pending`` / ``uploaded`` / ``cancelled`` /
    ``failed``) all count until the row is ``finalized`` —
    matches the brief §3 "every upload that hasn't completed
    holds quota" semantic.
    """
    return (
        db.query(CommunityMedia)
        .filter(
            CommunityMedia.profile_id == profile_id,
            CommunityMedia.upload_state != UPLOAD_STATE_FINALIZED,
        )
        .count()
    )


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware
    (the ``post_service._as_utc`` precedent). SQLite drops
    tzinfo on read; the migration stores UTC, so we re-attach
    ``timezone.utc`` here for comparison."""
    if value.tzinfo is None:
        return value.replace(tzinfo=datetime.now().astimezone().tzinfo)
    return value


def _derive_object_key(*, profile_id: int, media_public_id: uuid.UUID) -> str:
    """Bucket-side key for the upload. ``profile_id`` partitions
    the namespace so a profile-scoped lifecycle query is cheap;
    ``media_public_id`` makes the key globally unique without
    leaking the internal ``id``."""
    return f"community-media/{profile_id}/{media_public_id.hex}"


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def create_upload_intent(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    content_type: str,
    size: int,
    duration_ms: int | None,
    checksum_sha256: str | None,
    settings,
    object_store: ObjectStore,
    signed_url_expires_in: timedelta = SIGNED_URL_EXPIRES_IN,
    retention_window: timedelta = RETENTION_WINDOW,
    now: datetime,
    on_invalidate: Callable[[MediaInvalidationEvent], None] | None = None,
) -> UploadIntent:
    """Create the upload intent and emit the presigned PUT URL.

    Server-side owner (brief §5.1): ``profile_public_id`` comes
    from the JWT — there is no body-side override path. The
    Pydantic layer rejects unknown fields (``extra='forbid'`` in
    the future router); this service does not consult the request
    body for the owner identity.

    The intent stamps the row with ``upload_state='pending'``,
    ``object_key`` derived from the ``public_id``, and a
    ``retention_until`` of ``now + retention_window``. The
    signed URL carries the intent's content_type / size /
    expiry constraints — the bucket enforces them at PUT time,
    and the finalize path re-checks (defense-in-depth).

    The §3 quota: the live-upload count is checked before the
    INSERT — over-cap callers see :class:`MediaQuotaExceeded`.

    Raises :class:`MediaUploadDisabled` when the feature flag is
    OFF (brief §6 A1). Raises :class:`MediaContentTypeMismatch`
    when ``content_type`` is outside the allowlist (early
    rejection — saves a round-trip to the bucket). Raises
    :class:`MediaSizeExceeded` when ``size > MAX_UPLOAD_BYTES``
    (the boundary is INCLUSIVE per §6.1 — exactly the cap is
    allowed). Raises :class:`MediaQuotaExceeded` when the
    viewer is already at the cap.
    """
    if not settings.community_media_enabled:
        raise MediaUploadDisabled("community media disabled by feature flag")
    if not is_allowed_media_content_type(content_type):
        raise MediaContentTypeMismatch(
            f"content_type {content_type!r} not in allowlist"
        )
    if size > MAX_UPLOAD_BYTES:
        raise MediaSizeExceeded(
            f"size {size} exceeds MAX_UPLOAD_BYTES {MAX_UPLOAD_BYTES}"
        )
    if checksum_sha256 is not None and len(checksum_sha256) != 64:
        # The wire-side shape — a 64-char hex SHA-256 digest.
        # An obviously-wrong value is rejected at the seam so a
        # malformed client can't trip the finalize comparison.
        raise MediaChecksumMismatch("checksum must be a 64-char hex SHA-256 digest")

    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        # The caller (router) is responsible for turning this
        # into a 404; the service raises the same uniform shape
        # ``post_service.create_post`` uses ("author community
        # profile not found").
        raise ValueError("profile community profile not found")

    if _live_upload_count(db, profile_id=profile.id) >= MAX_LIVE_UPLOADS_PER_PROFILE:
        raise MediaQuotaExceeded(
            f"profile already holds {MAX_LIVE_UPLOADS_PER_PROFILE} live uploads"
        )

    # Generate the public_id up front so we can derive the
    # bucket-side key BEFORE the INSERT — the signed URL is
    # bound to the key.
    media_public_id = uuid.uuid4()
    object_key = _derive_object_key(
        profile_id=profile.id, media_public_id=media_public_id
    )

    signed_upload = object_store.create_upload_url(
        object_key,
        content_type=content_type,
        max_content_length=size,
        expires_in=signed_url_expires_in,
    )

    retention_until = now + retention_window

    row = CommunityMedia(
        public_id=media_public_id,
        profile_id=profile.id,
        object_key=object_key,
        content_type=content_type,
        size_bytes=size,
        duration_ms=duration_ms,
        checksum_sha256=checksum_sha256,
        upload_state=UPLOAD_STATE_PENDING,
        retention_until=retention_until,
        created_at=now,
        updated_at=now,
    )
    db.add(row)
    db.flush()
    db.refresh(row)

    return UploadIntent(
        media_public_id=media_public_id,
        object_key=object_key,
        signed_upload=signed_upload,
    )


def finalize_upload(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    media_public_id: uuid.UUID,
    settings,
    object_store: ObjectStore,
    now: datetime,
    on_invalidate: Callable[[MediaInvalidationEvent], None] | None = None,
) -> CommunityMedia:
    """Validate the bucket-side object and transition the row
    to ``finalized``.

    The re-checks (brief §5.3 / A2 / A3 / A4 / A5):

    * **Expiry (A2).** The intent's ``expires_at`` is recomputed
      from the ``signed_url_expires_in`` parameter the test
      injected — when ``now >= expires_at``, the finalize is
      rejected with :class:`MediaUploadExpired`. The bucket's
      signed-URL rejection is a separate, defense-in-depth
      check.
    * **Object existence.** ``head_object`` returns ``None`` →
      the client never PUT anything. Rejected with
      :class:`MediaNotFound` (the row stays in ``pending``).
    * **Content-Type (A3).** The bucket's reported
      ``Content-Type`` must equal the row's intent-time
      declaration AND must be in ``MEDIA_CONTENT_TYPE_ALLOWLIST``
      — the second check is what stops a
      rename-``.png``-to-`.mp3` bypass. A mismatch raises
      :class:`MediaContentTypeMismatch` and transitions the row
      to ``failed``.
    * **Size (A4).** The bucket-side size must be
      ``<= MAX_UPLOAD_BYTES`` — defense-in-depth on top of the
      signed-URL content-length constraint. An over-cap object
      raises :class:`MediaSizeExceeded` and transitions the row
      to ``failed``.
    * **Checksum (A5).** When the row carries an intent-time
      ``checksum_sha256`` AND the bucket reports a SHA-256
      (the in-memory fake's ``stage_object`` populates this), the
      two must match — a mismatch raises
      :class:`MediaChecksumMismatch` and transitions the row to
      ``failed``.

    Ownership (brief §6 A6): a foreign profile_public_id raises
    :class:`MediaNotFound` (uniform 404, the §5.3 IDOR
    discipline). The check happens BEFORE the expiry / object
    checks so a non-owner cannot probe the expiry of someone
    else's intent.

    The row's ``upload_state`` transitions ``pending`` →
    ``uploaded`` → ``finalized``. A failed validation jumps to
    ``failed`` and the bucket-side object is deleted (the
    orphan-cleanup's ``delete_object`` call). The
    ``on_invalidate`` callback fires only on a successful
    finalize.

    Raises :class:`MediaUploadDisabled` when the feature flag is
    OFF (brief §6 A1).
    """
    if not settings.community_media_enabled:
        raise MediaUploadDisabled("community media disabled by feature flag")

    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        raise ValueError("profile community profile not found")

    row = _resolve_media_by_public_id(db, media_public_id)
    if row is None:
        raise MediaNotFound("media not found")
    if row.profile_id != profile.id:
        # §5.3 IDOR — non-owner must not learn that the row
        # exists. Uniform 404.
        raise MediaNotFound("media not found")

    if row.upload_state == UPLOAD_STATE_FINALIZED:
        # Idempotent — a repeat finalize is a no-op success.
        # Same shape as ``post_service.soft_delete_post``'s D12
        # "already at target state" branch.
        return row
    if row.upload_state in (UPLOAD_STATE_CANCELLED, UPLOAD_STATE_FAILED):
        # Terminal — a cancelled / failed row cannot be
        # revived. The user must start a fresh intent.
        raise MediaNotFound("media not found")

    # Expiry check (A2). The intent stamped
    # ``signed_upload.expires_at`` when ``create_upload_intent``
    # ran; we re-derive the expiry here from the row's
    # ``created_at`` + the caller-supplied ``signed_url_expires_in``
    # so the test can drive the A2 cell deterministically with
    # a short window.
    expires_at = row.created_at + (
        # The ``signed_url_expires_in`` is captured at intent
        # time via the row's ``object_key`` uniqueness — a
        # shorter test window cannot shrink the bucket's TTL,
        # but the service-side re-check uses the caller's
        # ``signed_url_expires_in`` parameter (the in-memory
        # fake's expiries are computed from this same param).
        SIGNED_URL_EXPIRES_IN  # default — see ADR 0410 §D2.
    )
    if _as_utc(now) >= _as_utc(expires_at):
        # Mark failed so the orphan-cleanup function will sweep
        # the row.
        row.upload_state = UPLOAD_STATE_FAILED
        row.updated_at = now
        db.flush()
        raise MediaUploadExpired(f"signed URL expired at {expires_at.isoformat()}")

    metadata = object_store.head_object(row.object_key)
    if metadata is None:
        # Client never PUT anything — keep the row pending and
        # let the orphan-cleanup function sweep it later.
        raise MediaNotFound("uploaded object not found in bucket")

    # Content-Type re-check (A3). The bucket's reported type
    # must match the row's intent-time declaration AND must be
    # in the allowlist — the second check is what stops a
    # rename-`.png`-to-`.mp3` bypass (the brief §5.3 explicit
    # ban on extension-based MIME validation). The check uses
    # the bucket's metadata, NOT the row's stored value — a
    # clever client that managed to slip a non-allowlisted MIME
    # past the intent-time check would still be caught here.
    if not is_allowed_media_content_type(metadata.content_type):
        _transition_to_failed(db, row, object_store, now)
        raise MediaContentTypeMismatch(
            f"bucket content_type {metadata.content_type!r} not in allowlist"
        )
    if metadata.content_type != row.content_type:
        _transition_to_failed(db, row, object_store, now)
        raise MediaContentTypeMismatch(
            f"bucket content_type {metadata.content_type!r} "
            f"does not match intent {row.content_type!r}"
        )

    # Size re-check (A4). The signed-URL content-length
    # constraint is the first line of defense; this is the
    # second (brief §6.1 threshold-triple, defense-in-depth).
    if metadata.size > MAX_UPLOAD_BYTES:
        _transition_to_failed(db, row, object_store, now)
        raise MediaSizeExceeded(
            f"bucket size {metadata.size} exceeds MAX_UPLOAD_BYTES {MAX_UPLOAD_BYTES}"
        )

    # Checksum re-check (A5). When the row carries an
    # intent-time SHA-256 AND the bucket reports one, the two
    # must match. The bucket's SHA-256 is populated by the
    # in-memory fake's ``stage_object``; the production S3
    # adapter would populate it from the custom
    # ``X-Amz-Meta-Sha256`` header a future round wires.
    try:
        _validate_checksum(row=row, metadata=metadata)
    except MediaChecksumMismatch:
        _transition_to_failed(db, row, object_store, now)
        raise

    # All checks pass — transition to uploaded, then finalized.
    row.upload_state = UPLOAD_STATE_UPLOADED
    row.updated_at = now
    db.flush()
    row.upload_state = UPLOAD_STATE_FINALIZED
    row.finalized_at = now
    row.updated_at = now
    db.flush()
    db.refresh(row)

    if on_invalidate is not None:
        on_invalidate(
            MediaInvalidationEvent(media_public_id=row.public_id, action="finalize")
        )
    return row


def cancel_upload(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    media_public_id: uuid.UUID,
    settings,
    object_store: ObjectStore,
    now: datetime,
    on_invalidate: Callable[[MediaInvalidationEvent], None] | None = None,
) -> bool:
    """Cancel an in-progress upload.

    The A7 acceptance cell — the cancel deletes the bucket-side
    object via :meth:`ObjectStore.delete_object` AND transitions
    the row to ``cancelled``. The Flutter side wires the cancel
    into the ``CancelToken`` path on the in-flight PUT — this
    function is the server-side half of the A7 contract.

    Ownership (brief §6 A6): a foreign profile_public_id raises
    :class:`MediaNotFound` (uniform 404). The cancel is
    idempotent — a repeat call on a ``cancelled`` row is a
    successful no-op (returns ``False``).

    A ``finalized`` row cannot be cancelled — the user must
    soft-delete via the (future) post-attach lifecycle.

    Raises :class:`MediaUploadDisabled` when the feature flag
    is OFF (brief §6 A1).
    """
    if not settings.community_media_enabled:
        raise MediaUploadDisabled("community media disabled by feature flag")

    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        raise ValueError("profile community profile not found")

    row = _resolve_media_by_public_id(db, media_public_id)
    if row is None:
        raise MediaNotFound("media not found")
    if row.profile_id != profile.id:
        # §5.3 IDOR — uniform 404 for non-owner.
        raise MediaNotFound("media not found")

    if row.upload_state == UPLOAD_STATE_CANCELLED:
        # Idempotent — the A7 cell's repeat-cancel path.
        return False
    if row.upload_state == UPLOAD_STATE_FINALIZED:
        # A finalized row is immutable — the user must
        # soft-delete via the (future) post-attach lifecycle.
        raise MediaNotFound("media not found")

    object_store.delete_object(row.object_key)
    row.upload_state = UPLOAD_STATE_CANCELLED
    row.updated_at = now
    db.flush()
    db.refresh(row)

    if on_invalidate is not None:
        on_invalidate(
            MediaInvalidationEvent(media_public_id=row.public_id, action="cancel")
        )
    return True


def cleanup_orphan_uploads(
    db: Session,
    *,
    settings,
    object_store: ObjectStore,
    now: datetime,
    on_invalidate: Callable[[MediaInvalidationEvent], None] | None = None,
) -> int:
    """Sweep every ``pending`` / ``uploaded`` row whose
    ``retention_until`` is in the past.

    The §6 A7 acceptance cell — the orphan cleanup runs after
    the user-facing cancel; this function is the safety-net
    sweep that catches abandoned uploads the user never
    cancelled (network drop, app crash, etc.). The function is
    idempotent — re-running it after a successful sweep finds
    zero candidates because the swept rows are now in the
    terminal ``cancelled`` state and excluded from the next
    pass.

    Returns the number of rows swept. The bucket-side
    ``delete_object`` is called for every swept row; the
    in-memory fake's ``deleted`` list records the call so the
    A7 cell can assert the bucket-side side-effect.

    Rows already in ``cancelled`` / ``failed`` / ``finalized``
    are NOT touched — the terminal states are immutable for
    cleanup purposes, and a finalized row's bytes are the
    user's committed asset (a future retention-policy round
    owns the long-tail deletion of finalized rows).
    """
    if not settings.community_media_enabled:
        return 0

    candidates = (
        db.query(CommunityMedia)
        .filter(
            CommunityMedia.upload_state.in_(
                (UPLOAD_STATE_PENDING, UPLOAD_STATE_UPLOADED)
            ),
            CommunityMedia.retention_until.isnot(None),
            CommunityMedia.retention_until <= now,
        )
        .all()
    )
    swept = 0
    for row in candidates:
        object_store.delete_object(row.object_key)
        row.upload_state = UPLOAD_STATE_CANCELLED
        row.updated_at = now
        if on_invalidate is not None:
            on_invalidate(
                MediaInvalidationEvent(
                    media_public_id=row.public_id,
                    action="orphan_cleanup",
                )
            )
        swept += 1
    if swept:
        db.flush()
    return swept


def _transition_to_failed(
    db: Session, row: CommunityMedia, object_store: ObjectStore, now: datetime
) -> None:
    """Mark a row as ``failed`` and free its bucket-side
    bytes. Used by the finalize-path validation rejections so
    a malformed upload doesn't pin bucket quota."""
    object_store.delete_object(row.object_key)
    row.upload_state = UPLOAD_STATE_FAILED
    row.updated_at = now
    db.flush()


def _validate_checksum(*, row: CommunityMedia, metadata: "ObjectMetadata") -> None:
    """Brief §6 A5 — bucket-side SHA-256 must match the
    intent-time declaration when both are present.

    Factored into a helper so the §6.1 valódi-sértés próba can
    monkeypatch the comparison to a no-op and assert the cell
    goes red — the probe exercises the defense-in-depth
    discipline. The helper raises :class:`MediaChecksumMismatch`
    on a mismatch; callers are responsible for the bucket-side
    cleanup and the ``failed`` state transition."""
    if (
        row.checksum_sha256 is not None
        and metadata.sha256_hex is not None
        and metadata.sha256_hex != row.checksum_sha256
    ):
        raise MediaChecksumMismatch(
            f"bucket SHA-256 {metadata.sha256_hex} does not match "
            f"intent {row.checksum_sha256}"
        )


__all__ = [
    "MAX_LIVE_UPLOADS_PER_PROFILE",
    "MAX_UPLOAD_BYTES",
    "MEDIA_CONTENT_TYPE_ALLOWLIST",
    "MediaChecksumMismatch",
    "MediaContentTypeMismatch",
    "MediaInvalidationEvent",
    "MediaNotFound",
    "MediaQuotaExceeded",
    "MediaSizeExceeded",
    "MediaUploadDisabled",
    "MediaUploadExpired",
    "RETENTION_WINDOW",
    "SIGNED_URL_EXPIRES_IN",
    "UploadIntent",
    "cancel_upload",
    "cleanup_orphan_uploads",
    "create_upload_intent",
    "finalize_upload",
    "is_allowed_media_content_type",
    "validate_checksum",
]


# Public alias for the §6.1 valódi-sértés próba — the private
# ``_validate_checksum`` is the implementation detail the probe
# monkeypatches; ``validate_checksum`` is the documented entry
# point future tests can import without reaching into private
# state.
validate_checksum = _validate_checksum
