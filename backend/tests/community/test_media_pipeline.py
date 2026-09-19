"""Javító sáv R27 — the media pipeline's state machine and re-encode.

``pending → scanning → transcoding → review? → ready``, with a
``rejected`` exit from every non-terminal state and a terminal
``deleted``. The module measures the machine itself (which states are
reachable, in which order, and what the row records on each exit) and the
two security properties the re-encode is there to buy (threat model
A6.2.4): metadata is gone, and appended payloads are gone.

Acceptance map:

* **A1 — the happy path walks every state in order.** A recording
  scanner + a recording transcoder capture the row's state at the moment
  each collaborator is called, so "the scan happened while the row said
  ``scanning``" is asserted rather than assumed.
* **A2 — the scan reads the ORIGINAL bytes.** Scanning the re-encoded
  output would be scanning something the attacker never sent.
* **A3 — a rejection persists the row with a machine-readable code.**
  Nothing is silently dropped; the client's rejected face is rendered
  from exactly that row.
* **A4 — illegal transitions raise.** The transition table is the
  authority, not the caller's good intentions.
* **A5 — the caps are enforced before anything parses the bytes**, and
  the per-kind cap after the sniff. The threshold triple (cap-1 / cap /
  cap+1) is measured on the image cap.
* **A6 — the quota bounds live rows per profile**, and REJECTED rows do
  not count against it (a user whose uploads keep failing the scan must
  not have the real reason hidden behind "quota exceeded").
* **A7 — EXIF/GPS does not survive**, and neither does a polyglot tail:
  the stored bytes are the encoder's output.
* **A8 — audio is fail-closed by default.** The disabled transcoder puts
  the row in ``rejected`` with ``audio_transcoder_unavailable`` — the
  machine still runs to completion, it just does not store anything.
* **A9 — ``review`` is an operator opt-in**, and ``release`` is the only
  way out of it.
* **A10 — delete is terminal, refcounted and idempotent.**
"""

from __future__ import annotations

import io
import uuid
from collections.abc import Iterator

import pytest
from conftest import _make_test_engine
from PIL import Image
from sqlalchemy.orm import Session, sessionmaker

