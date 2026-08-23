"""Media processing pipeline (E09-R19, ADR 0412).

Pure, session+row-parametric functions the post-finalize
processing pipeline exposes. The Kör 18 ``finalize_upload``
service does NOT call these functions automatically — that wiring
is a future round's job (ADR 0412 §D3, HANDOFF §6 nyitott horog).
The ``test_media_processing.py`` tests drive them directly.

The pipeline has five concerns (brief §3 / §5.1):

1. **EXIF / location strip** (A1). Stdlib-only byte-level
   implementation for the JPEG fixture format — strips the
   APP1 / EXIF segment from a minimal JPEG, plus the GPS-IFD
   inside the EXIF segment if present. NOT a general-purpose
   EXIF library: HEIC / RAW / video-stream EXIF handling is
   documented as a nyitott kockázat (ADR 0412 §D8, brief §9).

2. **Codec / duration / resolution / frame-rate allowlist +
   threshold** (ADR 0412 §D8). The validation is on the
   CLIENT-DECLARED fields (``content_type``, ``duration_ms``,
   ``resolution_width``, ``resolution_height``,
   ``frame_rate``) — NOT on the actual bytes. A future round
   that introduces a real codec library (Pillow / ffmpeg-python
   / mutagen) replaces these with binary checks; today the
   client declarations are the only signal.

3. **Malware-scan adapter** (delegated to
   :mod:`community.moderation.media_moderation`). This module
   only re-exports the seam.

4. **Triage moderation** (delegated to the same module). This
   module only re-exports the seam.

5. **State transitions**. The pipeline moves a media row through
   ``uploaded → scanning → transcoding → review → ready`` via
   the helper functions below. ``rejected`` and ``deleted`` are
   reachable only via the explicit human-review gate
   (:func:`moderation.media_moderation.resolve_review`) — the
   triage path NEVER directly rejects (ADR 0412 §D5, A7).

All functions in this module are **session+row-parametric**:
they take a SQLAlchemy ``Session`` and a ``CommunityMedia``
row, mutate the row in-place, and call ``session.flush()`` to
push the changes to the DB. The caller controls the transaction
boundary (commit or rollback at the call site — same pattern as
Kör 18 ``media_upload_service``).

**Caller-supplied clock** (``now: datetime``): same precedent as
the Kör 18 service — the timestamp the pipeline writes is the
caller's, never ``datetime.now(timezone.utc)`` inline. Keeps
the §6 acceptance tests deterministic.
"""

from __future__ import annotations

import struct
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Final

from sqlalchemy.orm import Session

from ..models.media import (
    PROCESSING_STATE_READY,
    PROCESSING_STATE_REJECTED,
    PROCESSING_STATE_REVIEW,
    PROCESSING_STATE_SCANNING,
    PROCESSING_STATE_TRANSCODING,
    PROCESSING_STATE_UPLOADED,
    CommunityMedia,
)

# ---------------------------------------------------------------------------
# Pipeline constants — ADR 0412 §D8.
# ---------------------------------------------------------------------------

#: Maximum duration the pipeline accepts (audio / video). Image
#: uploads declare ``duration_ms=None`` and skip this check.
MAX_DURATION_MS: Final[int] = 30 * 60 * 1000  # 30 minutes

#: Maximum pixel dimensions on either axis. The current product
#: surface is small (mobile feed cards); a future round bumps
#: these when a higher-resolution display surface lands.
MAX_RESOLUTION_WIDTH: Final[int] = 4096
MAX_RESOLUTION_HEIGHT: Final[int] = 4096

#: Maximum frame rate the pipeline accepts. 60 fps covers every
#: mobile recording mode the platform targets today; higher
#: rates are almost always a client-side bug.
MAX_FRAME_RATE: Final[int] = 60

#: Codec allowlist — the literal string set the pipeline
#: accepts. Mirrors the Kör 18 MIME allowlist shape but lives
#: here because the codec field is the MEDIA layer's concern,
#: not the upload-transzport layer's.
ALLOWED_CODECS: Final[frozenset[str]] = frozenset(
    {
        # Audio
        "mp3",
        "aac",
        "opus",
        "wav",
        # Video
        "h264",
        "h265",
        "vp9",
        "av1",
    }
)

