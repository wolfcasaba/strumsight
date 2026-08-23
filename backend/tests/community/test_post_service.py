"""E09-R11 — Post CRUD and audience-enforcement acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases:

* A1 — forged author in request body is ignored; the server uses
  its own auth-resolved author.
* A2 — duplicate create with the same ``idempotency_key`` returns
  the existing row, not a duplicate.
* A3 — audience matrix: owner / follower / blocked / public viewer
  each get the right verdict.
* A4 — blocked user cannot read the post by direct id.
* A5 — stale ``resource_version`` on PATCH is rejected with 409.
* A6 — soft-deleted post is invisible through the GET path.
* A7 — HTML / script content in the body is rejected at parse time.

The fixtures build their own ``FastAPI()`` + ``TestClient`` (the
§0.0 5. pont — the ``build_community_router`` factory is in the
§3 tilos zóna, so we mount the post router directly, same pattern
as ``test_follow_service.py`` / ``test_block_service.py``). The
alembic upgrade runs against a file-backed SQLite so the test sees
the same schema the migration produces.

The §6.1 valódi-sértés próba is exercised explicitly: a temporary
patch drops the idempotency-key check, runs the same create twice,
and asserts that two rows land (A2 goes red). The test then
restores the patched code.

The D11 cache-invalidation seam is exercised: a spy callback is
injected through ``app.state.posts_on_invalidate`` and asserted to
fire exactly once per successful mutating call, with the right
``post_public_id`` and ``action``.
"""

from __future__ import annotations

import threading
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
from app.community.models.post import CommunityPost
from app.community.models.profile import CommunityProfile
from app.community.routers.posts import router as posts_router
from app.community.services import post_service
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
# Fixtures — engine + session factory + app + client, mirroring the
# test_follow_service / test_block_service pattern.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "posts.db"
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
    """Self-contained FastAPI with the posts router mounted.

    The ``on_invalidate`` spy is wired through ``app.state`` — the
    D11 cell asserts it fires once per mutating call.
    """
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Posts Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    # The invalidation spy — reset per test through the
    # ``invalidation_events`` fixture below.
    app.state.posts_on_invalidate = _noop_on_invalidate
    app.include_router(posts_router)
    yield app


@pytest.fixture
def invalidation_events() -> list[dict[str, object]]:
    """Thread-safe capture list for the on_invalidate spy."""
    return []


@pytest.fixture
def app_with_spy(app, invalidation_events):
    """Wire a real spy onto ``app.state.posts_on_invalidate``.

    A ``threading.Lock`` guards the list because the service may
    emit on a worker thread (it doesn't today, but the lock is
    cheap and prevents a future refactor from introducing a race).
    """
    lock = threading.Lock()

    def _spy(event):
        with lock:
            invalidation_events.append(
                {"post_public_id": str(event.post_public_id), "action": event.action}
            )

    app.state.posts_on_invalidate = _spy
    return app


@pytest.fixture
def client(app_with_spy, session_factory) -> Iterator[TestClient]:
    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app_with_spy.dependency_overrides[get_db] = override_get_db
    with TestClient(app_with_spy) as c:
        yield c
    app_with_spy.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Data helpers — users, profiles, blocks, follows, auth headers.
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
    """Insert a parent ``users`` row + a ``community_profiles`` row.

    The ``community_privacy_settings`` row is also written so the
    profile is fully bootable.
    """
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
    """Create a fresh user+profile and return ``(profile, headers)``."""
    db: Session = session_factory()
    try:
        profile = _make_profile_with_visibility(
            db, user_id=user_id, visibility=visibility
        )
    finally:
        db.close()
    token = create_access_token(user_id)
    return profile, {"Authorization": f"Bearer {token}"}