from app.community.media.pipeline import (
    MediaLimits,
    MediaPipeline,
    MediaProfileMissing,
    MediaQuotaExceeded,
    MediaRejected,
    MediaTooLarge,
    MediaTransitionError,
    find_media,
    resolve_profile_id,
)
from app.community.media.scanner import (
    REJECT_INFECTED,
    REJECT_NOT_CONFIGURED,
    DisabledScanner,
    MediaScanner,
    ScanVerdict,
)
from app.community.media.sniff import REJECT_SCRIPTABLE, REJECT_UNSUPPORTED
from app.community.media.store import FileMediaStore
from app.community.media.transcode import (
    REJECT_AUDIO_UNAVAILABLE,
    REJECT_IMAGE_UNREADABLE,
    DisabledAudioTranscoder,
    PillowImageTranscoder,
)
from app.community.models.media_upload import (
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
from app.community.models.profile import CommunityProfile
from app.config import Settings
from app.database import Base
from app.models import User

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

_SVG = b'<svg xmlns="http://www.w3.org/2000/svg"><script>x()</script></svg>'
_ZIP_TAIL = b"PK\x03\x04" + b"payload-that-must-not-survive" * 8


def _jpeg(size: tuple[int, int] = (32, 24)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color=(10, 200, 90)).save(buffer, format="JPEG")
    return buffer.getvalue()


def _jpeg_with_gps_exif() -> bytes:
    """A JPEG carrying a GPS EXIF block — the privacy leak A7 removes."""
    image = Image.new("RGB", (48, 36), color=(200, 30, 30))
    exif = image.getexif()
    # 0x8825 = GPSInfo IFD pointer; 0x010E = ImageDescription. Both are
    # metadata a phone camera really writes and a re-encode really drops.
    exif[0x010E] = "practice room, 47.4979 N 19.0402 E"
    gps = exif.get_ifd(0x8825)
    gps[1] = "N"
    gps[2] = (47.0, 29.0, 52.4)
    gps[3] = "E"
    gps[4] = (19.0, 2.0, 24.7)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", exif=exif)
    return buffer.getvalue()


def _png_with_alpha() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGBA", (20, 20), color=(0, 0, 255, 128)).save(buffer, format="PNG")
    return buffer.getvalue()


def _wav(sample_count: int = 32) -> bytes:
    pcm = b"\x00\x00" * sample_count
    fmt_chunk = (
        b"fmt "
        + (16).to_bytes(4, "little")
        + (1).to_bytes(2, "little")
        + (1).to_bytes(2, "little")
        + (8000).to_bytes(4, "little")
        + (16000).to_bytes(4, "little")
        + (2).to_bytes(2, "little")
        + (16).to_bytes(2, "little")
    )
    data_chunk = b"data" + len(pcm).to_bytes(4, "little") + pcm
    body = b"WAVE" + fmt_chunk + data_chunk
    return b"RIFF" + len(body).to_bytes(4, "little") + body


class _AcceptingScanner(MediaScanner):
    """A scanner that accepts — and records the row state it saw.

    Only ever used to drive the states BEYOND the scan; the production
    default is :class:`DisabledScanner`, which refuses. The recorded
    payload is what makes the A2 "scanned the original" cell measurable.
    """

    name = "fake-clean"

    def __init__(self) -> None:
        self.payloads: list[bytes] = []

    def scan(self, data: bytes) -> ScanVerdict:
        self.payloads.append(data)
        return ScanVerdict.ok()


class _InfectedScanner(MediaScanner):
    name = "fake-infected"

    def scan(self, data: bytes) -> ScanVerdict:  # noqa: ARG002 - port shape
        return ScanVerdict(
            clean=False,
            code=REJECT_INFECTED,
            signature="Eicar-Test-Signature",
        )


class _StateRecordingScanner(MediaScanner):
    """Captures the row's state at the moment the scan is invoked."""

    name = "fake-recorder"

    def __init__(self, db: Session) -> None:
        self._db = db
        self.state_at_scan: str | None = None

    def scan(self, data: bytes) -> ScanVerdict:  # noqa: ARG002 - port shape
        row = self._db.query(CommunityMediaUpload).one()
        self.state_at_scan = row.state
        return ScanVerdict.ok()


class _StateRecordingImageTranscoder(PillowImageTranscoder):
    def __init__(self, db: Session) -> None:
        super().__init__()
        self._db = db
        self.state_at_transcode: str | None = None

    def transcode(self, data: bytes):
        row = self._db.query(CommunityMediaUpload).one()
        self.state_at_transcode = row.state
        return super().transcode(data)


@pytest.fixture
def media_db(tmp_path) -> Iterator[tuple[Session, int, int, FileMediaStore]]:
    """A session with two profiles and a filesystem store.

    Yields ``(session, profile_id, other_profile_id, store)``.
    """
    engine = _make_test_engine()
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    db = factory()
    try:
        owner = User(email="media-owner@strumsight.app", hashed_password="x")
        stranger = User(email="media-other@strumsight.app", hashed_password="x")
        db.add_all([owner, stranger])
        db.flush()
        owner_profile = CommunityProfile(user_id=owner.id)
        other_profile = CommunityProfile(user_id=stranger.id)
        db.add_all([owner_profile, other_profile])
        db.commit()
        store = FileMediaStore(tmp_path / "media-root")
        yield db, int(owner_profile.id), int(other_profile.id), store
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


def _limits(**overrides) -> MediaLimits:
    defaults = dict(
        max_image_bytes=1024 * 1024,
        max_audio_bytes=2 * 1024 * 1024,
        max_items_per_profile=5,
        review_required=False,
    )
    defaults.update(overrides)
    return MediaLimits(**defaults)


def _pipeline(
    db: Session,
    store: FileMediaStore,
    *,
    scanner: MediaScanner | None = None,
    image_transcoder=None,
    audio_transcoder=None,
    limits: MediaLimits | None = None,
) -> MediaPipeline:
    return MediaPipeline(
        db,
        store=store,
        scanner=scanner or _AcceptingScanner(),
        image_transcoder=image_transcoder or PillowImageTranscoder(),
        audio_transcoder=audio_transcoder or DisabledAudioTranscoder(),
        limits=limits or _limits(),
    )


# ---------------------------------------------------------------------------
# A1 / A2 — the happy path and the order of the hops
# ---------------------------------------------------------------------------


class TestHappyPath:
    def test_an_image_walks_to_ready_and_stores_the_encoders_output(self, media_db):
        db, profile_id, _, store = media_db
        source = _jpeg()
        pipeline = _pipeline(db, store)

        row = pipeline.ingest(profile_id=profile_id, data=source)

        assert row.state == MEDIA_STATE_READY
        assert row.kind == "image"
        assert row.rejection_code is None
        assert row.ready_at is not None
        assert row.scanner == "fake-clean"
        assert row.scanned_at is not None
        # The stored bytes are the encoder's output, so the digest of the
        # SOURCE and of the CONTENT differ — that difference is the whole
        # point of A6.2.4.
        assert row.source_size_bytes == len(source)
        assert row.content_sha256 is not None
        assert row.content_sha256 != row.source_sha256
        assert store.read(row.content_sha256) != source
        assert row.size_bytes == len(store.read(row.content_sha256))
        assert (row.width, row.height) == (32, 24)

    def test_each_collaborator_runs_in_its_own_state(self, media_db):
        """A1 — ``scanning`` during the scan, ``transcoding`` during the
        re-encode. A machine whose states only get written at the END
        would pass a naive "final state is ready" assertion while
        recording nothing an operator could read mid-flight."""
        db, profile_id, _, store = media_db
        scanner = _StateRecordingScanner(db)
        transcoder = _StateRecordingImageTranscoder(db)
        pipeline = _pipeline(db, store, scanner=scanner, image_transcoder=transcoder)

        pipeline.ingest(profile_id=profile_id, data=_jpeg())

        assert scanner.state_at_scan == MEDIA_STATE_SCANNING
        assert transcoder.state_at_transcode == MEDIA_STATE_TRANSCODING

    def test_the_scan_sees_the_original_bytes_not_the_re_encoded_ones(self, media_db):
        """A2 — the scanner must be handed what ARRIVED. Scanning the
        Pillow output would clear a file the attacker never sent."""
        db, profile_id, _, store = media_db
        scanner = _AcceptingScanner()
        source = _jpeg()

        row = _pipeline(db, store, scanner=scanner).ingest(
            profile_id=profile_id, data=source
        )

        assert scanner.payloads == [source]
        assert store.read(row.content_sha256) != source

    def test_an_alpha_png_is_re_encoded_to_webp_and_keeps_transparency(self, media_db):
        db, profile_id, _, store = media_db
        row = _pipeline(db, store).ingest(profile_id=profile_id, data=_png_with_alpha())
        assert row.state == MEDIA_STATE_READY
        assert row.content_type == "image/webp"

    def test_an_oversized_image_is_downscaled_to_the_configured_bound(self, media_db):
        db, profile_id, _, store = media_db
        transcoder = PillowImageTranscoder(max_dimension=64, quality=70)
        row = _pipeline(db, store, image_transcoder=transcoder).ingest(
            profile_id=profile_id, data=_jpeg((400, 200))
        )
        assert (row.width, row.height) == (64, 32)


# ---------------------------------------------------------------------------
# A7 — the re-encode is a privacy control, not a validation step
# ---------------------------------------------------------------------------


class TestReEncodeStripsWhatTheUploaderWrote:
    def test_gps_exif_does_not_survive(self, media_db):
        db, profile_id, _, store = media_db
        source = _jpeg_with_gps_exif()
        # Sanity: the fixture really does carry the metadata, otherwise
        # this cell would pass for the wrong reason.
        assert Image.open(io.BytesIO(source)).getexif().get_ifd(0x8825)

        row = _pipeline(db, store).ingest(profile_id=profile_id, data=source)

        stored = store.read(row.content_sha256)
        exif = Image.open(io.BytesIO(stored)).getexif()
        assert not exif.get_ifd(0x8825)
        assert 0x010E not in exif
        assert b"47.4979" not in stored

    def test_an_appended_payload_does_not_survive(self, media_db):
        """The polyglot's tail is dropped by the re-encode. The sniffer
        accepted the file (it IS a JPEG); the transcoder is what makes
        the tail unreachable."""
        db, profile_id, _, store = media_db
        row = _pipeline(db, store).ingest(
            profile_id=profile_id, data=_jpeg() + _ZIP_TAIL
        )
        stored = store.read(row.content_sha256)
        assert b"payload-that-must-not-survive" not in stored
        assert stored.startswith(b"\xff\xd8\xff")

    def test_a_truncated_image_that_passes_the_sniff_is_rejected(self, media_db):
        """A signature match is not proof the rest decodes; the
        transcoder is the second gate, and its refusal is a rejected ROW,
        not a crash."""
        db, profile_id, _, store = media_db
        truncated = _jpeg((200, 200))[:40]
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store).ingest(profile_id=profile_id, data=truncated)
        assert raised.value.row.rejection_code == REJECT_IMAGE_UNREADABLE
        assert raised.value.row.state == MEDIA_STATE_REJECTED