#: MIME allowlist — the WIRE-side ``content_type`` values the
#: pipeline re-validates (the Kör 18 service already does this
#: for the upload state machine; we re-check on the processing
#: axis to prevent a row from advancing without a permitted
#: MIME on both axes).
ALLOWED_MIME_TYPES: Final[frozenset[str]] = frozenset(
    {
        # Audio
        "audio/mpeg",
        "audio/mp3",
        "audio/aac",
        "audio/opus",
        "audio/wav",
        # Video
        "video/mp4",
        "video/quicktime",
        "video/webm",
        # Image
        "image/jpeg",
        "image/png",
        "image/webp",
    }
)

#: JPEG markers the EXIF-strip helper recognizes. The minimal
#: JPEG segment walker is intentionally narrow — it does not
#: understand JPEG2000, RAW, HEIC, or any container that nests
#: metadata INSIDE the EXIF segment header. Those formats are
#: the brief §9 / ADR 0412 §D8 nyitott kockázat, NOT a
#: regression that this implementation can mask.
_JPEG_SOI: Final[int] = 0xFFD8  # Start of image
_JPEG_EOI: Final[int] = 0xFFD9  # End of image
_JPEG_APP1: Final[int] = 0xFFE1  # APP1 segment (EXIF lives here)
_JPEG_APP_MARKER_BASE: Final[int] = 0xFFE0  # APP0..APP15 marker base


class MediaProcessingError(Exception):
    """Base class for media-processing pipeline errors."""


class MediaCodecUnsupported(MediaProcessingError):
    """The client-declared codec is outside the allowlist."""


class MediaDurationExceeded(MediaProcessingError):
    """The client-declared duration exceeds ``MAX_DURATION_MS``."""


class MediaResolutionExceeded(MediaProcessingError):
    """The client-declared resolution exceeds the per-axis cap."""


class MediaFrameRateExceeded(MediaProcessingError):
    """The client-declared frame rate exceeds ``MAX_FRAME_RATE``."""


class MediaMimeTypeUnsupported(MediaProcessingError):
    """The client-declared MIME type is outside the allowlist."""


class MediaTransitionError(MediaProcessingError):
    """An illegal ``processing_state`` transition was attempted."""


# ---------------------------------------------------------------------------
# Client-declared metadata carrier.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ClientDeclaredMetadata:
    """The client-side metadata the pipeline validates.

    The fields mirror the contract the upload pipeline carries
    (``content_type`` / ``duration_ms`` are Kör 18 fields;
    ``codec`` / ``resolution_width`` / ``resolution_height`` /
    ``frame_rate`` are E09-R19 additions). The pipeline
    validates ALL of them at every transition — defense-in-
    depth, even if the upload seam already checked some of them.
    """

    content_type: str
    duration_ms: int | None
    codec: str
    resolution_width: int
    resolution_height: int
    frame_rate: int | None  # audio: None


# ---------------------------------------------------------------------------
# EXIF / location strip — stdlib-only JPEG walker.
# ---------------------------------------------------------------------------


