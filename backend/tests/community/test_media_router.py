"""End-to-end measurement of the Community media HTTP surface (WP-H5).

``services/media_upload_service.py`` (E09-R18) and
``tasks/media_processing.py`` (E09-R19) shipped with no router — ADR
0410's Következmények recorded the gap explicitly. This module measures
the router that closes it, and specifically the controls the presigned
design could not have:

* **Type sniffing** — a renamed file is rejected on its magic bytes, not
  on its extension or its declared header.
* **Size cap** — the threshold triple against the router's own 8 MiB
  cap.
* **Metadata stripping** — the bytes that come back out of ``GET`` no
  longer contain the EXIF/GPS payload that went in. Guarded against
  vacuous success by first asserting the fixture really carries it.
* **Ownership + leak-guard** — a foreign caller cannot tell "not yours"
  from "does not exist".
* **Visibility inheritance** — an attached media row is exactly as
  visible as its post.
* **The human review gate** — bytes are unreachable until a moderator
  approves (ADR 0412 D5).
* **Flag-off ⇒ route absent** — registration-level gating (ADR 0497
  D1), not a runtime 403.

The fixtures are built byte by byte in this module rather than checked
in as binaries, so a reader can see exactly what is being uploaded and
exactly which metadata is expected to disappear.
"""

from __future__ import annotations

import struct
import uuid
import zlib

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

from app.community import build_community_router
from app.community.models.media import CommunityMedia  # noqa: F401
from app.community.models.moderation import CommunityModerator
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.routers.media import (
    MAX_ROUTER_DURATION_MS,
    MAX_STORED_ITEMS_PER_PROFILE,
    MAX_ROUTER_UPLOAD_BYTES,
    MEDIA_UPLOAD_WINDOW_SECONDS,
    MEDIA_UPLOADS_PER_WINDOW,
)
from app.community.storage.local_object_store import LocalObjectStore
from app.community.storage.media_bytes import (
    MediaBytesMalformed,
    probe_duration_ms,
    sanitize_media_bytes,
    sniff_content_type,
)
from app.config import Settings
from app.database import Base
from app.ratelimit import RateLimiter

# ---------------------------------------------------------------------------
# Byte fixtures.
# ---------------------------------------------------------------------------

#: The GPS-ish payload planted in every image fixture. If this string
#: survives a round-trip, the scrubber failed.
SECRET_EXIF = b"GPSLatitude=47.4979;GPSLongitude=19.0402;Serial=ABC123"


def make_jpeg(*, with_exif: bool = True) -> bytes:
    """A minimal but structurally valid JPEG.

    Layout: SOI, optional APP1/EXIF, APP2 (an ICC-shaped segment that
    also carries the secret — the E09-R19 walker only removes APP1, so
    this segment is what proves the router's own pass runs), DQT, SOS +
    scan bytes, EOI.
    """
    out = bytearray(b"\xff\xd8")
    if with_exif:
        app1 = b"Exif\x00\x00" + SECRET_EXIF
        out += b"\xff\xe1" + struct.pack(">H", len(app1) + 2) + app1
        app2 = b"ICC_PROFILE\x00" + SECRET_EXIF
        out += b"\xff\xe2" + struct.pack(">H", len(app2) + 2) + app2
        comment = b"photographer: " + SECRET_EXIF
        out += b"\xff\xfe" + struct.pack(">H", len(comment) + 2) + comment
    dqt = bytes(64)
    out += b"\xff\xdb" + struct.pack(">H", len(dqt) + 2) + dqt
    sos_header = b"\x01\x00\x00\x3f\x00"
    out += b"\xff\xda" + struct.pack(">H", len(sos_header) + 2) + sos_header
    out += b"\x11\x22\x33\x44"  # entropy-coded data
    out += b"\xff\xd9"
    return bytes(out)


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def make_png(*, with_metadata: bool = True) -> bytes:
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    out += _png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
    if with_metadata:
        out += _png_chunk(b"eXIf", SECRET_EXIF)
        out += _png_chunk(b"tEXt", b"Comment\x00" + SECRET_EXIF)
    out += _png_chunk(b"IDAT", zlib.compress(b"\x00\x00"))
    out += _png_chunk(b"IEND", b"")
    return bytes(out)


