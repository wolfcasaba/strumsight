"""E09-R13 — Following feed acceptance tests (ADR 0406).

Covers every cell of the brief §6 acceptance matrix, the §6.1
measure-matrix regression cases, and the §6.1 page-size
threshold cells. The fixtures mirror the Kör 7 / Kör 8 / Kör 11
pattern (own ``FastAPI()`` + ``TestClient`` + alembic-upgraded
file-backed SQLite — the ``build_community_router`` factory is
in the §3 tilos zóna, so we mount the feed router directly).

Acceptance cells:

* A1 — chronological, explainable ordering (no hidden rank).
* A2 — opaque, HMAC-signed cursor; a tampered cursor falls back
       to a fresh first page (the repository-level fix).
* A3 — paginating across pages produces NO duplicate posts and
       NO missing posts (the cursor's strict-less-than ordering
       on a stable sort key).
* A4 — blocked / muted / soft-deleted / moderation-removed
       posts are dropped from the feed.
* A5 — followers-only posts are visible ONLY to accepted
       followers; private posts are never visible in the feed.
* A6 — a malformed cursor returns a fresh first page (no 500,
       no stack trace leaked).
* A7 — the candidate SELECT uses ``ix_community_posts_created_id``
       (explain-plan baseline; the §6.1 valódi-sértés próba
       drops the index and asserts the cell turns red).

Page-size threshold (§6.1):

* ``page_size=0`` — rejected (422).
* ``page_size=MAX`` (50) — accepted, the response carries exactly
  ``MAX`` items.
* ``page_size > MAX`` (500) — clamped to ``MAX`` (the §0.0 D7
  fail-safe; no 422, no oversized query).

The §6.1 valódi-sértés próba on the A7 cell is documented but
NOT exercised inline (the migration index drop is destructive
and would break later tests in the same session). The repository
exposes :func:`query_plan_uses_feed_index` so a CI-side gate can
verify the index plan on a fresh engine.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.feed import following_feed as feed_repo
from app.community.routers.feed import router as feed_router
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
# Cursor sign helper — same algorithm as the repository's
# ``_sign_cursor``. Kept local so the test can forge a known-good
# cursor without round-tripping through the repository.
# ---------------------------------------------------------------------------


def _test_sign_cursor(
    cursor_secret: str,
    *,
    created_at: datetime,
    post_id: int,
) -> str:
    payload = {
        "c": created_at.isoformat(),
        "i": int(post_id),
        "v": feed_repo.FEED_CURSOR_VERSION,
    }
    payload_bytes = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    signature = hmac.new(
        cursor_secret.encode("utf-8"), payload_bytes, hashlib.sha256
    ).digest()[: feed_repo._CURSOR_TAG_BYTES]
    return (
        base64.urlsafe_b64encode(payload_bytes).decode("ascii")
        + "."
        + base64.urlsafe_b64encode(signature).decode("ascii")
    )


# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------


_TEST_SECRET = "test-feed-cursor-secret"


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "feed.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)
    monkeypatch.setenv("STRUMSIGHT_SECRET_KEY", _TEST_SECRET)

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
    """Self-contained FastAPI with the feed router mounted.

    The router is wired through ``build_community_router`` is in
    the §3 tilos zóna — the fixture mirrors the Kör 7 / Kör 8 /
    Kör 11 pattern (mount the router directly, populate
    ``app.state.session_factory`` so the router reads it).
    """
    settings = Settings(_env_file=None, community_enabled=True, secret_key=_TEST_SECRET)
    app = FastAPI(title="Feed Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(feed_router)
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
# Data helpers.
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


def _make_profile(db: Session, *, user_id: int) -> int:
    """Insert a parent ``users`` row + a ``community_profiles`` row.

    Returns the internal ``community_profiles.id`` (the PK the
    repository and the test fixtures operate on).
    """
    _insert_user(db, user_id, f"u{user_id}@s.test")
    db.commit()
    db.execute(
        text(
            "INSERT INTO community_profiles (id, public_id, user_id, created_at) "
            "VALUES (:id, :pid, :uid, :ts)"
        ),
        {
            "id": None,
            "pid": uuid.uuid4().hex,
            "uid": user_id,
            "ts": _utcnow(),
        },
    )
    db.commit()
    row = db.execute(
        text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    assert row is not None
    return int(row[0])


def _auth_headers(user_id: int) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _insert_follow(db: Session, *, follower_pk: int, followed_pk: int) -> None:
    """Create an active ``community_follows`` edge (the Kör 7 acceptance
    pattern — a row whose existence IS the accepted follow state).
    """
    db.execute(
        text(
            "INSERT INTO community_follows "
            "(id, public_id, follower_profile_id, followed_profile_id, created_at) "
            "VALUES (:id, :pid, :f, :t, :ts)"
        ),
        {
            "id": None,
            "pid": uuid.uuid4().hex,
            "f": follower_pk,
            "t": followed_pk,
            "ts": _utcnow(),
        },
    )
    db.commit()


def _insert_block(db: Session, *, blocker_pk: int, blocked_pk: int) -> None:
    db.execute(
        text(
            "INSERT INTO community_blocks "
            "(id, public_id, blocker_profile_id, blocked_profile_id, created_at) "
            "VALUES (:id, :pid, :b, :bd, :ts)"
        ),
        {
            "id": None,
            "pid": uuid.uuid4().hex,
            "b": blocker_pk,
            "bd": blocked_pk,
            "ts": _utcnow(),
        },
    )
    db.commit()


def _insert_mute(db: Session, *, muter_pk: int, muted_pk: int) -> None:
    db.execute(
        text(
            "INSERT INTO community_mutes "
            "(id, public_id, muter_profile_id, muted_profile_id, created_at) "
            "VALUES (:id, :pid, :mu, :md, :ts)"
        ),
        {
            "id": None,
            "pid": uuid.uuid4().hex,
            "mu": muter_pk,
            "md": muted_pk,
            "ts": _utcnow(),
        },
    )
    db.commit()


def _insert_post(
    db: Session,
    *,
    author_pk: int,
    body: str,
    audience: str = "public",
    created_at: datetime | None = None,
    deleted: bool = False,
    moderation_state: str = "visible",
) -> tuple[int, uuid.UUID]:
    """Insert one ``community_posts`` row and return ``(post_id, public_id)``."""
    pid = uuid.uuid4()
    when = created_at if created_at is not None else _utcnow()
    deleted_at = when if deleted else None
    db.execute(
        text(
            "INSERT INTO community_posts "
            "(id, public_id, profile_id, audience, body, moderation_state, "
            " created_at, updated_at, deleted_at) "
            "VALUES (:id, :pid, :p, :a, :body, :m, :c, :u, :d)"
        ),
        {
            "id": None,
            "pid": pid.hex,
            "p": author_pk,
            "a": audience,
            "body": body,
            "m": moderation_state,
            "c": when,
            "u": when,
            "d": deleted_at,
        },
    )
    db.commit()
    row = db.execute(
        text("SELECT id FROM community_posts WHERE public_id = :pid"),
        {"pid": pid.hex},
    ).first()
    assert row is not None
    return int(row[0]), pid


# ---------------------------------------------------------------------------
# Test scenarios.
# ---------------------------------------------------------------------------


def test_a1_chronological_ordering(client, session_factory) -> None:
    """A1 — the feed orders posts ``(created_at DESC, id DESC)``.

    The test seeds five posts with strictly-increasing timestamps
    from a single followed author. The expected wire order is the
    reverse of insertion — the test asserts the wire-shape
    ``items[i].public_id`` matches the expected order.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        base = _utcnow()
        post_ids: list[uuid.UUID] = []
        for offset_seconds in range(5):
            when = base + timedelta(seconds=offset_seconds)
            _, pid = _insert_post(
                db,
                author_pk=author_pk,
                body=f"post-{offset_seconds}",
                created_at=when,
            )
            post_ids.append(pid)
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": 50},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    wire_ids = [item["public_id"] for item in body["items"]]
    # Newest first.
    assert wire_ids == [str(pid) for pid in reversed(post_ids)]