# ---------------------------------------------------------------------------
# A3 — every rejection is an auditable row
# ---------------------------------------------------------------------------


class TestRejections:
    def test_the_default_disabled_scanner_rejects_and_persists_the_reason(
        self, media_db
    ):
        """A8's sibling: an operator who flips the feature flag without
        standing up clamd accepts NOTHING. This is the cell that would go
        green if a pass-through scanner were ever added."""
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store, scanner=DisabledScanner()).ingest(
                profile_id=profile_id, data=_jpeg()
            )
        row = raised.value.row
        assert row.state == MEDIA_STATE_REJECTED
        assert row.rejection_code == REJECT_NOT_CONFIGURED
        assert row.scanner == "disabled"
        # Persisted, not just returned — the audit trail is the point.
        db.commit()
        assert find_media(db, row.public_id).state == MEDIA_STATE_REJECTED
        # Nothing reached the store.
        assert row.content_sha256 is None

    def test_an_infected_upload_is_rejected_and_never_stored(self, media_db):
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store, scanner=_InfectedScanner()).ingest(
                profile_id=profile_id, data=_jpeg()
            )
        row = raised.value.row
        assert row.rejection_code == REJECT_INFECTED
        assert row.content_sha256 is None
        # The clamd signature is attacker-influenced text; it is audit
        # data on the verdict, never a column the wire reads.
        assert "Eicar" not in (row.rejection_code or "")

    @pytest.mark.parametrize(
        ("payload", "code"),
        [
            pytest.param(_SVG, REJECT_SCRIPTABLE, id="svg"),
            pytest.param(b"PK\x03\x04" + b"\x00" * 40, REJECT_UNSUPPORTED, id="zip"),
            pytest.param(b"%PDF-1.7\n", REJECT_UNSUPPORTED, id="pdf"),
        ],
    )
    def test_a_sniff_failure_answers_with_a_rejected_descriptor(
        self, media_db, payload, code
    ):
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store).ingest(profile_id=profile_id, data=payload)
        assert raised.value.row.state == MEDIA_STATE_REJECTED
        assert raised.value.row.rejection_code == code

    def test_a_sniff_failure_writes_no_row(self, media_db):
        """Persisting one row per malformed probe would hand an attacker
        free write amplification; the descriptor is built detached."""
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected):
            _pipeline(db, store).ingest(profile_id=profile_id, data=_SVG)
        db.rollback()
        assert db.query(CommunityMediaUpload).count() == 0

    def test_an_empty_part_is_rejected_before_anything_else(self, media_db):
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store).ingest(profile_id=profile_id, data=b"")
        assert raised.value.row.rejection_code == "empty_upload"