def _riff_chunk(kind: bytes, payload: bytes) -> bytes:
    padded = payload + (b"\x00" if len(payload) & 1 else b"")
    return kind + struct.pack("<I", len(payload)) + padded


def make_wav(*, seconds: float = 1.0, with_metadata: bool = True) -> bytes:
    sample_rate = 8000
    channels = 1
    bits = 8
    byte_rate = sample_rate * channels * (bits // 8)
    fmt = struct.pack(
        "<HHIIHH", 1, channels, sample_rate, byte_rate, channels * bits // 8, bits
    )
    body = bytearray()
    body += _riff_chunk(b"fmt ", fmt)
    if with_metadata:
        body += _riff_chunk(b"LIST", b"INFO" + _riff_chunk(b"ICMT", SECRET_EXIF))
    body += _riff_chunk(b"data", b"\x80" * int(byte_rate * seconds))
    return b"RIFF" + struct.pack("<I", len(body) + 4) + b"WAVE" + bytes(body)


#: One 128 kbps / 44.1 kHz MPEG-1 Layer III frame: 417 bytes, ~26.12 ms.
_MP3_FRAME = b"\xff\xfb\x90\x00" + bytes(413)
MP3_FRAME_MS = 1152 * 1000 / 44100


def make_mp3(*, frames: int = 4, with_tags: bool = True) -> bytes:
    out = bytearray()
    if with_tags:
        payload = b"COMM" + SECRET_EXIF
        size = len(payload)
        syncsafe = bytes(
            ((size >> 21) & 0x7F, (size >> 14) & 0x7F, (size >> 7) & 0x7F, size & 0x7F)
        )
        out += b"ID3\x04\x00\x00" + syncsafe + payload
    out += _MP3_FRAME * frames
    if with_tags:
        out += b"TAG" + SECRET_EXIF.ljust(125, b"\x00")[:125]
    return bytes(out)


# ---------------------------------------------------------------------------
# App fixtures.
# ---------------------------------------------------------------------------


def _profile_for(session_factory, email: str) -> None:
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        db.add(CommunityProfile(user_id=user_id))
        db.commit()
    finally:
        db.close()


def _grant_moderator(session_factory, email: str) -> None:
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        db.add(CommunityModerator(user_id=user_id))
        db.commit()
    finally:
        db.close()


def _media_settings(tmp_path, **overrides) -> Settings:
    return Settings(
        community_enabled=True,
        community_writes_enabled=True,
        community_media_enabled=True,
        community_media_dir=str(tmp_path / "media"),
        **overrides,
    )


@pytest.fixture
def media_client(tmp_path):
    """Media-enabled app + author / stranger / moderator identities."""
    settings = _media_settings(tmp_path)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    # A fresh limiter per test: the router's module-level default is
    # process-global on purpose (that is what makes it a limiter), which
    # would otherwise let one test's uploads throttle the next one's.
    app.state.media_rate_limiter = RateLimiter(
        MEDIA_UPLOADS_PER_WINDOW, MEDIA_UPLOAD_WINDOW_SECONDS
    )
    with TestClient(app) as client:
        _, author = make_authenticated_user(
            session_factory, email="author@strumsight.app"
        )
        _, stranger = make_authenticated_user(
            session_factory, email="stranger@strumsight.app"
        )
        _, moderator = make_authenticated_user(
            session_factory, email="mod@strumsight.app"
        )
        for email in (
            "author@strumsight.app",
            "stranger@strumsight.app",
            "mod@strumsight.app",
        ):
            _profile_for(session_factory, email)
        _grant_moderator(session_factory, "mod@strumsight.app")
        try:
            yield client, author, stranger, moderator, session_factory
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _sf_of(media_client_fixture):
    return media_client_fixture[4]


def _upload(client, headers, body: bytes, *, filename: str, content_type: str):
    return client.post(
        "/community/media",
        headers=headers,
        files={"file": (filename, body, content_type)},
    )


def _approve(client, moderator_headers, media_id: str, decision: str = "approved"):
    return client.post(
        f"/community/media/{media_id}/review",
        headers=moderator_headers,
        json={"decision": decision},
    )


def _create_post(client, headers, *, audience: str = "public", key: str = "p1") -> str:
    response = client.post(
        "/community/posts",
        headers=headers,
        json={"audience": audience, "body": "take", "idempotency_key": key},
    )
    assert response.status_code == 201, response.text
    return response.json()["public_id"]


# ---------------------------------------------------------------------------
# A0 — the fixtures really carry what the scrubber must remove.
# ---------------------------------------------------------------------------


class TestFixturesAreNotVacuous:
    """Without these, every "metadata was stripped" assertion below could
    pass on a fixture that never had metadata in the first place."""

    def test_image_fixtures_contain_the_secret(self):
        assert SECRET_EXIF in make_jpeg()
        assert SECRET_EXIF in make_png()

    def test_audio_fixtures_contain_the_secret(self):
        assert SECRET_EXIF in make_wav()
        assert SECRET_EXIF in make_mp3()

    def test_fixtures_sniff_as_their_intended_type(self):
        assert sniff_content_type(make_jpeg()) == "image/jpeg"
        assert sniff_content_type(make_png()) == "image/png"
        assert sniff_content_type(make_wav()) == "audio/x-wav"
        assert sniff_content_type(make_mp3()) == "audio/mpeg"
        assert sniff_content_type(make_mp3(with_tags=False)) == "audio/mpeg"


# ---------------------------------------------------------------------------
# A1 — magic-byte sniffing.
# ---------------------------------------------------------------------------


class TestTypeSniffing:
    def test_a1_a_renamed_file_with_a_lying_header_is_refused(self, media_client):
        """PNG bytes, a ``.jpg`` name and an ``image/jpeg`` header — the
        exact shape of a content-type-confusion attempt."""
        client, author, *_ = media_client
        response = _upload(
            client,
            author,
            make_png(),
            filename="innocent.jpg",
            content_type="image/jpeg",
        )
        assert response.status_code == 415, response.text
        assert "does not match" in response.json()["detail"]

    def test_a1b_an_unknown_signature_is_refused(self, media_client):
        client, author, *_ = media_client
        response = _upload(
            client,
            author,
            b"#!/bin/sh\nrm -rf /\n" + b"\x00" * 64,
            filename="take.mp3",
            content_type="audio/mpeg",
        )
        assert response.status_code == 415, response.text

    def test_a1c_a_type_outside_the_router_allowlist_is_refused(self, media_client):
        """``video/mp4`` is in the E09-R18 pipeline allowlist but NOT in
        the router's: there is no server-side scrubber for ISO-BMFF
        metadata, so accepting it would be a silent egress path."""
        client, author, *_ = media_client
        ftyp = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomiso2mp41"
        response = _upload(
            client, author, ftyp + bytes(64), filename="clip.mp4", content_type=""
        )
        assert response.status_code == 415, response.text

    def test_a1d_extension_is_never_consulted(self, media_client):
        """A correct file with a nonsense extension and no declared type
        is accepted — the decision is the bytes', not the name's."""
        client, author, *_ = media_client
        response = _upload(
            client, author, make_wav(), filename="whatever.exe", content_type=""
        )
        assert response.status_code == 201, response.text
        assert response.json()["content_type"] == "audio/x-wav"


# ---------------------------------------------------------------------------
# A2 — size + duration caps.
# ---------------------------------------------------------------------------


class TestCaps:
    def test_a2_size_cap_threshold_pair(self, media_client):
        client, author, *_ = media_client
        # Just under the cap: a WAV padded with silence. The data chunk
        # dominates, so the body size is predictable.
        head = len(make_wav(seconds=0)) if False else None
        assert head is None  # keep the reader honest: size comes from the real body
        under = make_wav(seconds=1.0, with_metadata=False)
        assert len(under) < MAX_ROUTER_UPLOAD_BYTES
        assert (
            _upload(
                client, author, under, filename="a.wav", content_type="audio/x-wav"
            ).status_code
            == 201
        )
        over = make_wav(seconds=0) + b"\x00" * (MAX_ROUTER_UPLOAD_BYTES + 1)
        assert len(over) > MAX_ROUTER_UPLOAD_BYTES
        response = _upload(
            client, author, over, filename="b.wav", content_type="audio/x-wav"
        )
        assert response.status_code == 413, response.text

    def test_a2b_duration_cap_is_measured_from_the_bytes(self, media_client):
        client, author, *_ = media_client
        # 8 kHz / 8-bit mono keeps a >5-minute file comfortably under the
        # 8 MiB byte cap, so the DURATION cap is what rejects it — not
        # the size cap wearing a duration mask.
        long_wav = make_wav(seconds=MAX_ROUTER_DURATION_MS / 1000 + 5)
        assert len(long_wav) < MAX_ROUTER_UPLOAD_BYTES
        response = _upload(
            client, author, long_wav, filename="long.wav", content_type="audio/x-wav"
        )
        assert response.status_code == 413, response.text
        assert "duration" in response.json()["detail"]

    def test_a2c_measured_duration_lands_on_the_row(self, media_client):
        client, author, *_ = media_client
        response = _upload(
            client,
            author,
            make_wav(seconds=2.0),
            filename="two.wav",
            content_type="audio/x-wav",
        )
        assert response.status_code == 201, response.text
        assert response.json()["duration_ms"] == pytest.approx(2000, abs=50)

    def test_a2d_mp3_duration_is_measured_from_frame_headers(self):
        body = make_mp3(frames=10)
        clean = sanitize_media_bytes(body, content_type="audio/mpeg")
        measured = probe_duration_ms(clean, content_type="audio/mpeg")
        assert measured == pytest.approx(10 * MP3_FRAME_MS, abs=5)

    def test_a2e_an_empty_body_is_refused(self, media_client):
        client, author, *_ = media_client
        response = _upload(client, author, b"", filename="x.wav", content_type="")
        assert response.status_code in (400, 415), response.text


# ---------------------------------------------------------------------------
# A3 — metadata stripping, measured on the bytes that come back out.
# ---------------------------------------------------------------------------


class TestMetadataStripping:
    @pytest.mark.parametrize(
        ("body", "content_type", "filename"),
        [
            (make_jpeg(), "image/jpeg", "shot.jpg"),
            (make_png(), "image/png", "shot.png"),
            (make_wav(), "audio/x-wav", "take.wav"),
            (make_mp3(), "audio/mpeg", "take.mp3"),
        ],
    )
    def test_a3_the_secret_never_survives_a_round_trip(
        self, media_client, body, content_type, filename
    ):
        client, author, _stranger, moderator, _sf = media_client
        assert SECRET_EXIF in body  # the fixture is not vacuous
        created = _upload(
            client, author, body, filename=filename, content_type=content_type
        )
        assert created.status_code == 201, created.text
        media_id = created.json()["public_id"]
        assert _approve(client, moderator, media_id).status_code == 200
        fetched = client.get(f"/community/media/{media_id}", headers=author)
        assert fetched.status_code == 200, fetched.text
        assert SECRET_EXIF not in fetched.content
        assert b"GPSLatitude" not in fetched.content

    def test_a3b_the_stored_object_on_disk_is_the_scrubbed_copy(
        self, media_client, tmp_path
    ):
        """Not just the response — the bytes at rest carry no metadata
        either. A scrubber that only filtered the response would leave
        the original on disk for the next backup to pick up."""
        client, author, *_ = media_client
        created = _upload(
            client, author, make_jpeg(), filename="s.jpg", content_type="image/jpeg"
        )
        assert created.status_code == 201, created.text
        stored = list((tmp_path / "media").rglob("*"))
        blobs = [p for p in stored if p.is_file() and p.suffix != ".meta"]
        assert blobs, "no object written"
        for blob in blobs:
            assert SECRET_EXIF not in blob.read_bytes()

    def test_a3c_jpeg_keeps_its_scan_data(self):
        """The scrubber must not be a shredder — a stripped JPEG is still
        a JPEG with its image data intact."""
        clean = sanitize_media_bytes(make_jpeg(), content_type="image/jpeg")
        assert clean.startswith(b"\xff\xd8")
        assert clean.endswith(b"\xff\xd9")
        assert b"\xff\xda" in clean  # SOS survives
        assert b"\xff\xdb" in clean  # quantization table survives

    def test_a3d_wav_keeps_fmt_and_data(self):
        clean = sanitize_media_bytes(make_wav(), content_type="audio/x-wav")
        assert b"fmt " in clean and b"data" in clean
        assert b"LIST" not in clean

    def test_a3e_a_truncated_container_is_rejected_not_silently_passed(self):
        with pytest.raises(MediaBytesMalformed):
            sanitize_media_bytes(make_png()[:30], content_type="image/png")


# ---------------------------------------------------------------------------
# A4 — ownership + the uniform leak-guard.
# ---------------------------------------------------------------------------


class TestOwnershipAndLeakGuard:
    def test_a4_a_stranger_cannot_read_an_unattached_upload(self, media_client):
        client, author, stranger, moderator, _sf = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        assert _approve(client, moderator, media_id).status_code == 200
        unknown = str(uuid.uuid4())
        for path in (f"/community/media/{media_id}", f"/community/media/{media_id}/meta"):
            mine = client.get(path, headers=author)
            theirs = client.get(path, headers=stranger)
            assert mine.status_code == 200, mine.text
            assert theirs.status_code == 404
        # The denial is indistinguishable from a nonexistent id — same
        # status AND same body.
        denied = client.get(f"/community/media/{media_id}/meta", headers=stranger)
        absent = client.get(f"/community/media/{unknown}/meta", headers=stranger)
        assert denied.status_code == absent.status_code == 404
        assert denied.json() == absent.json()

    def test_a4b_a_stranger_cannot_delete_or_attach(self, media_client):
        client, author, stranger, *_ = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        their_post = _create_post(client, stranger, key="stranger-post")
        assert client.delete(
            f"/community/media/{media_id}", headers=stranger
        ).status_code == 404
        assert (
            client.post(
                f"/community/media/{media_id}/attach",
                headers=stranger,
                json={"post_public_id": their_post},
            ).status_code
            == 404
        )

    def test_a4c_the_owner_cannot_attach_to_someone_elses_post(self, media_client):
        client, author, stranger, *_ = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        foreign_post = _create_post(client, stranger, key="foreign")
        response = client.post(
            f"/community/media/{media_id}/attach",
            headers=author,
            json={"post_public_id": foreign_post},
        )
        assert response.status_code == 404, response.text

    def test_a4d_the_response_never_carries_internal_identifiers(self, media_client):
        client, author, *_ = media_client
        payload = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()
        for leaked in ("id", "object_key", "profile_id", "moderation_provider"):
            assert leaked not in payload, f"{leaked} leaked onto the wire"
        assert set(payload) == {
            "public_id",
            "owner_public_id",
            "content_type",
            "size_bytes",
            "duration_ms",
            "processing_state",
            "post_public_id",
            "created_at",
        }

    def test_a4e_an_undocumented_body_field_is_refused(self, media_client):
        client, author, *_ = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        post_id = _create_post(client, author, key="own")
        response = client.post(
            f"/community/media/{media_id}/attach",
            headers=author,
            json={"post_public_id": post_id, "profile_id": 1},
        )
        assert response.status_code == 422, response.text


# ---------------------------------------------------------------------------
# A5 — visibility is inherited from the post.
# ---------------------------------------------------------------------------


class TestVisibilityInheritance:
    def _ready_media(self, client, author, moderator) -> str:
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        assert _approve(client, moderator, media_id).status_code == 200
        return media_id

    def test_a5_attaching_to_a_public_post_opens_the_media(self, media_client):
        client, author, stranger, moderator, _sf = media_client
        media_id = self._ready_media(client, author, moderator)
        assert client.get(
            f"/community/media/{media_id}", headers=stranger
        ).status_code == 404
        post_id = _create_post(client, author, audience="public", key="pub")
        attached = client.post(
            f"/community/media/{media_id}/attach",
            headers=author,
            json={"post_public_id": post_id},
        )
        assert attached.status_code == 200, attached.text
        assert attached.json()["post_public_id"] == post_id
        assert client.get(
            f"/community/media/{media_id}", headers=stranger
        ).status_code == 200

    def test_a5b_a_private_post_keeps_the_media_closed(self, media_client):
        client, author, stranger, moderator, _sf = media_client
        media_id = self._ready_media(client, author, moderator)
        post_id = _create_post(client, author, audience="private", key="priv")
        assert (
            client.post(
                f"/community/media/{media_id}/attach",
                headers=author,
                json={"post_public_id": post_id},
            ).status_code
            == 200
        )
        assert client.get(
            f"/community/media/{media_id}", headers=stranger
        ).status_code == 404
        assert client.get(
            f"/community/media/{media_id}", headers=author
        ).status_code == 200

    def test_a5c_re_parenting_to_a_second_post_is_refused(self, media_client):
        client, author, _stranger, moderator, _sf = media_client
        media_id = self._ready_media(client, author, moderator)
        first = _create_post(client, author, audience="private", key="one")
        second = _create_post(client, author, audience="public", key="two")
        assert (
            client.post(
                f"/community/media/{media_id}/attach",
                headers=author,
                json={"post_public_id": first},
            ).status_code
            == 200
        )
        # Re-attaching to the SAME post is idempotent...
        assert (
            client.post(
                f"/community/media/{media_id}/attach",
                headers=author,
                json={"post_public_id": first},
            ).status_code
            == 200
        )
        # ...but moving it would retroactively widen the audience.
        response = client.post(
            f"/community/media/{media_id}/attach",
            headers=author,
            json={"post_public_id": second},
        )
        assert response.status_code == 409, response.text


# ---------------------------------------------------------------------------
# A6 — the human review gate (ADR 0412 D5).
# ---------------------------------------------------------------------------


class TestReviewGate:
    def test_a6_a_fresh_upload_is_not_playable(self, media_client):
        client, author, *_ = media_client
        created = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        )
        assert created.json()["processing_state"] == "review"
        media_id = created.json()["public_id"]
        # The owner can see the STATE but not the bytes.
        assert client.get(
            f"/community/media/{media_id}/meta", headers=author
        ).status_code == 200
        assert client.get(
            f"/community/media/{media_id}", headers=author
        ).status_code == 404

    def test_a6b_only_a_moderator_can_resolve_the_review(self, media_client):
        client, author, stranger, moderator, _sf = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        # Neither the author nor a stranger may approve their own media.
        assert _approve(client, author, media_id).status_code == 403
        assert _approve(client, stranger, media_id).status_code == 403
        assert _approve(client, moderator, media_id).status_code == 200
        assert client.get(
            f"/community/media/{media_id}", headers=author
        ).status_code == 200

    def test_a6c_a_rejected_row_never_serves_bytes(self, media_client):
        client, author, _stranger, moderator, _sf = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        assert _approve(client, moderator, media_id, "rejected").status_code == 200
        assert client.get(
            f"/community/media/{media_id}", headers=author
        ).status_code == 404
        meta = client.get(f"/community/media/{media_id}/meta", headers=author)
        assert meta.status_code == 200
        assert meta.json()["processing_state"] == "rejected"

    def test_a6d_an_invented_decision_is_refused(self, media_client):
        client, author, _stranger, moderator, _sf = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        assert _approve(client, moderator, media_id, "approved-ish").status_code == 422


