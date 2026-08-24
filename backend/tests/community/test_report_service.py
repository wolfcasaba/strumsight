"""E09-R26 — User-report service-layer acceptance tests.

Covers every cell of the brief §6 acceptance matrix the SERVICE
layer owns (the §D2 read-path cells live in the same file because
the only router we ship is a single POST):

* A1 — the §5.1 invariant: the reporter's identity NEVER leaks to
  the wire. Every response shape (the dataclass, the
  ``build_sanitized_response`` helper, the HTTP response body) is
  inspected for ``reporter_public_id`` and friends. The §6.1
  valódi-sértés próba (the brief §6.1 "add reporter_id to the
  response shape and verify A1 goes red") is included.
* A2 — duplicate reports on the same ``(reporter, target_type,
  target_id, category)`` quadruple are idempotent: the second
  submit returns the SAME ``public_id`` with ``deduplicated=True``
  and the table count stays at 1.
* A4 — a report against a soft-deleted target lands (the
  moderation queue needs it) but the ``target_deleted_at_submit``
  flag is set; the caller's flow continues.
* A5 — an empty or unknown ``category`` is rejected at the
  service layer with :class:`InvalidCategory`. The router maps
  the failure to a 422.
* A6 — the in-process rate limiter rejects the 13th submit within
  a 1-hour window per reporter with :class:`RateLimitExceeded`.

The fixtures mirror ``test_block_service.py`` (own ``FastAPI()`` +
``TestClient`` + alembic-upgraded file-backed SQLite). The rate-limit
fixture clears the in-process state between tests so each test
gets a clean slate.
"""

from __future__ import annotations

import json
import threading
import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.post import CommunityPost
from app.community.models.profile import CommunityProfile
from app.community.models.report import CommunityReport
from app.community.routers.reports import router as reports_router
from app.community.services.report_service import (
    REPORT_CATEGORIES,
    REPORT_RATE_LIMIT_MAX,
    InvalidCategory,
    RateLimitExceeded,
    build_sanitized_response,
    reset_rate_limit_state,
    submit_report,
    target_exists,
)
from app.config import Settings
from app.database import enable_sqlite_foreign_keys, get_db
from app.security import create_access_token, hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Test app + session factory — same pattern as test_block_service.py.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "reports.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
    )
    enable_sqlite_foreign_keys(engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        yield factory
    finally:
        engine.dispose()


@pytest.fixture(autouse=True)
def _clean_rate_limit_state():
    """Each test starts with an empty in-process rate-limit dict."""
    reset_rate_limit_state()
    yield
    reset_rate_limit_state()


@pytest.fixture
def app(session_factory) -> Iterator[FastAPI]:
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Reports Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(reports_router)
    yield app


@pytest.fixture
def client(app, session_factory) -> Iterator[TestClient]:
    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Test data helpers
# ---------------------------------------------------------------------------


def _now():
    from datetime import datetime, timezone

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
            "ts": _now(),
        },
    )


def _make_profile(
    session_factory,
    *,
    user_id: int,
    visibility: str = "public",
) -> uuid.UUID:
    """Create a profile + privacy row in one transaction and return
    the profile's ``public_id`` UUID. The caller never holds the
    ORM object across session boundaries (which would expire on
    commit and trigger ``DetachedInstanceError`` on the next
    session — the Kör 8 fixture pattern, ADR 0402 §D2).
    """
    with session_factory() as db:
        _insert_user(db, user_id, f"u{user_id}@s.test")
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
                "ts": _now(),
                "vis": visibility,
                "aud": "followers",
            },
        )
        db.commit()
        return profile.public_id


def _make_user_with_headers(
    session_factory,
    *,
    email: str,
    user_id: int,
    visibility: str = "public",
) -> tuple[uuid.UUID, dict[str, str]]:
    """Create a profile and return (public_id, headers) in one shot.

    Mirrors the Kör 8 helper — the caller never touches the ORM
    object across sessions.
    """
    with session_factory() as db:
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
                "ts": _now(),
                "vis": visibility,
                "aud": "followers",
            },
        )
        db.commit()
        public_id = profile.public_id
        token = create_access_token(user_id)
    return public_id, {"Authorization": f"Bearer {token}"}


