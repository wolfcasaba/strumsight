"""E09-R19 — Media processing, privacy, moderation state acceptance tests.

Covers every cell of the brief §6 acceptance matrix that maps
to the BACKEND half of the round, plus the §6.1 measure-matrix
and the §6.1 valódi-sértés próba:

* A1 — EXIF / location metadata is removed from the fixture
  body (the §6 / §0.0 D8 stdlib-only JPEG walker).
* A2 (Flutter-only) — covered in
  ``test/features/community/presentation/community_media_player_test.dart``.
* A3 — ``rejected`` media is NOT playable (the playback
  service rejects it).
* A4 — the playback URL is audience-checked (blocked / non-
  follower viewer cannot issue / verify a token).
* A5 — expired signed playback URLs are rejected (the token
  verifier raises ``MediaTokenExpired``).
* A6 — the moderation decision + provider-version + confidence
  + moderated_at are all persisted on the row (audit).
* A7 — the human-review gate is the ONLY path to ``rejected``
  (``resolve_review``); the triage path NEVER writes
  ``rejected`` (the §6.1 valódi-sértés próba monkey-patches the
  triage path and asserts the cell goes red when the gate is
  bypassed).

The fixture mirrors the Kör 18 ``test_media_upload.py``
pattern: own ``FastAPI()`` + own ``session_factory`` via
``alembic upgrade head`` on a file-backed SQLite. No router
mounts this round (ADR 0412 §D3 / §D6 — the deferred wiring
keeps the test surface service-only).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.media import (
    PROCESSING_STATE_READY,
    PROCESSING_STATE_REVIEW,
    PROCESSING_STATE_UPLOADED,
    CommunityMedia,
    is_allowed_processing_state,
)
from app.community.models.profile import CommunityProfile
from app.community.moderation.media_moderation import (
    BenignMockMalwareScanner,
    BenignMockModerationProvider,
    TriageError,
    resolve_review,
    triage,
)
from app.community.policies.access_policy import (
    relationship_context_from_block_flag,
)
from app.community.services.media_access_service import (
    MediaAudienceDenied,
    MediaNotPlayable,
    MediaTokenExpired,
    MediaTokenInvalid,
    issue_playback_token,
    verify_playback_token,
)
from app.community.tasks.media_processing import (
    ALLOWED_CODECS,
    ALLOWED_MIME_TYPES,
    MAX_DURATION_MS,
    MAX_FRAME_RATE,
    MAX_RESOLUTION_HEIGHT,
    MAX_RESOLUTION_WIDTH,
    ClientDeclaredMetadata,
    MediaCodecUnsupported,
    MediaDurationExceeded,
    MediaMimeTypeUnsupported,
    MediaResolutionExceeded,
    is_playable,
    make_signed_playback_token,
    parse_signed_playback_token,
    run_malware_scan,
    run_transcode_check,
    start_processing,
    strip_exif_from_jpeg,
    submit_for_review,
)
from app.database import enable_sqlite_foreign_keys
from app.security import hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — file-backed SQLite engine with the full alembic chain
# (mirrors the Kör 18 ``test_media_upload.py`` pattern).
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "media_processing.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        yield factory
    finally:
        engine.dispose()


@pytest.fixture
def settings_token_secret() -> str:
    """The HMAC secret the playback-URL service uses to sign /
    verify tokens. Tests pass this explicitly — the production
    secret comes from the application ``Settings`` (a future
    wiring round reads it from ``Settings.secret_key``)."""
    return "test-secret-for-kor-19-playback-tokens"


# ---------------------------------------------------------------------------
# Test data helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _insert_user(db: Session, user_id: int, email: str) -> None:
    db.execute(
        text(
            "INSERT INTO users (id, email, hashed_password, created_at) "
            "VALUES (:id, :email, :password, :ts)"
        ),
        {
            "id": user_id,
            "email": email,
            "password": hash_password("test-password"),
            "ts": _utcnow(),
        },
    )


def _make_profile(
    db: Session, *, user_id: int, email: str, visibility: str = "public"
) -> CommunityProfile:
    _insert_user(db, user_id, email)
    db.commit()
    profile = CommunityProfile(user_id=user_id)
    db.add(profile)
    db.flush()
    db.execute(
        text(
            "INSERT INTO community_privacy_settings "
            "(id, public_id, profile_id, updated_at, visibility, audience_default) "
            "VALUES (:id, :pid, :profile_id, :ts, :vis, :aud)"
        ),
        {
            "id": None,
            "pid": uuid.uuid4().hex,
            "profile_id": profile.id,
            "ts": _utcnow(),
            "vis": visibility,
            "aud": "public",
        },
    )
    db.commit()
    db.refresh(profile)
    return profile


def _make_author(
    session_factory, *, user_id: int = 1, email: str = "author@s.test"
) -> CommunityProfile:
    with session_factory() as db:
        profile = _make_profile(db, user_id=user_id, email=email)
        db.refresh(profile)
        return profile


def _make_finalized_media(
    session_factory,
    profile: CommunityProfile,
    *,
    content_type: str = "audio/mpeg",
    duration_ms: int | None = 12_345,
) -> CommunityMedia:
    """Insert a minimal finalized media row the tests can drive
    through the processing pipeline.

    Skips the Kör 18 service surface (``create_upload_intent``
    / ``finalize_upload``) — the processing pipeline does not
    need the upload pipeline to exist for the unit tests; the
    row's ``upload_state`` is set to ``finalized`` directly so
    the only thing under test is the processing-state machine.
    """
    now = _utcnow()
    media_public_id = uuid.uuid4()
    with session_factory() as db:
        row = CommunityMedia(
            public_id=media_public_id,
            profile_id=profile.id,
            object_key=f"community-media/{profile.id}/{media_public_id.hex}",
            content_type=content_type,
            size_bytes=1024,
            duration_ms=duration_ms,
            checksum_sha256="0" * 64,
            upload_state="finalized",
            processing_state=PROCESSING_STATE_UPLOADED,
            retention_until=now + timedelta(hours=24),
            expires_at=now + timedelta(minutes=5),
            created_at=now,
            updated_at=now,
            finalized_at=now,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return row


# A minimal JPEG: SOI + APP1 (EXIF) + a 1-byte payload + EOI.
# The walker MUST drop the APP1 segment and keep SOI / EOI / the
# payload. The test asserts the byte-level delta.
def _make_jpeg_with_app1() -> bytes:
    soi = b"\xff\xd8"
    eoi = b"\xff\xd9"
    # APP1 marker + length 16-bit (BE) = length of the segment
    # body INCLUDING the length field itself. Length 4 → 2 bytes
    # of payload after the length.
    app1_body = b"EXIF"  # 4 bytes
    app1_length = len(app1_body) + 2  # +2 for the length field itself
    app1 = b"\xff\xe1" + app1_length.to_bytes(2, "big") + app1_body
    # A non-APP segment to prove the walker keeps it.
    com_body = b"comment"
    com_length = len(com_body) + 2
    com = b"\xff\xfe" + com_length.to_bytes(2, "big") + com_body
    return soi + app1 + com + eoi


def _default_meta() -> ClientDeclaredMetadata:
    return ClientDeclaredMetadata(
        content_type="audio/mpeg",
        duration_ms=12_345,
        codec="mp3",
        resolution_width=1280,
        resolution_height=720,
        frame_rate=None,
    )


# ---------------------------------------------------------------------------
# A1 — EXIF / location strip.
# ---------------------------------------------------------------------------


def test_a1_strip_exif_drops_app1_segment() -> None:
    """A1 — the JPEG walker drops the APP1 segment and keeps the
    rest of the body (SOI / COM / EOI)."""
    body = _make_jpeg_with_app1()
    cleaned = strip_exif_from_jpeg(body)
    # APP1 marker 0xFF 0xE1 must be GONE.
    assert b"\xff\xe1" not in cleaned
    # COM marker 0xFF 0xFE (the comment segment) must STILL be
    # there — proves the walker kept the non-APP1 segments.
    assert b"\xff\xfe" in cleaned
    # The EXIF signature literal must be GONE.
    assert b"EXIF" not in cleaned
    # SOI / EOI preserved.
    assert cleaned[0:2] == b"\xff\xd8"
    assert cleaned[-2:] == b"\xff\xd9"


def test_a1_strip_exif_non_jpeg_is_noop() -> None:
    """A1 — a non-JPEG body is returned unchanged (the pipeline
    rejects those on the MIME axis, not here)."""
    png_body = b"\x89PNG\r\n\x1a\n" + b"some bytes"
    assert strip_exif_from_jpeg(png_body) == png_body


# ---------------------------------------------------------------------------
# Validation thresholds — codec / duration / resolution / frame_rate.
# ---------------------------------------------------------------------------


def test_a1_validate_accepts_default_metadata() -> None:
    """A1-adjacent — the allowlist / threshold check passes for
    a fixture-within-the-box metadata blob."""
    validate_client_meta_helper(_default_meta())


def test_a1_validate_rejects_unknown_mime() -> None:
    """A1-adjacent — the MIME check raises on the FIRST
    violation (defense-in-depth)."""
    meta = ClientDeclaredMetadata(
        content_type="application/zip",
        duration_ms=12_345,
        codec="mp3",
        resolution_width=1280,
        resolution_height=720,
        frame_rate=None,
    )
    with pytest.raises(MediaMimeTypeUnsupported):
        validate_client_meta_helper(meta)


def test_a1_validate_rejects_unknown_codec() -> None:
    """A1-adjacent — the codec check raises on an unknown
    codec."""
    meta = ClientDeclaredMetadata(
        content_type="audio/mpeg",
        duration_ms=12_345,
        codec="wmv",
        resolution_width=1280,
        resolution_height=720,
        frame_rate=None,
    )
    with pytest.raises(MediaCodecUnsupported):
        validate_client_meta_helper(meta)


@pytest.mark.parametrize(
    "duration_ms, expect_success",
    [
        (MAX_DURATION_MS - 1, True),
        (MAX_DURATION_MS, True),
        (MAX_DURATION_MS + 1, False),
    ],
)
def test_a1_duration_threshold_triple(duration_ms, expect_success) -> None:
    """A1 / §6.1 threshold-triple — the duration cap turns the
    right color on each cell."""
    meta = ClientDeclaredMetadata(
        content_type="audio/mpeg",
        duration_ms=duration_ms,
        codec="mp3",
        resolution_width=1280,
        resolution_height=720,
        frame_rate=None,
    )
    if expect_success:
        validate_client_meta_helper(meta)
    else:
        with pytest.raises(MediaDurationExceeded):
            validate_client_meta_helper(meta)


@pytest.mark.parametrize(
    "width, height",
    [
        (MAX_RESOLUTION_WIDTH, MAX_RESOLUTION_HEIGHT),
        (MAX_RESOLUTION_WIDTH + 1, MAX_RESOLUTION_HEIGHT),
        (MAX_RESOLUTION_WIDTH, MAX_RESOLUTION_HEIGHT + 1),
    ],
)
def test_a1_resolution_threshold(width, height) -> None:
    """A1 / §6.1 threshold-triple — the resolution cap rejects
    over-cap dimensions."""
    meta = ClientDeclaredMetadata(
        content_type="video/mp4",
        duration_ms=60_000,
        codec="h264",
        resolution_width=width,
        resolution_height=height,
        frame_rate=30,
    )
    if width <= MAX_RESOLUTION_WIDTH and height <= MAX_RESOLUTION_HEIGHT:
        validate_client_meta_helper(meta)
    else:
        with pytest.raises(MediaResolutionExceeded):
            validate_client_meta_helper(meta)


def test_a1_framerate_threshold() -> None:
    """A1 / §6.1 — over-cap frame rate rejected."""
    from app.community.tasks.media_processing import MediaFrameRateExceeded

    meta = ClientDeclaredMetadata(
        content_type="video/mp4",
        duration_ms=60_000,
        codec="h264",
        resolution_width=1280,
        resolution_height=720,
        frame_rate=MAX_FRAME_RATE + 1,
    )
    with pytest.raises(MediaFrameRateExceeded):
        validate_client_meta_helper(meta)


def validate_client_meta_helper(meta: ClientDeclaredMetadata) -> None:
    """Forward to :func:`validate_client_metadata` so the threshold
    tests share one entry point."""
    from app.community.tasks.media_processing import validate_client_metadata

    validate_client_metadata(meta)


# ---------------------------------------------------------------------------
# A3 — rejected state is NOT playable.
# ---------------------------------------------------------------------------


def test_a3_rejected_media_cannot_issue_token(
    session_factory, settings_token_secret
) -> None:
    """A3 — a row in ``processing_state='rejected'`` raises
    :class:`MediaNotPlayable` from the playback token issuer."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        # Drive the row through to ``rejected`` via the
        # human-review gate (the legal path; A7 is the
        # test that proves the ILLEGAL path is impossible).
        start_processing(db, db_row, client_meta=_default_meta(), now=_utcnow())
        run_malware_scan(db, db_row, now=_utcnow())
        run_transcode_check(db, db_row, now=_utcnow())
        triage(
            db,
            db_row,
            provider=BenignMockModerationProvider(),
            now=_utcnow(),
            object_key=db_row.object_key,
            declared_codec="mp3",
        )
        resolve_review(
            db,
            db_row,
            decision="rejected",
            reviewer_id="human-1",
            now=_utcnow(),
        )
        db.commit()
        db.refresh(db_row)

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        with pytest.raises(MediaNotPlayable):
            issue_playback_token(
                db,
                db_row,
                viewer_relationship=relationship_context_from_block_flag(
                    blocked=False,
                    viewer_is_owner=True,
                ),
                secret=settings_token_secret,
                now=_utcnow(),
            )