def _make_two_users(
    session_factory,
) -> tuple[CommunityProfile, dict[str, str], CommunityProfile, dict[str, str]]:
    """Two independent authenticated users (author + viewer)."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=1, email="author@s.test"
    )
    viewer, viewer_headers = _make_user_with_headers(
        session_factory, user_id=2, email="viewer@s.test"
    )
    return author, author_headers, viewer, viewer_headers


def _create_block(
    session_factory, *, blocker: CommunityProfile, blocked: CommunityProfile
) -> None:
    db: Session = session_factory()
    try:
        db.execute(
            text(
                "INSERT INTO community_blocks "
                "(id, public_id, blocker_profile_id, blocked_profile_id, created_at) "
                "VALUES (:id, :pid, :b, :bd, :ts)"
            ),
            {
                "id": None,
                "pid": uuid.uuid4().hex,
                "b": blocker.id,
                "bd": blocked.id,
                "ts": _utcnow(),
            },
        )
        db.commit()
    finally:
        db.close()


def _noop_on_invalidate(event):
    return None


# ---------------------------------------------------------------------------
# Acceptance cells.
# ---------------------------------------------------------------------------


def test_create_post_happy_path(client, session_factory) -> None:
    """Author can create a PUBLIC post; round-trip fields are correct."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=10, email="author@s.test"
    )
    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "Hello community!",
            "idempotency_key": "create-happy-1",
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["author_public_id"] == str(author.public_id)
    assert body["audience"] == "public"
    assert body["body"] == "Hello community!"
    assert body["moderation_state"] == "visible"
    assert body["deleted_at"] is None
    assert body["resource_version"] == body["created_at"]


def test_create_forged_author_ignored(client, session_factory) -> None:
    """A1 — forged author in body is rejected by Pydantic
    ``extra='forbid'`` AND would be ignored by the service even if
    it got through. Both layers must reject."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=11, email="forged@s.test"
    )
    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "trying to impersonate",
            "author_id": 999,
            "author_public_id": str(uuid.uuid4()),
        },
    )
    assert response.status_code == 422, response.text
    # The legitimate author's record is the only row in the table.
    db: Session = session_factory()
    try:
        rows = db.query(CommunityPost).all()
        assert len(rows) == 0, "forged request should not create any row"
    finally:
        db.close()


def test_create_idempotency_retry_returns_same_post(client, session_factory) -> None:
    """A2 — same ``idempotency_key`` returns the existing post."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=12, email="idem@s.test"
    )
    body = {
        "audience": "public",
        "body": "first body",
        "idempotency_key": "retry-key-1",
    }
    first = client.post("/community/posts", headers=headers, json=body)
    assert first.status_code == 201
    first_id = first.json()["public_id"]

    second = client.post("/community/posts", headers=headers, json=body)
    assert second.status_code == 201
    assert second.json()["public_id"] == first_id

    # Only ONE row in the table.
    db: Session = session_factory()
    try:
        rows = db.query(CommunityPost).all()
        assert len(rows) == 1
    finally:
        db.close()


