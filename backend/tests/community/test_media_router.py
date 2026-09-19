"""Javító sáv R27 — the HTTP media surface, end to end.

``POST /community/media`` (multipart), ``GET /community/media/{id}`` and
``DELETE /community/media/{id}``, driven through a real ``TestClient``
against a real ``build_community_router`` aggregate — the registration
gate, the auth chain, the multipart parser, the pipeline, the filesystem
store and the post-attachment path all in one process.

The happy path runs through a REAL clamd session (``fake_clamd.py``
listening on an ephemeral port, selected via
``STRUMSIGHT_MEDIA_SCANNER=clamd``) rather than an injected fake
scanner. That is deliberate: ``build_media_scanner`` is part of what this
round ships, and a test that bypasses it would leave "the operator
configured clamd and uploads now work" unmeasured — which is exactly the
configuration the runbook tells an operator to create.

Acceptance map:

* **A1 — the flag is a REGISTRATION gate.** With
  ``community_media_enabled`` off the three paths are not in the route
  table at all; there is no runtime 403 to probe and no handler to reach.
* **A2 — the upload answers with the descriptor the client models**, and
  the descriptor leaks nothing: no internal id, no filesystem path, no
  content digest.
* **A3 — a pipeline rejection is a 201 carrying a ``rejected``
  descriptor**, not a 4xx. The genuinely exceptional outcomes (cap,
  quota, throttle, no profile) keep their status codes.
* **A4 — the filename and the multipart ``Content-Type`` never decide
  anything.** An SVG posted as ``holiday.jpg`` with ``image/jpeg`` is
  rejected; a JPEG posted as ``notes.txt`` with
  ``application/octet-stream`` is accepted.
* **A5 — download serves the SERVER's content-type with the hardening
  headers**, and is audience-checked: a loose upload is owner-only, an
  attached one follows the post's own visibility, and every refusal is
  the same 404.
* **A6 — delete is owner-only, terminal and idempotent.**
* **A7 — attachment is re-validated server-side at publish time**:
  ownership, ``ready`` state and the not-already-attached rule, all
  behind a uniform error, and the published post carries the descriptor.
* **A8 — two independent budgets**: a per-IP throttle and a per-profile
  quota, each measurable on its own.
"""

from __future__ import annotations

import io
import uuid

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fake_clamd import FakeClamd
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.community.routers.media import reset_rate_limiters
from app.config import Settings
from app.database import Base

_SECRET = "a-real-32-char-test-secret-key-value"  # strumsight:allow-secret teszt-fixture Settings, nem éles kulcs

_SVG = b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'


def _jpeg(size: tuple[int, int] = (40, 30), color=(10, 180, 90)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color=color).save(buffer, format="JPEG")
    return buffer.getvalue()


def _profile_for(session_factory, email: str) -> int:
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        profile = CommunityProfile(user_id=user_id)
        db.add(profile)
        db.commit()
        return int(profile.id)
    finally:
        db.close()


def _media_settings(tmp_path, clamd_port: int | None, **overrides) -> Settings:
    defaults = dict(
        community_enabled=True,
        community_writes_enabled=True,
        community_media_enabled=True,
        media_root=str(tmp_path / "media-root"),
        media_scanner="clamd" if clamd_port else "disabled",
        media_scanner_port=clamd_port or 3310,
        media_scanner_timeout_seconds=5.0,
        secret_key=_SECRET,
    )
    defaults.update(overrides)
    return Settings(**defaults)


class _Fixture:
    """The app + the two accounts + the session factory, in one handle."""

    def __init__(self, client, owner, other, session_factory, clamd) -> None:
        self.client = client
        self.owner = owner
        self.other = other
        self.session_factory = session_factory
        self.clamd = clamd


def _build_media_fixture(tmp_path, *, clamd_answer=b"stream: OK\0", **overrides):
    reset_rate_limiters()
    clamd = FakeClamd(clamd_answer) if clamd_answer is not None else None
    settings = _media_settings(tmp_path, clamd.port if clamd else None, **overrides)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    client = TestClient(app)
    return app, client, engine, session_factory, clamd


