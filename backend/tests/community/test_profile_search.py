"""E09-R09 — Profile search router + repository acceptance tests.

Covers every cell of the brief §6 acceptance matrix and the §6.1
valódi-sértés próba:

* A1 — The endpoint accepts only ``q`` (handle prefix). There is
        no ``email`` / ``phone`` / ``location`` parameter — the
        SDD §5.2 contact-discovery class is forbidden.
* A2 — Blocked and PRIVATE profiles do NOT appear in the
        results. The §6.1 measure-matrix flips this by replacing
        the §D2 block-filter call with a no-op and asserts the
        A2 cell turns red.
* A3 — The candidate SELECT uses the ``ix_community_profiles_
        handle_normalized`` UNIQUE INDEX, not a full table scan.
        The repository exposes ``query_plan_uses_index`` for the
        test to assert against the live EXPLAIN plan.
* A4 — The endpoint is rate-limited (429 on the N+1-th request
        inside the window).
* A6 — Unicode normalisation collapses precomposed vs decomposed
        forms before the LIKE matches the index.

The fixtures mirror the Kör 7 / Kör 8 pattern: own ``FastAPI()`` +
``TestClient`` + alembic-upgraded file-backed SQLite. The
``profile_search_repository`` is mounted via ``routers.search``.
"""

from __future__ import annotations

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
from app.community.models.profile import CommunityProfile
from app.community.repositories import profile_search_repository as repo
from app.community.routers.search import reset_rate_limiters
from app.community.routers.search import router as search_router
from app.community.services.identity_service import (
    assign_handle,
    commit_with_uniqueness_check,
)
from app.community.models.safety_relationships import CommunityBlock
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
# Test app + session factory — own FastAPI() + TestClient + alembic-upgraded
# file-backed SQLite (the Kör 7 / Kör 8 pattern).
# ---------------------------------------------------------------------------


@pytest.fixture
def engine(tmp_path, monkeypatch) -> Iterator:
    db_path = tmp_path / "search.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    eng = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
    )
    enable_sqlite_foreign_keys(eng)
    try:
        yield eng
    finally:
        eng.dispose()


@pytest.fixture
def session_factory(engine) -> Iterator[sessionmaker[Session]]:
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        yield factory
    finally:
        # The ``engine`` fixture owns disposal.
        pass


@pytest.fixture
def app(session_factory) -> Iterator[FastAPI]:
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Profile-Search Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(search_router)
    reset_rate_limiters()
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
    reset_rate_limiters()
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


def _make_profile_with_handle_and_visibility(
    db: Session,
    *,
    user_id: int,
    handle: str,
    visibility: str = "public",
) -> CommunityProfile:
    """Create a ``community_profiles`` row with a chosen visibility.

    The handle is assigned via the Kör 3 ``assign_handle`` service
    so the normalized column is populated alongside ``handle_display``;
    the search index lives on the normalized form.
    """
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
    assign_handle(db, profile.id, handle, handle.lower())
    commit_with_uniqueness_check(db)
    db.refresh(profile)
    return profile