# ---------------------------------------------------------------------------
# A7 — delete.
# ---------------------------------------------------------------------------


class TestDelete:
    def test_a7_delete_removes_the_bytes_and_tombstones_the_row(
        self, media_client, tmp_path
    ):
        client, author, _stranger, moderator, _sf = media_client
        media_id = _upload(
            client, author, make_wav(), filename="t.wav", content_type="audio/x-wav"
        ).json()["public_id"]
        assert _approve(client, moderator, media_id).status_code == 200
        blobs = [
            p
            for p in (tmp_path / "media").rglob("*")
            if p.is_file() and p.suffix != ".meta"
        ]
        assert blobs
        assert client.delete(
            f"/community/media/{media_id}", headers=author
        ).status_code == 200
        assert not [p for p in blobs if p.exists()], "bytes survived a deletion request"
        # The row is gone from every read path, owner included.
        assert client.get(
            f"/community/media/{media_id}/meta", headers=author
        ).status_code == 404
        # Idempotent.
        assert client.delete(
            f"/community/media/{media_id}", headers=author
        ).status_code == 200


# ---------------------------------------------------------------------------
# A8 — quota + rate limit.
# ---------------------------------------------------------------------------


class TestAbuseLimits:
    def test_a8_the_rate_limiter_stops_a_burst(self, tmp_path):
        settings = _media_settings(tmp_path)
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        app.state.media_rate_limiter = RateLimiter(2, 3600.0)
        with TestClient(app) as client:
            _, author = make_authenticated_user(
                session_factory, email="burst@strumsight.app"
            )
            _profile_for(session_factory, "burst@strumsight.app")
            body = make_wav(seconds=0.1)
            codes = [
                _upload(
                    client, author, body, filename="t.wav", content_type="audio/x-wav"
                ).status_code
                for _ in range(3)
            ]
        Base.metadata.drop_all(bind=engine)
        engine.dispose()
        assert codes[:2] == [201, 201]
        assert codes[2] == 429

    def test_a8b_the_item_quota_stops_hoarding(self, media_client):
        """The storage quota, not the E09-R18 live-upload quota.

        MEASURED: ``MAX_LIVE_UPLOADS_PER_PROFILE`` counts rows in a
        non-finalized upload state. The server-received flow finalizes
        inside the same request, so that count is back to zero before
        the next upload arrives and the E09-R18 quota can never fire
        here. The router's own item/byte quota is what actually bounds
        a hoarding account — this test pins that, and would go red if a
        refactor deleted the check believing the old quota covered it.
        """
        client, author, *_ = media_client
        client.app.state.media_rate_limiter = RateLimiter(10_000, 3600.0)
        body = make_wav(seconds=0.1)
        codes = [
            _upload(
                client, author, body, filename="t.wav", content_type="audio/x-wav"
            ).status_code
            for _ in range(MAX_STORED_ITEMS_PER_PROFILE + 2)
        ]
        assert codes.count(201) == MAX_STORED_ITEMS_PER_PROFILE, codes
        assert codes[-1] == 429, codes

    def test_a8c_deleting_frees_the_quota(self, media_client):
        client, author, *_ = media_client
        body = make_wav(seconds=0.1)
        first = _upload(
            client, author, body, filename="t.wav", content_type="audio/x-wav"
        )
        assert first.status_code == 201
        media_id = first.json()["public_id"]
        assert client.delete(
            f"/community/media/{media_id}", headers=author
        ).status_code == 200
        db = _sf_of(media_client)()
        try:
            from app.community.routers.media import _stored_usage

            items, stored = _stored_usage(db, profile_id=1)
        finally:
            db.close()
        assert items == 0 and stored == 0


