"""E09-R17 — Bookmark service acceptance tests (ADR 0408).

Covers every cell of the brief §6 acceptance matrix that maps to
the BACKEND half of the round (A1 / A2 / A3). The Flutter-side
acceptance cells (A4 / A5 / A6 / A7) live in
``test/features/community/application/import_share_artifact_test.dart``.

* **A1** — set is idempotent on the same ``(post, viewer)`` pair
  (one row, no duplicates); remove is idempotent (the second
  call returns ``noop`` and never inflates a negative count).
* **A2** — the bookmark count is NEVER projected onto the public
  ``PostOut``. The §5.2 invariant: the count is private to the
  viewer / post pair. The test asserts the GET response on a
  freshly-bookmarked post has no bookmark-count field and the
  same field set as a never-bookmarked post.
* **A3** — soft-deleted (and moderation-removed) post bookmark
  is safe: the list endpoint emits a tombstone element
  (``is_tombstone=true``), not a null deref / crash. The row
  stays (the user explicitly asked to save it); the post side
  is gone.

The §6.1 valódi-sértés próba is exercised explicitly: the A1
probe drops BOTH the service-level guard AND the DB-level
``UNIQUE(post_id, profile_id)`` constraint, runs the same set
twice, and asserts that two distinct rows land. The probe
demonstrates the §6.1 measure-matrix cell.

The fixtures mirror the existing ``test_post_service.py`` and
``test_reaction_service.py`` pattern (own ``FastAPI()`` + own
``TestClient``), with the bookmarks router mounted directly. The
production ``build_community_router`` factory is not touched
(the Kör 7–8 / §3 tilos-zóna discipline).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.bookmark import CommunityBookmark
from app.community.models.profile import CommunityProfile
from app.community.routers.bookmarks import (
    BookmarkPostNotFound,
    BookmarkViewerNotFound,
    remove_bookmark,
    set_bookmark,
)
from app.community.routers.bookmarks import (
    router as bookmarks_router,
)
from app.community.routers.posts import router as posts_router
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
# Fixtures — engine + session factory + app + client.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "bookmarks.db"
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
def app(session_factory) -> Iterator[FastAPI]:
    """Self-contained FastAPI with the bookmarks + posts routers mounted.

    Both routers are mounted so the A2 cell can fetch a post via
    ``/community/posts/{id}`` and assert the response carries no
    bookmark-count field. The bookmarks router is the
    service-shape's HTTP surface; the posts router is the public
    projection the A2 measure-matrix inspects.
    """
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Bookmarks Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(bookmarks_router)
    app.include_router(posts_router)
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
# Data helpers — users, profiles, auth headers, posts.
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


def _make_profile_with_visibility(
    db: Session,
    *,
    user_id: int,
    display_name: str | None = None,
    visibility: str = "public",
) -> CommunityProfile:
    _insert_user(db, user_id, f"u{user_id}@s.test")
    db.commit()
    profile = CommunityProfile(user_id=user_id)
    if display_name is not None:
        profile.display_name = display_name
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


def _make_user_with_headers(
    session_factory,
    *,
    user_id: int,
    email: str,
    visibility: str = "public",
) -> tuple[CommunityProfile, dict[str, str]]:
    db: Session = session_factory()
    try:
        profile = _make_profile_with_visibility(
            db, user_id=user_id, visibility=visibility
        )
    finally:
        db.close()
    token = create_access_token(user_id)
    return profile, {"Authorization": f"Bearer {token}"}


def _create_post(
    client: TestClient,
    session_factory,
    *,
    author: CommunityProfile,
    author_headers: dict[str, str],
    body: str = "hello community",
    idempotency_key: str = "post-1",
) -> str:
    """Create a post via the posts router and return the public_id."""
    response = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": body,
            "idempotency_key": idempotency_key,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["public_id"]


def _soft_delete_post(
    session_factory,
    *,
    post_public_id: str,
) -> None:
    """Mark the post as soft-deleted at the SQL level.

    Goes around the router (which is owner-scoped, and the A3
    tombstone path is exactly the same regardless of who deleted
    the post — the bookmark is on the viewer's list, the post
    is the joined row).
    """
    db: Session = session_factory()
    try:
        db.execute(
            text("UPDATE community_posts SET deleted_at = :ts WHERE public_id = :pid"),
            {"ts": _utcnow().isoformat(), "pid": uuid.UUID(post_public_id).hex},
        )
        db.commit()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Acceptance cells.
# ---------------------------------------------------------------------------


def test_set_bookmark_creates_one_row(client, session_factory) -> None:
    """A1 — first set creates exactly one row."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=10, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=11, email="viewer@s.test"
    )
    pid = _create_post(
        client, session_factory, author=author, author_headers=author_headers
    )

    response = client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "ok"
    assert body["post_public_id"] == pid

    # Exactly one row.
    db: Session = session_factory()
    try:
        rows = db.query(CommunityBookmark).all()
        assert len(rows) == 1
    finally:
        db.close()


