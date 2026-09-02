"""Capacity-guard smoke tests — E12-R29 (round brief §6 A2/A3/A4).

Covers the three backend-side acceptance cells the round brief §0.0
pre-flight revision (P1–P5) re-measured on this tree:

* A2 — rate-limit smoke on the MOUNTED ``/auth/login`` endpoint. The
  threshold-triple is computed from ``login_limiter.max_attempts``
  (``backend/app/routers/auth.py:16``), never hardcoded (§0.0 P5) —
  a future change to the limiter's constant re-derives the three
  request counts automatically instead of silently going stale.
  ``RateLimiter.allow()`` compares BEFORE appending
  (``backend/app/ratelimit.py:36``), so the Nth request still passes
  and only the (N+1)th 429s.

* A3 — the media-upload size guard, exercised at the SERVICE layer
  (§0.0 P3: the Community router is not mounted in ``create_app()``,
  so there is no HTTP surface to hit here). ``MAX_UPLOAD_BYTES - 1``
  and ``MAX_UPLOAD_BYTES`` are accepted (the boundary is inclusive);
  ``MAX_UPLOAD_BYTES + 1`` raises :class:`MediaSizeExceeded`.

* A4 — the moderation-queue smoke, exercised on the MEASURED read
  path (§0.0 P1): ``submit_report`` does NOT itself open a
  moderation case (a ``grep`` for ``case_service`` /
  ``get_or_create_case`` inside ``report_service.py`` returns zero
  hits) — the row only becomes visible in the queue once
  ``get_or_create_case`` is called against the same
  ``(target_type, target_id)``. Two reports from two distinct
  reporters against the same target land two ``community_reports``
  rows, and the case opened afterwards carries a ``priority_score``
  that reflects the report count (``report_count * PRIORITY_WEIGHT_
  REPORT_COUNT`` — the case's only other two inputs, automation
  confidence and account history, are both zero for a fresh case
  with no automation signal and no closed prior cases).

The A3/A4 fixtures build their OWN engine/session via
``alembic upgrade head`` on a file-backed SQLite, mirroring
``backend/tests/community/test_media_upload.py`` /
``.../test_report_service.py`` (§0.0 P3/P4) — the
``backend/tests/community/conftest.py`` fixtures are scoped to the
``community/`` subpackage and are not importable from this file,
which lives at the ``tests/`` package root.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.profile import CommunityProfile
from app.community.moderation.case_service import (
    PRIORITY_WEIGHT_REPORT_COUNT,
    get_or_create_case,
    list_open_cases,
)
from app.community.services.media_upload_service import (
    MAX_UPLOAD_BYTES,
    MediaSizeExceeded,
    create_upload_intent,
)
from app.community.services.report_service import (
    reset_rate_limit_state,
    submit_report,
)
from app.community.storage.object_store import InMemoryObjectStore
from app.config import Settings
from app.database import enable_sqlite_foreign_keys
from app.routers.auth import login_limiter
from app.security import hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# A2 — rate-limit threshold-triple on the mounted /auth/login (§0.0 P5).
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "attempt_offset, expect_status",
    [
        (-1, 401),  # below the threshold (N-1) — accepted (never 429)
        (0, 401),  # exactly at the threshold (N) — still accepted (inclusive)
        (1, 429),  # above the threshold (N+1) — rejected
    ],
)
def test_a2_login_rate_limit_threshold_triple(client, attempt_offset, expect_status):
    """§0.0 P5 — the three cells are computed from
    ``login_limiter.max_attempts``, not hardcoded 9/10/11."""
    max_attempts = login_limiter.max_attempts
    total_requests = max_attempts + attempt_offset
    payload = {"email": "nobody@strumsight.app", "password": "wrong-password"}

    last_response = None
    for _ in range(total_requests):
        last_response = client.post("/auth/login", json=payload)

    assert last_response is not None
    assert last_response.status_code == expect_status, last_response.text
    if expect_status == 429:
        assert "Retry-After" in last_response.headers


# ---------------------------------------------------------------------------
# A3/A4 fixtures — own engine + alembic upgrade head (§0.0 P3/P4).
# ---------------------------------------------------------------------------


@pytest.fixture
def capacity_session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "capacity_guards.db"
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
def community_media_settings() -> Settings:
    return Settings(
        _env_file=None, community_enabled=True, community_media_enabled=True
    )


def _make_profile(session_factory, *, user_id: int, email: str) -> uuid.UUID:
    """Insert a ``users`` row + a ``community_profiles`` row and return the
    profile's ``public_id``. No ``community_privacy_settings`` row is
    needed — neither ``create_upload_intent`` nor ``submit_report`` reads
    it (only ``CommunityProfile`` is resolved from ``profile_public_id`` /
    ``reporter_public_id``)."""
    with session_factory() as db:
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
        db.commit()
        profile = CommunityProfile(user_id=user_id)
        db.add(profile)
        db.commit()
        db.refresh(profile)
        return profile.public_id


# ---------------------------------------------------------------------------
# A3 — upload-size threshold-triple, service layer (§0.0 P3).
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "size_offset, expect_size_exceeded",
    [
        (-1, False),  # MAX_UPLOAD_BYTES - 1 — accepted
        (0, False),  # MAX_UPLOAD_BYTES — accepted (boundary is inclusive)
        (1, True),  # MAX_UPLOAD_BYTES + 1 — rejected
    ],
)
def test_a3_upload_size_threshold_triple(
    capacity_session_factory,
    community_media_settings,
    size_offset,
    expect_size_exceeded,
):
    profile_public_id = _make_profile(
        capacity_session_factory, user_id=1, email="uploader@s.test"
    )
    store = InMemoryObjectStore()
    size = MAX_UPLOAD_BYTES + size_offset

    with capacity_session_factory() as db:
        if expect_size_exceeded:
            with pytest.raises(MediaSizeExceeded):
                create_upload_intent(
                    db,
                    profile_public_id=profile_public_id,
                    content_type="audio/mpeg",
                    size=size,
                    duration_ms=None,
                    checksum_sha256=None,
                    settings=community_media_settings,
                    object_store=store,
                    now=_utcnow(),
                )
        else:
            intent = create_upload_intent(
                db,
                profile_public_id=profile_public_id,
                content_type="audio/mpeg",
                size=size,
                duration_ms=None,
                checksum_sha256=None,
                settings=community_media_settings,
                object_store=store,
                now=_utcnow(),
            )
            db.commit()
            assert intent.media_public_id is not None


# ---------------------------------------------------------------------------
# A4 — moderation-queue smoke on the measured route (§0.0 P1).
# ---------------------------------------------------------------------------


def test_a4_report_row_queryable_then_case_opens_with_report_signal(
    capacity_session_factory,
):
    """§0.0 P1 — ``submit_report`` only writes ``community_reports``; the
    target's case is not open until ``get_or_create_case`` runs. Two
    reports from two distinct reporters against the same target land two
    rows, and the case opened afterwards carries a ``priority_score`` that
    reflects the report signal (2 reports)."""
    reset_rate_limit_state()
    reporter_1 = _make_profile(
        capacity_session_factory, user_id=1, email="reporter1@s.test"
    )
    reporter_2 = _make_profile(
        capacity_session_factory, user_id=2, email="reporter2@s.test"
    )
    target_type = "post"
    target_id = str(uuid.uuid4())

    with capacity_session_factory() as db:
        first = submit_report(
            db,
            reporter_public_id=reporter_1,
            target_type=target_type,
            target_id=target_id,
            category="spam",
        )
        db.commit()
    assert first.deduplicated is False

    with capacity_session_factory() as db:
        second = submit_report(
            db,
            reporter_public_id=reporter_2,
            target_type=target_type,
            target_id=target_id,
            category="spam",
        )
        db.commit()
    assert second.deduplicated is False

    # The reports land as plain rows — the sor lekérdezhető contract.
    # No moderation case exists yet (submit_report never opens one, §0.0 P1).
    with capacity_session_factory() as db:
        rows = db.execute(
            text("SELECT id FROM community_reports WHERE target_id = :tid"),
            {"tid": target_id},
        ).fetchall()
        assert len(rows) == 2, "both distinct reporters' rows must land"

        open_cases_before = list_open_cases(db)
        assert not any(c.target_id == target_id for c in open_cases_before), (
            "A4 violated — a case for the target exists before "
            "get_or_create_case was ever called"
        )

    # get_or_create_case opens the case — this is the MEASURED route
    # (§0.0 P1) from a bejelentés-sor to the moderation queue.
    with capacity_session_factory() as db:
        case = get_or_create_case(
            db, target_type=target_type, target_id=target_id, now=_utcnow()
        )
        db.commit()

        open_cases_after = list_open_cases(db)
        assert any(c.target_id == target_id for c in open_cases_after), (
            "A4 violated — the target's case does not appear in "
            "list_open_cases() after get_or_create_case"
        )
        # Két bejelentés esetén a jel 2 (§0.0 P1) — automation_confidence
        # and account_history are both zero for a fresh case with no
        # automation signal and no closed prior cases against the (unknown)
        # target author, so priority_score is purely the report signal.
        assert case.priority_score == 2 * PRIORITY_WEIGHT_REPORT_COUNT, (
            "A4 violated — the report signal is not reflected in priority_score"
        )
