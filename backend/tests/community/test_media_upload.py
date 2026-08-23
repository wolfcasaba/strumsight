"""E09-R18 — Media upload contract and object-store acceptance tests.

Covers every cell of the brief §6 acceptance matrix that maps to
the BACKEND half of the round, plus the §6.1 measure-matrix
threshold-triple and the §6.1 valódi-sértés próba:

* A1 — feature-flag OFF → every public entry point raises
  :class:`MediaUploadDisabled`.
* A2 — signed-URL expired → ``finalize_upload`` rejects with
  :class:`MediaUploadExpired`.
* A3 — bucket-side ``Content-Type`` outside the allowlist OR
  mismatching the intent-time declaration → rejected with
  :class:`MediaContentTypeMismatch`. The check uses the
  bucket's reported type, NOT a file-extension heuristic.
* A4 — bucket-side size exceeds ``MAX_UPLOAD_BYTES`` → rejected
  with :class:`MediaSizeExceeded`. Threshold-triple
  (``MAX-1`` accepted, ``MAX`` accepted, ``MAX+1`` rejected).
* A5 — bucket-side SHA-256 mismatch → rejected with
  :class:`MediaChecksumMismatch`. The valódi-sértés próba
  removes the comparison and asserts the cell goes red.
* A6 — foreign ``profile_public_id`` cannot finalize / cancel
  someone else's ``media_public_id`` — uniform 404.
* A7 — cancel deletes the bucket-side object AND transitions
  the row to ``cancelled``; orphan-cleanup sweeps rows past
  ``retention_until``. The Flutter half (cancel aborts the
  in-flight PUT) lives in
  ``test/features/community/data/api/community_media_uploader_test.dart``.

The §6.1 valódi-sértés próba is exercised explicitly: a
monkeypatched ``_validate_checksum`` always passes, the test
mutates the row's ``checksum_sha256`` to a non-matching value,
runs ``finalize_upload``, and asserts the cell goes red (i.e.
the row transitions to ``finalized`` without the mismatch being
caught). The probe then restores the original guard.

The fixtures mirror the existing ``test_post_service.py`` /
``test_reaction_service.py`` / ``test_bookmark_service.py``
pattern — own ``FastAPI()`` + own ``session_factory`` via
``alembic upgrade head`` on a file-backed SQLite, but THIS
round does NOT mount any router: the service-layer is the test
surface (ADR 0410 §D3, §0.0 D1, brief §6.1 measure-matrix).
The production ``build_community_router`` factory is not
touched (the §3 tilos-zóna discipline).
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
    UPLOAD_STATE_CANCELLED,
    UPLOAD_STATE_FAILED,
    UPLOAD_STATE_FINALIZED,
    UPLOAD_STATE_PENDING,
    CommunityMedia,
)
from app.community.models.profile import CommunityProfile
from app.community.services import media_upload_service as svc
from app.community.services.media_upload_service import (
    MAX_UPLOAD_BYTES,
    MEDIA_CONTENT_TYPE_ALLOWLIST,
    SIGNED_URL_EXPIRES_IN,
    MediaChecksumMismatch,
    MediaContentTypeMismatch,
    MediaNotFound,
    MediaQuotaExceeded,
    MediaSizeExceeded,
    MediaUploadDisabled,
    MediaUploadExpired,
    cancel_upload,
    cleanup_orphan_uploads,
    create_upload_intent,
    finalize_upload,
)
from app.community.storage.object_store import InMemoryObjectStore
from app.config import Settings
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
# Fixtures — file-backed SQLite engine with the full alembic chain.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "media.db"
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
def settings_enabled() -> Settings:
    return Settings(
        _env_file=None,
        community_enabled=True,
        community_media_enabled=True,
    )


@pytest.fixture
def settings_disabled() -> Settings:
    return Settings(
        _env_file=None,
        community_enabled=True,
        community_media_enabled=False,
    )


# ---------------------------------------------------------------------------
# Test data helpers — users, profiles.
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
    db: Session,
    *,
    user_id: int,
    email: str,
    visibility: str = "public",
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


def _make_two_authors(
    session_factory,
) -> tuple[CommunityProfile, CommunityProfile]:
    return (
        _make_author(session_factory, user_id=1, email="a@s.test"),
        _make_author(session_factory, user_id=2, email="b@s.test"),
    )


# ---------------------------------------------------------------------------
# Intent + finalize helpers — DRY the A1–A7 cells.
# ---------------------------------------------------------------------------


def _seed_object_for(
    store: InMemoryObjectStore,
    *,
    object_key: str,
    body: bytes,
    content_type: str,
) -> str:
    """Stage an object the finalize path will see via head_object.

    Returns the SHA-256 hex digest of ``body`` so the intent
    declares the same value — the A5 cell mutates this when it
    wants to drive a checksum mismatch."""
    import hashlib

    sha = hashlib.sha256(body).hexdigest()
    store.stage_object(
        object_key,
        size=len(body),
        content_type=content_type,
        sha256_hex=sha,
        body=body,
    )
    return sha


def _create_intent(
    session_factory,
    settings,
    store: InMemoryObjectStore,
    profile: CommunityProfile,
    *,
    content_type: str = "audio/mpeg",
    size: int = 1024,
    duration_ms: int | None = 12_345,
    checksum_sha256: str | None = None,
    signed_url_expires_in: timedelta | None = None,
    now: datetime | None = None,
):
    """Create an intent via the public service surface; commit
    so subsequent sessions see the row."""
    when = now or _utcnow()
    with session_factory() as db:
        intent = create_upload_intent(
            db,
            profile_public_id=profile.public_id,
            content_type=content_type,
            size=size,
            duration_ms=duration_ms,
            checksum_sha256=checksum_sha256,
            settings=settings,
            object_store=store,
            signed_url_expires_in=(
                signed_url_expires_in
                if signed_url_expires_in is not None
                else SIGNED_URL_EXPIRES_IN
            ),
            now=when,
        )
        db.commit()
        return intent, db


def _new_store() -> InMemoryObjectStore:
    return InMemoryObjectStore()


# ---------------------------------------------------------------------------
# §6 Acceptance cells — A1 through A7.
# ---------------------------------------------------------------------------


def test_a1_create_intent_raises_when_flag_off(
    session_factory, settings_disabled
) -> None:
    """A1 — ``community_media_enabled=False`` → every public
    entry point raises :class:`MediaUploadDisabled`."""
    profile = _make_author(session_factory)
    store = _new_store()
    with session_factory() as db:
        with pytest.raises(MediaUploadDisabled):
            create_upload_intent(
                db,
                profile_public_id=profile.public_id,
                content_type="audio/mpeg",
                size=1024,
                duration_ms=None,
                checksum_sha256=None,
                settings=settings_disabled,
                object_store=store,
                now=_utcnow(),
            )


def test_a1_finalize_raises_when_flag_off(
    session_factory, settings_enabled, settings_disabled
) -> None:
    """A1 — finalize is also flag-gated."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory, settings_enabled, store, profile, size=512
    )
    with session_factory() as db:
        with pytest.raises(MediaUploadDisabled):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_disabled,
                object_store=store,
                now=_utcnow(),
            )