def test_set_bookmark_idempotent_no_second_row(client, session_factory) -> None:
    """A1 — second set with the same (post, viewer) does NOT create
    a second row. The §6 A1 idempotency invariant."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=12, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=13, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="idem-1",
    )

    # Two set calls.
    r1 = client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
    r2 = client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
    assert r1.status_code == 200, r1.text
    assert r2.status_code == 200, r2.text
    assert r1.json()["status"] == "ok"
    assert r2.json()["status"] == "ok"

    db: Session = session_factory()
    try:
        rows = db.query(CommunityBookmark).all()
        assert len(rows) == 1, "second set must NOT create a second row"
    finally:
        db.close()


def test_remove_bookmark_idempotent_noop_on_second(client, session_factory) -> None:
    """A1 — second remove returns ``noop`` without raising and
    does not create a negative-count condition (the row is
    simply absent)."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=14, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=15, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="remove-1",
    )

    # Set, then remove twice.
    client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
    r1 = client.delete(f"/community/bookmarks/{pid}", headers=viewer_headers)
    r2 = client.delete(f"/community/bookmarks/{pid}", headers=viewer_headers)
    assert r1.status_code == 200
    assert r1.json()["status"] == "ok"
    assert r2.status_code == 200
    assert r2.json()["status"] == "noop"

    db: Session = session_factory()
    try:
        rows = db.query(CommunityBookmark).all()
        assert len(rows) == 0
    finally:
        db.close()


def test_post_out_does_not_carry_bookmark_count(client, session_factory) -> None:
    """A2 — the public ``PostOut`` projection never carries a
    bookmark-count field, even when the viewer has bookmarked
    the post. The §5.2 invariant: the bookmark count is
    private to the viewer / post pair."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=16, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=17, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="count-1",
    )

    # Sanity: the post is visible BEFORE the bookmark.
    r0 = client.get(f"/community/posts/{pid}", headers=viewer_headers)
    assert r0.status_code == 200, r0.text
    fields_before = sorted(r0.json().keys())
    # The §5.2 invariant: no bookmark-count field of any name.
    assert "bookmark_count" not in fields_before
    assert "bookmarkCount" not in fields_before

    # The viewer bookmarks the post.
    set_resp = client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
    assert set_resp.status_code == 200

    # Re-fetch the post: the field set MUST be identical. The
    # §5.2 invariant is structural — adding a bookmark does not
    # inject a count into the public projection.
    r1 = client.get(f"/community/posts/{pid}", headers=viewer_headers)
    assert r1.status_code == 200, r1.text
    fields_after = sorted(r1.json().keys())
    assert fields_before == fields_after
    assert "bookmark_count" not in fields_after
    assert "bookmarkCount" not in fields_after


def test_list_bookmarks_emits_tombstone_for_soft_deleted_post(
    client, session_factory
) -> None:
    """A3 — a soft-deleted post's bookmark appears in the caller's
    list as a tombstone element (``is_tombstone=true``). The
    bookmark row is NOT removed — the user explicitly asked to
    save it. The Flutter ``BookmarksScreen`` reads the flag and
    renders the "no longer available" state.

    The probe does NOT crash on the missing post; the row stays
    in the table; the next cursor advances past it."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=18, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=19, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="tomb-1",
    )

    # Bookmark, then soft-delete the post.
    client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
    _soft_delete_post(session_factory, post_public_id=pid)

    # The list endpoint must NOT crash; it must return ONE row
    # with ``is_tombstone=True`` and the same post_public_id.
    response = client.get("/community/bookmarks", headers=viewer_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) == 1, "soft-delete must NOT remove the bookmark"
    item = body["items"][0]
    assert item["post_public_id"] == pid
    assert item["is_tombstone"] is True

    # The bookmark row is still in the table.
    db: Session = session_factory()
    try:
        rows = db.query(CommunityBookmark).all()
        assert len(rows) == 1
    finally:
        db.close()