def _make_user_with_headers(
    session_factory,
    *,
    email: str,
    user_id: int,
    handle: str | None = None,
    visibility: str = "public",
) -> tuple[uuid.UUID, dict[str, str]]:
    """Insert a fresh user + profile + JWT pair for the search caller."""
    with session_factory() as db:
        kwargs: dict[str, object] = {"user_id": user_id, "visibility": visibility}
        if handle is not None:
            kwargs["handle"] = handle
        profile = _make_profile_with_handle_and_visibility(db, **kwargs)
        token = create_access_token(user_id)
        return profile.public_id, {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# A1 — no email / phone / location parameter is honored by the router
# ---------------------------------------------------------------------------


def test_a1_search_accepts_only_q_handle_prefix(client, session_factory):
    """A1 — the only search key is the handle prefix. Email / phone /
    location parameters are silently dropped by FastAPI's
    parameter binding (they are NOT in the signature).

    The Pydantic layer rejects unknown query params with 422,
    so a regression that adds an ``email=`` parameter would
    surface here as either:
      * a 200 with a different result set (the endpoint USES the
        param), or
      * a 200 still returning the q-filtered set (the param is
        silently dropped).
    Either is acceptable as long as the contact-style key does
    NOT narrow the result set. We assert that.
    """
    _, viewer_headers = _make_user_with_headers(
        session_factory,
        email="viewer@s.test",
        user_id=1,
        handle="viewer",
    )
    _make_user_with_headers(
        session_factory,
        email="alice@s.test",
        user_id=2,
        handle="alice",
    )

    forbidden_params = ("email", "phone", "location", "phone_number")
    for forbidden in forbidden_params:
        response = client.get(
            "/community/profiles/search",
            params={
                "q": "alice",
                forbidden: "anything-here",
            },
            headers=viewer_headers,
        )
        # Acceptable outcomes: 200 (param ignored, q still works)
        # or 422 (FastAPI rejected the unknown param). UNACCEPTABLE:
        # any response that narrows the result set based on the
        # forbidden key — but the q-only path is the same code
        # path either way.
        assert response.status_code in (200, 422), (
            f"A1 violated — unexpected status {response.status_code} for "
            f"forbidden param '{forbidden}': {response.text}"
        )
        if response.status_code == 200:
            body = response.json()
            assert len(body["public_ids"]) == 1, (
                f"A1 violated — '{forbidden}' param changed the result set"
            )


def test_a1_search_router_source_does_not_reference_contact_keys():
    """A1 — code-level: the search endpoint signature accepts only
    the documented parameters (``q`` / ``cursor`` / ``limit`` /
    ``current_user``). A regression that adds an ``email=`` /
    ``phone=`` parameter leaves a forbidden key in the
    signature — that's the cell we test.

    The test parses the source AST and inspects the
    ``search_profiles_endpoint`` function parameters, so docstring
    prose that mentions "email" (e.g. explaining the §A1
    invariant) does NOT trip the assertion.
    """
    import ast
    import inspect

    from app.community.routers import search as router_module

    source = inspect.getsource(router_module)
    tree = ast.parse(source)
    target_names = {
        "search_profiles_endpoint",
        "check_availability",  # not in this module but kept for completeness
    }
    forbidden_keys = {"email", "phone", "phone_number", "location", "contact", "address"}

    found_endpoints: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name in {"search_profiles_endpoint"}:
            found_endpoints.append(node.name)
            for arg in node.args.args + node.args.kwonlyargs:
                if arg.arg.lower() in forbidden_keys:
                    raise AssertionError(
                        f"A1 violated — search endpoint parameter '{arg.arg}' "
                        f"is on the forbidden contact-discovery list."
                    )
    assert found_endpoints, (
        "A1 setup error — search_profiles_endpoint not found via AST scan"
    )


# ---------------------------------------------------------------------------
# A2 — blocked and PRIVATE profiles are excluded
# ---------------------------------------------------------------------------


def test_a2_private_profile_excluded_from_results(client, session_factory):
    """A2 — a PRIVATE-visibility profile is invisible to search."""
    _, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    _make_user_with_headers(
        session_factory,
        email="alice@s.test",
        user_id=2,
        handle="alice-public",
        visibility="public",
    )
    _make_user_with_headers(
        session_factory,
        email="alice-priv@s.test",
        user_id=3,
        handle="alice-private",
        visibility="private",
    )

    response = client.get(
        "/community/profiles/search?q=alice",
        headers=viewer_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    public_ids = set(body["public_ids"])
    assert len(public_ids) == 1, f"A2 violated — got {public_ids}"


def test_a2_followers_visibility_profile_kept(client, session_factory):
    """A2 — a FOLLOWERS-visibility profile IS searchable (the §5.4
    SDD-invariáns: only PRIVATE is hidden). A regression to
    "FOLLOWERS too" would silently shrink the discoverable set.
    """
    _, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    _make_user_with_headers(
        session_factory,
        email="alice@s.test",
        user_id=2,
        handle="alice-followers",
        visibility="followers",
    )

    response = client.get(
        "/community/profiles/search?q=alice",
        headers=viewer_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["public_ids"]) == 1


def test_a2_blocked_profile_excluded_from_results(client, session_factory):
    """A2 — a profile blocked in either direction does not appear."""
    viewer_pid, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    blocked_pid, _ = _make_user_with_headers(
        session_factory, email="blocked@s.test", user_id=2, handle="blocked-bob"
    )

    # Establish a block edge (viewer → blocked-bob) directly via
    # the ORM row.
    with session_factory() as db:
        viewer_pk = (
            db.query(CommunityProfile).filter_by(public_id=viewer_pid).one().id
        )
        blocked_pk = (
            db.query(CommunityProfile).filter_by(public_id=blocked_pid).one().id
        )
        db.add(
            CommunityBlock(
                blocker_profile_id=viewer_pk,
                blocked_profile_id=blocked_pk,
            )
        )
        db.commit()

    response = client.get(
        "/community/profiles/search?q=blocked",
        headers=viewer_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert str(blocked_pid) not in body["public_ids"], (
        "A2 violated — blocked profile appeared in search results"
    )


# ---------------------------------------------------------------------------
# A3 — index-based query plan (no full table scan)
# ---------------------------------------------------------------------------


def test_a3_query_plan_uses_handle_normalized_index(session_factory):
    """A3 — the candidate SELECT plans against the
    ``handle_normalized`` UNIQUE INDEX, not a full table scan.

    The repository exposes :func:`query_plan_uses_index` so the
    assertion does not depend on raw EXPLAIN-text shape (the
    SQLite ``EXPLAIN QUERY PLAN`` output references the index
    name; PostgreSQL would emit a different format but the same
    predicate holds).
    """
    _make_user_with_headers(
        session_factory, email="seed@s.test", user_id=1, handle="seed"
    )
    with session_factory() as db:
        assert repo.query_plan_uses_index(db, query="ali"), (
            "A3 violated — search SELECT does not use the handle_normalized "
            "index; a table scan would DoS the search endpoint at scale."
        )


def test_a3_query_plan_index_present_in_schema(engine):
    """A3 — the schema has the UNIQUE INDEX the query plan relies on.

    Same precedent as
    ``test_unique_index_is_on_normalized_not_display``: a regression
    that drops the migration's ``op.create_index`` would leave the
    planner without a usable index and the previous test would
    pass-by-accident (SQLite might still pick the column on its
    own for small tables).
    """
    from sqlalchemy import inspect

    insp = inspect(engine)
    indexes = insp.get_indexes("community_profiles")
    matched = [
        idx
        for idx in indexes
        if idx.get("column_names") == ["handle_normalized"] and idx.get("unique")
    ]
    assert matched, (
        "A3 violated — unique index on community_profiles.handle_normalized "
        "is missing; A3 cannot be enforced."
    )


# ---------------------------------------------------------------------------
# A4 — rate limit
# ---------------------------------------------------------------------------


def test_a4_rate_limit_blocks_burst_above_max(client, session_factory):
    """A4 — the N+1-th request inside the 60-second window returns 429.

    The fixture resets the limiter per test (the
    ``reset_rate_limiters`` call in the ``client`` fixture), so
    we drive the full burst fresh.
    """
    _, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )

    accepted = 0
    throttled = 0
    for _ in range(65):
        response = client.get(
            "/community/profiles/search",
            params={"q": "anything"},
            headers=viewer_headers,
        )
        if response.status_code == 200:
            accepted += 1
        elif response.status_code == 429:
            throttled += 1
    # The test does not pin the exact burst boundary (60/60/N)
    # because rate-limit buckets can be off-by-one across FastAPI's
    # ``TestClient`` connection pool; the property is "the burst is
    # bounded". 65 > 60, so at least one 429 must land.
    assert throttled >= 1, (
        f"A4 violated — no 429 observed in 65 requests "
        f"(accepted={accepted}, throttled={throttled})"
    )


def test_a4_rate_limit_resets_on_window_pass(client, session_factory):
    """A4 — after the limiter resets, the next request succeeds.

    We patch the limiter's clock so the test does not have to
    sleep for a real minute; the property is "the window slides",
    not "the wall clock advanced".
    """
    import time as _time

    from app.community.routers import search as router_module

    _, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )

    fake_now = {"t": 1_000_000.0}

    def _fake_time():
        return fake_now["t"]

    router_module._search_limiter._now = _fake_time  # type: ignore[attr-defined]
    try:
        # Burn through the quota — the 61st request returns 429.
        last_status = None
        for _ in range(70):
            response = client.get(
                "/community/profiles/search",
                params={"q": "anything"},
                headers=viewer_headers,
            )
            last_status = response.status_code
        assert last_status == 429, (
            f"A4 violated — expected 429 after burst, got {last_status}"
        )

        # Advance the clock past the window.
        fake_now["t"] += 120.0

        response = client.get(
            "/community/profiles/search",
            params={"q": "anything"},
            headers=viewer_headers,
        )
        assert response.status_code == 200, response.text
    finally:
        router_module._search_limiter._now = _time.monotonic  # type: ignore[attr-defined]


# ---------------------------------------------------------------------------
# A6 — Unicode normalisation
# ---------------------------------------------------------------------------


def test_a6_unicode_precomposed_vs_decomposed_match(client, session_factory):
    """A6 — a profile claimed with the precomposed 'é' is matched by
    a query with the decomposed 'e' + combining acute, and vice
    versa. The NFKC + casefold collapse is the A6 invariant."""
    _, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    # The handle is normalised server-side at claim time — both
    # forms collapse to the same canonical "café".
    _make_user_with_headers(
        session_factory,
        email="cafe@s.test",
        user_id=2,
        handle="café",  # precomposed
    )

    decomposed_query = "café"  # 'e' + combining acute
    precomposed_query = "café"

    response_pre = client.get(
        "/community/profiles/search",
        params={"q": precomposed_query},
        headers=viewer_headers,
    )
    response_decomp = client.get(
        "/community/profiles/search",
        params={"q": decomposed_query},
        headers=viewer_headers,
    )
    assert response_pre.status_code == 200
    assert response_decomp.status_code == 200
    body_pre = response_pre.json()
    body_decomp = response_decomp.json()
    assert body_pre["public_ids"] == body_decomp["public_ids"], (
        f"A6 violated — precomposed vs decomposed queries returned "
        f"different sets: {body_pre['public_ids']} vs {body_decomp['public_ids']}"
    )
    assert len(body_pre["public_ids"]) == 1


def test_a6_casefold_equivalence(client, session_factory):
    """A6 — uppercase / mixed-case queries match a lowercase claim."""
    _, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    _make_user_with_headers(
        session_factory,
        email="alice@s.test",
        user_id=2,
        handle="alice",
    )

    for variant in ("ALICE", "Alice", "alice"):
        response = client.get(
            "/community/profiles/search",
            params={"q": variant},
            headers=viewer_headers,
        )
        assert response.status_code == 200
        body = response.json()
        assert len(body["public_ids"]) == 1, (
            f"A6 violated — case variant '{variant}' returned "
            f"{body['public_ids']}"
        )


# ---------------------------------------------------------------------------
# Valódi-sértés próba — §D2 invariant: removing the block-filter call
# must turn A2 red.
# ---------------------------------------------------------------------------


def test_valodi_sertes_a2_block_filter_required(client, session_factory, monkeypatch):
    """§6.1 valódi-sértés — patch the repository so the page-level
    block-filter is a no-op. The A2 cell MUST turn red: the blocked
    profile appears in the results.
    """
    viewer_pid, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    blocked_pid, _ = _make_user_with_headers(
        session_factory, email="blocked@s.test", user_id=2, handle="blocked-bob"
    )

    with session_factory() as db:
        viewer_pk = (
            db.query(CommunityProfile).filter_by(public_id=viewer_pid).one().id
        )
        blocked_pk = (
            db.query(CommunityProfile).filter_by(public_id=blocked_pid).one().id
        )
        db.add(
            CommunityBlock(
                blocker_profile_id=viewer_pk,
                blocked_profile_id=blocked_pk,
            )
        )
        db.commit()

    real_filter = repo.filter_public_ids_against_viewer_blocks

    def _passthrough(db, *, viewer_profile_id, public_ids):
        return list(public_ids)

    monkeypatch.setattr(
        repo, "filter_public_ids_against_viewer_blocks", _passthrough
    )
    try:
        response = client.get(
            "/community/profiles/search?q=blocked",
            headers=viewer_headers,
        )
        assert response.status_code == 200
        body = response.json()
        assert str(blocked_pid) in body["public_ids"], (
            "§6.1 valódi-sértés failed — the blocked profile was STILL filtered "
            "even after the page-level block-filter was patched out. The A2 "
            "cell would NOT turn red; the regression would slip through."
        )
    finally:
        monkeypatch.setattr(
            repo, "filter_public_ids_against_viewer_blocks", real_filter
        )


# ---------------------------------------------------------------------------
# Concurrency stress — the §A2 sister case: two concurrent searches
# against the same viewer's block-set must NOT race-leak a blocked
# profile. Single-writer sanity, not a full threading test (the
# Kör 7 follow concurrency suite covers the block service's
# transactional seams).
# ---------------------------------------------------------------------------


def test_search_block_filter_integration_at_repository_level(session_factory):
    """A2 — repository-level: the §D2 page-level block-filter
    drops the blocked profile and keeps the benign one.

    The §6.1 valódi-sértés cell above exercises the same property
    via the HTTP router; this cell exercises it at the
    repository boundary so a regression that drifts the block
    filter from the helper to a parallel predicate in the
    repository would turn both cells red.

    Handles share a 3-char prefix so the search query (≥
    ``MIN_QUERY_LENGTH``) matches BOTH, and the block filter is
    the only thing that can distinguish them. A regression that
    drops the block-filter call would let the blocked profile
    through.
    """
    viewer_pid, _ = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, handle="viewer"
    )
    target_pid, _ = _make_user_with_headers(
        session_factory, email="blocked@s.test", user_id=2, handle="ben-block"
    )
    other_pid, _ = _make_user_with_headers(
        session_factory, email="benign@s.test", user_id=3, handle="ben-keep"
    )

    with session_factory() as db:
        viewer_pk = (
            db.query(CommunityProfile).filter_by(public_id=viewer_pid).one().id
        )
        target_pk = (
            db.query(CommunityProfile).filter_by(public_id=target_pid).one().id
        )
        db.add(
            CommunityBlock(
                blocker_profile_id=viewer_pk,
                blocked_profile_id=target_pk,
            )
        )
        db.commit()

    with session_factory() as db:
        page = repo.search_profiles(
            db,
            viewer_profile_id=viewer_pk,
            query="ben",
            cursor=None,
            limit=50,
        )
        results = set(page.public_ids)

    assert target_pid not in results, (
        "A2 violated — blocked profile leaked through the repository "
        "block-filter"
    )
    assert other_pid in results, (
        "A2 violated — benign profile was wrongly filtered"
    )