@pytest.fixture
def media(tmp_path):
    """Media ON, clamd up, two accounts with Community profiles."""
    app, client, engine, session_factory, clamd = _build_media_fixture(tmp_path)
    with client:
        _, owner = make_authenticated_user(
            session_factory, email="media-owner@strumsight.app"
        )
        _, other = make_authenticated_user(
            session_factory, email="media-other@strumsight.app"
        )
        _profile_for(session_factory, "media-owner@strumsight.app")
        _profile_for(session_factory, "media-other@strumsight.app")
        try:
            yield _Fixture(client, owner, other, session_factory, clamd)
        finally:
            if clamd is not None:
                clamd.close()
            Base.metadata.drop_all(bind=engine)
            engine.dispose()
            reset_rate_limiters()


def _upload(
    fixture: _Fixture,
    payload: bytes,
    *,
    headers=None,
    filename: str = "photo.jpg",
    content_type: str = "image/jpeg",
):
    return fixture.client.post(
        "/community/media",
        headers=headers or fixture.owner,
        files={"file": (filename, payload, content_type)},
    )


def _upload_ready(fixture: _Fixture, payload: bytes | None = None, **kwargs) -> dict:
    response = _upload(fixture, payload if payload is not None else _jpeg(), **kwargs)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["state"] == "ready", body
    return body


# ---------------------------------------------------------------------------
# A1 — the registration gate
# ---------------------------------------------------------------------------


class TestFeatureFlagIsARegistrationGate:
    def test_the_three_paths_are_absent_when_the_flag_is_off(self, tmp_path):
        app, client, engine, session_factory, clamd = _build_media_fixture(
            tmp_path, community_media_enabled=False
        )
        try:
            with client:
                _, headers = make_authenticated_user(
                    session_factory, email="flag-off@strumsight.app"
                )
                _profile_for(session_factory, "flag-off@strumsight.app")
                assert (
                    client.post(
                        "/community/media",
                        headers=headers,
                        files={"file": ("a.jpg", _jpeg(), "image/jpeg")},
                    ).status_code
                    == 404
                )
                probe = uuid.uuid4()
                assert (
                    client.get(f"/community/media/{probe}", headers=headers).status_code
                    == 404
                )
                assert (
                    client.delete(
                        f"/community/media/{probe}", headers=headers
                    ).status_code
                    == 404
                )
            # Not "404 from inside the router" — the routes do not exist.
            paths = {route.path for route in app.routes}
            assert "/community/media" not in paths
        finally:
            if clamd is not None:
                clamd.close()
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_the_paths_exist_when_the_flag_is_on(self, media):
        paths = {
            route.path
            for route in media.client.app.routes
            if "media" in getattr(route, "path", "")
        }
        assert "/community/media" in paths
        assert "/community/media/{public_id}" in paths

    def test_the_upload_requires_authentication(self, media):
        response = media.client.post(
            "/community/media",
            files={"file": ("a.jpg", _jpeg(), "image/jpeg")},
        )
        assert response.status_code in (401, 403)


# ---------------------------------------------------------------------------
# A2 / A3 / A4 — the upload
# ---------------------------------------------------------------------------