def test_set_bookmark_on_missing_post_returns_404(client, session_factory) -> None:
    """A3-adjacent — set on a non-existent post is 404 (the
    §5.3 IDOR / D7 uniform 404). The bookmark row does not land."""
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=20, email="viewer@s.test"
    )
    fake_pid = uuid.uuid4()
    response = client.post(f"/community/bookmarks/{fake_pid}", headers=viewer_headers)
    assert response.status_code == 404, response.text

    db: Session = session_factory()
    try:
        rows = db.query(CommunityBookmark).all()
        assert len(rows) == 0
    finally:
        db.close()


def test_service_set_bookmark_raises_for_missing_viewer(
    session_factory,
) -> None:
    """A1-adjacent — the service-level guard raises
    :class:`BookmarkViewerNotFound` when the JWT-resolved
    viewer has no community profile. The router layer turns
    this into a 404."""
    db: Session = session_factory()
    try:
        with pytest.raises(BookmarkViewerNotFound):
            set_bookmark(
                db,
                viewer_public_id=uuid.uuid4(),
                post_public_id=uuid.uuid4(),
                now=_utcnow(),
            )
    finally:
        db.close()


def test_service_set_bookmark_raises_for_invisible_post(
    client, session_factory
) -> None:
    """A1-adjacent — the service-level guard raises
    :class:`BookmarkPostNotFound` for a soft-deleted post."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=21, email="author@s.test"
    )
    viewer, _viewer_headers = _make_user_with_headers(
        session_factory, user_id=22, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="invis-1",
    )
    _soft_delete_post(session_factory, post_public_id=pid)

    db: Session = session_factory()
    try:
        with pytest.raises(BookmarkPostNotFound):
            set_bookmark(
                db,
                viewer_public_id=viewer.public_id,
                post_public_id=uuid.UUID(pid),
                now=_utcnow(),
            )
    finally:
        db.close()


def test_service_remove_bookmark_returns_false_when_absent(
    client, session_factory
) -> None:
    """A1-adjacent — remove on a never-bookmarked post is a no-op
    (``False``), not an exception. The §6 A3 invariant."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=23, email="author@s.test"
    )
    viewer, _viewer_headers = _make_user_with_headers(
        session_factory, user_id=24, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="absent-1",
    )

    db: Session = session_factory()
    try:
        result = remove_bookmark(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=uuid.UUID(pid),
        )
        assert result is False
    finally:
        db.close()