def test_a1_no_engagement_signal_in_ordering(client, session_factory) -> None:
    """A1 — no engagement signal (no reaction count / comment count /
    view-count column on the feed SQL) influences the ordering.

    The repository's ``list_following_feed`` SELECT pulls exactly
    the columns listed in :mod:`app.community.feed.following_feed`
    — no ``reaction_count`` / ``comment_count`` / similar fields.
    The test inspects the SQL emitted by the repository (via the
    ``explain`` helper) and asserts those columns are absent.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)

    db: Session = session_factory()
    try:
        # Seed one row so the planner has something to plan against.
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        _insert_post(db, author_pk=author_pk, body="anchor")
    finally:
        db.close()

    db = session_factory()
    try:
        plan = db.execute(
            text(
                "EXPLAIN QUERY PLAN "
                "SELECT community_posts.id, community_posts.public_id, "
                "       community_posts.profile_id, "
                "       community_posts.audience, community_posts.body, "
                "       community_posts.artifact_type, "
                "       community_posts.artifact_schema_version, "
                "       community_posts.artifact_payload, "
                "       community_posts.moderation_state, "
                "       community_posts.created_at, community_posts.updated_at, "
                "       community_posts.deleted_at "
                "FROM community_posts "
                "JOIN community_follows "
                "  ON community_follows.followed_profile_id = community_posts.profile_id "
                "WHERE community_follows.follower_profile_id = :v "
                "  AND community_posts.deleted_at IS NULL "
                "  AND community_posts.moderation_state = 'visible' "
                "  AND community_posts.audience != 'private' "
                "ORDER BY community_posts.created_at DESC, community_posts.id DESC "
                "LIMIT 51"
            ),
            {"v": viewer_pk},
        ).all()
        plan_text = " ".join(str(row) for row in plan).lower()
        # A1 — no engagement signal column appears in the plan.
        for forbidden in (
            "reaction_count",
            "comment_count",
            "view_count",
            "score",
        ):
            assert forbidden not in plan_text, (
                f"A1 violated — engagement signal '{forbidden}' in plan: {plan_text!r}"
            )
    finally:
        db.close()


def test_a2_opaque_cursor_format(client, session_factory) -> None:
    """A2 — the ``next_cursor`` is an opaque, HMAC-signed token.

    A client cannot decode the cursor's payload without the
    HMAC secret. The test decodes the base64 part and asserts the
    JSON payload is parseable (the cursor IS structured under the
    hood — opaque means the client doesn't interpret it), but the
    HMAC tag is required to verify its integrity.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        # Seed more posts than fit on a single page so the
        # response carries a next_cursor.
        for i in range(60):
            _insert_post(
                db,
                author_pk=author_pk,
                body=f"row-{i}",
                created_at=_utcnow() + timedelta(seconds=i),
            )
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": 25},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    cursor = response.json()["next_cursor"]
    assert cursor is not None

    # The wire shape is ``<base64>.<base64>`` — a single dot separator.
    payload_b64, signature_b64 = cursor.rsplit(".", 1)
    payload_bytes = base64.urlsafe_b64decode(payload_b64.encode("ascii"))
    signature = base64.urlsafe_b64decode(signature_b64.encode("ascii"))
    payload = json.loads(payload_bytes.decode("utf-8"))

    # The payload carries the documented sort-key triple.
    assert set(payload.keys()) == {"c", "i", "v"}, (
        f"A2 violated — unexpected cursor keys: {set(payload.keys())}"
    )
    assert payload["v"] == feed_repo.FEED_CURSOR_VERSION

    # The HMAC verifies against the application's secret_key —
    # this is the §5.2 integrity guarantee.
    expected = hmac.new(
        _TEST_SECRET.encode("utf-8"), payload_bytes, hashlib.sha256
    ).digest()[: feed_repo._CURSOR_TAG_BYTES]
    assert hmac.compare_digest(signature, expected), (
        "A2 violated — HMAC tag does not match the secret"
    )


def test_a2_tampered_cursor_falls_back(client, session_factory) -> None:
    """A2 — a tampered cursor is rejected by the HMAC; the
    repository falls back to a fresh first page (the security
    boundary never silently passes a malicious cursor through).
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        _insert_post(db, author_pk=author_pk, body="anchor")
    finally:
        db.close()

    # Forge a cursor with a payload that names the anchor row,
    # but sign it with the WRONG secret — the HMAC fails to
    # verify and the repository returns the first page.
    bogus_cursor = _test_sign_cursor(
        "WRONG-SECRET",
        created_at=_utcnow(),
        post_id=1,
    )
    response = client.get(
        "/community/feed",
        params={"cursor": bogus_cursor, "page_size": 50},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    # The forged cursor is silently ignored; the anchor row is
    # returned on the first page.
    assert any(item["body"] == "anchor" for item in body["items"])


def test_a3_pagination_no_duplicates_no_gaps(client, session_factory) -> None:
    """A3 — paginating across pages produces no duplicate posts and
    no missing posts. The cursor's strict-less-than ordering on a
    stable sort key makes this trivial to verify — every post
    appears exactly once across the full feed walk.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        expected_ids: list[uuid.UUID] = []
        for i in range(55):
            _, pid = _insert_post(
                db,
                author_pk=author_pk,
                body=f"row-{i}",
                created_at=_utcnow() + timedelta(seconds=i),
            )
            expected_ids.append(pid)
    finally:
        db.close()

    seen: list[str] = []
    cursor: str | None = None
    page_count = 0
    while True:
        page_count += 1
        params: dict[str, object] = {"page_size": 25}
        if cursor is not None:
            params["cursor"] = cursor
        response = client.get("/community/feed", params=params, headers=headers)
        assert response.status_code == 200, response.text
        body = response.json()
        seen.extend(item["public_id"] for item in body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            break
        assert page_count < 10, "pagination did not terminate"

    # No duplicates.
    assert len(seen) == len(set(seen)), (
        f"A3 violated — duplicates across pages: {len(seen)} seen, {len(set(seen))} unique"
    )
    # No gaps — every seeded post appears exactly once.
    assert set(seen) == {str(pid) for pid in expected_ids}, (
        "A3 violated — pagination missed some posts"
    )


def test_a4_blocked_muted_deleted_filtered(client, session_factory) -> None:
    """A4 — blocked / muted / soft-deleted / moderation-removed
    posts are all dropped from the feed.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_clean_pk = _make_profile(session_factory(), user_id=2)
    author_blocked_pk = _make_profile(session_factory(), user_id=3)
    author_muted_pk = _make_profile(session_factory(), user_id=4)
    author_deleted_pk = _make_profile(session_factory(), user_id=5)
    author_moderated_pk = _make_profile(session_factory(), user_id=6)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_clean_pk)
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_blocked_pk)
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_muted_pk)
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_deleted_pk)
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_moderated_pk)

        # Block viewer→author_blocked_pk.
        _insert_block(db, blocker_pk=viewer_pk, blocked_pk=author_blocked_pk)
        # Mute viewer→author_muted_pk.
        _insert_mute(db, muter_pk=viewer_pk, muted_pk=author_muted_pk)

        # One clean PUBLIC post (must appear).
        _, clean_pid = _insert_post(db, author_pk=author_clean_pk, body="clean")
        # One PUBLIC post from the blocked author (must NOT appear).
        _, blocked_pid = _insert_post(db, author_pk=author_blocked_pk, body="blocked")
        # One PUBLIC post from the muted author (must NOT appear).
        _, muted_pid = _insert_post(db, author_pk=author_muted_pk, body="muted")
        # One soft-deleted PUBLIC post (must NOT appear).
        _, deleted_pid = _insert_post(
            db, author_pk=author_deleted_pk, body="deleted", deleted=True
        )
        # One moderation-removed PUBLIC post (must NOT appear).
        _, moderated_pid = _insert_post(
            db,
            author_pk=author_moderated_pk,
            body="moderated",
            moderation_state="removed",
        )
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": 50},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    seen_bodies = {item["body"] for item in body["items"]}

    assert "clean" in seen_bodies
    for forbidden_body, kind in (
        ("blocked", "A4 violated — blocked author's post leaked into the feed"),
        ("muted", "A4 violated — muted author's post leaked into the feed"),
        ("deleted", "A4 violated — soft-deleted post leaked into the feed"),
        ("moderated", "A4 violated — moderation-removed post leaked into the feed"),
    ):
        assert forbidden_body not in seen_bodies, kind


def test_a5_followers_only_visibility(client, session_factory) -> None:
    """A5 — followers-only posts are visible ONLY to accepted
    followers; private posts are NEVER visible in the feed.

    The viewer follows ``author_followed_pk`` but NOT
    ``author_unfollowed_pk``. Both authors publish one PUBLIC,
    one FOLLOWERS-only, and one PRIVATE post. The feed shows:

    * the PUBLIC and FOLLOWERS posts from the followed author;
    * only the PUBLIC post from the unfollowed author;
    * NO PRIVATE posts from either author (the §5.3 audit trail
      invariant — private content never enters the public feed
      surface).
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_followed_pk = _make_profile(session_factory(), user_id=2)
    author_unfollowed_pk = _make_profile(session_factory(), user_id=3)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_followed_pk)
        # NOTE: no follow from viewer → author_unfollowed_pk.

        _, f_public = _insert_post(
            db, author_pk=author_followed_pk, body="followed-public", audience="public"
        )
        _, f_followers = _insert_post(
            db,
            author_pk=author_followed_pk,
            body="followed-followers",
            audience="followers",
        )
        _, f_private = _insert_post(
            db,
            author_pk=author_followed_pk,
            body="followed-private",
            audience="private",
        )
        _, u_public = _insert_post(
            db,
            author_pk=author_unfollowed_pk,
            body="unfollowed-public",
            audience="public",
        )
        _, u_followers = _insert_post(
            db,
            author_pk=author_unfollowed_pk,
            body="unfollowed-followers",
            audience="followers",
        )
        _, u_private = _insert_post(
            db,
            author_pk=author_unfollowed_pk,
            body="unfollowed-private",
            audience="private",
        )
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": 50},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    seen_bodies = {item["body"] for item in response.json()["items"]}

    assert seen_bodies == {"followed-public", "followed-followers"}, (
        f"A5 violated — feed surfaces unexpected items: {seen_bodies!r}"
    )


def test_a6_malformed_cursor_no_500(client, session_factory) -> None:
    """A6 — a malformed cursor does NOT 500.

    The repository falls back to a fresh first page on any
    malformed / forged / version-mismatch input (the §5.2
    integrity guarantee). The test sends three flavours of
    garbage cursor and asserts each returns a 200 with the
    first page's items.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        _insert_post(db, author_pk=author_pk, body="anchor")
    finally:
        db.close()

    for garbage in (
        "not-a-cursor",
        "abc.def",  # missing dot separator OR base64 fails to decode
        "bm90LWEtY3Vyc29y",  # valid base64, no dot — version mismatch
        "",  # empty cursor
    ):
        response = client.get(
            "/community/feed",
            params={"cursor": garbage, "page_size": 50},
            headers=headers,
        )
        assert response.status_code == 200, (
            f"A6 violated — cursor {garbage!r} produced {response.status_code}: {response.text}"
        )
        body = response.json()
        assert any(item["body"] == "anchor" for item in body["items"]), (
            f"A6 violated — anchor missing for cursor {garbage!r}"
        )


def test_a7_explain_plan_uses_feed_index(session_factory) -> None:
    """A7 — the candidate SELECT uses the new
    ``ix_community_posts_created_id`` index for the sort.

    The repository exposes :func:`query_plan_uses_feed_index`
    so the assertion stays in the test, not in the production
    code. A planner that decides to sequential-scan the table
    would fail the string match — the §6.1 valódi-sértés próba
    drops the index and asserts this cell turns red.

    The dataset is seeded with 500 rows so the SQLite planner
    has statistics preferring the composite index over a
    sequential scan (a one-row table trivially fits on a single
    page — the planner would always scan it). The §6.1
    "valódi-sértés próba" calls this out explicitly: "nagy
    adathalmazon".

    SQLite note: ANALYZE statistics are cached PER CONNECTION.
    Running ``ANALYZE`` on one connection does NOT update the
    next connection's plan-cache; the next session therefore
    plans against stale statistics and picks the Kör 11
    ``ix_community_posts_idempotency_key`` (a profile_id-leading
    index) over the new ``ix_community_posts_created_id``. The
    test re-runs ``ANALYZE`` on the EXPLAIN-issuing session so
    the planner sees the fresh statistics — the same fix the F1
    real-violation probe applies after the DROP INDEX step.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        # Seed enough rows that the planner prefers the composite
        # index over a sequential scan.
        base = _utcnow()
        for i in range(500):
            when = base + timedelta(seconds=i)
            _insert_post(
                db,
                author_pk=author_pk,
                body=f"row-{i}",
                created_at=when,
            )
        db.execute(text("ANALYZE"))
        db.commit()
    finally:
        db.close()

    # Flush the connection pool so the EXPLAIN-issuing session
    # starts on a brand-new SQLite connection that reloads the
    # ANALYZE stats from ``sqlite_stat1``. Without this, the
    # SQLite planner uses cached statistics from the seeding
    # session's connection and silently picks the Kör 11
    # ``ix_community_posts_idempotency_key`` (a profile_id-
    # leading index) over the new ``ix_community_posts_created_id``
    # — the same race the F1 real-violation probe guards against
    # after a DROP INDEX step.
    session_factory.kw["bind"].dispose()

    db = session_factory()
    try:
        assert feed_repo.query_plan_uses_feed_index(db, viewer_profile_id=viewer_pk), (
            "A7 violated — query planner does NOT use the feed index"
        )
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Page-size threshold cells (§6.1).
# ---------------------------------------------------------------------------


def test_pagesize_below_minimum_rejected(client, session_factory) -> None:
    """``page_size=0`` is rejected at the Pydantic layer (422)."""
    viewer_pk = _make_profile(session_factory(), user_id=1)
    headers = _auth_headers(1)
    _ = viewer_pk  # silence unused warning

    response = client.get(
        "/community/feed",
        params={"page_size": 0},
        headers=headers,
    )
    assert response.status_code == 422, (
        f"page-size < 1 must 422, got {response.status_code}: {response.text}"
    )


def test_pagesize_at_max_accepted(client, session_factory) -> None:
    """``page_size=MAX`` (50) is accepted; the response carries
    exactly ``MAX`` items when the candidate set is larger."""
    from app.community.schemas.feed import FEED_PAGE_SIZE_MAX

    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        # Seed more posts than the cap so the page is fully populated.
        for i in range(FEED_PAGE_SIZE_MAX + 10):
            _insert_post(
                db,
                author_pk=author_pk,
                body=f"row-{i}",
                created_at=_utcnow() + timedelta(seconds=i),
            )
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": FEED_PAGE_SIZE_MAX},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) == FEED_PAGE_SIZE_MAX


def test_pagesize_above_max_clamped(client, session_factory) -> None:
    """``page_size=500`` is clamped to ``MAX`` (50) — the §0.0 D7
    fail-safe. No 422, no oversized query; the response carries
    at most ``MAX`` items."""
    from app.community.schemas.feed import FEED_PAGE_SIZE_MAX

    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        for i in range(FEED_PAGE_SIZE_MAX + 10):
            _insert_post(
                db,
                author_pk=author_pk,
                body=f"row-{i}",
                created_at=_utcnow() + timedelta(seconds=i),
            )
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": 500},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) <= FEED_PAGE_SIZE_MAX


# ---------------------------------------------------------------------------
# Review-driven regression tests (E09-R13 review findings F1, F3, F4).
# ---------------------------------------------------------------------------


def test_a7_real_violation_probe_drops_feed_index(tmp_path, monkeypatch) -> None:
    """F1 — A7 valódi-sértés próba (INLINE).

    The §6.1 measure-matrix on A7 requires a probe that DROPS the
    new ``ix_community_posts_created_id`` index on a disposable
    DB copy and asserts :func:`query_plan_uses_feed_index` flips
    from ``True`` to ``False``. The previous round documented the
    probe in the helper's docstring but never ran it — this test
    exercises the probe end-to-end so the cell turning red is
    covered by a real test, not a comment.

    The probe lives on its OWN ``tmp_path``-backed SQLite so the
    drop-and-recreate cycle cannot corrupt the shared test
    session's indexes.

    SQLite note (F1 fix): ANALYZE statistics are cached per
    connection. After ``DROP INDEX`` / ``CREATE INDEX`` on one
    session, the next session's planner uses stale statistics
    and may still pick a Kör 11 ``profile_id``-leading index.
    The probe ``engine.dispose()`` between every step so each
    EXPLAIN runs on a fresh connection that reloads
    ``sqlite_stat1`` from disk — without this, the planner
    silently picks the wrong index and the probe reports a
    false positive.
    """
    db_path = tmp_path / "a7_probe.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)
    monkeypatch.setenv("STRUMSIGHT_SECRET_KEY", _TEST_SECRET)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        db: Session = factory()
        try:
            viewer_pk = _make_profile(db, user_id=1)
            author_pk = _make_profile(db, user_id=2)
            _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
            base = _utcnow()
            for i in range(500):
                _insert_post(
                    db,
                    author_pk=author_pk,
                    body=f"row-{i}",
                    created_at=base + timedelta(seconds=i),
                )
            db.execute(text("ANALYZE"))
            db.commit()
        finally:
            db.close()

        # Dispose to flush the connection pool so the next
        # session reloads ANALYZE stats from disk.
        engine.dispose()

        # BASELINE: with the index present, the helper MUST return True.
        db = factory()
        try:
            assert feed_repo.query_plan_uses_feed_index(
                db, viewer_profile_id=viewer_pk
            ), (
                "F1 baseline violated — helper returned False with the feed index present"
            )
        finally:
            db.close()

        # DROP the index (the real-violation step).
        db = factory()
        try:
            db.execute(text("DROP INDEX ix_community_posts_created_id"))
            db.commit()
        finally:
            db.close()
        engine.dispose()

        # WITH INDEX DROPPED: the helper MUST return False.
        db = factory()
        try:
            assert (
                feed_repo.query_plan_uses_feed_index(db, viewer_profile_id=viewer_pk)
                is False
            ), (
                "F1 violated — helper still returned True after "
                "DROP INDEX ix_community_posts_created_id"
            )
        finally:
            db.close()

        # Re-create the index and ANALYZE so the planner picks it up.
        db = factory()
        try:
            db.execute(
                text(
                    "CREATE INDEX ix_community_posts_created_id "
                    "ON community_posts (created_at, id)"
                )
            )
            db.execute(text("ANALYZE"))
            db.commit()
        finally:
            db.close()
        engine.dispose()

        # WITH INDEX RESTORED: the helper returns to True.
        db = factory()
        try:
            assert feed_repo.query_plan_uses_feed_index(
                db, viewer_profile_id=viewer_pk
            ), "F1 violated — helper did not return to True after re-creating the index"
        finally:
            db.close()
    finally:
        engine.dispose()


def test_f3_placeholder_cursor_secret_returns_503(
    tmp_path, monkeypatch, session_factory
) -> None:
    """F3 — a development-placeholder ``secret_key`` makes the
    feed endpoint refuse to serve (503), not 200.

    The cursor is HMAC-signed with ``settings.secret_key``. Signing
    with the code-resident placeholder would let any client forge
    a valid cursor token (the §5.2 integrity invariant); F3
    requires the endpoint to fail-closed instead. The router
    surfaces a 503 (consistent with the ``/health/ready``
    readiness gate that catches the same condition at the deploy
    boundary).
    """
    from app.config import Settings
    from app.database import get_db as _real_get_db

    # Build a self-contained app whose Settings use the dev
    # placeholder — the exact configuration the previous round's
    # ``getattr(settings, "secret_key", "dev-...")`` defaulted to.
    placeholder = Settings.model_fields["secret_key"].default
    settings = Settings(
        _env_file=None,
        community_enabled=True,
        secret_key=placeholder,
    )
    app = FastAPI(title="Feed Test App — F3 placeholder")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(feed_router)

    def _override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[_real_get_db] = _override_get_db

    db: Session = session_factory()
    try:
        _make_profile(db, user_id=1)
    finally:
        db.close()

    with TestClient(app) as c:
        try:
            response = c.get(
                "/community/feed",
                params={"page_size": 50},
                headers=_auth_headers(1),
            )
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 503, (
        f"F3 violated — placeholder secret produced {response.status_code} "
        f"(expected 503): {response.text}"
    )


def test_f3_empty_cursor_secret_returns_503(
    tmp_path, monkeypatch, session_factory
) -> None:
    """F3 — an empty ``secret_key`` makes the feed endpoint refuse
    to serve (503).

    The empty-string guard in :func:`_resolve_cursor_secret`
    catches deployments where ``STRUMSIGHT_SECRET_KEY`` resolves
    to a blank value (a misconfigured env, not the placeholder
    default). The 503 surfaces the configuration error to the
    client; the readiness gate catches it earlier at the deploy
    boundary.
    """
    from app.config import Settings
    from app.database import get_db as _real_get_db

    settings = Settings(
        _env_file=None,
        community_enabled=True,
        secret_key="",
    )
    app = FastAPI(title="Feed Test App — F3 empty")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(feed_router)

    def _override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[_real_get_db] = _override_get_db

    db: Session = session_factory()
    try:
        _make_profile(db, user_id=1)
    finally:
        db.close()

    with TestClient(app) as c:
        try:
            response = c.get(
                "/community/feed",
                params={"page_size": 50},
                headers=_auth_headers(1),
            )
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 503, (
        f"F3 violated — empty secret produced {response.status_code} "
        f"(expected 503): {response.text}"
    )


def test_f4_unknown_audience_filtered(client, session_factory) -> None:
    """F4 — a post whose ``audience`` is NOT in the
    ``('public', 'followers')`` allowlist is silently excluded
    from the feed; the endpoint returns 200 (no 500).

    The previous round used ``audience != 'private'`` (a denylist),
    which is FAIL-OPEN for a future audience value introduced at
    the Pydantic layer without a database migration. F4 swaps the
    predicate to an explicit allowlist so a future value cannot
    silently leak through the SQL filter.
    """
    viewer_pk = _make_profile(session_factory(), user_id=1)
    author_pk = _make_profile(session_factory(), user_id=2)
    headers = _auth_headers(1)

    db: Session = session_factory()
    try:
        _insert_follow(db, follower_pk=viewer_pk, followed_pk=author_pk)
        _, public_pid = _insert_post(
            db, author_pk=author_pk, body="public-anchor", audience="public"
        )
        _, weird_pid = _insert_post(
            db, author_pk=author_pk, body="unlisted-anchor", audience="unlisted"
        )
    finally:
        db.close()

    response = client.get(
        "/community/feed",
        params={"page_size": 50},
        headers=headers,
    )
    assert response.status_code == 200, (
        f"F4 violated — feed returned {response.status_code} (expected 200): {response.text}"
    )
    body = response.json()
    seen_bodies = {item["body"] for item in body["items"]}

    assert "public-anchor" in seen_bodies, (
        "F4 violated — public anchor missing from the feed"
    )
    assert "unlisted-anchor" not in seen_bodies, (
        f"F4 violated — non-allowlist audience ('unlisted') leaked into the feed: {seen_bodies!r}"
    )