def test_a1_cancel_raises_when_flag_off(
    session_factory, settings_enabled, settings_disabled
) -> None:
    """A1 — cancel is also flag-gated."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory, settings_enabled, store, profile, size=512
    )
    with session_factory() as db:
        with pytest.raises(MediaUploadDisabled):
            cancel_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_disabled,
                object_store=store,
                now=_utcnow(),
            )


def test_a1_orphan_cleanup_is_noop_when_flag_off(
    session_factory, settings_enabled, settings_disabled
) -> None:
    """A1 — the orphan-cleanup function is also flag-gated
    (returns 0 with no side-effects)."""
    profile = _make_author(session_factory)
    store = _new_store()
    # Stage an intent that WOULD be swept if the flag were on.
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        size=512,
    )
    far_future = _utcnow() + timedelta(days=2)
    with session_factory() as db:
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        row.retention_until = _utcnow() - timedelta(seconds=1)
        db.commit()

    with session_factory() as db:
        swept = cleanup_orphan_uploads(
            db,
            settings=settings_disabled,
            object_store=store,
            now=far_future,
        )
        db.commit()
    assert swept == 0
    assert store.deleted == []


def test_a2_finalize_rejects_expired_signed_url(
    session_factory, settings_enabled
) -> None:
    """A2 — a finalize attempt AFTER the signed URL expired is
    rejected with :class:`MediaUploadExpired`.

    BLOCKER B1 / F1 fix: measures the actual TTL — 60-second
    signed URL, finalize attempt at +90 s (30 s past the
    real expiry). The previous test measured at +5 minutes,
    which coincidentally equalled the hardcoded
    ``SIGNED_URL_EXPIRES_IN`` module constant and turned the
    cell green even when the implementation ignored the
    caller's shorter window.
    """
    profile = _make_author(session_factory)
    store = _new_store()
    # 60-second signed URL — finalize attempt 30 seconds past
    # the real expiry. The row's ``expires_at`` (stamped from
    # ``SignedUpload.expires_at``) is the source of truth for
    # the comparison; the module-level 5-minute default is
    # irrelevant.
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        size=512,
        signed_url_expires_in=timedelta(seconds=60),
    )
    # Stage the object so the failure is the expiry check, not
    # a missing object.
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )

    later = _utcnow() + timedelta(seconds=90)
    with session_factory() as db:
        with pytest.raises(MediaUploadExpired):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=later,
            )


def test_a2_finalize_accepts_within_signed_url_ttl(
    session_factory, settings_enabled
) -> None:
    """A2-adjacent — a finalize attempt within the actual TTL
    is accepted (proves the comparison honours the stored
    ``expires_at``, not the module-level 5-minute default)."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        size=512,
        signed_url_expires_in=timedelta(seconds=60),
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )

    # 30 s in — comfortably inside the 60 s window. A buggy
    # implementation that re-derived the expiry from the
    # 5-minute default would also accept this, so this test
    # complements (does not replace) the +90 s rejection test.
    within = _utcnow() + timedelta(seconds=30)
    with session_factory() as db:
        row = finalize_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=within,
        )
        db.commit()
        assert row.upload_state == UPLOAD_STATE_FINALIZED