def test_list_bookmarks_isolated_per_viewer(client, session_factory) -> None:
    """A1-adjacent — the list is ALWAYS caller-scoped. Viewer A's
    bookmark is not visible to viewer B. The §5.2 invariant:
    the bookmark is private to the viewer / post pair."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=25, email="author@s.test"
    )
    viewer_a, viewer_a_headers = _make_user_with_headers(
        session_factory, user_id=26, email="a@s.test"
    )
    viewer_b, viewer_b_headers = _make_user_with_headers(
        session_factory, user_id=27, email="b@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="iso-1",
    )

    # Only viewer A bookmarks.
    client.post(f"/community/bookmarks/{pid}", headers=viewer_a_headers)

    # Viewer A's list: ONE row.
    a_list = client.get("/community/bookmarks", headers=viewer_a_headers)
    assert a_list.status_code == 200
    assert len(a_list.json()["items"]) == 1

    # Viewer B's list: ZERO rows.
    b_list = client.get("/community/bookmarks", headers=viewer_b_headers)
    assert b_list.status_code == 200
    assert b_list.json()["items"] == []

    # Sanity — the DB has exactly ONE row total.
    db: Session = session_factory()
    try:
        rows = db.query(CommunityBookmark).all()
        assert len(rows) == 1
    finally:
        db.close()


def test_list_bookmarks_cursor_pagination_round_trip(client, session_factory) -> None:
    """A3-adjacent — the cursor keyset paginates the list forward
    and never skips / duplicates. The D4 cursor shape."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=28, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=29, email="viewer@s.test"
    )
    # Three posts, three bookmarks.
    pids: list[str] = []
    for i in range(3):
        pid = _create_post(
            client,
            session_factory,
            author=author,
            author_headers=author_headers,
            idempotency_key=f"page-{i}",
        )
        pids.append(pid)
        client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)
        # Force a distinct ``created_at`` by sleeping a millisecond.
        import time

        time.sleep(0.005)

    # Page size 2: first page returns 2, the cursor advances to the
    # last row.
    r1 = client.get("/community/bookmarks?limit=2", headers=viewer_headers)
    assert r1.status_code == 200, r1.text
    body1 = r1.json()
    assert len(body1["items"]) == 2
    assert body1["next_cursor"] is not None

    # Second page: the last remaining row.
    r2 = client.get(
        f"/community/bookmarks?limit=2&cursor={body1['next_cursor']}",
        headers=viewer_headers,
    )
    assert r2.status_code == 200, r2.text
    body2 = r2.json()
    assert len(body2["items"]) == 1
    assert body2["next_cursor"] is None

    # No duplicates across pages.
    ids1 = [item["bookmark_id"] for item in body1["items"]]
    ids2 = [item["bookmark_id"] for item in body2["items"]]
    assert set(ids1).isdisjoint(set(ids2))