# ---------------------------------------------------------------------------
# A9 — registration-level gating.
# ---------------------------------------------------------------------------


class TestFlagGating:
    def _paths(self, **flags) -> set[str]:
        settings = Settings(**flags)
        router = build_community_router(settings)
        if router is None:
            return set()
        return {route.path for route in router.routes}

    def test_a9_media_routes_are_absent_when_the_media_flag_is_off(self):
        on = self._paths(
            community_enabled=True,
            community_writes_enabled=True,
            community_media_enabled=True,
        )
        off = self._paths(
            community_enabled=True,
            community_writes_enabled=True,
            community_media_enabled=False,
        )
        assert any(path.startswith("/community/media") for path in on)
        assert not any(path.startswith("/community/media") for path in off)

    def test_a9b_media_routes_are_absent_when_writes_are_off(self):
        """The upload is a write, so the writes flag gates it too — the
        three-way AND ``docs/security/community-threat-model.md`` §6
        requires."""
        paths = self._paths(
            community_enabled=True,
            community_writes_enabled=False,
            community_media_enabled=True,
        )
        assert not any(path.startswith("/community/media") for path in paths)

    def test_a9c_a_disabled_flag_yields_404_not_403(self, tmp_path):
        settings = _media_settings(tmp_path)
        settings = settings.model_copy(update={"community_media_enabled": False})
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        with TestClient(app) as client:
            _, author = make_authenticated_user(
                session_factory, email="off@strumsight.app"
            )
            _profile_for(session_factory, "off@strumsight.app")
            response = _upload(
                client,
                author,
                make_wav(),
                filename="t.wav",
                content_type="audio/x-wav",
            )
        Base.metadata.drop_all(bind=engine)
        engine.dispose()
        assert response.status_code == 404, response.text


