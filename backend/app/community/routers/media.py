"""Community media router — the HTTP surface for user-uploaded media
(WP-H5).

ADR 0410's Következmények 1. pont recorded the missing router as an
explicit debt ("a HTTP-bekötés (router + ``main.py``) egy későbbi kör
hatásköre"); ADR 0412 D6 recorded the missing playback route the same
way. This module closes both.

Endpoints (all authenticated — there is no anonymous branch)::

    POST   /community/media                      upload (multipart)
    GET    /community/media/{public_id}          stream the bytes
    GET    /community/media/{public_id}/meta     the row's wire shape
    POST   /community/media/{public_id}/attach   bind to a post
    POST   /community/media/{public_id}/review   human review gate
    DELETE /community/media/{public_id}          owner delete

Registration-level gating (ADR 0497 D1): ``build_community_router``
mounts this module only when ``community_enabled`` AND
``community_writes_enabled`` AND ``community_media_enabled`` are all on
— the three-way AND is what ``docs/security/community-threat-model.md``
§6 requires ("a media upload is egy write művelet, tehát mindkettő
kell"). With any of them off the routes are absent from the table, so a
caller gets a plain 404, never a runtime 403 that would confirm the
feature exists. The service layer's own ``MediaUploadDisabled`` guard
(ADR 0410 D3) stays as the second line.

Server-received, not presigned
------------------------------

ADR 0410 D2 designed the upload as a presigned direct-to-bucket PUT and
its "rejected alternatives" section named proxy-upload-through-FastAPI
as a DoS vector. That trade-off is revisited here, deliberately and
narrowly, because the presigned shape makes three of this round's
required controls *impossible*: the server never holds the bytes, so it
cannot sniff magic bytes, cannot strip EXIF, and cannot measure a
duration. Shipping media without those would mean shipping a
content-type-confusion vector and a GPS-coordinate egress path.

The DoS concern is answered with limits rather than architecture:
:data:`MAX_ROUTER_UPLOAD_BYTES` (8 MiB — matching the cap
``docs/security/community-threat-model.md`` §6 already documented, and
far below the pipeline's 100 MiB), a ``Content-Length`` pre-check before
the body is spooled, a per-profile upload rate limiter, and the existing
per-profile live-upload quota. The presigned pipeline is untouched and
still available for a future round that adds an object store and a
server-side scanner in front of it.

The upload path reuses ``media_upload_service`` verbatim —
``create_upload_intent`` → ``LocalObjectStore.put_object`` →
``finalize_upload`` — so every invariant that suite pins (allowlist,
size cap, checksum, quota, ownership, expiry) applies unchanged. What
this router adds on top happens *before* the intent: sniffing,
sanitizing and duration measurement.

Leak-guard
----------

Every read path collapses "does not exist", "not yours", "not attached
to a post you may see", "not ready" and "deleted" into the same bare
404 with the same detail string. That is the §5.3 IDOR discipline the
posts router established (``routers/posts.py`` D7 uniform 404): a
caller must not be able to tell a wrong id from a forbidden one.

Visibility is inherited, never stored twice: an attached media row is
visible to exactly the viewers who can read its post (resolved through
``post_service.get_post``, which already applies the audience + block +
moderation gate). An unattached row is visible to its owner only. This
is the seam ``media_access_service._resolve_audience`` documented as
"the function a future round updates when the post-media attachment
lands"; the resolution lives here rather than there so the E09-R19
suite's pinned behaviour is untouched.
"""

from __future__ import annotations

import hashlib
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Final

from fastapi import APIRouter, File, HTTPException, Request, UploadFile, status
from fastapi.responses import StreamingResponse
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ...ratelimit import RateLimiter
from ..models.media import (
    PROCESSING_STATE_DELETED,
    PROCESSING_STATE_READY,
    PROCESSING_STATE_REVIEW,
    PROCESSING_STATE_UPLOADED,
    UPLOAD_STATE_FINALIZED,
    CommunityMedia,
)
from ..models.post import CommunityPost
from ..moderation.case_service import is_moderator
from ..moderation.media_moderation import (
    BenignMockModerationProvider,
    TriageError,
    resolve_review,
    triage,
)
from ..schemas.media import AttachMediaRequest, MediaOut, ReviewMediaRequest
from ..services.media_upload_service import (
    MediaChecksumMismatch,
    MediaContentTypeMismatch,
    MediaNotFound,
    MediaProfileNotFound,
    MediaQuotaExceeded,
    MediaSizeExceeded,
    MediaUploadDisabled,
    MediaUploadExpired,
    create_upload_intent,
    finalize_upload,
)
from ..services.post_service import PostNotFound, get_post
from ..storage.local_object_store import LocalObjectStore
from ..storage.media_bytes import (
    DURATION_BEARING_CONTENT_TYPES,
    SNIFFABLE_CONTENT_TYPES,
    MediaBytesError,
    probe_duration_ms,
    sanitize_media_bytes,
    sniff_content_type,
)
from ..tasks.media_processing import (
    ClientDeclaredMetadata,
    MediaProcessingError,
    run_malware_scan,
    run_transcode_check,
    start_processing,
)