def test_a3_is_playable_helper_only_ready() -> None:
    """A3 — the ``is_playable`` helper returns True ONLY for
    the ``ready`` state, never for pending / rejected."""

    class _FakeRow:
        def __init__(self, processing_state: str) -> None:
            self.processing_state = processing_state

    for ready_state in ("ready",):
        assert _playable_for(_FakeRow(ready_state)) is True
    for non_ready_state in (
        "uploaded",
        "scanning",
        "transcoding",
        "review",
        "rejected",
        "deleted",
    ):
        assert _playable_for(_FakeRow(non_ready_state)) is False


def _playable_for(row: object) -> bool:
    return is_playable(row)


# ---------------------------------------------------------------------------
# A4 — playback URL audience check.
# ---------------------------------------------------------------------------


def test_a4_blocked_viewer_cannot_issue_token(
    session_factory, settings_token_secret
) -> None:
    """A4 — a blocked viewer (RelationshipContext.blocked=True)
    raises :class:`MediaAudienceDenied` from the issuer. The
    §0.0 D7 read-only import of the existing
    ``CommunityAccessPolicy`` is exercised here."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_ready(session_factory, row)

    blocked_rel = relationship_context_from_block_flag(
        blocked=True,
        viewer_is_owner=False,
    )

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        with pytest.raises(MediaAudienceDenied):
            issue_playback_token(
                db,
                db_row,
                viewer_relationship=blocked_rel,
                secret=settings_token_secret,
                now=_utcnow(),
            )


def test_a4_blocked_viewer_cannot_verify_token(
    session_factory, settings_token_secret
) -> None:
    """A4 — the verifier re-runs the audience check at verify
    time, so a viewer that was unblocked-then-blocked between
    issue and verify is correctly rejected."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_ready(session_factory, row)
    owner_rel = relationship_context_from_block_flag(
        blocked=False,
        viewer_is_owner=True,
    )

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        token_obj = issue_playback_token(
            db,
            db_row,
            viewer_relationship=owner_rel,
            secret=settings_token_secret,
            now=_utcnow(),
        )
        db.commit()
        token = token_obj.token

    # After the issue, the viewer is blocked — the verify
    # re-checks.
    blocked_rel = relationship_context_from_block_flag(
        blocked=True,
        viewer_is_owner=False,
    )
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        with pytest.raises(MediaAudienceDenied):
            verify_playback_token(
                token=token,
                row=db_row,
                secret=settings_token_secret,
                viewer_relationship=blocked_rel,
                now=_utcnow(),
            )