class TestUpload:
    def test_a_clean_image_becomes_a_ready_descriptor(self, media):
        body = _upload_ready(media)

        assert uuid.UUID(body["public_id"])
        assert body["kind"] == "image"
        assert body["rejection_code"] is None
        # The SERVER's verdict — the re-encode's output type, not the
        # multipart header the caller wrote.
        assert body["content_type"] == "image/jpeg"
        assert body["size_bytes"] > 0
        assert (body["width"], body["height"]) == (40, 30)
        assert body["created_at"]
        # The scan really ran through a real clamd session.
        assert media.clamd.sessions == 1

    def test_the_descriptor_leaks_no_internal_identity(self, media):
        """A2 — no row id, no filesystem path, no content digest. The
        digest in particular would turn the store into a cross-user
        oracle ("does anyone else hold this exact file?")."""
        body = _upload_ready(media)
        assert set(body) == {
            "public_id",
            "kind",
            "state",
            "rejection_code",
            "content_type",
            "size_bytes",
            "width",
            "height",
            "duration_ms",
            "created_at",
        }

    def test_the_stored_bytes_are_the_encoders_output_not_the_upload(self, media):
        source = _jpeg() + b"PK\x03\x04trailing-payload"
        body = _upload_ready(media, source)
        served = media.client.get(
            f"/community/media/{body['public_id']}", headers=media.owner
        )
        assert served.status_code == 200
        assert served.content != source
        assert b"trailing-payload" not in served.content

    def test_a_scriptable_payload_is_a_201_rejected_descriptor(self, media):
        """A3 — the client already renders a rejected face; turning this
        into a 4xx would force it to invent one."""
        response = _upload(media, _SVG)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["state"] == "rejected"
        assert body["rejection_code"] == "scriptable_media_rejected"

    def test_an_infected_payload_is_rejected_without_echoing_the_signature(
        self, tmp_path
    ):
        """The clamd finding's name is attacker-influenced text; it stays
        in the audit trail and never reaches the wire."""
        app, client, engine, session_factory, clamd = _build_media_fixture(
            tmp_path, clamd_answer=b"stream: Eicar-Test-Signature FOUND\0"
        )
        try:
            with client:
                _, headers = make_authenticated_user(
                    session_factory, email="infected@strumsight.app"
                )
                _profile_for(session_factory, "infected@strumsight.app")
                response = client.post(
                    "/community/media",
                    headers=headers,
                    files={"file": ("a.jpg", _jpeg(), "image/jpeg")},
                )
                assert response.status_code == 201, response.text
                body = response.json()
                assert body["state"] == "rejected"
                assert body["rejection_code"] == "malware_detected"
                assert "Eicar" not in response.text
        finally:
            clamd.close()
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_an_unconfigured_scanner_rejects_every_upload(self, tmp_path):
        """The fail-closed default: flipping the feature flag WITHOUT
        standing up clamd accepts nothing (runbook §7.3)."""
        app, client, engine, session_factory, clamd = _build_media_fixture(
            tmp_path, clamd_answer=None
        )
        try:
            with client:
                _, headers = make_authenticated_user(
                    session_factory, email="no-scanner@strumsight.app"
                )
                _profile_for(session_factory, "no-scanner@strumsight.app")
                response = client.post(
                    "/community/media",
                    headers=headers,
                    files={"file": ("a.jpg", _jpeg(), "image/jpeg")},
                )
                assert response.status_code == 201, response.text
                assert response.json()["rejection_code"] == "scanner_not_configured"
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_the_filename_and_multipart_content_type_decide_nothing(self, media):
        """A4 — both directions of the renamed-payload matrix, over the
        real multipart parser."""
        disguised = _upload(
            media, _SVG, filename="holiday.jpg", content_type="image/jpeg"
        )
        assert disguised.json()["state"] == "rejected"

        honest = _upload(
            media,
            _jpeg(),
            filename="notes.txt",
            content_type="application/octet-stream",
        )
        assert honest.json()["state"] == "ready"

    def test_an_empty_part_is_its_own_rejection(self, media):
        response = _upload(media, b"")
        assert response.status_code == 201
        assert response.json()["rejection_code"] == "empty_upload"

    def test_an_audio_upload_is_rejected_while_the_transcoder_is_disabled(self, media):
        wav_pcm = b"\x00\x00" * 16
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
        data_chunk = b"data" + len(wav_pcm).to_bytes(4, "little") + wav_pcm
        body_bytes = b"WAVE" + fmt_chunk + data_chunk
        wav = b"RIFF" + len(body_bytes).to_bytes(4, "little") + body_bytes

        response = _upload(media, wav, filename="take.wav", content_type="audio/wav")
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["kind"] == "audio"
        assert body["state"] == "rejected"
        assert body["rejection_code"] == "audio_transcoder_unavailable"

    def test_a_caller_without_a_community_profile_gets_404(self, media):
        _, headers = make_authenticated_user(
            media.session_factory, email="profileless@strumsight.app"
        )
        response = _upload(media, _jpeg(), headers=headers)
        assert response.status_code == 404