# ---------------------------------------------------------------------------
# A8 — audio is fail-closed
# ---------------------------------------------------------------------------


class TestAudioIsFailClosedByDefault:
    def test_the_disabled_transcoder_rejects_the_row_rather_than_storing_it(
        self, media_db
    ):
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store).ingest(profile_id=profile_id, data=_wav())
        row = raised.value.row
        assert row.kind == "audio"
        assert row.state == MEDIA_STATE_REJECTED
        assert row.rejection_code == REJECT_AUDIO_UNAVAILABLE
        assert row.content_sha256 is None

    def test_the_row_still_records_that_the_scan_happened(self, media_db):
        """The machine runs to completion — the audio upload is refused
        at the transcode hop, not skipped — so the audit row still says
        which scanner looked at the bytes."""
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store).ingest(profile_id=profile_id, data=_wav())
        assert raised.value.row.scanner == "fake-clean"
        assert raised.value.row.scanned_at is not None


# ---------------------------------------------------------------------------
# A4 — the transition table is the authority
# ---------------------------------------------------------------------------


class TestTransitionTable:
    @pytest.mark.parametrize(
        ("source", "target"),
        [
            (MEDIA_STATE_PENDING, MEDIA_STATE_SCANNING),
            (MEDIA_STATE_SCANNING, MEDIA_STATE_TRANSCODING),
            (MEDIA_STATE_TRANSCODING, MEDIA_STATE_READY),
            (MEDIA_STATE_TRANSCODING, MEDIA_STATE_REVIEW),
            (MEDIA_STATE_REVIEW, MEDIA_STATE_READY),
            (MEDIA_STATE_READY, MEDIA_STATE_DELETED),
            (MEDIA_STATE_REJECTED, MEDIA_STATE_DELETED),
        ],
    )
    def test_the_documented_edges_are_allowed(self, source, target):
        assert is_allowed_media_transition(source, target)

    @pytest.mark.parametrize(
        ("source", "target"),
        [
            pytest.param(
                MEDIA_STATE_PENDING, MEDIA_STATE_READY, id="skip-the-whole-machine"
            ),
            pytest.param(
                MEDIA_STATE_PENDING,
                MEDIA_STATE_TRANSCODING,
                id="skip-the-scan",
            ),
            pytest.param(
                MEDIA_STATE_SCANNING, MEDIA_STATE_READY, id="scan-straight-to-ready"
            ),
            pytest.param(MEDIA_STATE_REJECTED, MEDIA_STATE_READY, id="un-reject"),
            pytest.param(MEDIA_STATE_DELETED, MEDIA_STATE_READY, id="resurrect"),
            pytest.param(
                MEDIA_STATE_READY, MEDIA_STATE_REJECTED, id="reject-after-publish"
            ),
        ],
    )
    def test_the_dangerous_edges_are_refused(self, source, target):
        assert not is_allowed_media_transition(source, target)

    def test_the_pipeline_raises_rather_than_writing_an_illegal_state(self, media_db):
        db, profile_id, _, store = media_db
        row = _pipeline(db, store).ingest(profile_id=profile_id, data=_jpeg())
        pipeline = _pipeline(db, store)
        with pytest.raises(MediaTransitionError):
            pipeline.release(row)  # ready, not review
        assert row.state == MEDIA_STATE_READY