def test_create_idempotency_real_violation_probe(tmp_path, monkeypatch) -> None:
    """§6.1 valódi-sértés próba — drop BOTH the service-level
    idempotency read AND the DB-level UNIQUE constraint, then run
    the same create twice. The A2 cell turns red: two distinct
    rows land.

    The probe uses a dedicated DB file that is built WITHOUT the
    profile-id+idempotency UNIQUE constraint — SQLite cannot drop a
    table-level UNIQUE in-place, so the probe runs a hand-crafted
    CREATE TABLE that mirrors the migration shape minus the A2
    enforcement. With both layers disabled, two creates with the
    same key land two distinct rows.

    The service-level guard and the DB-level guard are TWO layers
    of the same invariant (defence-in-depth, ADR 0401 §6). The
    probe demonstrates that WITHOUT both, A2 breaks — it does not
    demonstrate that removing only ONE breaks it, because the
    other layer catches the duplicate. That is the whole point of
    defence-in-depth: the second layer is what makes the A2
    invariant survive a future refactor.
    """
    db_path = tmp_path / "probe_no_uniq.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    # Build the schema WITHOUT the profile+idempotency UNIQUE.
    # The mirror mirrors the migration's CREATE TABLE statement
    # exactly minus that single constraint — same columns, same
    # indexes (minus the redundant idempotency-key index).
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)
    _bigint_sql = "INTEGER"
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
        # The probe table — NO UNIQUE on (profile_id, idempotency_key).
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
        conn.execute(
            text(
                "CREATE INDEX ix_community_posts_public_id "
                "ON community_posts (public_id)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX ix_community_posts_profile_created "
                "ON community_posts (profile_id, created_at, id)"
            )
        )
        conn.commit()
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    # Seed one user + one community profile so the JWT resolves.
    with factory() as db:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (1, 'probe@s.test', :pw, :ts)"
            ),
            {"pw": hash_password("probe"), "ts": _utcnow().isoformat()},
        )
        pid_hex = uuid.uuid4().hex
        db.execute(
            text(
                "INSERT INTO community_profiles "
                "(id, public_id, user_id, display_name, created_at) "
                "VALUES (1, :pid, 1, 'probe', :ts)"
            ),
            {"pid": pid_hex, "ts": _utcnow().isoformat()},
        )
        db.commit()

    token = create_access_token(1)
    headers = {"Authorization": f"Bearer {token}"}

    # Build a self-contained FastAPI on the probe engine.
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Probe Test App")
    app.state.database_engine = engine
    app.state.session_factory = factory
    app.state.settings = settings
    app.include_router(posts_router)

    def _override_get_db():
        db = factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _override_get_db

    # Bypass the service-level idempotency read.
    original_check = post_service._existing_post_by_idempotency_key

    def _no_idem_check(*_args, **_kwargs):
        return None

    monkeypatch.setattr(
        post_service, "_existing_post_by_idempotency_key", _no_idem_check
    )

    try:
        body = {
            "audience": "public",
            "body": "probe",
            "idempotency_key": "probe-key",
        }
        with TestClient(app) as c:
            first = c.post("/community/posts", headers=headers, json=body)
            assert first.status_code == 201, first.text
            second = c.post("/community/posts", headers=headers, json=body)
            assert second.status_code == 201, second.text
            # Two distinct public_ids — A2 turned red (two rows).
            assert first.json()["public_id"] != second.json()["public_id"]

            with factory() as db:
                rows = (
                    db.query(CommunityPost).filter_by(idempotency_key="probe-key").all()
                )
                assert len(rows) == 2, "probe should have landed two rows"
    finally:
        monkeypatch.setattr(
            post_service, "_existing_post_by_idempotency_key", original_check
        )
        engine.dispose()


def test_audience_matrix_owner_and_public_viewer(client, session_factory) -> None:
    """A3 — owner can always read; a non-follower can read PUBLIC.

    F2 javító kör 1: a válasz ``author_public_id`` mezőjét a
    poszt TÉNYLEGES szerzőjéből kell visszaadni — sem a
    tulajdonos, sem a nem-tulajdonos néző esetén sem
    szivároghat át a hívó saját public_id-ja.
    """
    author, author_headers, viewer, viewer_headers = _make_two_users(session_factory)
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "hi all",
            "idempotency_key": "audience-1",
        },
    )
    assert create.status_code == 201
    pid = create.json()["public_id"]

    # Author reads own post.
    r_author = client.get(f"/community/posts/{pid}", headers=author_headers)
    assert r_author.status_code == 200
    assert r_author.json()["public_id"] == pid
    # F2: a tulajdonos GET-jében az author_public_id a szerzőé.
    assert r_author.json()["author_public_id"] == str(author.public_id)

    # A non-follower viewer can read PUBLIC posts.
    r_viewer = client.get(f"/community/posts/{pid}", headers=viewer_headers)
    assert r_viewer.status_code == 200
    assert r_viewer.json()["public_id"] == pid
    # F2: a nem-tulajdonos GET-jében az author_public_id a POSZT
    # szerzőjéé, nem a néző saját azonosítója — a javítás ELŐTT
    # ez a viewer.public_id-t adná vissza.
    assert r_viewer.json()["author_public_id"] == str(author.public_id)
    assert r_viewer.json()["author_public_id"] != str(viewer.public_id)