# ---------------------------------------------------------------------------
# A8 — the two budgets
# ---------------------------------------------------------------------------


class TestBudgets:
    def test_an_over_cap_upload_is_413_with_the_limit_named(self, tmp_path):
        app, client, engine, session_factory, clamd = _build_media_fixture(
            tmp_path, media_max_image_bytes=256, media_max_audio_bytes=256
        )
        try:
            with client:
                _, headers = make_authenticated_user(
                    session_factory, email="too-big@strumsight.app"
                )
                _profile_for(session_factory, "too-big@strumsight.app")
                response = client.post(
                    "/community/media",
                    headers=headers,
                    files={"file": ("a.jpg", _jpeg((300, 300)), "image/jpeg")},
                )
                assert response.status_code == 413, response.text
                detail = response.json()["detail"]
                assert detail["error"] == "file_too_large"
                assert detail["limit_bytes"] == 256
        finally:
            clamd.close()
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_the_per_profile_quota_answers_409(self, tmp_path):
        app, client, engine, session_factory, clamd = _build_media_fixture(
            tmp_path, media_max_items_per_profile=1
        )
        try:
            with client:
                _, headers = make_authenticated_user(
                    session_factory, email="quota@strumsight.app"
                )
                _profile_for(session_factory, "quota@strumsight.app")
                first = client.post(
                    "/community/media",
                    headers=headers,
                    files={"file": ("a.jpg", _jpeg((10, 10)), "image/jpeg")},
                )
                assert first.status_code == 201, first.text
                second = client.post(
                    "/community/media",
                    headers=headers,
                    files={"file": ("b.jpg", _jpeg((12, 12)), "image/jpeg")},
                )
                assert second.status_code == 409, second.text
                assert second.json()["detail"]["error"] == "quota_exceeded"
        finally:
            clamd.close()
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_the_per_ip_throttle_answers_429(self, tmp_path):
        """A8 — the throttle is INDEPENDENT of the quota: it bounds the
        request rate from one host, including the requests that never
        produce a row (rejections)."""
        app, client, engine, session_factory, clamd = _build_media_fixture(
            tmp_path,
            media_upload_rate_limit_max=2,
            media_upload_rate_limit_window=3600,
        )
        try:
            with client:
                _, headers = make_authenticated_user(
                    session_factory, email="throttle@strumsight.app"
                )
                _profile_for(session_factory, "throttle@strumsight.app")
                for _ in range(2):
                    accepted = client.post(
                        "/community/media",
                        headers=headers,
                        files={"file": ("a.svg", _SVG, "image/svg+xml")},
                    )
                    assert accepted.status_code == 201, accepted.text
                throttled = client.post(
                    "/community/media",
                    headers=headers,
                    files={"file": ("a.jpg", _jpeg(), "image/jpeg")},
                )
                assert throttled.status_code == 429, throttled.text
        finally:
            clamd.close()
            Base.metadata.drop_all(bind=engine)
            engine.dispose()
            reset_rate_limiters()


# ---------------------------------------------------------------------------
# A5 — the download
# ---------------------------------------------------------------------------