# ---------------------------------------------------------------------------
# A10 — storage adapter hardening.
# ---------------------------------------------------------------------------


class TestLocalObjectStore:
    def test_a10_a_traversal_key_is_refused(self, tmp_path):
        store = LocalObjectStore(tmp_path / "root")
        for key in ("../escape", "a/../../escape", "/etc/passwd"):
            with pytest.raises(ValueError):
                store.put_object(key, body=b"x", content_type="audio/x-wav")

    def test_a10b_objects_are_not_world_readable(self, tmp_path):
        store = LocalObjectStore(tmp_path / "root")
        store.put_object("p/1", body=b"abc", content_type="audio/x-wav")
        mode = (tmp_path / "root" / "p" / "1").stat().st_mode & 0o077
        assert mode == 0, oct(mode)

    def test_a10c_head_object_reports_what_was_written(self, tmp_path):
        store = LocalObjectStore(tmp_path / "root")
        written = store.put_object("p/2", body=b"abcd", content_type="image/png")
        head = store.head_object("p/2")
        assert head is not None
        assert head.size == 4
        assert head.content_type == "image/png"
        assert head.sha256_hex == written.sha256_hex

    def test_a10d_head_object_is_none_for_a_missing_object(self, tmp_path):
        assert LocalObjectStore(tmp_path / "root").head_object("nope") is None

    def test_a10e_response_headers_forbid_sniffing_and_caching(self, media_client):
        client, author, _stranger, moderator, _sf = media_client
        media_id = _upload(
            client, author, make_jpeg(), filename="s.jpg", content_type="image/jpeg"
        ).json()["public_id"]
        assert _approve(client, moderator, media_id).status_code == 200
        response = client.get(f"/community/media/{media_id}", headers=author)
        assert response.headers["x-content-type-options"] == "nosniff"
        assert response.headers["cache-control"] == "private, no-store"
        assert response.headers["content-disposition"].startswith("attachment")