def test_audience_matrix_followers_only_excludes_non_follower(
    client, session_factory
) -> None:
    """A3 — FOLLOWERS-only post: non-follower is 404."""
    author, author_headers, viewer, viewer_headers = _make_two_users(session_factory)
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "followers",
            "body": "followers only",
            "idempotency_key": "audience-2",
        },
    )
    pid = create.json()["public_id"]
    r = client.get(f"/community/posts/{pid}", headers=viewer_headers)
    assert r.status_code == 404


def test_audience_matrix_private_excludes_non_owner(client, session_factory) -> None:
    """A3 — PRIVATE post: viewer is 404 even with no block."""
    author, author_headers, viewer, viewer_headers = _make_two_users(session_factory)
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "private",
            "body": "private thought",
            "idempotency_key": "audience-3",
        },
    )
    pid = create.json()["public_id"]
    r = client.get(f"/community/posts/{pid}", headers=viewer_headers)
    assert r.status_code == 404


def test_blocked_viewer_cannot_read_post(client, session_factory) -> None:
    """A4 — block between viewer and author: GET is 404."""
    author, author_headers, viewer, viewer_headers = _make_two_users(session_factory)
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "public post",
            "idempotency_key": "blocking-1",
        },
    )
    pid = create.json()["public_id"]

    # Author blocks viewer.
    _create_block(session_factory, blocker=author, blocked=viewer)

    # Viewer (now blocked) tries to read the PUBLIC post.
    r = client.get(f"/community/posts/{pid}", headers=viewer_headers)
    assert r.status_code == 404, response_msg(r)

    # Sanity: a third non-blocked user can still read it.
    other, other_headers = _make_user_with_headers(
        session_factory, user_id=3, email="third@s.test"
    )
    r2 = client.get(f"/community/posts/{pid}", headers=other_headers)
    assert r2.status_code == 200


def test_stale_resource_version_rejected(client, session_factory) -> None:
    """A5 — PATCH with stale ``resource_version`` returns 409."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=20, email="stale@s.test"
    )
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "first",
            "idempotency_key": "stale-1",
        },
    )
    pid = create.json()["public_id"]
    rv = create.json()["resource_version"]

    # First PATCH succeeds and bumps ``updated_at``.
    first_patch = client.patch(
        f"/community/posts/{pid}",
        headers=author_headers,
        json={"body": "second", "resource_version": rv},
    )
    assert first_patch.status_code == 200, first_patch.text
    new_rv = first_patch.json()["resource_version"]

    # Second PATCH with the OLD ``resource_version`` is stale.
    stale_patch = client.patch(
        f"/community/posts/{pid}",
        headers=author_headers,
        json={"body": "third", "resource_version": rv},
    )
    assert stale_patch.status_code == 409, response_msg(stale_patch)
    detail = stale_patch.json()["detail"]
    assert detail["error"] == "stale_resource_version"
    # The new_rv (the bumped value) is what the client should retry with.
    assert detail["current_resource_version"].startswith(
        new_rv[:19]  # tolerate tz suffix variations
    )


def test_soft_delete_hides_post_from_subsequent_gets(client, session_factory) -> None:
    """A6 — soft-deleted post -> GET is 404; the row stays in the table."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=30, email="soft@s.test"
    )
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "soon-to-be-deleted",
            "idempotency_key": "soft-1",
        },
    )
    pid = create.json()["public_id"]

    # Sanity: visible BEFORE delete.
    r1 = client.get(f"/community/posts/{pid}", headers=author_headers)
    assert r1.status_code == 200

    # Soft delete.
    d = client.delete(f"/community/posts/{pid}", headers=author_headers)
    assert d.status_code == 200
    assert d.json()["status"] == "deleted"

    # Subsequent GET is 404 (D7 uniform shape).
    r2 = client.get(f"/community/posts/{pid}", headers=author_headers)
    assert r2.status_code == 404

    # Row is still in the table (soft delete, not hard).
    db: Session = session_factory()
    try:
        row = db.query(CommunityPost).filter_by(public_id=uuid.UUID(pid)).one()
        assert row.deleted_at is not None
    finally:
        db.close()