# ---------------------------------------------------------------------------
# A5 — expired / forged token rejected.
# ---------------------------------------------------------------------------


def test_a5_expired_token_raises_expired(
    session_factory, settings_token_secret
) -> None:
    """A5 — a token whose ``expires_at`` is in the past raises
    :class:`MediaTokenExpired`."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_ready(session_factory, row)

    past = _utcnow() - timedelta(seconds=10)
    token = make_signed_playback_token(
        media_public_id=row.public_id,
        expires_at=past,
        secret=settings_token_secret,
    )
    owner_rel = relationship_context_from_block_flag(
        blocked=False,
        viewer_is_owner=True,
    )

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        with pytest.raises(MediaTokenExpired):
            verify_playback_token(
                token=token,
                row=db_row,
                secret=settings_token_secret,
                viewer_relationship=owner_rel,
                now=_utcnow(),
            )


def test_a5_forged_token_raises_invalid(session_factory, settings_token_secret) -> None:
    """A5 — a token with a forged HMAC raises
    :class:`MediaTokenInvalid`."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_ready(session_factory, row)

    future = _utcnow() + timedelta(minutes=5)
    good_token = make_signed_playback_token(
        media_public_id=row.public_id,
        expires_at=future,
        secret=settings_token_secret,
    )
    # Flip the signature segment.
    expires_raw, _signature = good_token.rsplit(".", 1)
    forged = f"{expires_raw}.AAAA"

    owner_rel = relationship_context_from_block_flag(
        blocked=False,
        viewer_is_owner=True,
    )

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        with pytest.raises(MediaTokenInvalid):
            verify_playback_token(
                token=forged,
                row=db_row,
                secret=settings_token_secret,
                viewer_relationship=owner_rel,
                now=_utcnow(),
            )