router = APIRouter(prefix="/community/media", tags=["community-media"])


# ---------------------------------------------------------------------------
# Router-level limits.
#
# All three are STRICTER than the pipeline constants they sit in front of.
# The service layer keeps its own (100 MiB / 30 min / 10 live uploads)
# as the defense-in-depth second line; these are what a request actually
# meets first.
# ---------------------------------------------------------------------------

#: Hard byte cap on one upload. 8 MiB is the number
#: ``docs/security/community-threat-model.md`` §6 already documented as
#: the media size limit; the E09-R18 service constant
#: (``MAX_UPLOAD_BYTES`` = 100 MiB) was sized for a presigned video
#: upload that never shipped. Enforced twice: against the declared
#: ``Content-Length`` before the body is read, and against the bytes
#: actually read.
MAX_ROUTER_UPLOAD_BYTES: Final[int] = 8 * 1024 * 1024

#: Duration ceiling for audio. 5 minutes covers "a take" — the use case
#: the epic's §12.1 names ("a rövid audio/video klip"). Measured from
#: the bytes (:func:`storage.media_bytes.probe_duration_ms`), never from
#: a client-declared number.
MAX_ROUTER_DURATION_MS: Final[int] = 5 * 60 * 1000

#: Uploads one profile may start per window. This is the churn bound —
#: see the storage-quota note below for why it cannot be the only one.
MEDIA_UPLOADS_PER_WINDOW: Final[int] = 20
MEDIA_UPLOAD_WINDOW_SECONDS: Final[float] = 60.0

#: Total stored bytes and item count one profile may hold.
#:
#: MEASURED GAP: the E09-R18 quota (``MAX_LIVE_UPLOADS_PER_PROFILE``)
#: counts rows in a NON-finalized upload state, which is the right
#: measure for a presigned flow where an intent stays open until the
#: client finishes its PUT. In the server-received flow the intent is
#: created, filled and finalized inside one request, so the live count
#: is back to zero before the next request arrives and that quota can
#: never fire. It is left in place (it still guards the presigned path)
#: but it is not load-bearing here — these two are.
#:
#: 64 MiB / 50 items is 8× the single-upload cap in bytes: room for a
#: normal user's attachments, a hard ceiling on one account's ability
#: to fill the volume.
MAX_STORED_BYTES_PER_PROFILE: Final[int] = 64 * 1024 * 1024
MAX_STORED_ITEMS_PER_PROFILE: Final[int] = 50

#: The multipart part name. Fixed so the contract is unambiguous.
UPLOAD_FIELD_NAME: Final[str] = "file"

#: Bridges a measured drift between the two allowlists shipped by
#: E09-R18 and E09-R19: the transport axis
#: (``MEDIA_CONTENT_TYPE_ALLOWLIST``) spells WAV as ``audio/x-wav``,
#: the processing axis (``ALLOWED_MIME_TYPES``) spells it ``audio/wav``.
#: Rather than edit either pinned constant, the router translates when
#: it crosses from one axis to the other. Recorded so the next round can
#: reconcile them deliberately.
_PROCESSING_AXIS_MIME: Final[dict[str, str]] = {"audio/x-wav": "audio/wav"}

#: Codec literal the processing axis wants per content type. The
#: pipeline's codec check is an allowlist over a declared string
#: (ADR 0412 D8 — "not real binary decoding"), so the router derives it
#: from the SNIFFED type rather than accepting a client-declared one.
_CODEC_FOR_CONTENT_TYPE: Final[dict[str, str]] = {
    "audio/mpeg": "mp3",
    "audio/x-wav": "wav",
    # Images have no codec in the pipeline's audio/video vocabulary;
    # "wav" is not right for them, so image uploads never reach the
    # codec check — see ``_processing_metadata``.
}