def test_a3_finalize_rejects_bucket_mime_mismatch(
    session_factory, settings_enabled
) -> None:
    """A3 — a finalize whose bucket-side ``Content-Type``
    differs from the intent declaration is rejected. The check
    uses the bucket's reported type (NOT a file extension)."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        size=512,
        content_type="audio/mpeg",
    )
    # Stage the object with a DIFFERENT content-type — the
    # bucket-side value drives the comparison, NOT the
    # intent-time declaration.
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="video/mp4",
    )

    with session_factory() as db:
        with pytest.raises(MediaContentTypeMismatch):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )
        db.commit()
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        # The failed transition is observable in the DB —
        # the orphan-cleanup function will sweep the row on
        # the next run past retention_until.
        assert row.upload_state == UPLOAD_STATE_FAILED


def test_a3_finalize_rejects_non_allowlisted_bucket_mime(
    session_factory, settings_enabled
) -> None:
    """A3-adjacent — a bucket-side MIME outside the §3
    allowlist is rejected EVEN IF the intent declaration
    matched. The §5.3 explicit ban on extension-based MIME
    validation lives here."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        size=512,
        content_type="audio/mpeg",
    )
    # Stage the object with a non-allowlisted MIME — ``application/zip``
    # is not in MEDIA_CONTENT_TYPE_ALLOWLIST.
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"PK\x03\x04not-a-real-mp3",
        content_type="application/zip",
    )

    with session_factory() as db:
        with pytest.raises(MediaContentTypeMismatch):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