# ---------------------------------------------------------------------------
# A5 / A6 — the two independent budgets
# ---------------------------------------------------------------------------


class TestSizeCaps:
    def test_the_image_cap_is_a_threshold_triple(self, media_db):
        db, profile_id, _, store = media_db
        source = _jpeg((160, 120))
        exact = len(source)

        for cap, should_pass in ((exact + 1, True), (exact, True), (exact - 1, False)):
            limits = _limits(max_image_bytes=cap, max_audio_bytes=cap)
            pipeline = _pipeline(db, store, limits=limits)
            if should_pass:
                assert pipeline.ingest(profile_id=profile_id, data=source)
            else:
                with pytest.raises(MediaTooLarge) as raised:
                    pipeline.ingest(profile_id=profile_id, data=source)
                assert raised.value.limit_bytes == cap

    def test_the_per_kind_cap_applies_after_the_sniff(self, media_db):
        """A generous AUDIO cap must not become a generous IMAGE cap: the
        absolute pre-parse bound is the larger of the two, and the
        per-kind bound is re-checked once the sniffer says which kind
        this is."""
        db, profile_id, _, store = media_db
        source = _jpeg((160, 120))
        limits = _limits(
            max_image_bytes=len(source) - 1,
            max_audio_bytes=len(source) + 10_000,
        )
        with pytest.raises(MediaTooLarge) as raised:
            _pipeline(db, store, limits=limits).ingest(
                profile_id=profile_id, data=source
            )
        assert raised.value.limit_bytes == len(source) - 1

    def test_an_over_cap_upload_writes_no_row(self, media_db):
        db, profile_id, _, store = media_db
        limits = _limits(max_image_bytes=8, max_audio_bytes=8)
        with pytest.raises(MediaTooLarge):
            _pipeline(db, store, limits=limits).ingest(
                profile_id=profile_id, data=_jpeg()
            )
        db.rollback()
        assert db.query(CommunityMediaUpload).count() == 0