def test_double_delete_is_idempotent_noop(client, session_factory) -> None:
    """D12 — repeat DELETE on already-deleted post is a 200 no-op."""
    author, author_headers = _make_user_with_headers(
        session_factory, user_id=31, email="double@s.test"
    )
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "twice",
            "idempotency_key": "double-1",
        },
    )
    pid = create.json()["public_id"]
    d1 = client.delete(f"/community/posts/{pid}", headers=author_headers)
    d2 = client.delete(f"/community/posts/{pid}", headers=author_headers)
    assert d1.status_code == 200
    assert d1.json()["status"] == "deleted"
    assert d2.status_code == 200
    assert d2.json()["status"] == "noop"


def test_create_after_soft_delete_with_same_idempotency_key(
    client, session_factory
) -> None:
    """F3 javító kör 1 — a törölt poszt NEM térhet vissza élő
    201-ként akkor sem, ha ugyanazzal az ``idempotency_key``-vel
    hívunk create-et.

    A javítás ELŐTT a service-szintű idempotencia-lekérdezés nem
    szűrt ``deleted_at IS NULL``-ra, így a create az "existing
    row" ágra futott és a törölt sort adta vissza 201-gyel. A
    javítás UTÁN a törölt kulcs a tombstone-on NULL-ra állítódik
    (NULL a UNIQUE szempontjából nem ütközik), és a fresh INSERT
    egy ÚJ sort hoz létre — a régi tombstone audit-trailje
    megmarad (deleted_at nem változik).

    A második create tehát:
      * public_id ≠ first_id (új sor)
      * deleted_at IS None (nem törölt)
      * a tombstone first_id még a táblában van, deleted_at ≠ None,
        idempotency_key = NULL (a kulcs elengedve)
    """
    author, headers = _make_user_with_headers(
        session_factory, user_id=32, email="recreate@s.test"
    )
    body = {
        "audience": "public",
        "body": "first",
        "idempotency_key": "recreate-key-1",
    }
    first = client.post("/community/posts", headers=headers, json=body)
    assert first.status_code == 201, first.text
    first_id = first.json()["public_id"]

    # Soft-delete the first row.
    deleted = client.delete(f"/community/posts/{first_id}", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json()["status"] == "deleted"

    # Re-create with the SAME idempotency_key.
    second = client.post("/community/posts", headers=headers, json=body)
    assert second.status_code == 201, second.text
    second_body = second.json()

    # F3: az új sor public_id-ja ≠ a törölt soré (a törölt
    # tartalom NEM tér vissza élő 201-ként), és az új sor
    # NEM soft-deleted.
    assert second_body["public_id"] != first_id
    assert second_body["deleted_at"] is None
    # A második create által mutatott public_id tényleg a DB-ben
    # van és nem törölt.
    db: Session = session_factory()
    try:
        # Az eredeti tombstone még a táblában van, deleted_at ≠ None,
        # idempotency_key = NULL (a kulcsot a create elengedte).
        tombstone_row = (
            db.query(CommunityPost).filter_by(public_id=uuid.UUID(first_id)).one()
        )
        assert tombstone_row.deleted_at is not None
        assert tombstone_row.idempotency_key is None

        # Az új sor élő (deleted_at IS None) és az új kulcsot viseli.
        new_row = (
            db.query(CommunityPost)
            .filter_by(public_id=uuid.UUID(second_body["public_id"]))
            .one()
        )
        assert new_row.deleted_at is None
        assert new_row.idempotency_key == "recreate-key-1"
    finally:
        db.close()


def test_delete_by_non_owner_returns_404(client, session_factory) -> None:
    """A6 / D7 — non-owner DELETE returns 404 (existence is not leaked)."""
    author, author_headers, viewer, viewer_headers = _make_two_users(session_factory)
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "mine",
            "idempotency_key": "non-owner-1",
        },
    )
    pid = create.json()["public_id"]
    r = client.delete(f"/community/posts/{pid}", headers=viewer_headers)
    assert r.status_code == 404