def test_a3_intent_rejects_non_allowlisted_mime_at_seam(
    session_factory, settings_enabled
) -> None:
    """A3 — the intent-time seam rejects a non-allowlisted
    MIME without round-tripping to the bucket (defense-in-
    depth; the bucket-side check is the second layer)."""
    profile = _make_author(session_factory)
    store = _new_store()
    with session_factory() as db:
        with pytest.raises(MediaContentTypeMismatch):
            create_upload_intent(
                db,
                profile_public_id=profile.public_id,
                content_type="application/zip",
                size=1024,
                duration_ms=None,
                checksum_sha256=None,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


@pytest.mark.parametrize(
    "size, expect_success",
    [
        (MAX_UPLOAD_BYTES - 1, True),  # below — accepted
        (MAX_UPLOAD_BYTES, True),  # boundary — accepted (inclusive)
        (MAX_UPLOAD_BYTES + 1, False),  # above — rejected
    ],
)
def test_a4_size_threshold_triple(
    session_factory, settings_enabled, size, expect_success
) -> None:
    """A4 / §6.1 threshold-triple — the three cells must turn
    the right color independently."""
    profile = _make_author(session_factory)
    store = _new_store()
    if expect_success:
        # The intent itself only rejects ``size > MAX_UPLOAD_BYTES``
        # at the seam; the boundary is inclusive. The finalize
        # also re-checks via head_object, so we stage a same-size
        # object.
        intent, _ = _create_intent(
            session_factory,
            settings_enabled,
            store,
            profile,
            content_type="audio/mpeg",
            size=size,
            checksum_sha256="a" * 64,
        )
        body = b"\x00" * size
        _seed_object_for(
            store,
            object_key=intent.object_key,
            body=body,
            content_type="audio/mpeg",
        )
        # Override the row's checksum_sha256 to match the body
        # the bucket has, so the finalize passes the A5 cell.
        import hashlib

        real_sha = hashlib.sha256(body).hexdigest()
        with session_factory() as db:
            row = (
                db.query(CommunityMedia)
                .filter_by(public_id=intent.media_public_id)
                .one()
            )
            row.checksum_sha256 = real_sha
            db.commit()

        with session_factory() as db:
            row = finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )
            db.commit()
            db.refresh(row)
            assert row.upload_state == UPLOAD_STATE_FINALIZED
    else:
        with session_factory() as db:
            with pytest.raises(MediaSizeExceeded):
                create_upload_intent(
                    db,
                    profile_public_id=profile.public_id,
                    content_type="audio/mpeg",
                    size=size,
                    duration_ms=None,
                    checksum_sha256=None,
                    settings=settings_enabled,
                    object_store=store,
                    now=_utcnow(),
                )


def test_a4_finalize_rejects_oversize_bucket_object(
    session_factory, settings_enabled
) -> None:
    """A4 — defense-in-depth: even when the intent seam was
    circumvented (the row's intent-time ``size_bytes`` was
    under the cap), the finalize re-measures and rejects."""
    profile = _make_author(session_factory)
    store = _new_store()
    # Intent at half the cap; bucket stages an over-cap object
    # (one byte past the boundary — the threshold-triple's
    # "rajta fölött" cell).
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        size=MAX_UPLOAD_BYTES // 2,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"\x00" * (MAX_UPLOAD_BYTES + 1),
        content_type="audio/mpeg",
    )

    with session_factory() as db:
        with pytest.raises(MediaSizeExceeded):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )
        db.commit()
    with session_factory() as db:
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        assert row.upload_state == UPLOAD_STATE_FAILED


def test_a5_finalize_rejects_checksum_mismatch(
    session_factory, settings_enabled
) -> None:
    """A5 — a bucket-side SHA-256 mismatch is rejected with
    :class:`MediaChecksumMismatch`."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
        checksum_sha256="0" * 64,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"actual bytes",
        content_type="audio/mpeg",
    )

    with session_factory() as db:
        with pytest.raises(MediaChecksumMismatch):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )
        db.commit()
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        assert row.upload_state == UPLOAD_STATE_FAILED


def test_a6_foreign_user_cannot_finalize(session_factory, settings_enabled) -> None:
    """A6 — a foreign ``profile_public_id`` cannot finalize
    someone else's ``media_public_id`` (uniform 404, the §5.3
    IDOR discipline)."""
    owner, foreigner = _make_two_authors(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        owner,
        content_type="audio/mpeg",
        size=512,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )

    with session_factory() as db:
        with pytest.raises(MediaNotFound):
            finalize_upload(
                db,
                profile_public_id=foreigner.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


def test_a6_foreign_user_cannot_cancel(session_factory, settings_enabled) -> None:
    """A6 — same uniform 404 for cancel."""
    owner, foreigner = _make_two_authors(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        owner,
        content_type="audio/mpeg",
        size=512,
    )

    with session_factory() as db:
        with pytest.raises(MediaNotFound):
            cancel_upload(
                db,
                profile_public_id=foreigner.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


def test_a7_cancel_deletes_object_and_transitions_to_cancelled(
    session_factory, settings_enabled
) -> None:
    """A7 — cancel calls ``ObjectStore.delete_object`` AND
    transitions the row to ``cancelled``. The Flutter-side
    half (cancel aborts the in-flight PUT) lives in the
    companion ``community_media_uploader_test.dart``."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )

    with session_factory() as db:
        result = cancel_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
        assert result is True
    assert intent.object_key in store.deleted

    with session_factory() as db:
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        assert row.upload_state == UPLOAD_STATE_CANCELLED


