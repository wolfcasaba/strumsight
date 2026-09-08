"""Community media router (javító sáv R27).

Three endpoints, all authenticated:

* ``POST   /community/media`` — multipart upload. Runs the whole
  pipeline in-request (sniff → scan → transcode → store) and answers
  with the resulting descriptor.
* ``GET    /community/media/{public_id}`` — streams the READY,
  re-encoded bytes with the server's own ``Content-Type``.
* ``DELETE /community/media/{public_id}`` — owner-only terminal delete.

Registration-level gate (ADR 0497 D1): ``build_community_router`` mounts
this router only when ``community_media_enabled`` is true, so a deploy
that has not flipped the flag answers 404 for all three paths — the
route does not exist, there is no runtime 403 to probe, and the client's
existing "not enabled on this server" path handles it unchanged.

Security decisions carried by THIS layer (the pipeline owns the rest):

* **Two independent budgets.** A per-IP sliding window
  (``client_ip_for_throttle``, the R14/R16 shared rule) bounds request
  rate; the per-profile row quota lives in the pipeline. Neither
  substitutes for the other: the throttle stops a burst from one host,
  the quota stops a patient account from filling the volume.
* **``Content-Length`` is not trusted.** The cap is enforced on the
  bytes actually read, so a lying header changes nothing. The declared
  length is used only as an early, cheap rejection.
* **No caller-supplied filename ever reaches disk.** The multipart
  ``filename`` is not persisted, not logged and not echoed: the stored
  path comes from the content digest, and the download endpoint sends
  ``Content-Disposition: inline`` with no name at all.
* **Uniform 404.** "no such media", "not yours", and "attached to a post
  you cannot see" are the same answer — the §5.3 IDOR discipline the
  post router established.
* **Downloads are not a rendering surface.** Every response carries
  ``X-Content-Type-Options: nosniff`` and
  ``Content-Security-Policy: default-src 'none'`` so a browser that
  somehow receives an unexpected type cannot be talked into executing
  it.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import APIRouter, File, HTTPException, Request, UploadFile, status
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...client_ip import client_ip_for_throttle
from ...config import Settings
from ...deps import CurrentUser
from ...ratelimit import RateLimiter
from ..media.pipeline import (
    MediaLimits,
    MediaPipeline,
    MediaProfileMissing,
    MediaQuotaExceeded,
    MediaRejected,
    MediaTooLarge,
    find_media,
    resolve_profile_id,
)
from ..media.scanner import build_media_scanner
from ..media.store import FileMediaStore, MediaStoreError
from ..media.transcode import build_audio_transcoder, build_image_transcoder
from ..models.media_upload import (
    MEDIA_STATE_READY,
    CommunityMediaUpload,
)
from ..models.post import CommunityPost
from ..schemas.media import MediaDeleteResult, MediaOut, media_to_out
from ..services.post_service import PostNotFound, get_post

router = APIRouter(prefix="/community/media", tags=["community-media"])

#: Multipart field name the client posts the bytes under.
_UPLOAD_FIELD = "file"

#: Chunk size for the streaming read that enforces the byte cap.
_READ_CHUNK = 256 * 1024

_upload_limiter = RateLimiter(max_attempts=20, window_seconds=3600.0)


def reset_rate_limiters() -> None:
    """Clear the upload limiter — the test seam (``search.py`` precedent)."""
    _upload_limiter.reset()


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _settings(request: Request) -> Settings:
    return request.app.state.settings


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "media_commit", None)
    if fn is None:
        db.commit()
    else:
        fn(db)


def _client_key(request: Request) -> str:
    """The throttle bucket — the shared trusted-proxy rule (R14/R16)."""
    return client_ip_for_throttle(request, _settings(request))


def _store(request: Request) -> FileMediaStore:
    return FileMediaStore(_settings(request).media_root)


def _pipeline(request: Request, db: Session) -> MediaPipeline:
    settings = _settings(request)
    return MediaPipeline(
        db,
        store=_store(request),
        scanner=build_media_scanner(settings),
        image_transcoder=build_image_transcoder(settings),
        audio_transcoder=build_audio_transcoder(settings),
        limits=MediaLimits.from_settings(settings),
    )


def _throttle(request: Request) -> None:
    settings = _settings(request)
    limiter = _upload_limiter
    limiter.max_attempts = settings.media_upload_rate_limit_max
    limiter.window_seconds = float(settings.media_upload_rate_limit_window)
    if not limiter.allow(_client_key(request)):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="media upload rate limit exceeded",
        )


async def _read_capped(upload: UploadFile, limit: int) -> bytes:
    """Read at most ``limit`` bytes, raising 413 past it.

    Reading in chunks and stopping one byte over the cap is what makes
    the limit real: ``await upload.read()`` would buffer the entire
    body first and only then compare, which is the denial-of-service the
    cap exists to prevent.
    """
    buffer = bytearray()
    while True:
        chunk = await upload.read(_READ_CHUNK)
        if not chunk:
            break
        buffer.extend(chunk)
        if len(buffer) > limit:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail={"error": "file_too_large", "limit_bytes": limit},
            )
    return bytes(buffer)


# ---------------------------------------------------------------------------
# POST /community/media
# ---------------------------------------------------------------------------


@router.post("", status_code=status.HTTP_201_CREATED)
async def upload_media(
    request: Request,
    current_user: CurrentUser,
    file: UploadFile = File(..., alias=_UPLOAD_FIELD),
) -> MediaOut:
    """Accept one media file and return its descriptor.

    A pipeline REJECTION is not an error status: the row exists, its
    state is ``rejected`` and its code says why, so the answer is a 201
    with that descriptor. The client already renders a rejected face;
    turning this into a 4xx would force it to invent one. The genuinely
    exceptional outcomes — over the cap, over quota, throttled, no
    profile — keep their status codes.
    """
    _throttle(request)
    settings = _settings(request)
    absolute_cap = max(
        settings.media_max_image_bytes,
        settings.media_max_audio_bytes,
    )
    data = await _read_capped(file, absolute_cap)

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            profile_id = resolve_profile_id(db, current_user.id)
        except MediaProfileMissing as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        pipeline = _pipeline(request, db)
        try:
            row = pipeline.ingest(profile_id=profile_id, data=data)
        except MediaRejected as exc:
            # The row (when persisted) carries the audit trail; commit
            # so the rejection is durable, then answer with it.
            _commit_via(request, db)
            return media_to_out(exc.row)
        except MediaTooLarge as exc:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail={
                    "error": "file_too_large",
                    "limit_bytes": exc.limit_bytes,
                },
            ) from exc
        except MediaQuotaExceeded as exc:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"error": "quota_exceeded"},
            ) from exc
        _commit_via(request, db)
        return media_to_out(row)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/media/{public_id}
# ---------------------------------------------------------------------------


def _viewer_may_read(
    db: Session,
    row: CommunityMediaUpload,
    *,
    viewer_profile_id: int,
) -> bool:
    """Owner, or a viewer who may see the post the media hangs on.

    A loose upload (no ``post_id``) is visible to its owner ONLY — the
    composer's in-progress attachment is not public just because someone
    guessed a UUID.
    """
    if row.profile_id == viewer_profile_id:
        return True
    if row.post_id is None:
        return False
    post = db.execute(
        select(CommunityPost).where(CommunityPost.id == row.post_id)
    ).scalar_one_or_none()
    if post is None:
        return False
    try:
        get_post(
            db,
            post_public_id=post.public_id,
            viewer_profile_id=viewer_profile_id,
        )
    except PostNotFound:
        return False
    return True


@router.get("/{public_id}")
def download_media(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> Response:
    """Stream the READY bytes, or 404.

    Non-ready states (pending / scanning / transcoding / review /
    rejected / deleted) all answer 404: there are no bytes a client may
    have, and distinguishing them here would leak the pipeline's
    internal progress to anyone holding an id.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_profile_id = resolve_profile_id(db, current_user.id)
        except MediaProfileMissing as exc:
            raise HTTPException(status_code=404, detail="media not found") from exc
        row = find_media(db, public_id)
        if row is None or row.state != MEDIA_STATE_READY:
            raise HTTPException(status_code=404, detail="media not found")
        if not _viewer_may_read(db, row, viewer_profile_id=viewer_profile_id):
            raise HTTPException(status_code=404, detail="media not found")
        digest = row.content_sha256
        if not digest:
            raise HTTPException(status_code=404, detail="media not found")
        try:
            payload = _store(request).read(digest)
        except MediaStoreError as exc:
            # The row says ready but the file is gone: a deploy-level
            # fault (a wiped volume), not a client error.
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="media storage unavailable",
            ) from exc
        return Response(
            content=payload,
            media_type=row.content_type,
            headers={
                # Immutable by construction: the bytes are addressed by
                # their own digest, so a given public_id's content can
                # never change. `private` keeps shared caches out of an
                # authenticated, audience-scoped resource.
                "Cache-Control": "private, max-age=86400, immutable",
                "Content-Disposition": "inline",
                "X-Content-Type-Options": "nosniff",
                "Content-Security-Policy": "default-src 'none'; sandbox",
            },
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/media/{public_id}
# ---------------------------------------------------------------------------


@router.delete("/{public_id}", status_code=status.HTTP_200_OK)
def delete_media(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> MediaDeleteResult:
    """Owner-only terminal delete. Idempotent on an already-deleted row."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_profile_id = resolve_profile_id(db, current_user.id)
        except MediaProfileMissing as exc:
            raise HTTPException(status_code=404, detail="media not found") from exc
        row = find_media(db, public_id)
        if row is None or row.profile_id != viewer_profile_id:
            raise HTTPException(status_code=404, detail="media not found")
        already = row.state == "deleted"
        _pipeline(request, db).delete(row)
        _commit_via(request, db)
        return MediaDeleteResult(status="noop" if already else "deleted")
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = ["reset_rate_limiters", "router"]