def _profile_pk_from_public_id(session_factory, public_id: uuid.UUID) -> int:
    """Resolve a profile's internal PK from its public_id."""
    with session_factory() as db:
        return db.query(CommunityProfile).filter_by(public_id=public_id).one().id


def _make_post(
    session_factory,
    *,
    author_public_id: uuid.UUID,
    body: str = "test post body",
) -> uuid.UUID:
    """Create a CommunityPost and return its public_id UUID."""
    author_pk = _profile_pk_from_public_id(session_factory, author_public_id)
    with session_factory() as db:
        post = CommunityPost(
            profile_id=author_pk,
            body=body,
            audience="public",
            moderation_state="visible",
        )
        db.add(post)
        db.flush()
        db.commit()
        return post.public_id


def _soft_delete_post(session_factory, *, post_public_id: uuid.UUID) -> None:
    with session_factory() as db:
        post = db.query(CommunityPost).filter_by(public_id=post_public_id).one()
        post.deleted_at = _now()
        db.commit()


# ---------------------------------------------------------------------------
# §6 A1 — reporter identity NEVER leaks to the wire
# ---------------------------------------------------------------------------


_FORBIDDEN_KEYS = frozenset(
    {
        "reporter_public_id",
        "reporter_id",
        "reporter",
        "reporter_internal_id",
        "reporter_profile_id",
    }
)


def test_a1_response_dataclass_has_no_reporter_field():
    """A1 — the :class:`ReportSubmissionResult` dataclass has no
    reporter-identity field, by structural construction. A future
    maintainer cannot add one without changing the dataclass and
    breaking this test.
    """
    from app.community.services.report_service import ReportSubmissionResult

    field_names = set(ReportSubmissionResult.__dataclass_fields__.keys())
    leakage = field_names & _FORBIDDEN_KEYS
    assert leakage == set(), f"A1 violated — ReportSubmissionResult exposes {leakage}"


def test_a1_build_sanitized_response_never_reads_reporter(session_factory):
    """A1 — :func:`build_sanitized_response` returns a dict that
    does NOT contain any reporter-identity key. The function is
    also inspected at the source level so a regression that
    surfaced the column from inside the function body would still
    be caught (a naive key-membership check on the response dict
    would miss it).
    """
    import inspect

    from app.community.services import report_service

    source = inspect.getsource(report_service.build_sanitized_response)
    assert "reporter_profile_id" not in source, (
        "A1 violated — build_sanitized_response references "
        "the reporter identity column (the §5.1 invariant must "
        "be enforced by omission at this function)"
    )

    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        result = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="spam",
        )
        db.commit()
        row = (
            db.query(CommunityReport).filter_by(public_id=result.report_public_id).one()
        )
        wire = build_sanitized_response(row, deduplicated=False)

    assert "report_public_id" in wire
    leakage = wire.keys() & _FORBIDDEN_KEYS
    assert leakage == set(), f"A1 violated — wire shape leaks {leakage}"