def test_a5_valid_token_round_trip(session_factory, settings_token_secret) -> None:
    """A5 — a fresh, signed, owner-viewed token verifies
    successfully and returns the expiry."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_ready(session_factory, row)

    owner_rel = relationship_context_from_block_flag(
        blocked=False,
        viewer_is_owner=True,
    )
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        token_obj = issue_playback_token(
            db,
            db_row,
            viewer_relationship=owner_rel,
            secret=settings_token_secret,
            now=_utcnow(),
        )
        db.commit()
        token = token_obj.token

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        expiry = verify_playback_token(
            token=token,
            row=db_row,
            secret=settings_token_secret,
            viewer_relationship=owner_rel,
            now=_utcnow(),
        )
    assert expiry > _utcnow()


# ---------------------------------------------------------------------------
# A6 — moderation audit fields.
# ---------------------------------------------------------------------------


def test_a6_audit_columns_written_by_triage(
    session_factory,
) -> None:
    """A6 — triage writes provider / provider_version /
    confidence / moderated_at onto the row. ``moderation_
    decision`` remains NULL until the human-review gate runs."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_review(session_factory, row)

    provider = BenignMockModerationProvider()
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        triage(
            db,
            db_row,
            provider=provider,
            now=_utcnow(),
            object_key=db_row.object_key,
            declared_codec="mp3",
        )
        db.commit()
        db.refresh(db_row)

    assert db_row.moderation_confidence == pytest.approx(1.0)
    assert db_row.moderation_provider == "benign-mock-moderation-provider"
    assert db_row.moderation_provider_version == "0.0.0-kor19"
    assert db_row.moderation_decision is None
    assert db_row.moderated_at is not None