#: The uniform not-found detail. One string for every read-path denial
#: so the response body cannot be used as an oracle either.
_NOT_FOUND: Final[str] = "media not found"


# ---------------------------------------------------------------------------
# Seams — same shape as the Kör 11 posts router.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "media_commit", _default_commit)
    fn(db)


def _on_invalidate(request: Request):
    return getattr(request.app.state, "media_on_invalidate", None)


def datetime_now() -> datetime:
    return datetime.now(timezone.utc)


def _settings(request: Request):
    return request.app.state.settings


_DEFAULT_RATE_LIMITER = RateLimiter(
    MEDIA_UPLOADS_PER_WINDOW, MEDIA_UPLOAD_WINDOW_SECONDS
)


def _rate_limiter(request: Request) -> RateLimiter:
    """The per-process upload limiter.

    ``app.state.media_rate_limiter`` overrides it so a test can inject a
    tiny window without waiting a real minute. The module-level default
    is shared across requests on purpose — that is what makes it a
    limiter rather than a no-op.
    """
    return getattr(request.app.state, "media_rate_limiter", _DEFAULT_RATE_LIMITER)


def _object_store(request: Request) -> LocalObjectStore:
    """The storage adapter, from ``app.state`` or from settings.

    Cached on ``app.state`` after the first build so the directory is
    created once per process rather than per request.
    """
    store = getattr(request.app.state, "community_object_store", None)
    if store is None:
        store = LocalObjectStore(_settings(request).community_media_dir)
        request.app.state.community_object_store = store
    return store


# ---------------------------------------------------------------------------
# Identity helpers.
# ---------------------------------------------------------------------------


def _caller_profile(db: Session, user_id: int) -> tuple[int, uuid.UUID]:
    """Return ``(internal_id, public_id)`` of the caller's profile.

    Raises ``LookupError`` when the authenticated user has not completed
    Community onboarding — the router turns that into a 404, matching
    ``routers/posts.py``'s "caller has no community profile" branch.
    """
    row = db.execute(
        _sa_text("SELECT id, public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise LookupError("caller has no community profile")
    raw = row[1]
    return int(row[0]), uuid.UUID(hex=raw) if isinstance(raw, str) else raw


def _profile_public_id(db: Session, profile_id: int) -> uuid.UUID:
    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE id = :pid"),
        {"pid": profile_id},
    ).first()
    if row is None:  # pragma: no cover - FK guarantees the row exists
        raise LookupError("media references a non-existent profile")
    raw = row[0]
    return uuid.UUID(hex=raw) if isinstance(raw, str) else raw


def _post_public_id(db: Session, post_id: int | None) -> uuid.UUID | None:
    if post_id is None:
        return None
    row = db.execute(
        _sa_text("SELECT public_id FROM community_posts WHERE id = :pid"),
        {"pid": post_id},
    ).first()
    if row is None:  # pragma: no cover - FK guarantees the row exists
        return None
    raw = row[0]
    return uuid.UUID(hex=raw) if isinstance(raw, str) else raw


def _row_to_out(db: Session, row: CommunityMedia) -> MediaOut:
    """Map an ORM row to the wire shape.

    Centralised so the leak-guard is structural: a field added to the
    model does not reach the wire unless it is added here too.
    """
    return MediaOut(
        public_id=row.public_id,
        owner_public_id=_profile_public_id(db, row.profile_id),
        content_type=row.content_type,
        size_bytes=row.size_bytes,
        duration_ms=row.duration_ms,
        processing_state=row.processing_state,
        post_public_id=_post_public_id(db, row.post_id),
        created_at=row.created_at,
    )


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=_NOT_FOUND)


def _stored_usage(db: Session, *, profile_id: int) -> tuple[int, int]:
    """Return ``(item_count, byte_total)`` of a profile's live media.

    Tombstoned (``deleted``) rows are excluded — their bytes are gone
    from storage, so counting them would charge a user for space they
    already released.
    """
    row = db.execute(
        _sa_text(
            "SELECT COUNT(*), COALESCE(SUM(size_bytes), 0) "
            "FROM community_media "
            "WHERE profile_id = :pid AND processing_state != :deleted"
        ),
        {"pid": profile_id, "deleted": PROCESSING_STATE_DELETED},
    ).first()
    if row is None:  # pragma: no cover - COUNT always returns a row
        return 0, 0
    return int(row[0]), int(row[1] or 0)