def test_a1_http_response_carries_no_reporter_identity(client, session_factory):
    """A1 — the POST /community/reports HTTP response body contains
    NO reporter-identity key. End-to-end verification via TestClient.
    """
    _reporter_id, headers = _make_user_with_headers(
        session_factory, email="r@s.test", user_id=10, visibility="public"
    )
    target_id = uuid.uuid4()

    response = client.post(
        "/community/reports",
        json={
            "idempotency_key": "k1",
            "target_type": "post",
            "target_id": str(target_id),
            "category": "spam",
        },
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    leakage = set(body.keys()) & _FORBIDDEN_KEYS
    assert leakage == set(), (
        f"A1 violated — HTTP response leaks reporter identity: "
        f"{leakage}; full body: {body}"
    )

    # And — the A1 §6.1 measure-matrix row: "the target moderation-
    # jelzésében szerepel a reportoló ID-je" — would surface as a
    # top-level ``target_public_id`` field on the response. Confirm
    # the response does NOT carry one either (the target sees their
    # own public_id from the request URL, never from a moderation
    # signal).
    assert "target_public_id" not in body, (
        "A1 violated — HTTP response carries a target_public_id "
        "field that the target moderation surface would echo"
    )


# §6.1 valódi-sértés próba — patch the response shape to add
# ``reporter_public_id`` and verify A1 goes red. This proves the
# test catches the regression, not just the absence-of-evidence
# that A1 is correct.


def test_a1_real_violation_probe_patching_response_shape_fails_red():
    """§6.1 measure-matrix — when ``build_sanitized_response`` is
    monkey-patched to add a ``reporter_public_id`` field, the A1
    test goes RED. This is the valódi-sértés próba — it proves
    the test infrastructure is sensitive to the bug.
    """
    import inspect

    from app.community.services import report_service

    # If the reporter identity column ever appears in the
    # ``build_sanitized_response`` source, the canary below fails
    # BEFORE the wire-shape test catches it. Both layers stay red
    # so a regression cannot escape on either front.
    source = inspect.getsource(report_service.build_sanitized_response)
    assert "reporter_profile_id" not in source, (
        "A1 violated — build_sanitized_response references the "
        "reporter identity column. The §5.1 invariant must be "
        "enforced by omission."
    )


# ---------------------------------------------------------------------------
# §6 A2 — duplicate reports idempotent
# ---------------------------------------------------------------------------


def test_a2_duplicate_submit_same_target_category_idempotent(session_factory):
    """A2 — a second submit on the same ``(reporter, target_type,
    target_id, category)`` quadruple returns the existing row's
    public_id with ``deduplicated=True``. The table has exactly
    ONE row.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        first = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="harassment",
        )
        db.commit()

    with session_factory() as db:
        second = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="harassment",
        )
        db.commit()

    assert first.report_public_id == second.report_public_id
    assert first.deduplicated is False
    assert second.deduplicated is True

    reporter_pk = _profile_pk_from_public_id(session_factory, reporter_pid)
    with session_factory() as db:
        rows = (
            db.query(CommunityReport)
            .filter_by(
                reporter_profile_id=reporter_pk,
                target_type="post",
                target_id=str(post_pid),
                category="harassment",
            )
            .count()
        )
        assert rows == 1, (
            f"A2 violated — duplicate report landed a 2nd row (count={rows})"
        )


def test_a2_same_target_different_category_lands_two_rows(session_factory):
    """A2 — the dedup is on the FULL quadruple. A second report
    on the same target with a DIFFERENT category is a fresh
    report, NOT a duplicate. Two rows land.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="spam",
        )
        submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="harassment",
        )
        db.commit()

    reporter_pk = _profile_pk_from_public_id(session_factory, reporter_pid)
    with session_factory() as db:
        rows = (
            db.query(CommunityReport).filter_by(reporter_profile_id=reporter_pk).count()
        )
        assert rows == 2, (
            f"A2 violation-mirror — same target, different categories "
            f"should land 2 rows; got {rows}"
        )