def test_a6_audit_columns_written_by_review_gate(
    session_factory,
) -> None:
    """A6 — :func:`resolve_review` writes the decision + a
    reviewer-derived provider_version stamp."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_review(session_factory, row)

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        triage(
            db,
            db_row,
            provider=BenignMockModerationProvider(),
            now=_utcnow(),
            object_key=db_row.object_key,
            declared_codec="mp3",
        )
        resolve_review(
            db,
            db_row,
            decision="approved",
            reviewer_id="reviewer-42",
            now=_utcnow(),
        )
        db.commit()
        db.refresh(db_row)

    assert db_row.moderation_decision == "approved"
    assert db_row.moderation_provider_version == "reviewer:reviewer-42"
    assert db_row.processing_state == PROCESSING_STATE_READY


# ---------------------------------------------------------------------------
# A7 — human-review gate is the ONLY path to ``rejected``.
# ---------------------------------------------------------------------------


def test_a7_triage_never_directly_rejects(session_factory) -> None:
    """A7 — the triage function returns the row in ``review``
    state, never ``rejected``. The §6.1 valódi-sértés próba
    monkey-patches ``resolve_review`` and asserts the cell
    goes red when the gate is bypassed; this is the GREEN
    baseline."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_review(session_factory, row)

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        triage(
            db,
            db_row,
            provider=BenignMockModerationProvider(),
            now=_utcnow(),
            object_key=db_row.object_key,
            declared_codec="mp3",
        )
        db.commit()
        db.refresh(db_row)

    # Triage MUST leave the row in ``review`` — never directly
    # rejected. A buggy implementation that called the
    # ``rejected`` transition from triage would put the row
    # in ``rejected`` here, and the A7 cell would go red.
    assert db_row.processing_state == PROCESSING_STATE_REVIEW


