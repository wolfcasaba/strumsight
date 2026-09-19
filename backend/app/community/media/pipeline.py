"""The Community media pipeline (javító sáv R27).

One entry point per lifecycle operation, and one state machine:

``ingest``  ``pending → scanning → transcoding → review? → ready``
            with a ``rejected`` exit from every non-terminal state.
``release`` ``review → ready`` (the operator's release of a parked row).
``delete``  ``ready|rejected → deleted`` + the refcounted file unlink.

Order matters and is not negotiable:

1. **Size cap** — before anything reads the bytes as media. A 300 MiB
   upload must not be decoded to find out it is too big.
2. **Magic-byte sniff** (A6.2.1) — decides kind and media type from the
   bytes alone, so steps 3–4 know which cap and which transcoder apply.
3. **Scan** (A6.2.5) — on the ORIGINAL bytes. Scanning the re-encoded
   output would be scanning something the attacker never sent; the point
   is to catch what arrived.
4. **Transcode** (A6.2.4) — the stored bytes are the encoder's output.
5. **Store** — content-addressed, after the row already exists, so a
   crash between write and commit leaves an orphan FILE (harmless,
   unreferenced) rather than a row pointing at nothing.

Every rejection persists the row with ``state='rejected'`` and a
machine-readable ``rejection_code``. Nothing is silently dropped: an
upload that failed the scan is an audit event, and the client renders the
existing ``rejected`` face for it.

The service takes its collaborators by injection (scanner, transcoders,
store, clock) — the tests drive real adapters where that is cheap (the
Pillow re-encode, the filesystem store) and fakes where it is not (a
socket-level fake clamd is its own test module).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models.media_upload import (
    MEDIA_STATE_DELETED,
    MEDIA_STATE_PENDING,
    MEDIA_STATE_READY,
    MEDIA_STATE_REJECTED,
    MEDIA_STATE_REVIEW,
    MEDIA_STATE_SCANNING,
    MEDIA_STATE_TRANSCODING,
    CommunityMediaUpload,
    is_allowed_media_transition,
)
from ..models.profile import CommunityProfile
from .scanner import MediaScanner
from .sniff import KIND_AUDIO, KIND_IMAGE, MediaSniffError, sniff_media
from .store import FileMediaStore, sha256_hex
from .transcode import (
    AudioTranscoder,
    ImageTranscoder,
    TranscodeError,
)

#: Rejection code when the upload is larger than the per-kind cap.
REJECT_TOO_LARGE = "file_too_large"
#: Rejection code when the profile already holds the maximum live rows.
REJECT_QUOTA = "quota_exceeded"


class MediaPipelineError(Exception):
    """Base for the errors the router maps to a status code."""


class MediaDisabled(MediaPipelineError):
    """``community_media_enabled`` is off — the router 404s."""


class MediaProfileMissing(MediaPipelineError):
    """The caller has no Community profile yet."""


class MediaNotFound(MediaPipelineError):
    """No such media, or the viewer may not see it (uniform 404)."""


class MediaQuotaExceeded(MediaPipelineError):
    """The per-profile live-row quota is full."""


class MediaTooLarge(MediaPipelineError):
    """The upload exceeds the per-kind byte cap."""

    def __init__(self, limit_bytes: int) -> None:
        super().__init__(f"upload exceeds {limit_bytes} bytes")
        self.limit_bytes = limit_bytes


class MediaRejected(MediaPipelineError):
    """The pipeline rejected the upload; the row records why.

    Carries the persisted row so the router can answer with the full
    descriptor (state ``rejected`` + the code) instead of a bare error —
    the client renders its rejected face from exactly that shape.
    """

    def __init__(self, row: CommunityMediaUpload) -> None:
        super().__init__(row.rejection_code or "rejected")
        self.row = row


class MediaTransitionError(MediaPipelineError):
    """An illegal state transition was attempted (a programming error)."""


@dataclass(frozen=True)
class MediaLimits:
    """The numeric bounds the pipeline enforces, resolved from Settings."""

    max_image_bytes: int
    max_audio_bytes: int
    max_items_per_profile: int
    review_required: bool

    @staticmethod
    def from_settings(settings) -> "MediaLimits":
        return MediaLimits(
            max_image_bytes=settings.media_max_image_bytes,
            max_audio_bytes=settings.media_max_audio_bytes,
            max_items_per_profile=settings.media_max_items_per_profile,
            review_required=settings.media_review_required,
        )

    def cap_for(self, kind: str) -> int:
        return self.max_image_bytes if kind == KIND_IMAGE else self.max_audio_bytes


class MediaPipeline:
    """Ingest / release / delete for one request's worth of work."""

    def __init__(
        self,
        db: Session,
        *,
        store: FileMediaStore,
        scanner: MediaScanner,
        image_transcoder: ImageTranscoder,
        audio_transcoder: AudioTranscoder,
        limits: MediaLimits,
        now: datetime | None = None,
    ) -> None:
        self._db = db
        self._store = store
        self._scanner = scanner
        self._image = image_transcoder
        self._audio = audio_transcoder
        self._limits = limits
        self._now = now or datetime.now(timezone.utc)

    # -- helpers --------------------------------------------------------

    def _transition(self, row: CommunityMediaUpload, to_state: str) -> None:
        if not is_allowed_media_transition(row.state, to_state):
            raise MediaTransitionError(
                f"illegal media transition {row.state!r} -> {to_state!r}"
            )
        row.state = to_state
        row.updated_at = self._now
        self._db.flush()

    def _reject(self, row: CommunityMediaUpload, code: str) -> MediaRejected:
        row.rejection_code = code
        self._transition(row, MEDIA_STATE_REJECTED)
        return MediaRejected(row)

    def _live_count(self, profile_id: int) -> int:
        """Rows a profile holds that are not deleted and not rejected.

        Rejected rows are excluded on purpose: a user whose uploads keep
        failing the scan would otherwise fill their own quota with
        nothing, and the resulting "quota exceeded" would hide the real
        reason (which the rejection code already states).
        """
        stmt = (
            select(func.count())
            .select_from(CommunityMediaUpload)
            .where(
                CommunityMediaUpload.profile_id == profile_id,
                CommunityMediaUpload.state.notin_(
                    (MEDIA_STATE_DELETED, MEDIA_STATE_REJECTED)
                ),
            )
        )
        return int(self._db.execute(stmt).scalar_one())

    def _other_references(self, row: CommunityMediaUpload) -> int:
        """Live rows OTHER than ``row`` pointing at the same digest."""
        if not row.content_sha256:
            return 0
        stmt = (
            select(func.count())
            .select_from(CommunityMediaUpload)
            .where(
                CommunityMediaUpload.content_sha256 == row.content_sha256,
                CommunityMediaUpload.id != row.id,
                CommunityMediaUpload.state != MEDIA_STATE_DELETED,
            )
        )
        return int(self._db.execute(stmt).scalar_one())

    # -- ingest ---------------------------------------------------------

    def ingest(
        self,
        *,
        profile_id: int,
        data: bytes,
    ) -> CommunityMediaUpload:
        """Run the full machine over ``data`` and return the row.

        Raises :class:`MediaRejected` (carrying the persisted, rejected
        row), :class:`MediaTooLarge` or :class:`MediaQuotaExceeded`. A
        successful call returns a row in ``ready`` (or ``review`` when
        the operator requires one).
        """
        if self._live_count(profile_id) >= self._limits.max_items_per_profile:
            raise MediaQuotaExceeded(REJECT_QUOTA)

        # (1) Size, before anything parses the bytes. The bound checked
        # here is the LARGER of the two caps, because the per-kind cap
        # is only knowable after the sniff; the per-kind check follows
        # immediately afterwards.
        absolute_cap = max(
            self._limits.max_image_bytes,
            self._limits.max_audio_bytes,
        )
        if len(data) > absolute_cap:
            raise MediaTooLarge(absolute_cap)

        # (2) Magic bytes. A sniff failure never creates a row: there is
        # nothing to audit about bytes that are not media at all, and
        # persisting one row per probe would hand an attacker a free
        # write amplification.
        try:
            sniffed = sniff_media(data)
        except MediaSniffError as exc:
            raise MediaRejected(
                self._rejected_stub(profile_id, data, exc.code)
            ) from exc

        cap = self._limits.cap_for(sniffed.kind)
        if len(data) > cap:
            raise MediaTooLarge(cap)

        row = CommunityMediaUpload(
            public_id=uuid.uuid4(),
            profile_id=profile_id,
            kind=sniffed.kind,
            state=MEDIA_STATE_PENDING,
            content_type=sniffed.media_type,
            source_sha256=sha256_hex(data),
            source_size_bytes=len(data),
            created_at=self._now,
            updated_at=self._now,
        )
        self._db.add(row)
        self._db.flush()

        # (3) Scan the ORIGINAL bytes.
        self._transition(row, MEDIA_STATE_SCANNING)
        verdict = self._scanner.scan(data)
        row.scanner = self._scanner.name
        row.scanned_at = self._now
        if not verdict.clean:
            raise self._reject(row, verdict.code or "scan_failed")

        # (4) Re-encode.
        self._transition(row, MEDIA_STATE_TRANSCODING)
        try:
            if sniffed.kind == KIND_IMAGE:
                encoded = self._image.transcode(data)
            elif sniffed.kind == KIND_AUDIO:
                encoded = self._audio.transcode(
                    data,
                    media_type=sniffed.media_type,
                )
            else:  # pragma: no cover - sniffer returns only two kinds
                raise TranscodeError("unsupported_media_type")
        except TranscodeError as exc:
            raise self._reject(row, exc.code) from exc

        # (5) Store.
        digest, _ = self._store.put(encoded.data)
        row.content_sha256 = digest
        row.content_type = encoded.media_type
        row.size_bytes = len(encoded.data)
        row.width = encoded.width
        row.height = encoded.height
        row.duration_ms = encoded.duration_ms

        if self._limits.review_required:
            self._transition(row, MEDIA_STATE_REVIEW)
        else:
            self._transition(row, MEDIA_STATE_READY)
            row.ready_at = self._now
            self._db.flush()
        return row

    def _rejected_stub(
        self,
        profile_id: int,
        data: bytes,
        code: str,
    ) -> CommunityMediaUpload:
        """A detached, unsaved row describing a pre-persist rejection.

        Returned inside :class:`MediaRejected` so the router can answer
        with the same descriptor shape as a persisted rejection without
        writing a row for every malformed probe.
        """
        return CommunityMediaUpload(
            public_id=uuid.uuid4(),
            profile_id=profile_id,
            kind="unknown",
            state=MEDIA_STATE_REJECTED,
            rejection_code=code,
            content_type="application/octet-stream",
            source_sha256=sha256_hex(data),
            source_size_bytes=len(data),
            created_at=self._now,
            updated_at=self._now,
        )

    # -- release / delete -----------------------------------------------

    def release(self, row: CommunityMediaUpload) -> CommunityMediaUpload:
        """Move a parked ``review`` row to ``ready``."""
        if row.state != MEDIA_STATE_REVIEW:
            raise MediaTransitionError(
                f"only a review row can be released (state={row.state!r})"
            )
        self._transition(row, MEDIA_STATE_READY)
        row.ready_at = self._now
        self._db.flush()
        return row

    def delete(self, row: CommunityMediaUpload) -> CommunityMediaUpload:
        """Terminal delete: state ``deleted`` + refcounted file unlink.

        Idempotent — deleting an already-deleted row is a no-op, so a
        retried DELETE cannot 500.
        """
        if row.state == MEDIA_STATE_DELETED:
            return row
        digest = row.content_sha256
        others = self._other_references(row)
        self._transition(row, MEDIA_STATE_DELETED)
        row.deleted_at = self._now
        row.post_id = None
        self._db.flush()
        if digest:
            self._store.delete(digest, other_references=others)
        return row


def find_media(db: Session, public_id: uuid.UUID) -> CommunityMediaUpload | None:
    """Row lookup by wire identity. ``None`` when absent."""
    stmt = select(CommunityMediaUpload).where(
        CommunityMediaUpload.public_id == public_id
    )
    return db.execute(stmt).scalar_one_or_none()


def resolve_profile_id(db: Session, user_id: int) -> int:
    """Internal ``community_profiles.id`` for a JWT subject.

    Raises :class:`MediaProfileMissing` when the caller has no profile —
    the router maps that to the same 404 every other Community write
    surface uses.
    """
    stmt = select(CommunityProfile.id).where(CommunityProfile.user_id == user_id)
    found = db.execute(stmt).scalar_one_or_none()
    if found is None:
        raise MediaProfileMissing("caller has no community profile")
    return int(found)


__all__ = [
    "REJECT_QUOTA",
    "REJECT_TOO_LARGE",
    "MediaDisabled",
    "MediaLimits",
    "MediaNotFound",
    "MediaPipeline",
    "MediaPipelineError",
    "MediaProfileMissing",
    "MediaQuotaExceeded",
    "MediaRejected",
    "MediaTooLarge",
    "MediaTransitionError",
    "find_media",
    "resolve_profile_id",
]