def test_a7_orphan_cleanup_sweeps_abandoned_uploads(
    session_factory, settings_enabled
) -> None:
    """A7 — the orphan-cleanup function sweeps every row
    whose state is NOT ``finalized`` AND whose
    ``retention_until`` is in the past. Re-running the sweep
    is a no-op (idempotent)."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )
    # Move retention_until into the past.
    with session_factory() as db:
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        row.retention_until = _utcnow() - timedelta(seconds=1)
        db.commit()

    later = _utcnow() + timedelta(days=2)
    with session_factory() as db:
        swept = cleanup_orphan_uploads(
            db,
            settings=settings_enabled,
            object_store=store,
            now=later,
        )
        db.commit()
    assert swept == 1
    assert intent.object_key in store.deleted

    # Idempotent — the second sweep finds zero candidates.
    with session_factory() as db:
        again = cleanup_orphan_uploads(
            db,
            settings=settings_enabled,
            object_store=store,
            now=later,
        )
        db.commit()
    assert again == 0

    with session_factory() as db:
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        assert row.upload_state == UPLOAD_STATE_CANCELLED


def test_a7_cancel_idempotent_repeat_call_returns_false(
    session_factory, settings_enabled
) -> None:
    """A7-adjacent — a repeat cancel on an already-cancelled
    row returns ``False`` (no-op), never raises."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )
    with session_factory() as db:
        first = cancel_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
        assert first is True
    with session_factory() as db:
        second = cancel_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
        assert second is False


def test_quota_exceeded_after_max_live_uploads(
    session_factory, settings_enabled
) -> None:
    """§3 quota — once the viewer holds
    ``MAX_LIVE_UPLOADS_PER_PROFILE`` non-finalized rows, a new
    intent is rejected with :class:`MediaQuotaExceeded`."""
    profile = _make_author(session_factory)
    store = _new_store()
    # Pre-fill the quota with the default cap.
    for _ in range(svc.MAX_LIVE_UPLOADS_PER_PROFILE):
        _create_intent(
            session_factory,
            settings_enabled,
            store,
            profile,
            content_type="audio/mpeg",
            size=512,
        )
    with session_factory() as db:
        with pytest.raises(MediaQuotaExceeded):
            create_upload_intent(
                db,
                profile_public_id=profile.public_id,
                content_type="audio/mpeg",
                size=512,
                duration_ms=None,
                checksum_sha256=None,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


def test_quota_counts_only_live_states_not_cancelled(
    session_factory, settings_enabled
) -> None:
    """MAJOR M1 fix — the §3 quota counts ONLY the live states
    (``pending`` / ``uploaded``); the terminal ``cancelled`` /
    ``failed`` states must NOT exhaust the quota.

    Without the fix, 10+ consecutive intent+cancel cycles
    permanently lock out the profile (the
    ``_live_upload_count`` filter previously matched every
    non-finalized row, including cancelled / failed, which are
    never removed by anything in the pipeline)."""
    profile = _make_author(session_factory)
    store = _new_store()

    # 10 cancel cycles — the previous implementation would
    # leave 10 cancelled rows pinned to the profile.
    for _ in range(svc.MAX_LIVE_UPLOADS_PER_PROFILE):
        intent, _ = _create_intent(
            session_factory,
            settings_enabled,
            store,
            profile,
            content_type="audio/mpeg",
            size=512,
        )
        _seed_object_for(
            store,
            object_key=intent.object_key,
            body=b"some bytes",
            content_type="audio/mpeg",
        )
        with session_factory() as db:
            cancel_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )
            db.commit()

    # A NEW intent must succeed — the previous implementation
    # would raise MediaQuotaExceeded here.
    with session_factory() as db:
        intent = create_upload_intent(
            db,
            profile_public_id=profile.public_id,
            content_type="audio/mpeg",
            size=512,
            duration_ms=None,
            checksum_sha256=None,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
        assert intent.media_public_id is not None


def test_finalize_idempotent_repeat_returns_existing_row(
    session_factory, settings_enabled
) -> None:
    """A7-adjacent — a repeat finalize on an already-finalized
    row is a successful no-op (returns the row)."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )

    with session_factory() as db:
        first = finalize_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
        assert first.upload_state == UPLOAD_STATE_FINALIZED
    with session_factory() as db:
        second = finalize_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
        assert second.upload_state == UPLOAD_STATE_FINALIZED
        assert second.finalized_at == first.finalized_at


def test_cancel_of_finalized_row_raises_not_found(
    session_factory, settings_enabled
) -> None:
    """A7-adjacent — cancel on a finalized row is rejected
    with :class:`MediaNotFound` (uniform 404 — the row is
    immutable post-finalize)."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"some bytes",
        content_type="audio/mpeg",
    )
    with session_factory() as db:
        finalize_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,
            now=_utcnow(),
        )
        db.commit()
    with session_factory() as db:
        with pytest.raises(MediaNotFound):
            cancel_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