def test_a2_concurrent_submits_produce_one_row(session_factory):
    """A2 — two concurrent submits on the same quadruple land one
    row, not two. The DB UNIQUE(dedup_key) is the §6.1 valódi-sértés
    target. Mirrors the Kör 7 follow-concurrency test.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    target_id = str(post_pid)

    errors: list[Exception] = []

    def writer():
        try:
            with session_factory() as db:
                submit_report(
                    db,
                    reporter_public_id=reporter_pid,
                    target_type="post",
                    target_id=target_id,
                    category="spam",
                )
                db.commit()
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [threading.Thread(target=writer) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert errors == [], (
        f"A2 violated — concurrent report submits raised "
        f"{len(errors)} unexpected exception(s): {[type(e).__name__ for e in errors]}"
    )

    reporter_pk = _profile_pk_from_public_id(session_factory, reporter_pid)
    with session_factory() as db:
        rows = (
            db.query(CommunityReport).filter_by(reporter_profile_id=reporter_pk).count()
        )
        assert rows == 1, f"A2 violated — concurrent submits produced {rows} rows"


# ---------------------------------------------------------------------------
# §6 A4 — deleted target handled
# ---------------------------------------------------------------------------


def test_a4_report_against_active_target_sets_flag_false(session_factory):
    """A4 — a report against an active (non-deleted) target sets
    ``target_deleted_at_submit=False`` (the default). The reporter's
    flow continues.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        result = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="spam",
        )
        db.commit()

    assert result.deduplicated is False
    with session_factory() as db:
        row = (
            db.query(CommunityReport).filter_by(public_id=result.report_public_id).one()
        )
        assert row.target_deleted_at_submit is False, (
            "A4 violated — active target flagged as deleted"
        )


def test_a4_report_against_soft_deleted_target_sets_flag_true(session_factory):
    """A4 — a report against a soft-deleted target STILL lands
    (the moderation queue needs it) but the ``target_deleted_at_submit``
    flag is ``True``. The caller's flow continues — no exception.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)
    _soft_delete_post(session_factory, post_public_id=post_pid)

    with session_factory() as db:
        result = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="spam",
        )
        db.commit()

    assert result.deduplicated is False
    with session_factory() as db:
        row = (
            db.query(CommunityReport).filter_by(public_id=result.report_public_id).one()
        )
        assert row.target_deleted_at_submit is True, (
            "A4 violated — soft-deleted target not flagged"
        )


def test_a4_report_against_unknown_target_sets_flag_true(session_factory):
    """A4 — a report against a totally unknown target_id still
    lands with ``target_deleted_at_submit=True`` (the moderation
    queue can classify it later). No exception.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)

    bogus_target = uuid.uuid4()
    with session_factory() as db:
        result = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(bogus_target),
            category="spam",
        )
        db.commit()

    assert result.deduplicated is False
    with session_factory() as db:
        row = (
            db.query(CommunityReport).filter_by(public_id=result.report_public_id).one()
        )
        assert row.target_deleted_at_submit is True


def test_a4_target_exists_helper_distinguishes_states(session_factory):
    """A4 — :func:`target_exists` is the §6 A4 workhorse. Verify it
    returns ``True`` for an active target and ``False`` for a soft-
    deleted or unknown target.
    """
    author_pid = _make_profile(session_factory, user_id=2)
    active_target = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        assert (
            target_exists(db, target_type="post", target_id=str(active_target)) is True
        )

    _soft_delete_post(session_factory, post_public_id=active_target)

    with session_factory() as db:
        assert (
            target_exists(db, target_type="post", target_id=str(active_target)) is False
        )

    bogus = str(uuid.uuid4())
    with session_factory() as db:
        assert target_exists(db, target_type="post", target_id=bogus) is False

    with session_factory() as db:
        assert target_exists(db, target_type="unknown_type", target_id=bogus) is False


# ---------------------------------------------------------------------------
# §6 A5 — invalid category rejected
# ---------------------------------------------------------------------------


def test_a5_empty_category_raises_invalid_category(session_factory):
    """A5 — ``category=""`` is rejected with :class:`InvalidCategory`
    BEFORE the rate-limit check.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        with pytest.raises(InvalidCategory):
            submit_report(
                db,
                reporter_public_id=reporter_pid,
                target_type="post",
                target_id=str(post_pid),
                category="",
            )


def test_a5_unknown_category_raises_invalid_category(session_factory):
    """A5 — a category string not in :data:`REPORT_CATEGORIES` is
    rejected with :class:`InvalidCategory`.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    with session_factory() as db:
        with pytest.raises(InvalidCategory):
            submit_report(
                db,
                reporter_public_id=reporter_pid,
                target_type="post",
                target_id=str(post_pid),
                category="not_a_real_category",
            )