def test_list_bookmarks_tampered_cursor_starts_from_top(
    client, session_factory
) -> None:
    """A3-adjacent — a tampered cursor decodes to ``None`` and
    the list restarts from the top. The §6.1 valódi-sértés
    probe the brief calls out explicitly: the list never
    crashes on a bad cursor."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=30, email="author@s.test"
    )
    _viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=31, email="viewer@s.test"
    )
    pid = _create_post(
        client,
        session_factory,
        author=author,
        author_headers=author_headers,
        idempotency_key="tamper-1",
    )
    client.post(f"/community/bookmarks/{pid}", headers=viewer_headers)

    # A tampered cursor — the list endpoint must NOT crash.
    response = client.get(
        "/community/bookmarks?cursor=not-a-real-cursor",
        headers=viewer_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) == 1
    assert body["next_cursor"] is None


# ---------------------------------------------------------------------------
# §6.1 valódi-sértés próba — A1 (idempotency) real-violation probe.
# ---------------------------------------------------------------------------


def test_a1_idempotency_real_violation_probe(
    client, session_factory, tmp_path, monkeypatch
) -> None:
    """§6.1 valódi-sértés próba — drop BOTH the service-level
    no-op guard AND the DB-level UNIQUE constraint, then run
    the same ``set_bookmark`` twice. The A1 cell turns red:
    two distinct rows land.

    The probe uses a dedicated DB file built WITHOUT the
    ``(post_id, profile_id)`` UNIQUE constraint — SQLite cannot
    drop a table-level UNIQUE in-place, so the probe runs a
    hand-crafted CREATE TABLE that mirrors the migration shape
    minus that single constraint. With both layers disabled,
    two ``set_bookmark`` calls land two distinct rows.

    The service-level guard and the DB-level guard are TWO
    layers of the same invariant (defence-in-depth, the
    reaction-service §6.1 probe precedent). The probe
    demonstrates that WITHOUT both, A1 breaks — it does not
    demonstrate that removing only ONE breaks it, because the
    other layer catches the duplicate. That is the whole point
    of defence-in-depth: the second layer is what makes the
    A1 invariant survive a future refactor.
    """
    db_path = tmp_path / "probe_no_uniq_bookmarks.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    # Build the schema WITHOUT the (post_id, profile_id) UNIQUE
    # constraint. The mirror mirrors the migration's CREATE TABLE
    # statement exactly minus that single constraint.
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)
    with engine.connect() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    email TEXT NOT NULL,
                    hashed_password TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE community_profiles (
                    id INTEGER PRIMARY KEY,
                    public_id CHAR(32) NOT NULL UNIQUE,
                    user_id INTEGER NOT NULL UNIQUE,
                    display_name TEXT,
                    created_at TEXT NOT NULL
                )
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE community_privacy_settings (
                    id INTEGER PRIMARY KEY,
                    public_id CHAR(32) NOT NULL UNIQUE,
                    profile_id INTEGER NOT NULL UNIQUE,
                    updated_at TEXT NOT NULL,
                    visibility TEXT NOT NULL DEFAULT 'followers',
                    audience_default TEXT NOT NULL DEFAULT 'followers'
                )
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE community_posts (
                    id INTEGER PRIMARY KEY,
                    public_id CHAR(32) NOT NULL UNIQUE,
                    profile_id INTEGER NOT NULL,
                    audience VARCHAR NOT NULL DEFAULT 'public',
                    club_id INTEGER,
                    body VARCHAR(5000) NOT NULL,
                    artifact_type VARCHAR,
                    artifact_schema_version INTEGER,
                    artifact_payload TEXT,
                    moderation_state VARCHAR NOT NULL DEFAULT 'visible',
                    idempotency_key VARCHAR,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT
                )
                """
            )
        )
        # The probe table — NO UNIQUE on (post_id, profile_id).
        conn.execute(
            text(
                """
                CREATE TABLE community_bookmarks (
                    id INTEGER PRIMARY KEY,
                    post_id INTEGER NOT NULL,
                    profile_id INTEGER NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
        )
        conn.execute(
            text(
                "CREATE INDEX ix_community_bookmarks_profile_created "
                "ON community_bookmarks (profile_id, created_at, id)"
            )
        )
        conn.commit()
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    # Seed two users (author + viewer) and a single post.
    with factory() as db:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (1, 'probe-author@s.test', :pw, :ts), "
                "(2, 'probe-viewer@s.test', :pw, :ts)"
            ),
            {"pw": hash_password("probe"), "ts": _utcnow().isoformat()},
        )
        author_pid_hex = uuid.uuid4().hex
        viewer_pid_hex = uuid.uuid4().hex
        db.execute(
            text(
                "INSERT INTO community_profiles "
                "(id, public_id, user_id, display_name, created_at) "
                "VALUES (1, :apid, 1, 'probe-author', :ts), "
                "(2, :vpid, 2, 'probe-viewer', :ts)"
            ),
            {
                "apid": author_pid_hex,
                "vpid": viewer_pid_hex,
                "ts": _utcnow().isoformat(),
            },
        )
        post_pid_hex = uuid.uuid4().hex
        db.execute(
            text(
                "INSERT INTO community_posts "
                "(id, public_id, profile_id, audience, body, "
                "moderation_state, created_at, updated_at) "
                "VALUES (1, :ppid, 1, 'public', 'probe', 'visible', :ts, :ts)"
            ),
            {"ppid": post_pid_hex, "ts": _utcnow().isoformat()},
        )
        db.commit()

    # Bypass the service-level existing-bookmark guard.
    from app.community.routers import bookmarks as bookmarks_module

    original_existing = bookmarks_module._existing_bookmark

    def _no_existing(*_args, **_kwargs):
        return None

    monkeypatch.setattr(bookmarks_module, "_existing_bookmark", _no_existing)

    try:
        viewer_public = uuid.UUID(hex=viewer_pid_hex)
        post_public = uuid.UUID(hex=post_pid_hex)
        with factory() as db:
            set_bookmark(
                db,
                viewer_public_id=viewer_public,
                post_public_id=post_public,
                now=_utcnow(),
            )
            db.commit()
        with factory() as db:
            set_bookmark(
                db,
                viewer_public_id=viewer_public,
                post_public_id=post_public,
                now=_utcnow(),
            )
            db.commit()

        # Two distinct rows landed — A1 turned red.
        with factory() as db:
            rows = db.execute(text("SELECT id FROM community_bookmarks")).fetchall()
            assert len(rows) == 2, "probe should have landed two rows — A1 broken"
    finally:
        monkeypatch.setattr(bookmarks_module, "_existing_bookmark", original_existing)
        engine.dispose()


# ---------------------------------------------------------------------------
# Tiny helper.
# ---------------------------------------------------------------------------


def response_msg(r):
    """Return a debug-friendly summary of a TestClient response."""
    return f"{r.status_code} {r.text}"