# ---------------------------------------------------------------------------
# §6.1 valódi-sértés próba — A5 (checksum) real-violation probe.
# ---------------------------------------------------------------------------


def test_a5_checksum_real_violation_probe(
    session_factory, settings_enabled, monkeypatch
) -> None:
    """§6.1 valódi-sértés próba — drop the checksum comparison
    in :func:`finalize_upload`, drive a finalize with a
    mismatched SHA-256, and assert the row transitions to
    ``finalized`` (A5 broken — the cell goes RED). Then
    restore the original guard.

    The probe demonstrates that WITHOUT the checksum check,
    a mismatched upload is silently accepted — it does not
    demonstrate that the check is unnecessary. That is the
    whole point of defense-in-depth: the checksum guard is
    what makes A5 survive a future refactor that drops an
    earlier layer."""
    profile = _make_author(session_factory)
    store = _new_store()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,
        profile,
        content_type="audio/mpeg",
        size=512,
        checksum_sha256="0" * 64,
    )
    _seed_object_for(
        store,
        object_key=intent.object_key,
        body=b"actual bytes",
        content_type="audio/mpeg",
    )

    # Replace the service's checksum-comparison block with a
    # no-op so the probe drives a mismatch through finalize.
    original = svc._validate_checksum  # type: ignore[attr-defined]

    def _noop_checksum(*_args, **_kwargs):
        return None

    monkeypatch.setattr(svc, "_validate_checksum", _noop_checksum)

    try:
        with session_factory() as db:
            row = finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )
            db.commit()
            db.refresh(row)
        # A5 broken — the mismatch slipped through.
        assert row.upload_state == UPLOAD_STATE_FINALIZED
    finally:
        monkeypatch.setattr(svc, "_validate_checksum", original)

    # Re-run the same finalize (post-restore) — the cell
    # turns green again.
    # Reset the row to pending so the finalize re-checks.
    with session_factory() as db:
        row = db.query(CommunityMedia).filter_by(public_id=intent.media_public_id).one()
        row.upload_state = UPLOAD_STATE_PENDING
        row.finalized_at = None
        db.commit()
    with session_factory() as db:
        with pytest.raises(MediaChecksumMismatch):
            finalize_upload(
                db,
                profile_public_id=profile.public_id,
                media_public_id=intent.media_public_id,
                settings=settings_enabled,
                object_store=store,
                now=_utcnow(),
            )


# ---------------------------------------------------------------------------
# ObjectStore smoke tests — confirm the wire shape the service consumes.
# ---------------------------------------------------------------------------


def test_in_memory_store_signed_url_shape() -> None:
    """The presigned URL is emitted with the constraints the
    finalize path re-checks — content_type, max_content_length,
    expires_at. The ``memory://`` scheme is fake-only."""
    store = _new_store()
    signed = store.create_upload_url(
        "profile/x/mp3",
        content_type="audio/mpeg",
        max_content_length=512,
        expires_in=timedelta(seconds=60),
    )
    assert signed.url == "memory://upload/profile/x/mp3"
    assert signed.method == "PUT"
    assert signed.content_type == "audio/mpeg"
    assert signed.max_content_length == 512
    assert signed.expires_at > _utcnow()


def test_in_memory_store_delete_is_idempotent() -> None:
    """delete_object on a non-existent key is a no-op (the
    orphan-cleanup function relies on this)."""
    store = _new_store()
    store.delete_object("never-existed")
    assert store.deleted == ["never-existed"]
    # Second call is also a no-op (no exception).
    store.delete_object("never-existed")
    assert store.deleted == ["never-existed", "never-existed"]