class TestDownload:
    def test_the_owner_gets_the_bytes_with_the_hardening_headers(self, media):
        body = _upload_ready(media)
        response = media.client.get(
            f"/community/media/{body['public_id']}", headers=media.owner
        )

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("image/jpeg")
        assert response.headers["x-content-type-options"] == "nosniff"
        assert "default-src 'none'" in response.headers["content-security-policy"]
        assert response.headers["cache-control"].startswith("private")
        # No caller-supplied filename ever comes back out.
        assert response.headers["content-disposition"] == "inline"
        assert "photo.jpg" not in response.headers.get("content-disposition", "")
        assert Image.open(io.BytesIO(response.content)).size == (40, 30)

    def test_a_loose_upload_is_owner_only(self, media):
        """A5 — the composer's in-progress attachment is not public just
        because somebody guessed a UUID."""
        body = _upload_ready(media)
        response = media.client.get(
            f"/community/media/{body['public_id']}", headers=media.other
        )
        assert response.status_code == 404

    def test_an_unknown_id_and_a_hidden_one_answer_identically(self, media):
        body = _upload_ready(media)
        hidden = media.client.get(
            f"/community/media/{body['public_id']}", headers=media.other
        )
        unknown = media.client.get(
            f"/community/media/{uuid.uuid4()}", headers=media.other
        )
        assert hidden.status_code == unknown.status_code == 404
        assert hidden.json() == unknown.json()

    def test_a_rejected_row_has_no_downloadable_bytes(self, media):
        rejected = _upload(media, _SVG).json()
        response = media.client.get(
            f"/community/media/{rejected['public_id']}", headers=media.owner
        )
        assert response.status_code == 404

    @pytest.mark.parametrize(
        "candidate",
        [
            pytest.param("..%2F..%2Fetc%2Fpasswd", id="encoded-traversal"),
            pytest.param("not-a-uuid", id="not-a-uuid"),
            pytest.param("00000000-0000-0000-0000-000000000000", id="nil-uuid"),
        ],
    )
    def test_the_path_segment_can_never_address_a_file(self, media, candidate):
        """There is no code path from a request field to a path segment:
        the segment is parsed as a UUID, the row carries the digest, and
        the digest is what the store resolves."""
        response = media.client.get(
            f"/community/media/{candidate}", headers=media.owner
        )
        assert response.status_code in (404, 422)

    def test_the_download_requires_authentication(self, media):
        body = _upload_ready(media)
        response = media.client.get(f"/community/media/{body['public_id']}")
        assert response.status_code in (401, 403)


# ---------------------------------------------------------------------------
# A6 — delete
# ---------------------------------------------------------------------------


class TestDelete:
    def test_the_owner_deletes_and_the_bytes_stop_being_served(self, media):
        body = _upload_ready(media)
        response = media.client.delete(
            f"/community/media/{body['public_id']}", headers=media.owner
        )
        assert response.status_code == 200
        assert response.json() == {"status": "deleted"}
        assert (
            media.client.get(
                f"/community/media/{body['public_id']}", headers=media.owner
            ).status_code
            == 404
        )

    def test_a_second_delete_is_a_no_op_not_a_500(self, media):
        body = _upload_ready(media)
        media.client.delete(
            f"/community/media/{body['public_id']}", headers=media.owner
        )
        repeat = media.client.delete(
            f"/community/media/{body['public_id']}", headers=media.owner
        )
        assert repeat.status_code == 200
        assert repeat.json() == {"status": "noop"}

    def test_a_stranger_cannot_delete_and_cannot_tell_it_exists(self, media):
        body = _upload_ready(media)
        foreign = media.client.delete(
            f"/community/media/{body['public_id']}", headers=media.other
        )
        unknown = media.client.delete(
            f"/community/media/{uuid.uuid4()}", headers=media.other
        )
        assert foreign.status_code == unknown.status_code == 404
        assert foreign.json() == unknown.json()
        # And the owner's media survived the attempt.
        assert (
            media.client.get(
                f"/community/media/{body['public_id']}", headers=media.owner
            ).status_code
            == 200
        )


# ---------------------------------------------------------------------------
# A7 — attaching media to a post
# ---------------------------------------------------------------------------


def _create_post(fixture: _Fixture, *, headers=None, media_ids=None, key="k-1"):
    payload = {
        "audience": "public",
        "body": "gyakorlás közben",
        "idempotency_key": key,
    }
    if media_ids is not None:
        payload["media_ids"] = media_ids
    return fixture.client.post(
        "/community/posts", headers=headers or fixture.owner, json=payload
    )