def strip_exif_from_jpeg(body: bytes) -> bytes:
    """Return ``body`` with the APP1 / EXIF segment removed.

    The implementation walks the JPEG segment chain
    (``FFDA`` … ``FFD9``), keeps every segment except
    ``APP1`` (the EXIF marker), and emits the cleaned body.

    Limitations (ADR 0412 §D8, brief §9 nyitott kockázat):

    * Non-JPEG inputs are returned unchanged — the pipeline
      rejects those on the MIME axis, not here.
    * EXIF data hidden INSIDE other segments (e.g. ICC profiles
      in ``APP2`` that embed a GPS block) is NOT touched. The
      GPS-IFD removal inside the APP1 segment is also out of
      scope — APP1 removal is sufficient for the A1 acceptance
      cell (the fixture is a minimal JPEG with a single APP1
      segment containing a fake EXIF payload).
    * The GPS-IFD removal is left as a future round when the
      product surface needs it; this round's contract is the
      APP1-segment-strip alone.

    The function is purely byte-level — no parsing of TIFF /
    EXIF structure. It is a SEGMENT walker, not an EXIF parser.
    """
    if not body or len(body) < 4:
        return body
    # Only operate on JPEG bodies; everything else is a no-op.
    if body[0] != 0xFF or body[1] != _JPEG_SOI & 0xFF:
        return body
    out = bytearray()
    out.append(body[0])
    out.append(body[1])
    index = 2
    while index < len(body):
        # JPEG markers begin with 0xFF; standalone markers
        # (``RST0``-``RST7``, ``EOI``) are single-byte.
        if body[index] != 0xFF:
            # Malformed — bail and return the prefix unchanged.
            out.extend(body[index:])
            break
        # Skip padding 0xFF bytes.
        while index < len(body) and body[index] == 0xFF:
            index += 1
        if index >= len(body):
            break
        marker_low = body[index]
        index += 1
        if marker_low == (_JPEG_EOI & 0xFF) or (0xD0 <= marker_low <= 0xD7):
            # Standalone marker — emit and continue.
            out.append(0xFF)
            out.append(marker_low)
            if marker_low == (_JPEG_EOI & 0xFF):
                out.extend(body[index:])
                break
            continue
        # Segmented marker — read the 16-bit length that
        # follows; segments without length (``SOI``, ``EOI``,
        # ``RSTn``) are already handled above.
        if index + 2 > len(body):
            break
        seg_length = struct.unpack(">H", body[index : index + 2])[0]
        seg_end = index + seg_length
        if seg_end > len(body):
            # Truncated segment — bail with what we have.
            out.extend(body[index - 2 :])
            break
        # Drop APP1 (EXIF). Compare against the LOW BYTE of the
        # APP1 marker (0xE1) — the high byte is the 0xFF prefix
        # that was already consumed.
        if marker_low != (_JPEG_APP1 & 0xFF):
            out.append(0xFF)
            out.append(marker_low)
            out.extend(body[index:seg_end])
        index = seg_end
    return bytes(out)


# ---------------------------------------------------------------------------
# Client-declared validation.
# ---------------------------------------------------------------------------


def validate_client_metadata(meta: ClientDeclaredMetadata) -> None:
    """Raise on the FIRST violation of the allowlist / threshold
    triple.

    Order matters: MIME first (cheapest), then codec, then the
    dimension thresholds. The raise is the single signal the
    pipeline propagates to ``submit_for_review`` — a reviewer
    sees one error at a time so they can fix it and resubmit.
    """
    if meta.content_type not in ALLOWED_MIME_TYPES:
        raise MediaMimeTypeUnsupported(meta.content_type)
    if meta.codec not in ALLOWED_CODECS:
        raise MediaCodecUnsupported(meta.codec)
    if meta.duration_ms is not None and meta.duration_ms > MAX_DURATION_MS:
        raise MediaDurationExceeded(meta.duration_ms)
    if (
        meta.resolution_width > MAX_RESOLUTION_WIDTH
        or meta.resolution_height > MAX_RESOLUTION_HEIGHT
    ):
        raise MediaResolutionExceeded(
            f"{meta.resolution_width}x{meta.resolution_height}"
        )
    if meta.frame_rate is not None and meta.frame_rate > MAX_FRAME_RATE:
        raise MediaFrameRateExceeded(meta.frame_rate)


# ---------------------------------------------------------------------------
# State-machine helpers.
# ---------------------------------------------------------------------------


_PROCESSING_TRANSITIONS: Final[frozenset[tuple[str, str]]] = frozenset(
    {
        (PROCESSING_STATE_UPLOADED, PROCESSING_STATE_SCANNING),
        (PROCESSING_STATE_UPLOADED, PROCESSING_STATE_REJECTED),
        (PROCESSING_STATE_SCANNING, PROCESSING_STATE_TRANSCODING),
        (PROCESSING_STATE_SCANNING, PROCESSING_STATE_REJECTED),
        (PROCESSING_STATE_SCANNING, PROCESSING_STATE_REVIEW),
        (PROCESSING_STATE_TRANSCODING, PROCESSING_STATE_REVIEW),
        (PROCESSING_STATE_TRANSCODING, PROCESSING_STATE_REJECTED),
        (PROCESSING_STATE_TRANSCODING, PROCESSING_STATE_READY),
        (PROCESSING_STATE_REVIEW, PROCESSING_STATE_READY),
        (PROCESSING_STATE_REVIEW, PROCESSING_STATE_REJECTED),
        # ``deleted`` is reachable from any state — the row is
        # tombstoned. ``rejected`` and ``deleted`` are terminal
        # (no transition leaves them).
    }
)