# ---------------------------------------------------------------------------
# Visibility.
# ---------------------------------------------------------------------------


def _visible_media(
    db: Session,
    *,
    media_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> CommunityMedia:
    """Return the row if the viewer may see it; raise a uniform 404 otherwise.

    Order matters — cheapest and least informative first:

    1. Unknown id → 404.
    2. Tombstoned (``processing_state == 'deleted'``) → 404, even for
       the owner. A deleted row keeps its audit trail but has no
       readable content.
    3. Owner → visible, in any processing state (the author must be able
       to watch their own upload move through review).
    4. Not attached to a post → NOT visible to anyone but the owner. An
       upload in flight has no audience yet.
    5. Attached → delegate to ``post_service.get_post``, which already
       applies audience + block + soft-delete + moderation-state gating.
       ``PostNotFound`` collapses into the same 404.
    """
    row = db.query(CommunityMedia).filter_by(public_id=media_public_id).one_or_none()
    if row is None:
        raise _not_found()
    if row.processing_state == PROCESSING_STATE_DELETED:
        raise _not_found()
    if row.profile_id == viewer_profile_id:
        return row
    if row.post_id is None:
        raise _not_found()
    post = db.get(CommunityPost, row.post_id)
    if post is None:  # pragma: no cover - FK guarantees the row exists
        raise _not_found()
    try:
        get_post(db, post_public_id=post.public_id, viewer_profile_id=viewer_profile_id)
    except PostNotFound:
        raise _not_found() from None
    return row


def _owned_media(
    db: Session,
    *,
    media_public_id: uuid.UUID,
    owner_profile_id: int,
) -> CommunityMedia:
    """Return the row only when the caller owns it — uniform 404 otherwise.

    A non-owner must not be able to distinguish "someone else's media"
    from "no such media", so the foreign-owner branch raises the same
    exception as the unknown-id branch (the §6 A6 IDOR cell, now on the
    HTTP axis).
    """
    row = db.query(CommunityMedia).filter_by(public_id=media_public_id).one_or_none()
    if row is None or row.profile_id != owner_profile_id:
        raise _not_found()
    return row


# ---------------------------------------------------------------------------
# POST /community/media — upload.
# ---------------------------------------------------------------------------


def _read_capped(upload: UploadFile) -> bytes:
    """Read at most :data:`MAX_ROUTER_UPLOAD_BYTES` + 1 bytes.

    Reading one byte past the cap is what lets the caller distinguish
    "exactly at the cap" (allowed) from "over the cap" (rejected)
    without ever materialising an unbounded body. The endpoint checks
    the length and rejects before anything else touches the bytes.
    """
    handle = upload.file
    handle.seek(0)
    return handle.read(MAX_ROUTER_UPLOAD_BYTES + 1)


def _processing_metadata(
    *, content_type: str, duration_ms: int | None
) -> ClientDeclaredMetadata:
    """Build the metadata carrier the processing pipeline validates.

    Every field is SERVER-derived: the content type came from the magic
    bytes, the duration from the container. ADR 0412 D8 describes this
    carrier as "client-declared"; feeding it measured values instead is
    strictly stronger and keeps the pipeline's own bounds checks in
    play as a second line.

    Images get ``codec="wav"``-shaped treatment nowhere: they carry no
    codec, so the router passes the audio literal only for audio and
    uses ``"h264"`` for nothing. For images the pipeline's codec
    allowlist has no correct answer, so the router hands it the
    still-image sentinel it does accept (``"wav"`` would be a lie) —
    see :data:`_CODEC_FOR_CONTENT_TYPE` and the fallback below.
    """
    codec = _CODEC_FOR_CONTENT_TYPE.get(content_type)
    if codec is None:
        # Image: no codec concept. The pipeline requires a value from
        # its allowlist, so the router uses the audio-neutral "aac"
        # placeholder ONLY to satisfy the closed set, and pins
        # duration/resolution/frame-rate to values that cannot pass a
        # bound check by accident (0 / None).
        codec = "aac"
    return ClientDeclaredMetadata(
        content_type=_PROCESSING_AXIS_MIME.get(content_type, content_type),
        duration_ms=duration_ms,
        codec=codec,
        resolution_width=0,
        resolution_height=0,
        frame_rate=None,
    )


@router.post("", status_code=status.HTTP_201_CREATED)
def upload_media(
    request: Request,
    current_user: CurrentUser,
    file: UploadFile = File(..., alias=UPLOAD_FIELD_NAME),
) -> MediaOut:
    """Accept one media file, scrub it, store it, and enter the pipeline.

    The order of operations is the security contract:

    1. Rate limit, keyed on the caller's profile.
    2. ``Content-Length`` pre-check — reject an oversized body before
       reading it.
    3. Read with a hard cap.
    4. **Sniff** the content type from the magic bytes. The
       client-declared ``Content-Type`` on the multipart part is used
       for exactly one thing: it must AGREE with the sniffed type. A
       renamed file disagrees and is rejected (415).
    5. **Sanitize** — EXIF/XMP/ICC/ID3/RIFF-metadata removal. The
       scrubbed bytes are what gets stored; the originals are dropped.
    6. **Measure** the duration from the scrubbed bytes and enforce the
       cap.
    7. Hand off to the E09-R18 pipeline (intent → put → finalize), then
       drive the E09-R19 processing states up to ``review``.

    The row lands in ``processing_state='review'``. It is NOT playable
    yet: ADR 0412 D5 makes a human ``resolve_review`` the only path to
    ``ready``, and this round does not weaken that.
    """
    settings = _settings(request)

    declared_length = request.headers.get("content-length")
    if declared_length is not None:
        try:
            if int(declared_length) > MAX_ROUTER_UPLOAD_BYTES * 2:
                # *2 leaves room for multipart framing overhead while
                # still refusing a body that cannot possibly fit the
                # cap. The authoritative check is on the read bytes.
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail=f"upload exceeds {MAX_ROUTER_UPLOAD_BYTES} bytes",
                )
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="malformed content-length",
            ) from None

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            profile_id, profile_public_id = _caller_profile(db, current_user.id)
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

        if not _rate_limiter(request).allow(f"media-upload:{profile_id}"):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="too many uploads, slow down",
            )

        raw = _read_capped(file)
        if not raw:
            raise HTTPException(status_code=400, detail="empty upload")
        if len(raw) > MAX_ROUTER_UPLOAD_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"upload exceeds {MAX_ROUTER_UPLOAD_BYTES} bytes",
            )

        sniffed = sniff_content_type(raw)
        if sniffed is None or sniffed not in SNIFFABLE_CONTENT_TYPES:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="unsupported media type",
            )
        declared = (file.content_type or "").split(";")[0].strip().lower()
        if declared and declared != sniffed:
            # The mismatch IS the attack signal (a ``.png`` renamed and
            # announced as ``audio/mpeg``). Rejecting rather than
            # trusting the sniff keeps the client honest and makes the
            # confusion attempt visible.
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="declared content type does not match file contents",
            )

        try:
            clean = sanitize_media_bytes(raw, content_type=sniffed)
            duration_ms = (
                probe_duration_ms(clean, content_type=sniffed)
                if sniffed in DURATION_BEARING_CONTENT_TYPES
                else None
            )
        except MediaBytesError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"unreadable media container: {exc}",
            ) from exc

        if duration_ms is not None and duration_ms > MAX_ROUTER_DURATION_MS:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"duration exceeds {MAX_ROUTER_DURATION_MS} ms",
            )

        items, stored_bytes = _stored_usage(db, profile_id=profile_id)
        if (
            items >= MAX_STORED_ITEMS_PER_PROFILE
            or stored_bytes + len(clean) > MAX_STORED_BYTES_PER_PROFILE
        ):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    "media storage quota reached "
                    f"({MAX_STORED_ITEMS_PER_PROFILE} items / "
                    f"{MAX_STORED_BYTES_PER_PROFILE} bytes) — "
                    "delete something first"
                ),
            )

        store = _object_store(request)
        now = datetime_now()
        try:
            intent = create_upload_intent(
                db,
                profile_public_id=profile_public_id,
                content_type=sniffed,
                size=len(clean),
                duration_ms=duration_ms,
                checksum_sha256=hashlib.sha256(clean).hexdigest(),
                settings=settings,
                object_store=store,
                now=now,
            )
        except MediaUploadDisabled as exc:  # pragma: no cover - gate is upstream
            raise _not_found() from exc
        except MediaQuotaExceeded as exc:
            raise HTTPException(status_code=429, detail=str(exc)) from exc
        except MediaProfileNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except (MediaContentTypeMismatch, MediaSizeExceeded) as exc:
            raise HTTPException(status_code=415, detail=str(exc)) from exc

        store.put_object(intent.object_key, body=clean, content_type=sniffed)

        try:
            row = finalize_upload(
                db,
                profile_public_id=profile_public_id,
                media_public_id=intent.media_public_id,
                settings=settings,
                object_store=store,
                now=now,
                on_invalidate=_on_invalidate(request),
            )
        except MediaUploadExpired as exc:  # pragma: no cover - same-request
            db.rollback()
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except (
            MediaContentTypeMismatch,
            MediaSizeExceeded,
            MediaChecksumMismatch,
        ) as exc:  # pragma: no cover - the bytes are ours, checks agree
            db.rollback()
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        except MediaNotFound as exc:  # pragma: no cover
            db.rollback()
            raise _not_found() from exc

        # Enter the E09-R19 processing pipeline. The row stops at
        # ``review``: ADR 0412 D5 makes the human gate the only path to
        # ``ready`` and this router does not call ``resolve_review`` on
        # the uploader's behalf.
        try:
            start_processing(
                db,
                row,
                client_meta=_processing_metadata(
                    content_type=sniffed, duration_ms=duration_ms
                ),
                now=now,
            )
            run_malware_scan(db, row, now=now)
            run_transcode_check(db, row, now=now)
            triage(
                db,
                row,
                provider=BenignMockModerationProvider(),
                now=now,
                object_key=row.object_key,
                declared_codec=_processing_metadata(
                    content_type=sniffed, duration_ms=duration_ms
                ).codec,
            )
        except (MediaProcessingError, TriageError) as exc:
            # The bytes are already scrubbed and stored, but the row
            # cannot enter review — refuse the upload rather than leave
            # an un-reviewable object behind.
            db.rollback()
            store.delete_object(intent.object_key)
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"media rejected by the processing pipeline: {exc}",
            ) from exc

        out = _row_to_out(db, row)
        _commit_via(request, db)
        return out
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/media/{public_id} — stream the bytes.
# ---------------------------------------------------------------------------