class TestPostAttachment:
    def test_a_published_post_carries_its_ready_media(self, media):
        uploaded = _upload_ready(media)
        response = _create_post(media, media_ids=[uploaded["public_id"]])

        assert response.status_code == 201, response.text
        body = response.json()
        assert [item["public_id"] for item in body["media"]] == [uploaded["public_id"]]
        assert body["media"][0]["state"] == "ready"

    def test_a_post_without_media_carries_an_empty_list_not_a_null(self, media):
        """The client never has to distinguish "absent" from "none"."""
        response = _create_post(media, key="k-no-media")
        assert response.status_code == 201, response.text
        assert response.json()["media"] == []

    def test_the_single_post_read_agrees_with_the_publish_response(self, media):
        uploaded = _upload_ready(media)
        created = _create_post(media, media_ids=[uploaded["public_id"]]).json()
        fetched = media.client.get(
            f"/community/posts/{created['public_id']}", headers=media.owner
        )
        assert fetched.status_code == 200, fetched.text
        assert fetched.json()["media"] == created["media"]

    def test_someone_elses_media_cannot_be_attached(self, media):
        """A7 — the client's list is a request, never an assertion."""
        stolen = _upload_ready(media, headers=media.other)
        response = _create_post(media, media_ids=[stolen["public_id"]])
        assert response.status_code == 400, response.text
        # And the theft is indistinguishable from an invented id.
        invented = _create_post(media, media_ids=[str(uuid.uuid4())], key="k-invented")
        assert invented.status_code == 400
        assert invented.json()["detail"] == response.json()["detail"]

    def test_a_rejected_row_cannot_be_attached(self, media):
        rejected = _upload(media, _SVG).json()
        response = _create_post(media, media_ids=[rejected["public_id"]])
        assert response.status_code == 400, response.text

    def test_the_same_media_cannot_ride_two_posts(self, media):
        uploaded = _upload_ready(media)
        first = _create_post(media, media_ids=[uploaded["public_id"]], key="k-a")
        assert first.status_code == 201, first.text
        second = _create_post(media, media_ids=[uploaded["public_id"]], key="k-b")
        assert second.status_code == 400, second.text

    def test_a_duplicate_id_inside_one_list_is_refused(self, media):
        uploaded = _upload_ready(media)
        response = _create_post(
            media, media_ids=[uploaded["public_id"], uploaded["public_id"]]
        )
        assert response.status_code == 400, response.text

    def test_more_than_the_cap_is_a_422_before_any_database_read(self, media):
        ids = [str(uuid.uuid4()) for _ in range(5)]
        response = _create_post(media, media_ids=ids)
        assert response.status_code == 422, response.text

    def test_attached_media_becomes_visible_to_the_posts_audience(self, media):
        """A5 — a loose upload is owner-only, but once it hangs on a
        public post its bytes follow the post's own visibility."""
        uploaded = _upload_ready(media)
        assert (
            media.client.get(
                f"/community/media/{uploaded['public_id']}", headers=media.other
            ).status_code
            == 404
        )

        created = _create_post(media, media_ids=[uploaded["public_id"]])
        assert created.status_code == 201, created.text

        assert (
            media.client.get(
                f"/community/media/{uploaded['public_id']}", headers=media.other
            ).status_code
            == 200
        )

    def test_deleting_the_media_drops_it_from_the_posts_descriptor(self, media):
        """A post whose attachment was deleted renders as a post with no
        media, never as a broken tile."""
        uploaded = _upload_ready(media)
        created = _create_post(media, media_ids=[uploaded["public_id"]]).json()
        media.client.delete(
            f"/community/media/{uploaded['public_id']}", headers=media.owner
        )
        fetched = media.client.get(
            f"/community/posts/{created['public_id']}", headers=media.owner
        )
        assert fetched.status_code == 200, fetched.text
        assert fetched.json()["media"] == []