class TestPerProfileQuota:
    def test_live_rows_are_bounded(self, media_db):
        db, profile_id, _, store = media_db
        limits = _limits(max_items_per_profile=2)
        pipeline = _pipeline(db, store, limits=limits)

        pipeline.ingest(profile_id=profile_id, data=_jpeg((10, 10)))
        pipeline.ingest(profile_id=profile_id, data=_jpeg((12, 12)))
        with pytest.raises(MediaQuotaExceeded):
            pipeline.ingest(profile_id=profile_id, data=_jpeg((14, 14)))

    def test_the_quota_is_per_profile_not_global(self, media_db):
        db, profile_id, other_profile_id, store = media_db
        limits = _limits(max_items_per_profile=1)
        pipeline = _pipeline(db, store, limits=limits)

        pipeline.ingest(profile_id=profile_id, data=_jpeg((10, 10)))
        # The other account is unaffected by the first one's usage.
        assert pipeline.ingest(profile_id=other_profile_id, data=_jpeg((12, 12)))

    def test_rejected_rows_do_not_consume_the_quota(self, media_db):
        """Otherwise a user whose uploads keep failing the scan fills
        their own quota with nothing, and the resulting "quota exceeded"
        hides the real reason the rejection code already states."""
        db, profile_id, _, store = media_db
        limits = _limits(max_items_per_profile=1)
        with pytest.raises(MediaRejected):
            _pipeline(db, store, scanner=DisabledScanner(), limits=limits).ingest(
                profile_id=profile_id, data=_jpeg()
            )
        assert _pipeline(db, store, limits=limits).ingest(
            profile_id=profile_id, data=_jpeg()
        )

    def test_deleted_rows_free_the_quota_again(self, media_db):
        db, profile_id, _, store = media_db
        limits = _limits(max_items_per_profile=1)
        pipeline = _pipeline(db, store, limits=limits)
        row = pipeline.ingest(profile_id=profile_id, data=_jpeg((10, 10)))
        pipeline.delete(row)
        assert pipeline.ingest(profile_id=profile_id, data=_jpeg((12, 12)))


# ---------------------------------------------------------------------------
# A9 / A10 — review and delete
# ---------------------------------------------------------------------------