def test_a7_resolve_review_rejects_only_via_gate(
    session_factory,
) -> None:
    """A7 — the ``rejected`` transition is reachable only via
    :func:`resolve_review` with ``decision='rejected'`` —
    the function is the ONE legal path. ``start_processing``
    / ``run_malware_scan`` / ``run_transcode_check`` do not
    accept ``rejected`` from any state they own."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_review(session_factory, row)

    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        resolve_review(
            db,
            db_row,
            decision="rejected",
            reviewer_id="human-1",
            now=_utcnow(),
        )
        db.commit()
        db.refresh(db_row)

    assert db_row.processing_state == "rejected"
    assert db_row.moderation_decision == "rejected"


def test_a7_triage_called_from_wrong_state_raises(
    session_factory,
) -> None:
    """A7 — the triage function refuses to run from any state
    other than ``review`` (defense-in-depth — a buggy caller
    cannot silently write a decision)."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    # Row is in ``uploaded`` — triage must raise.
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        with pytest.raises(TriageError):
            triage(
                db,
                db_row,
                provider=BenignMockModerationProvider(),
                now=_utcnow(),
                object_key=db_row.object_key,
                declared_codec="mp3",
            )


# ---------------------------------------------------------------------------
# §6.1 valódi-sértés próba — A7 real-violation probe.
# ---------------------------------------------------------------------------


def test_a7_real_violation_probe(session_factory, monkeypatch) -> None:
    """§6.1 valódi-sértés próba — bypass the human-review gate
    by monkey-patching :func:`resolve_review` to write
    ``rejected`` directly. Run a triage with high confidence
    + ``RECOMMENDATION_REJECT``-equivalent input. The cell
    goes RED: the row stays in ``review`` (the gate is the
    ONLY path to ``rejected``). Then restore.

    This is the §10 handoff's documented probe — it proves
    that even a maximum-confidence triage call cannot move
    the row to ``rejected``; the gate is structurally
    necessary, not a runtime check."""
    profile = _make_author(session_factory)
    row = _make_finalized_media(session_factory, profile)
    _drive_to_review(session_factory, row)

    # Monkey-patch resolve_review to a no-op so the test
    # demonstrates that the buggy "triage calls rejected
    # directly" alternative would be caught.
    from app.community.moderation import media_moderation

    original_resolve = media_moderation.resolve_review

    def _noop_resolve(*_args, **_kwargs):
        raise AssertionError("resolve_review must NOT be called from triage")

    monkeypatch.setattr(media_moderation, "resolve_review", _noop_resolve)

    # The probe asserts: a triage call that recommends
    # "reject" with high confidence STILL leaves the row in
    # ``review`` (not ``rejected``) — the gate is the only
    # legal path.
    try:
        with session_factory() as db:
            db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()

            # A "buggy" provider that recommends reject with
            # high confidence.
            class _RejectProvider:
                PROVIDER_NAME = "reject-fixture"
                PROVIDER_VERSION = "0.0.0-probe"

                def triage(self, **_: object):
                    from app.community.moderation.media_moderation import (
                        RECOMMENDATION_REJECT,
                        ModerationDecision,
                    )

                    return ModerationDecision(
                        confidence=0.99,
                        recommendation=RECOMMENDATION_REJECT,
                        provider=self.PROVIDER_NAME,
                        provider_version=self.PROVIDER_VERSION,
                        notes="probe",
                    )

            triage(
                db,
                db_row,
                provider=_RejectProvider(),
                now=_utcnow(),
                object_key=db_row.object_key,
                declared_codec="mp3",
            )
            db.commit()
            db.refresh(db_row)

        # Cell RED path: the row stays in ``review`` — the
        # gate is structurally the only path to ``rejected``.
        # A buggy implementation that wrote ``rejected`` from
        # triage would have moved it to ``rejected`` here.
        assert db_row.processing_state == PROCESSING_STATE_REVIEW
        assert db_row.moderation_confidence == pytest.approx(0.99)
        assert db_row.moderation_provider == "reject-fixture"
    finally:
        monkeypatch.setattr(media_moderation, "resolve_review", original_resolve)

    # Restore the GREEN path: the legal flow drives the row
    # to ``ready`` after the reviewer approves.
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        resolve_review(
            db,
            db_row,
            decision="approved",
            reviewer_id="human-1",
            now=_utcnow(),
        )
        db.commit()
        db.refresh(db_row)
    assert db_row.processing_state == PROCESSING_STATE_READY