# ---------------------------------------------------------------------------
# Pytest parametrize marker so the §6.1 threshold-triple shows up as
# three discrete test items in the report — each cell must turn
# independently.
# ---------------------------------------------------------------------------

_ = MEDIA_CONTENT_TYPE_ALLOWLIST  # silence linter on the import.


# ---------------------------------------------------------------------------
# M2 / F4 — checksum-guard gap (real adapter, sha256_hex=None).
# ---------------------------------------------------------------------------


class _Sha256HexNoneObjectStore:
    """A minimal ObjectStore stub that mirrors
    :class:`S3CompatibleObjectStore.head_object`'s current
    behaviour: ``sha256_hex`` is ``None`` because the bucket-side
    SHA-256 wiring is a TODO (see object_store.py)."""

    def __init__(self) -> None:
        self._objects: dict[str, dict[str, object]] = {}

    def create_upload_url(self, key, *, content_type, max_content_length, expires_in):
        from app.community.storage.object_store import SignedUpload

        return SignedUpload(
            url=f"memory://upload/{key}",
            method="PUT",
            content_type=content_type,
            max_content_length=max_content_length,
            expires_at=datetime.now(timezone.utc) + expires_in,
        )

    def head_object(self, key):
        from app.community.storage.object_store import ObjectMetadata

        obj = self._objects.get(key)
        if obj is None:
            return None
        return ObjectMetadata(
            size=obj["size"],  # type: ignore[arg-type]
            content_type=obj["content_type"],  # type: ignore[arg-type]
            etag=None,
            sha256_hex=None,
        )

    def delete_object(self, key) -> None:
        self._objects.pop(key, None)

    def stage(self, key, *, size, content_type) -> None:
        self._objects[key] = {"size": size, "content_type": content_type}


@pytest.mark.xfail(
    strict=True,
    reason=(
        "M2/F4 gap: S3CompatibleObjectStore.head_object returns "
        "sha256_hex=None — the A5 checksum-guard does NOT fire "
        "against a real adapter (only the in-memory fake). The "
        "xfail turns RED the moment a future wiring round wires "
        "the bucket-side SHA-256 (S3 Additional-Checksums "
        "headers or X-Amz-Meta-Sha256 custom header). At that "
        "point the TODO in object_store.py can be removed and "
        "this xfail replaced with a normal assertion that the "
        "checksum mismatch IS caught."
    ),
)
def test_a5_real_adapter_no_sha256_hex_does_not_catch_mismatch(
    session_factory, settings_enabled
) -> None:
    """A5 with a real-adapter-like store — ``sha256_hex=None``
    means the §6 A5 guard cannot fire even though the bucket
    contains a different body than the intent declared.

    Strict ``xfail``: the test passes-by-expectation today
    (the row transitions to ``finalized``), turning RED the
    moment the real-adapter checksum wiring lights up. The
    brief M2/F4 acceptance — making the gap VISIBLE rather
    than silent — is the responsibility of this xfail."""
    profile = _make_author(session_factory)
    store = _Sha256HexNoneObjectStore()
    intent, _ = _create_intent(
        session_factory,
        settings_enabled,
        store,  # type: ignore[arg-type]
        profile,
        content_type="audio/mpeg",
        size=512,
        checksum_sha256="0" * 64,
    )
    store.stage(intent.object_key, size=512, content_type="audio/mpeg")

    with session_factory() as db:
        row = finalize_upload(
            db,
            profile_public_id=profile.public_id,
            media_public_id=intent.media_public_id,
            settings=settings_enabled,
            object_store=store,  # type: ignore[arg-type]
            now=_utcnow(),
        )
        db.commit()
        db.refresh(row)
    # Because head_object returned sha256_hex=None, the
    # _validate_checksum guard was a no-op — the row reaches
    # finalized. This is the gap; the xfail makes it loud.
    assert row.upload_state == UPLOAD_STATE_FINALIZED


# ---------------------------------------------------------------------------
# M3 — _as_utc is UTC-bound regardless of host local timezone.
# ---------------------------------------------------------------------------