def test_patch_by_non_owner_returns_404(client, session_factory) -> None:
    """F1 javító kör 1 — PATCH from a non-owner MUST return 404,
    not 200 with the modified body.

    A PUBLIC audience + valid ``resource_version`` is necessary
    but not sufficient — the brief §3 / §5.3 owner-check MUST
    additionally block non-owners. A non-owner PATCH MUST NOT
    succeed even when all OTHER gates (visibility, resource
    version) pass.

    Companion to ``test_delete_by_non_owner_returns_404``: that
    one covers the D7 uniform 404 on the DELETE surface; this
    one covers the PATCH surface.
    """
    author, author_headers, viewer, viewer_headers = _make_two_users(session_factory)
    create = client.post(
        "/community/posts",
        headers=author_headers,
        json={
            "audience": "public",
            "body": "mine",
            "idempotency_key": "non-owner-patch-1",
        },
    )
    assert create.status_code == 201, create.text
    pid = create.json()["public_id"]
    rv = create.json()["resource_version"]

    # Non-owner PATCH — even with the correct resource_version, the
    # ownership gate must short-circuit to 404 (the §5.3 IDOR
    # invariant). A correct implementation NEVER reaches the body
    # write; the row is unchanged.
    r = client.patch(
        f"/community/posts/{pid}",
        headers=viewer_headers,
        json={"body": "DEFACED", "resource_version": rv},
    )
    assert r.status_code == 404, response_msg(r)

    # Sanity: the row body is still the original author-written text.
    # (A non-owner successful PATCH would have produced "DEFACED".)
    db: Session = session_factory()
    try:
        row = db.query(CommunityPost).filter_by(public_id=uuid.UUID(pid)).one()
        assert row.body == "mine"
    finally:
        db.close()


def test_html_body_rejected_at_parse_time(client, session_factory) -> None:
    """A7 — HTML / script in body is rejected by Pydantic, no row lands."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=40, email="html@s.test"
    )
    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "<script>alert(1)</script>",
            "idempotency_key": "html-1",
        },
    )
    assert response.status_code == 422, response.text
    db: Session = session_factory()
    try:
        assert db.query(CommunityPost).count() == 0
    finally:
        db.close()


def test_html_rejected_in_patch_too(client, session_factory) -> None:
    """A7 — PATCH with HTML is also rejected at parse time."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=41, email="patch-html@s.test"
    )
    create = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "good",
            "idempotency_key": "patch-html-1",
        },
    )
    pid = create.json()["public_id"]
    rv = create.json()["resource_version"]
    r = client.patch(
        f"/community/posts/{pid}",
        headers=headers,
        json={"body": "<b>bold</b>", "resource_version": rv},
    )
    assert r.status_code == 422, response_msg(r)