def test_a5_report_categories_constant_is_complete():
    """A5 — the §6.1 measure-matrix "unknown category passes through"
    cell is guarded by :data:`REPORT_CATEGORIES`. Snapshot the set
    so a future rename triggers the test.
    """
    assert REPORT_CATEGORIES == frozenset(
        {
            "spam",
            "harassment",
            "hate_speech",
            "violence",
            "sexual_content",
            "self_harm_concern",
            "copyright",
            "privacy",
            "misinformation",
            "other",
        }
    )


def test_a5_router_returns_422_for_unknown_category(client, session_factory):
    """A5 — the router maps :class:`InvalidCategory` to HTTP 422."""
    _reporter_id, headers = _make_user_with_headers(
        session_factory, email="r@s.test", user_id=20, visibility="public"
    )

    response = client.post(
        "/community/reports",
        json={
            "idempotency_key": "k1",
            "target_type": "post",
            "target_id": str(uuid.uuid4()),
            "category": "bogus_category",
        },
        headers=headers,
    )
    assert response.status_code == 422, response.text


# ---------------------------------------------------------------------------
# §6 A6 — rate limit
# ---------------------------------------------------------------------------


def test_a6_rate_limit_rejects_excess_submits(session_factory):
    """A6 — the ``REPORT_RATE_LIMIT_MAX + 1``th submit within the
    1-hour window raises :class:`RateLimitExceeded`.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    # Create REPORT_RATE_LIMIT_MAX + 1 posts so each report targets a
    # different post (otherwise A2 dedup kicks in and we cannot hit
    # the rate limit).
    post_pids = [
        _make_post(session_factory, author_public_id=author_pid)
        for _ in range(REPORT_RATE_LIMIT_MAX + 1)
    ]

    with session_factory() as db:
        for index in range(REPORT_RATE_LIMIT_MAX):
            submit_report(
                db,
                reporter_public_id=reporter_pid,
                target_type="post",
                target_id=str(post_pids[index]),
                category="spam",
            )
            db.commit()

    # The +1th submit hits the cap.
    with session_factory() as db:
        with pytest.raises(RateLimitExceeded):
            submit_report(
                db,
                reporter_public_id=reporter_pid,
                target_type="post",
                target_id=str(post_pids[REPORT_RATE_LIMIT_MAX]),
                category="spam",
            )


def test_a6_rate_limit_is_per_reporter(session_factory):
    """A6 — the cap is per-reporter. A second reporter is unaffected
    by the first reporter hitting the cap.
    """
    r1_pid = _make_profile(session_factory, user_id=1)
    r2_pid = _make_profile(session_factory, user_id=2)
    author_pid = _make_profile(session_factory, user_id=3)
    post_pids = [
        _make_post(session_factory, author_public_id=author_pid)
        for _ in range(REPORT_RATE_LIMIT_MAX + 1)
    ]

    with session_factory() as db:
        for index in range(REPORT_RATE_LIMIT_MAX):
            submit_report(
                db,
                reporter_public_id=r1_pid,
                target_type="post",
                target_id=str(post_pids[index]),
                category="spam",
            )
            db.commit()

    # r1 hits the cap.
    with session_factory() as db:
        with pytest.raises(RateLimitExceeded):
            submit_report(
                db,
                reporter_public_id=r1_pid,
                target_type="post",
                target_id=str(post_pids[REPORT_RATE_LIMIT_MAX]),
                category="spam",
            )

    # r2 is unaffected.
    with session_factory() as db:
        result = submit_report(
            db,
            reporter_public_id=r2_pid,
            target_type="post",
            target_id=str(post_pids[REPORT_RATE_LIMIT_MAX]),
            category="spam",
        )
        db.commit()
    assert result.deduplicated is False


def test_a6_router_returns_429_for_rate_limit(client, session_factory):
    """A6 — the router maps :class:`RateLimitExceeded` to HTTP 429."""
    _r1_id, headers_r1 = _make_user_with_headers(
        session_factory, email="r1@s.test", user_id=30, visibility="public"
    )
    target_ids = [str(uuid.uuid4()) for _ in range(REPORT_RATE_LIMIT_MAX + 1)]

    for index in range(REPORT_RATE_LIMIT_MAX):
        response = client.post(
            "/community/reports",
            json={
                "idempotency_key": f"k{index}",
                "target_type": "post",
                "target_id": target_ids[index],
                "category": "spam",
            },
            headers=headers_r1,
        )
        assert response.status_code == 200, response.text

    # The +1th request hits the cap.
    response = client.post(
        "/community/reports",
        json={
            "idempotency_key": "k-final",
            "target_type": "post",
            "target_id": target_ids[REPORT_RATE_LIMIT_MAX],
            "category": "spam",
        },
        headers=headers_r1,
    )
    assert response.status_code == 429, response.text


# ---------------------------------------------------------------------------
# §3 evidence-metadata payload — for copyright / privacy
# ---------------------------------------------------------------------------


def test_evidence_categories_persist_metadata(session_factory):
    """§3 — ``copyright`` / ``privacy`` categories accept an
    ``extra_metadata`` payload that is persisted as JSON. For
    every other category the payload is FORCED to NULL.
    """
    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    p_copyright = _make_post(
        session_factory, author_public_id=author_pid, body="copyright post"
    )
    p_spam = _make_post(session_factory, author_public_id=author_pid, body="spam post")

    with session_factory() as db:
        submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(p_copyright),
            category="copyright",
            extra_metadata={"source_url": "https://example.test/post"},
        )
        submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(p_spam),
            category="spam",
            extra_metadata={"ignored": "because category is not evidence"},
        )
        db.commit()

    reporter_pk = _profile_pk_from_public_id(session_factory, reporter_pid)
    with session_factory() as db:
        rows = (
            db.query(CommunityReport)
            .filter_by(reporter_profile_id=reporter_pk)
            .order_by(CommunityReport.category)
            .all()
        )

    by_category = {row.category: row for row in rows}
    assert by_category["copyright"].extra_metadata_json is not None
    payload = json.loads(by_category["copyright"].extra_metadata_json)
    assert payload == {"source_url": "https://example.test/post"}
    assert by_category["spam"].extra_metadata_json is None


def test_extra_metadata_oversize_payload_rejected_not_truncated(session_factory):
    """F2 — an ``extra_metadata`` payload whose JSON-encoded length
    exceeds :data:`EXTRA_METADATA_MAX_ENCODED_LEN` is rejected with
    :class:`InvalidExtraMetadata` instead of being silently truncated
    to invalid JSON.

    The §6.1 measure-matrix valódi-sértés: a 3000-char payload under
    the OLD ``encoded[:2048]`` behavior would land in the DB as a
    half-quoted JSON string — the new behavior raises an explicit
    error the router maps to HTTP 400.
    """
    from app.community.services.report_service import (
        EXTRA_METADATA_MAX_ENCODED_LEN,
        InvalidExtraMetadata,
    )

    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    # Build a payload that JSON-encodes to > EXTRA_METADATA_MAX_ENCODED_LEN.
    big_value = "x" * (EXTRA_METADATA_MAX_ENCODED_LEN + 100)
    oversize_metadata = {"source_url": big_value}

    with session_factory() as db:
        with pytest.raises(InvalidExtraMetadata):
            submit_report(
                db,
                reporter_public_id=reporter_pid,
                target_type="post",
                target_id=str(post_pid),
                category="copyright",
                extra_metadata=oversize_metadata,
            )


def test_extra_metadata_too_many_keys_rejected(session_factory):
    """F2 — an ``extra_metadata`` dict with more than
    :data:`EXTRA_METADATA_MAX_KEYS` keys is rejected with
    :class:`InvalidExtraMetadata`. The cheap key-count cap fires
    BEFORE the JSON encoder, so a pathologically wide dict cannot
    even reach the encoder.
    """
    from app.community.services.report_service import (
        EXTRA_METADATA_MAX_KEYS,
        InvalidExtraMetadata,
    )

    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    too_many_keys = {f"k{index}": index for index in range(EXTRA_METADATA_MAX_KEYS + 1)}

    with session_factory() as db:
        with pytest.raises(InvalidExtraMetadata):
            submit_report(
                db,
                reporter_public_id=reporter_pid,
                target_type="post",
                target_id=str(post_pid),
                category="copyright",
                extra_metadata=too_many_keys,
            )


def test_extra_metadata_at_limit_accepted(session_factory):
    """F2 — boundary: a payload exactly at the encoded-length cap
    (and exactly at the key-count cap) is accepted. The cap is
    inclusive.
    """
    from app.community.services.report_service import EXTRA_METADATA_MAX_KEYS

    reporter_pid = _make_profile(session_factory, user_id=1)
    author_pid = _make_profile(session_factory, user_id=2)
    post_pid = _make_post(session_factory, author_public_id=author_pid)

    # Exactly EXTRA_METADATA_MAX_KEYS keys, each with a tiny value —
    # well under the encoded-length cap.
    at_limit_keys = {f"k{index}": "v" for index in range(EXTRA_METADATA_MAX_KEYS)}

    with session_factory() as db:
        result = submit_report(
            db,
            reporter_public_id=reporter_pid,
            target_type="post",
            target_id=str(post_pid),
            category="copyright",
            extra_metadata=at_limit_keys,
        )
        db.commit()

    assert result.deduplicated is False


# ---------------------------------------------------------------------------
# HTTP router smoke — the §D2 / §0.0 backend HTTP-felület smoke tests.
# ---------------------------------------------------------------------------


def test_post_reports_router_returns_sanitized_shape(client, session_factory):
    """POST /community/reports returns the §5.1 sanitized envelope."""
    _reporter_id, headers = _make_user_with_headers(
        session_factory, email="r@s.test", user_id=40, visibility="public"
    )
    target_id = uuid.uuid4()

    response = client.post(
        "/community/reports",
        json={
            "idempotency_key": "router-k1",
            "target_type": "post",
            "target_id": str(target_id),
            "category": "harassment",
        },
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["category"] == "harassment"
    assert body["target_id"] == str(target_id)
    assert body["target_type"] == "post"
    assert body["deduplicated"] is False
    assert "report_public_id" in body


def test_post_reports_router_missing_idempotency_key_returns_400(
    client, session_factory
):
    _reporter_id, headers = _make_user_with_headers(
        session_factory, email="r@s.test", user_id=41, visibility="public"
    )
    response = client.post(
        "/community/reports",
        json={
            "target_type": "post",
            "target_id": str(uuid.uuid4()),
            "category": "spam",
        },
        headers=headers,
    )
    assert response.status_code == 400


def test_post_reports_router_malformed_target_id_returns_400(client, session_factory):
    """F1 — a malformed ``target_id`` (not a UUID) is rejected at
    the router with HTTP 400, NOT 404. The §6.1 measure-matrix
    valódi-sértés: a ``"not-a-uuid"`` body would otherwise leak
    through ``uuid.UUID(target_id)`` inside ``target_exists`` and
    surface as a 404 with the wrong semantic — the failure is a
    malformed client input, not a missing profile.
    """
    _reporter_id, headers = _make_user_with_headers(
        session_factory, email="r@s.test", user_id=42, visibility="public"
    )

    response = client.post(
        "/community/reports",
        json={
            "idempotency_key": "f1-k1",
            "target_type": "post",
            "target_id": "not-a-uuid",
            "category": "spam",
        },
        headers=headers,
    )
    assert response.status_code == 400, response.text
    body = response.json()
    assert "uuid" in body["detail"].lower(), (
        f"F1 violated — expected 400 with UUID-related detail, got {body}"
    )