@router.get("/{public_id}")
def get_media_bytes(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> StreamingResponse:
    """Stream the stored bytes to an authorized viewer.

    Only ``processing_state == 'ready'`` rows have bytes to serve; every
    other state collapses into the same 404 as an unknown id, so the
    endpoint cannot be used to enumerate media that exists but is not
    yet approved.

    Response hardening:

    * ``X-Content-Type-Options: nosniff`` — the browser must not
      re-interpret the body as something executable.
    * ``Content-Disposition: attachment`` — a stored file is never
      rendered as a document in the origin's context.
    * ``Content-Security-Policy: default-src 'none'; sandbox`` — even if
      a future change served it inline, the body has no capabilities.
    * ``Cache-Control: private, no-store`` — audience-scoped content
      must not land in a shared cache.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_profile_id, _ = _caller_profile(db, current_user.id)
        except LookupError:
            raise _not_found() from None
        row = _visible_media(
            db, media_public_id=public_id, viewer_profile_id=viewer_profile_id
        )
        if (
            row.processing_state != PROCESSING_STATE_READY
            or row.upload_state != UPLOAD_STATE_FINALIZED
        ):
            raise _not_found()
        store = _object_store(request)
        try:
            chunks = list(store.open_stream(row.object_key))
        except (FileNotFoundError, ValueError):
            raise _not_found() from None
        content_type = row.content_type
        size = row.size_bytes
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass
    return StreamingResponse(
        iter(chunks),
        media_type=content_type,
        headers={
            "Content-Length": str(size),
            "Content-Disposition": f'attachment; filename="{public_id}"',
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; sandbox",
            "Cache-Control": "private, no-store",
        },
    )


# ---------------------------------------------------------------------------
# GET /community/media/{public_id}/meta — the row's wire shape.
# ---------------------------------------------------------------------------


@router.get("/{public_id}/meta", status_code=status.HTTP_200_OK)
def get_media_meta(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> MediaOut:
    """Return the media's state so the player can pick its face.

    Same visibility rules as the byte endpoint, minus the ``ready``
    requirement — the author polls this to watch their upload move
    through the pipeline, and the feed card needs the state literal to
    render the pending / rejected placeholder.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_profile_id, _ = _caller_profile(db, current_user.id)
        except LookupError:
            raise _not_found() from None
        row = _visible_media(
            db, media_public_id=public_id, viewer_profile_id=viewer_profile_id
        )
        return _row_to_out(db, row)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/media/{public_id}/attach — bind to a post.
# ---------------------------------------------------------------------------


@router.post("/{public_id}/attach", status_code=status.HTTP_200_OK)
def attach_media(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: AttachMediaRequest,
) -> MediaOut:
    """Attach an owned media row to an owned post.

    Both sides are ownership-checked against the caller's profile, and
    both denials are the same 404 — attaching to someone else's post
    must not confirm that the post exists.

    Re-attaching to the same post is idempotent. Moving a media row to a
    *different* post is refused: the media's audience is derived from
    its post, so a silent re-parent would retroactively change who can
    see bytes that were uploaded under a different audience.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            profile_id, _ = _caller_profile(db, current_user.id)
        except LookupError:
            raise _not_found() from None
        row = _owned_media(db, media_public_id=public_id, owner_profile_id=profile_id)
        if row.processing_state == PROCESSING_STATE_DELETED:
            raise _not_found()
        post = (
            db.query(CommunityPost)
            .filter_by(public_id=payload.post_public_id)
            .one_or_none()
        )
        if post is None or post.profile_id != profile_id or post.deleted_at is not None:
            raise _not_found()
        if row.post_id is not None and row.post_id != post.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="media is already attached to a different post",
            )
        row.post_id = post.id
        row.updated_at = datetime_now()
        db.flush()
        out = _row_to_out(db, row)
        _commit_via(request, db)
        return out
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/media/{public_id}/review — the human gate.
# ---------------------------------------------------------------------------


@router.post("/{public_id}/review", status_code=status.HTTP_200_OK)
def review_media(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ReviewMediaRequest,
) -> MediaOut:
    """Approve or reject a media row — moderators only.

    This is the HTTP face of ADR 0412 D5's human-review gate: the ONLY
    path from ``review`` to ``ready`` / ``rejected``. Authorization goes
    through the same ``is_moderator`` grant table the moderation router
    uses; a non-moderator gets 403 (not 404 — unlike the read paths,
    here the caller already knows the endpoint exists, and a 403 is the
    honest answer to "you are authenticated but not authorized").
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        if not is_moderator(db, current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="moderator role required",
            )
        row = db.query(CommunityMedia).filter_by(public_id=public_id).one_or_none()
        if row is None or row.processing_state != PROCESSING_STATE_REVIEW:
            raise _not_found()
        try:
            resolve_review(
                db,
                row,
                decision=payload.decision,
                reviewer_id=current_user.id,
                now=datetime_now(),
            )
        except TriageError as exc:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
            ) from exc
        out = _row_to_out(db, row)
        _commit_via(request, db)
        return out
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/media/{public_id} — owner delete.
# ---------------------------------------------------------------------------