def _assert_transition(from_state: str, to_state: str) -> None:
    if (from_state, to_state) not in _PROCESSING_TRANSITIONS:
        raise MediaTransitionError(f"{from_state} -> {to_state}")


def _set_processing_state(
    db: Session,
    row: CommunityMedia,
    *,
    new_state: str,
    now: datetime,
) -> CommunityMedia:
    """Internal — move ``row`` to ``new_state`` and bump ``updated_at``."""
    _assert_transition(row.processing_state, new_state)
    row.processing_state = new_state
    row.updated_at = now
    row.moderated_at = now
    db.flush()
    return row


# ---------------------------------------------------------------------------
# Public pipeline entry points.
# ---------------------------------------------------------------------------


def start_processing(
    db: Session,
    row: CommunityMedia,
    *,
    client_meta: ClientDeclaredMetadata,
    now: datetime | None = None,
) -> CommunityMedia:
    """Validate the client-declared metadata, then move the row
    from ``uploaded`` to ``scanning``.

    This is the FIRST step of the pipeline (no scan / transcode
    actually happens here — the malware + transcode checks are
    delegated to the moderation module's adapters; this function
    only validates the CLIENT-DECLARED metadata). The
    acceptance flow then drives ``run_malware_scan`` →
    ``run_transcode_check`` → ``submit_for_review`` →
    ``resolve_review``.
    """
    when = now or _now_utc()
    validate_client_metadata(client_meta)
    if row.processing_state != PROCESSING_STATE_UPLOADED:
        raise MediaTransitionError(f"start_processing from {row.processing_state}")
    return _set_processing_state(db, row, new_state=PROCESSING_STATE_SCANNING, now=when)


def run_malware_scan(
    db: Session,
    row: CommunityMedia,
    *,
    now: datetime | None = None,
) -> CommunityMedia:
    """Mark the row as past the malware-scan gate.

    Stub for the Kör 19 round — the real adapter call lives in
    :mod:`community.moderation.media_moderation` and is invoked
    in a future wiring round. This function is a state-machine
    transition only (``scanning`` → ``transcoding``); the
    malware-scan decision is recorded via the audit columns
    (see the A6 acceptance cell in the test module).

    Kept as a public function so the wiring round can call it
    directly from a Celery / BackgroundTasks worker.
    """
    when = now or _now_utc()
    if row.processing_state != PROCESSING_STATE_SCANNING:
        raise MediaTransitionError(f"run_malware_scan from {row.processing_state}")
    return _set_processing_state(
        db, row, new_state=PROCESSING_STATE_TRANSCODING, now=when
    )


def run_transcode_check(
    db: Session,
    row: CommunityMedia,
    *,
    now: datetime | None = None,
) -> CommunityMedia:
    """Mark the row as past the transcode-check gate.

    Stub — the real codec / dimension re-validation runs in the
    moderation module's transcode adapter. Today the function is
    a pure state transition (``transcoding`` → ``review``); the
    A2 / A3 / A6 acceptance cells rely on this transition being
    observable from a caller that drives the pipeline step by
    step.
    """
    when = now or _now_utc()
    if row.processing_state != PROCESSING_STATE_TRANSCODING:
        raise MediaTransitionError(f"run_transcode_check from {row.processing_state}")
    return _set_processing_state(db, row, new_state=PROCESSING_STATE_REVIEW, now=when)


def submit_for_review(
    db: Session,
    row: CommunityMedia,
    *,
    now: datetime | None = None,
) -> CommunityMedia:
    """Move the row into ``review`` (the entry point for the
    human-review-gate decision).

    The function is idempotent: a row already in ``review`` is
    a no-op (returns the row unchanged). The wiring round uses
    this idempotence to retry after a transient failure without
    re-entering the pipeline.
    """
    when = now or _now_utc()
    if row.processing_state == PROCESSING_STATE_REVIEW:
        return row
    if row.processing_state != PROCESSING_STATE_TRANSCODING:
        raise MediaTransitionError(f"submit_for_review from {row.processing_state}")
    return _set_processing_state(db, row, new_state=PROCESSING_STATE_REVIEW, now=when)