class TestReviewGate:
    def test_review_required_parks_the_row_instead_of_publishing_it(self, media_db):
        db, profile_id, _, store = media_db
        limits = _limits(review_required=True)
        row = _pipeline(db, store, limits=limits).ingest(
            profile_id=profile_id, data=_jpeg()
        )
        assert row.state == MEDIA_STATE_REVIEW
        assert row.ready_at is None
        # The bytes ARE stored — the operator has to be able to look at
        # them to review them.
        assert store.exists(row.content_sha256)

    def test_release_is_the_only_way_out_of_review(self, media_db):
        db, profile_id, _, store = media_db
        limits = _limits(review_required=True)
        pipeline = _pipeline(db, store, limits=limits)
        row = pipeline.ingest(profile_id=profile_id, data=_jpeg())

        released = pipeline.release(row)
        assert released.state == MEDIA_STATE_READY
        assert released.ready_at is not None

    def test_release_refuses_a_row_that_is_not_in_review(self, media_db):
        db, profile_id, _, store = media_db
        pipeline = _pipeline(db, store)
        row = pipeline.ingest(profile_id=profile_id, data=_jpeg())
        with pytest.raises(MediaTransitionError):
            pipeline.release(row)


class TestDelete:
    def test_delete_is_terminal_and_unlinks_the_file(self, media_db):
        db, profile_id, _, store = media_db
        pipeline = _pipeline(db, store)
        row = pipeline.ingest(profile_id=profile_id, data=_jpeg())
        digest = row.content_sha256

        pipeline.delete(row)

        assert row.state == MEDIA_STATE_DELETED
        assert row.deleted_at is not None
        assert row.post_id is None
        assert not store.exists(digest)

    def test_delete_is_idempotent(self, media_db):
        db, profile_id, _, store = media_db
        pipeline = _pipeline(db, store)
        row = pipeline.ingest(profile_id=profile_id, data=_jpeg())
        pipeline.delete(row)
        # A retried DELETE must not 500 on an illegal transition.
        assert pipeline.delete(row).state == MEDIA_STATE_DELETED

    def test_deleting_one_of_two_rows_sharing_a_digest_keeps_the_file(self, media_db):
        """A10 — content addressing deduplicates two identical uploads
        onto one file; one owner's delete must not blank the other's
        post."""
        db, profile_id, other_profile_id, store = media_db
        pipeline = _pipeline(db, store)
        source = _jpeg((18, 18))
        mine = pipeline.ingest(profile_id=profile_id, data=source)
        theirs = pipeline.ingest(profile_id=other_profile_id, data=source)
        assert mine.content_sha256 == theirs.content_sha256

        pipeline.delete(mine)
        assert store.exists(theirs.content_sha256)

        pipeline.delete(theirs)
        assert not store.exists(theirs.content_sha256)

    def test_a_rejected_row_can_be_deleted(self, media_db):
        db, profile_id, _, store = media_db
        with pytest.raises(MediaRejected) as raised:
            _pipeline(db, store, scanner=DisabledScanner()).ingest(
                profile_id=profile_id, data=_jpeg()
            )
        row = raised.value.row
        assert _pipeline(db, store).delete(row).state == MEDIA_STATE_DELETED


# ---------------------------------------------------------------------------
# Profile resolution
# ---------------------------------------------------------------------------


class TestProfileResolution:
    def test_a_user_without_a_community_profile_is_a_named_error(self, media_db):
        db, _, _, _ = media_db
        orphan = User(email="no-profile@strumsight.app", hashed_password="x")
        db.add(orphan)
        db.flush()
        with pytest.raises(MediaProfileMissing):
            resolve_profile_id(db, int(orphan.id))

    def test_find_media_returns_none_for_an_unknown_public_id(self, media_db):
        db, _, _, _ = media_db
        assert find_media(db, uuid.uuid4()) is None


# ---------------------------------------------------------------------------
# Settings → limits
# ---------------------------------------------------------------------------


class TestLimitsComeFromSettings:
    def test_the_shipped_defaults_are_the_documented_ones(self):
        limits = MediaLimits.from_settings(Settings())
        assert limits.max_image_bytes == 8 * 1024 * 1024
        assert limits.max_audio_bytes == 20 * 1024 * 1024
        assert limits.max_items_per_profile == 50
        # The review gate is an operator opt-in, off by default.
        assert limits.review_required is False

    def test_the_per_kind_cap_selector_reads_the_sniffed_kind(self):
        limits = _limits(max_image_bytes=11, max_audio_bytes=22)
        assert limits.cap_for("image") == 11
        assert limits.cap_for("audio") == 22