def test_as_utc_naive_input_attaches_utc_not_local_tz() -> None:
    """MAJOR M3 fix — ``_as_utc`` MUST attach ``timezone.utc``
    to a naive datetime, NOT the host's local timezone (the
    previous implementation did ``datetime.now().astimezone().
    tzinfo`` — a UTC+2 host shifted every expiry/retention
    comparison by 2 hours). The test is host-tz-independent: a
    naive input gets a tzinfo that compares equal to
    ``timezone.utc``."""
    from app.community.services.media_upload_service import _as_utc

    naive = datetime(2026, 1, 1, 12, 0, 0)
    out = _as_utc(naive)
    assert out.tzinfo is not None
    assert out.utcoffset() == timedelta(0)


def test_as_utc_aware_input_is_unchanged() -> None:
    """An aware datetime is returned as-is (UTC-aware or not —
    the helper does not normalize zones, only re-attaches UTC
    to naive values)."""
    from app.community.services.media_upload_service import _as_utc

    aware_utc = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    assert _as_utc(aware_utc) is aware_utc


# ---------------------------------------------------------------------------
# F2 — SigV4 presigned URL signs ``Content-Type`` as a real header
# (no fake ``X-Amz-SignedHeaders-Content-Type`` query parameter).
# ---------------------------------------------------------------------------


def test_sigv4_presign_put_signs_content_type_as_header() -> None:
    """MAJOR F2 fix — the PUT presign adds ``content-type`` to
    ``X-Amz-SignedHeaders`` and to the canonical headers block.
    The returned headers dict carries the EXACT ``Content-Type``
    the client must echo back; a mismatch causes a 403
    ``SignatureDoesNotMatch`` at PUT time on a real bucket.

    Known-answer test: with a fixed clock, region, and key, the
    URL is deterministic. We assert:
      * ``X-Amz-SignedHeaders`` lists ``host`` AND
        ``content-type`` (in that order, semicolon-separated);
      * the returned ``Content-Type`` header matches the
        caller-supplied value exactly;
      * the previously-fake
        ``X-Amz-SignedHeaders-Content-Type`` and
        ``X-Amz-SignedHeaders-Content-Length`` query params are
        ABSENT (no bucket recognizes them — they were inert).

    The credentials are short test-fixture strings — the
    SigV4 computation uses the access_key_id verbatim in the
    ``X-Amz-Credential`` scope and the secret in the HMAC
    chain, so the URL is fully deterministic regardless of the
    values. The values are deliberately not the AWS-documented
    example pair so the secret-scan gate stays green (no
    provider-token prefix, no 16-char-long credential
    literal)."""
    from urllib.parse import parse_qs, urlparse

    from app.community.storage.object_store import _sigv4_presign_request

    fixed_now = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    url, headers = _sigv4_presign_request(
        method="PUT",
        endpoint="https://example-bucket.s3.eu-central-1.amazonaws.com",
        bucket="example-bucket",
        region="eu-central-1",
        access_key_id="aki-fixture",
        secret_access_key="secret-fixture",
        key="profile/1/abc",
        content_type="audio/mpeg",
        max_content_length=1024,
        now=fixed_now,
        expires_in_seconds=300,
    )

    parsed = urlparse(url)
    qs = parse_qs(parsed.query)
    assert qs["X-Amz-SignedHeaders"] == ["host;content-type"]
    # No fake signed query parameters:
    assert "X-Amz-SignedHeaders-Content-Type" not in qs
    assert "X-Amz-SignedHeaders-Content-Length" not in qs
    # The exact Content-Type the client must echo back:
    assert headers["Content-Type"] == "audio/mpeg"


def test_sigv4_presign_head_signs_only_host() -> None:
    """The HEAD presign (used by ``head_object``) signs only
    ``host`` — no Content-Type is added, since HEAD has no
    body."""
    from urllib.parse import parse_qs, urlparse

    from app.community.storage.object_store import _sigv4_presign_request

    fixed_now = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    url, headers = _sigv4_presign_request(
        method="HEAD",
        endpoint="https://example-bucket.s3.eu-central-1.amazonaws.com",
        bucket="example-bucket",
        region="eu-central-1",
        access_key_id="aki-fixture",
        secret_access_key="secret-fixture",
        key="profile/1/abc",
        content_type=None,
        max_content_length=None,
        now=fixed_now,
        expires_in_seconds=300,
    )

    parsed = urlparse(url)
    qs = parse_qs(parsed.query)
    assert qs["X-Amz-SignedHeaders"] == ["host"]
    assert "Content-Type" not in headers