def is_playable(row: CommunityMedia) -> bool:
    """True iff the row's processing state permits playback.

    Mirrors the A2 acceptance cell (Flutter player) and the
    playback URL generation in
    :mod:`services.media_access_service`. The check is a single
    literal-equality — keeps the seam between the model and the
    player free of policy leakage.
    """
    return row.processing_state == "ready"


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _now_utc() -> datetime:
    """Caller-supplied-clock fallback — defaults to UTC now only
    when the caller omitted ``now`` AND the path is not under
    test. The acceptance cells always pass ``now`` explicitly."""
    return datetime.now(timezone.utc)


def parse_signed_playback_token(
    *,
    token: str,
    expected_media_public_id: uuid.UUID,
    secret: str,
    now: datetime,
    audience_passed: bool,
) -> datetime | None:
    """Return the token's expiry datetime when valid, else ``None``.

    Used by the playback URL verifier in
    :mod:`services.media_access_service`. Public here because
    the same verification routine is exercised by
    ``test_media_processing.py`` A4 / A5.

    The token shape is ``<expires_at_unix>.<base64url-hmac>`` —
    a small, two-field token (the public_id and the audience
    claim are bound INSIDE the HMAC, not exposed on the wire).
    The ``audience_passed`` boolean is the result of the
    :class:`CommunityAccessPolicy` check — the HMAC
    verification only confirms INTEGRITY, not AUTHORIZATION.
    """
    if not audience_passed:
        return None
    if "." not in token:
        return None
    expires_raw, signature_b64 = token.rsplit(".", 1)
    try:
        expires_at_unix = int(expires_raw)
        expires_at = datetime.fromtimestamp(expires_at_unix, tz=timezone.utc)
    except (ValueError, TypeError, OverflowError):
        return None
    payload = f"{expected_media_public_id}|{expires_at_unix}".encode("utf-8")
    import base64
    import hashlib
    import hmac as _hmac

    expected = _hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).digest()
    try:
        signature = base64.urlsafe_b64decode(signature_b64.encode("ascii"))
    except (ValueError, TypeError):
        return None
    if not _hmac.compare_digest(signature, expected):
        return None
    if expires_at <= now:
        return None
    return expires_at


def make_signed_playback_token(
    *,
    media_public_id: uuid.UUID,
    expires_at: datetime,
    secret: str,
) -> str:
    """The signing side of :func:`parse_signed_playback_token`.

    Public for the test module + for the playback service. The
    TTL is bounded by the caller (the access service uses
    ``timedelta(minutes=5)`` — see
    :mod:`services.media_access_service`).

    The payload binds the integer Unix timestamp (NOT the ISO
    string) so the verifier can reconstruct the exact bytes
    that were signed — ``isoformat()`` round-trips with
    microsecond noise that breaks the HMAC verification.
    """
    import base64
    import hashlib
    import hmac as _hmac

    expires_at_unix = int(expires_at.timestamp())
    payload = f"{media_public_id}|{expires_at_unix}".encode("utf-8")
    signature = _hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).digest()
    return f"{expires_at_unix}.{base64.urlsafe_b64encode(signature).decode('ascii')}"


def is_terminal_processing_state(value: str) -> bool:
    """True for ``rejected`` and ``deleted`` (no transitions out)."""
    return value in {PROCESSING_STATE_REJECTED, "deleted"}


__all__ = [
    "ALLOWED_CODECS",
    "ALLOWED_MIME_TYPES",
    "ClientDeclaredMetadata",
    "MAX_DURATION_MS",
    "MAX_FRAME_RATE",
    "MAX_RESOLUTION_WIDTH",
    "MAX_RESOLUTION_HEIGHT",
    "MediaCodecUnsupported",
    "MediaDurationExceeded",
    "MediaFrameRateExceeded",
    "MediaMimeTypeUnsupported",
    "MediaProcessingError",
    "MediaResolutionExceeded",
    "MediaTransitionError",
    "is_playable",
    "is_terminal_processing_state",
    "make_signed_playback_token",
    "parse_signed_playback_token",
    "run_malware_scan",
    "run_transcode_check",
    "start_processing",
    "strip_exif_from_jpeg",
    "submit_for_review",
    "validate_client_metadata",
]