# ---------------------------------------------------------------------------
# A11 — authentication is not optional.
# ---------------------------------------------------------------------------


class TestAuthRequired:
    def test_a11_every_media_route_refuses_an_anonymous_caller(self, media_client):
        client, *_ = media_client
        media_id = str(uuid.uuid4())
        calls = [
            client.post(
                "/community/media", files={"file": ("t.wav", make_wav(), "audio/x-wav")}
            ),
            client.get(f"/community/media/{media_id}"),
            client.get(f"/community/media/{media_id}/meta"),
            client.post(
                f"/community/media/{media_id}/attach",
                json={"post_public_id": str(uuid.uuid4())},
            ),
            client.post(
                f"/community/media/{media_id}/review", json={"decision": "approved"}
            ),
            client.delete(f"/community/media/{media_id}"),
        ]
        assert all(call.status_code in (401, 403) for call in calls), [
            call.status_code for call in calls
        ]

    def test_a11b_a_caller_without_a_community_profile_is_404(self, tmp_path):
        settings = _media_settings(tmp_path)
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        with TestClient(app) as client:
            _, headers = make_authenticated_user(
                session_factory, email="noprofile@strumsight.app"
            )
            response = _upload(
                client,
                headers,
                make_wav(),
                filename="t.wav",
                content_type="audio/x-wav",
            )
        Base.metadata.drop_all(bind=engine)
        engine.dispose()
        assert response.status_code == 404, response.text