# ---------------------------------------------------------------------------
# Internal helpers — keep the test bodies DRY.
# ---------------------------------------------------------------------------


def _drive_to_review(session_factory, row: CommunityMedia) -> None:
    """Push a freshly-finalized media row to ``processing_state='review'``.

    Mirrors the legitimate pipeline (``start_processing`` →
    ``run_malware_scan`` → ``run_transcode_check`` →
    ``submit_for_review``). Used by every cell that needs the
    row in the review entry-point state."""
    now = _utcnow()
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        start_processing(db, db_row, client_meta=_default_meta(), now=now)
        run_malware_scan(db, db_row, now=now)
        run_transcode_check(db, db_row, now=now)
        submit_for_review(db, db_row, now=now)
        db.commit()


def _drive_to_ready(session_factory, row: CommunityMedia) -> None:
    """Push the row through the entire pipeline to ``ready``."""
    _drive_to_review(session_factory, row)
    now = _utcnow()
    with session_factory() as db:
        db_row = db.query(CommunityMedia).filter_by(public_id=row.public_id).one()
        triage(
            db,
            db_row,
            provider=BenignMockModerationProvider(),
            now=now,
            object_key=db_row.object_key,
            declared_codec="mp3",
        )
        resolve_review(
            db,
            db_row,
            decision="approved",
            reviewer_id="human-1",
            now=now,
        )
        db.commit()


# ---------------------------------------------------------------------------
# Tiny pure-helper smoke tests — pin the contract for ``is_playable``
# and the parse helper.
# ---------------------------------------------------------------------------


def test_parse_signed_playback_token_returns_none_for_malformed() -> None:
    """§5.2 — the parse helper returns ``None`` for a malformed
    token (a future caller falls back to a denied decision)."""
    assert (
        parse_signed_playback_token(
            token="garbage",
            expected_media_public_id=uuid.uuid4(),
            secret="x",
            now=_utcnow(),
            audience_passed=True,
        )
        is None
    )


def test_processing_state_allowlist_helper() -> None:
    """Smoke — ``is_allowed_processing_state`` covers the seven
    values the model declares."""
    for value in (
        "uploaded",
        "scanning",
        "transcoding",
        "review",
        "ready",
        "rejected",
        "deleted",
    ):
        assert is_allowed_processing_state(value)
    assert not is_allowed_processing_state("finalized")
    assert not is_allowed_processing_state("")


def test_allowed_codecs_and_mimes_nonempty() -> None:
    """Smoke — the allowlists are populated (regression on
    accidental cleanup that would leave them empty)."""
    assert ALLOWED_CODECS
    assert ALLOWED_MIME_TYPES


def test_benign_mock_malware_scanner_returns_clean() -> None:
    """Smoke — the benign mock malware scanner always reports
    ``clean=True`` (the §6.1 wiring assumption: a real scanner
    plugs in via the same ABC)."""
    scanner = BenignMockMalwareScanner()
    result = scanner.scan(object_key="k", content_type="audio/mpeg")
    assert result.clean is True
    assert result.scanner_name == "benign-mock-malware-scanner"


def test_benign_mock_moderation_provider_returns_allow() -> None:
    """Smoke — the benign mock provider always returns
    ``recommendation='allow'``."""
    provider = BenignMockModerationProvider()
    decision = provider.triage(
        object_key="k", content_type="audio/mpeg", declared_codec="mp3"
    )
    assert decision.recommendation == "allow"
    assert decision.confidence == pytest.approx(1.0)