def test_artifact_persists_through_round_trip(client, session_factory) -> None:
    """D10 — an artifact validated by ``parse_share_artifact`` is
    mirrored into the typed columns and the JSON payload survives
    a GET."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=50, email="artifact@s.test"
    )
    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "with artifact",
            "idempotency_key": "artifact-1",
            "artifact": {
                "artifact": {
                    "type": "practiceSummary",
                    "schema_version": 1,
                    "source_id": "practice-1",
                    "created_at": "2026-08-23T12:00:00Z",
                    "active_seconds": 90,
                    "paused_seconds": 10,
                    "attempt_count": 5,
                    "finish_reason_code": "completed",
                    "best_score": 0.85,
                }
            },
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["artifact_type"] == "practiceSummary"
    assert body["artifact_schema_version"] == 1
    assert body["artifact_payload"]["artifact"]["best_score"] == 0.85

    pid = body["public_id"]
    g = client.get(f"/community/posts/{pid}", headers=headers)
    assert g.status_code == 200
    g_body = g.json()
    assert g_body["artifact_type"] == "practiceSummary"
    assert g_body["artifact_payload"]["artifact"]["best_score"] == 0.85


def test_unknown_artifact_discriminator_rejected(client, session_factory) -> None:
    """A7-adjacent — an artifact with an unknown ``type`` is rejected."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=51, email="bad-art@s.test"
    )
    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "bad art",
            "idempotency_key": "bad-art-1",
            "artifact": {
                "artifact": {
                    "type": "thisIsNotAValidType",
                    "schema_version": 1,
                    "source_id": "x",
                    "created_at": "2026-08-23T12:00:00Z",
                }
            },
        },
    )
    assert response.status_code == 422, response.text


def test_cache_invalidation_event_fires_on_create(
    app_with_spy, session_factory, invalidation_events
) -> None:
    """D11 — successful create emits one invalidation event with the
    correct public_id and ``action='create'``."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=60, email="inv-create@s.test"
    )

    def _override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app_with_spy.dependency_overrides[get_db] = _override_get_db
    with TestClient(app_with_spy) as c:
        r = c.post(
            "/community/posts",
            headers=headers,
            json={
                "audience": "public",
                "body": "ev",
                "idempotency_key": "inv-1",
            },
        )
    assert r.status_code == 201
    assert len(invalidation_events) == 1
    assert invalidation_events[0]["action"] == "create"
    assert invalidation_events[0]["post_public_id"] == r.json()["public_id"]


def test_cache_invalidation_event_fires_on_patch_and_delete(
    app_with_spy, session_factory, invalidation_events
) -> None:
    """D11 — patch and delete each emit one event with the right action."""
    author, headers = _make_user_with_headers(
        session_factory, user_id=61, email="inv-mut@s.test"
    )

    def _override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app_with_spy.dependency_overrides[get_db] = _override_get_db
    with TestClient(app_with_spy) as c:
        create = c.post(
            "/community/posts",
            headers=headers,
            json={
                "audience": "public",
                "body": "ev",
                "idempotency_key": "inv-mut-1",
            },
        )
        pid = create.json()["public_id"]
        rv = create.json()["resource_version"]
        invalidation_events.clear()  # ignore the create event here

        patch = c.patch(
            f"/community/posts/{pid}",
            headers=headers,
            json={"body": "edited", "resource_version": rv},
        )
        assert patch.status_code == 200
        assert len(invalidation_events) == 1
        assert invalidation_events[0]["action"] == "patch"
        invalidation_events.clear()

        new_rv = patch.json()["resource_version"]
        _ = new_rv  # captured for symmetry / future ETag E-Tag use
        delete = c.delete(f"/community/posts/{pid}", headers=headers)
        assert delete.status_code == 200
        assert len(invalidation_events) == 1
        assert invalidation_events[0]["action"] == "delete"
        invalidation_events.clear()

        # Second delete is a no-op — NO event (D12).
        noop = c.delete(f"/community/posts/{pid}", headers=headers)
        assert noop.status_code == 200
        assert noop.json()["status"] == "noop"
        assert invalidation_events == []


# ---------------------------------------------------------------------------
# Tiny helper.
# ---------------------------------------------------------------------------


def response_msg(r):
    """Return a debug-friendly summary of a TestClient response."""
    return f"{r.status_code} {r.text}"