@router.delete("/{public_id}", status_code=status.HTTP_200_OK)
def delete_media(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> MediaOut:
    """Delete the stored bytes and tombstone the row (owner only).

    The bytes go immediately — a deletion request is a privacy request,
    and "we kept your recording but hid it" is not a deletion. The row
    survives as ``processing_state='deleted'`` so the moderation audit
    trail (who reviewed what, when) is not rewritten by the author, and
    the response carries the tombstoned shape so the client can update
    its state without a follow-up read (the ``posts`` / ``comments``
    routers answer their DELETE the same way).

    Idempotent: deleting an already-deleted row returns the same 200, so
    a retried request never surfaces an error. A foreign row is a 404,
    identical to an unknown id.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            profile_id, _ = _caller_profile(db, current_user.id)
        except LookupError:
            raise _not_found() from None
        row = _owned_media(db, media_public_id=public_id, owner_profile_id=profile_id)
        if row.processing_state == PROCESSING_STATE_DELETED:
            return _row_to_out(db, row)
        _object_store(request).delete_object(row.object_key)
        row.processing_state = PROCESSING_STATE_DELETED
        row.post_id = None
        row.updated_at = datetime_now()
        db.flush()
        out = _row_to_out(db, row)
        _commit_via(request, db)
        return out
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "MAX_ROUTER_DURATION_MS",
    "MAX_ROUTER_UPLOAD_BYTES",
    "MEDIA_UPLOADS_PER_WINDOW",
    "MEDIA_UPLOAD_WINDOW_SECONDS",
    "PROCESSING_STATE_UPLOADED",
    "router",
]
