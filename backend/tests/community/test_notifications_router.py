"""Community notifications router — HTTP acceptance tests (the
``routers/notifications.py`` surface over the E09-R20
``notification_service``, production-wiring round 2026-09-15).

The service's own invariants (A1–A7) are pinned in
``test_notification_service.py``; this file pins the WIRE contract the
Flutter ``HttpCommunityNotificationRepository`` decodes, through the
production ``build_community_router`` factory:

* list / paginate — newest-first, ``{"items", "next_cursor"}``
  envelope, the row field set is EXACTLY what the Dart decoder reads
  (``related_content_id`` — not ``entity_id`` — and no internal ids), a
  tampered cursor restarts from the top;
* A5 on the wire — a deleted entity suppresses ``related_content_id``;
* mark-read — ``read`` then ``noop`` (idempotent), another user's row
  is a silent ``noop`` that leaves it unread (IDOR guard);
* read-all up to — only rows at/before the cutoff transition;
* preferences — bare ``{category: level}`` map, PUT round-trips, a bad
  level is 422;
* anonymous callers are rejected on every route; a profile-less
  (authenticated but not onboarded) caller gets the uniform 404;
* gating — ``community_writes_enabled=False`` keeps the two reads and
  drops the three mutations; ``community_enabled=False`` mounts nothing.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community import build_community_router
from app.community.models.notification import (
    NOTIFICATION_TYPE_ALLOWLIST,
    NOTIFICATION_TYPE_COMMENT,
    NOTIFICATION_TYPE_SECURITY_ALERT,
)
from app.community.models.post import CommunityPost
from app.community.models.profile import CommunityProfile
from app.community.notifications import notification_service
from app.community.policies.access_policy import CommunityAudience
from app.community.services.post_service import create_post
from app.config import Settings
from app.database import enable_sqlite_foreign_keys, get_db
from app.security import create_access_token, hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"

_WIRE_ROW_FIELDS = {
    "public_id",
    "type",
    "title_key",
    "body_key",
    "related_content_id",
    "is_read",
    "created_at",
}


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — file-backed SQLite with the full alembic chain, the
# production router factory mounted with every flag on.
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _isolated_preference_store() -> Iterator[None]:
    """The service's preference store is process-local and keyed by the
    INTERNAL profile id, which restarts at 1 in every test database —
    clear it around each test so cells never see each other's writes."""
    notification_service._PREFERENCE_STORE.clear()
    try:
        yield
    finally:
        notification_service._PREFERENCE_STORE.clear()


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "notifications-router.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)
    command.upgrade(_alembic_config(), "head")
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        yield factory
    finally:
        engine.dispose()


def _open_settings(**overrides) -> Settings:
    base = dict(
        _env_file=None,
        community_enabled=True,
        community_writes_enabled=True,
    )
    base.update(overrides)
    return Settings(**base)


def _build_app(session_factory, settings: Settings) -> FastAPI:
    app = FastAPI(title="Notifications Router Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    router = build_community_router(settings)
    if router is not None:
        app.include_router(router)

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    return app


@pytest.fixture
def app(session_factory) -> FastAPI:
    return _build_app(session_factory, _open_settings())


@pytest.fixture
def client(app) -> Iterator[TestClient]:
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


def _headers(user_id: int) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _make_user(session_factory, *, user_id: int) -> dict[str, str]:
    """A ``users`` row WITHOUT a community profile (the not-onboarded
    caller)."""
    with session_factory() as db:
        _insert_user(db, user_id, f"u{user_id}@s.test")
        db.commit()
    return _headers(user_id)


def _make_profile(
    session_factory, *, user_id: int
) -> tuple[CommunityProfile, dict[str, str]]:
    with session_factory() as db:
        _insert_user(db, user_id, f"u{user_id}@s.test")
        db.commit()
        profile = CommunityProfile(user_id=user_id)
        db.add(profile)
        db.flush()
        db.execute(
            text(
                "INSERT INTO community_privacy_settings "
                "(id, public_id, profile_id, updated_at, visibility, "
                "audience_default) "
                "VALUES (:id, :pid, :profile_id, :ts, :vis, :aud)"
            ),
            {
                "id": None,
                "pid": uuid.uuid4().hex,
                "profile_id": profile.id,
                "ts": _utcnow(),
                "vis": "public",
                "aud": "public",
            },
        )
        db.commit()
        db.refresh(profile)
        return profile, _headers(user_id)


def _notify(
    session_factory,
    *,
    recipient: CommunityProfile,
    now: datetime,
    notification_type: str = NOTIFICATION_TYPE_SECURITY_ALERT,
    title_key: str = "community_notification_security_alert_title",
    body_key: str | None = "community_notification_security_alert_body",
    entity_type: str | None = None,
    entity_id: str | None = None,
) -> uuid.UUID:
    with session_factory() as db:
        row = notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=notification_type,
            title_key=title_key,
            body_key=body_key,
            actor_public_id=None,
            entity_type=entity_type,
            entity_id=entity_id,
            dedup_key=None,
            aggregate=False,
            now=now,
        )
        db.commit()
        return row.public_id


def _create_post(session_factory, *, author: CommunityProfile) -> CommunityPost:
    with session_factory() as db:
        post = create_post(
            db,
            author_public_id=author.public_id,
            audience=CommunityAudience.PUBLIC,
            body="notification-target",
            idempotency_key=f"post-{uuid.uuid4()}",
            now=_utcnow(),
        )
        db.commit()
        db.refresh(post)
        return post


def _unread_ids(session_factory, recipient: CommunityProfile) -> set[str]:
    with session_factory() as db:
        rows = db.execute(
            text(
                "SELECT public_id FROM community_notifications "
                "WHERE recipient_profile_id = :rid AND is_read = 0"
            ),
            {"rid": recipient.id},
        ).all()
        return {
            str(uuid.UUID(hex=r[0]) if isinstance(r[0], str) else r[0]) for r in rows
        }


# ---------------------------------------------------------------------------
# List / paginate.
# ---------------------------------------------------------------------------


def test_list_is_newest_first_and_paginates_with_cursor(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    base = _utcnow() - timedelta(minutes=10)
    ids = [
        _notify(session_factory, recipient=recipient, now=base + timedelta(minutes=i))
        for i in range(3)
    ]

    first = client.get("/community/notifications?limit=2", headers=headers)
    assert first.status_code == 200, first.text
    page = first.json()
    assert set(page) == {"items", "next_cursor"}
    assert [row["public_id"] for row in page["items"]] == [str(ids[2]), str(ids[1])]
    assert page["next_cursor"]

    second = client.get(
        f"/community/notifications?limit=2&cursor={page['next_cursor']}",
        headers=headers,
    )
    assert second.status_code == 200, second.text
    assert [row["public_id"] for row in second.json()["items"]] == [str(ids[0])]
    assert second.json()["next_cursor"] is None


def test_list_row_field_set_matches_the_flutter_decoder(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    _notify(
        session_factory,
        recipient=recipient,
        now=_utcnow(),
        notification_type=NOTIFICATION_TYPE_COMMENT,
        title_key="community_notification_comment_title",
        body_key=None,
    )
    response = client.get("/community/notifications", headers=headers)
    assert response.status_code == 200, response.text
    (row,) = response.json()["items"]
    assert set(row) == _WIRE_ROW_FIELDS
    assert row["type"] == NOTIFICATION_TYPE_COMMENT
    assert row["title_key"] == "community_notification_comment_title"
    assert row["body_key"] is None
    assert row["is_read"] is False
    # An ISO-8601 timestamp the Dart ``DateTime.tryParse`` accepts.
    assert datetime.fromisoformat(row["created_at"]).tzinfo is not None
    # Never an internal id on the wire.
    assert "id" not in row and "recipient_profile_id" not in row


def test_list_empty_inbox_and_tampered_cursor_never_500(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    empty = client.get("/community/notifications", headers=headers)
    assert empty.status_code == 200
    assert empty.json() == {"items": [], "next_cursor": None}

    nid = _notify(session_factory, recipient=recipient, now=_utcnow())
    tampered = client.get(
        "/community/notifications?cursor=not-a-real-cursor", headers=headers
    )
    assert tampered.status_code == 200, tampered.text
    assert [r["public_id"] for r in tampered.json()["items"]] == [str(nid)]

    assert (
        client.get("/community/notifications?limit=0", headers=headers).status_code
        == 422
    )
    assert (
        client.get("/community/notifications?limit=101", headers=headers).status_code
        == 422
    )


def test_list_is_scoped_to_the_caller(client, session_factory):
    alice, alice_headers = _make_profile(session_factory, user_id=1)
    bob, bob_headers = _make_profile(session_factory, user_id=2)
    mine = _notify(session_factory, recipient=alice, now=_utcnow())
    _notify(session_factory, recipient=bob, now=_utcnow())

    response = client.get("/community/notifications", headers=alice_headers)
    assert [r["public_id"] for r in response.json()["items"]] == [str(mine)]


def test_a5_deleted_entity_suppresses_related_content_id(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    post = _create_post(session_factory, author=recipient)
    now = _utcnow()
    live = _notify(
        session_factory,
        recipient=recipient,
        now=now - timedelta(seconds=1),
        notification_type=NOTIFICATION_TYPE_COMMENT,
        title_key="community_notification_comment_title",
        entity_type="post",
        entity_id=str(post.public_id),
    )
    gone = _notify(
        session_factory,
        recipient=recipient,
        now=now,
        notification_type=NOTIFICATION_TYPE_COMMENT,
        title_key="community_notification_comment_title",
        entity_type="post",
        entity_id=str(uuid.uuid4()),
    )
    response = client.get("/community/notifications", headers=headers)
    by_id = {r["public_id"]: r for r in response.json()["items"]}
    assert by_id[str(live)]["related_content_id"] == str(post.public_id)
    assert by_id[str(gone)]["related_content_id"] is None


# ---------------------------------------------------------------------------
# Mark read (idempotent) + IDOR guard.
# ---------------------------------------------------------------------------


def test_mark_read_transitions_once_then_noop(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    nid = _notify(session_factory, recipient=recipient, now=_utcnow())

    first = client.post(
        f"/community/notifications/{nid}/read",
        headers=headers,
        json={"idempotency_key": "k-1"},
    )
    assert first.status_code == 200, first.text
    assert first.json() == {"status": "read"}

    retry = client.post(
        f"/community/notifications/{nid}/read",
        headers=headers,
        json={"idempotency_key": "k-1"},
    )
    assert retry.status_code == 200
    assert retry.json() == {"status": "noop"}

    # A bare retry (no body) is also fine.
    bare = client.post(f"/community/notifications/{nid}/read", headers=headers)
    assert bare.status_code == 200
    assert bare.json() == {"status": "noop"}

    listed = client.get("/community/notifications", headers=headers).json()
    assert listed["items"][0]["is_read"] is True
    assert _unread_ids(session_factory, recipient) == set()


def test_mark_read_on_another_users_row_is_a_silent_noop(client, session_factory):
    alice, _ = _make_profile(session_factory, user_id=1)
    _, bob_headers = _make_profile(session_factory, user_id=2)
    nid = _notify(session_factory, recipient=alice, now=_utcnow())

    response = client.post(f"/community/notifications/{nid}/read", headers=bob_headers)
    assert response.status_code == 200
    assert response.json() == {"status": "noop"}
    assert _unread_ids(session_factory, alice) == {str(nid)}

    unknown = client.post(
        f"/community/notifications/{uuid.uuid4()}/read", headers=bob_headers
    )
    assert unknown.status_code == 200
    assert unknown.json() == {"status": "noop"}

    assert (
        client.post(
            "/community/notifications/not-a-uuid/read", headers=bob_headers
        ).status_code
        == 422
    )


def test_mark_read_rejects_unknown_body_fields(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    nid = _notify(session_factory, recipient=recipient, now=_utcnow())
    response = client.post(
        f"/community/notifications/{nid}/read",
        headers=headers,
        json={"recipient_id": 42},
    )
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# Read-all up to a cutoff.
# ---------------------------------------------------------------------------


def test_read_all_marks_only_rows_up_to_the_cutoff(client, session_factory):
    recipient, headers = _make_profile(session_factory, user_id=1)
    base = _utcnow() - timedelta(minutes=10)
    oldest, middle, newest = (
        _notify(session_factory, recipient=recipient, now=base + timedelta(minutes=i))
        for i in range(3)
    )

    response = client.post(
        "/community/notifications/read-all",
        headers=headers,
        json={"up_to_public_id": str(middle), "idempotency_key": "ra-1"},
    )
    assert response.status_code == 200, response.text
    assert response.json() == {"status": "read", "count": 2}
    assert _unread_ids(session_factory, recipient) == {str(newest)}

    retry = client.post(
        "/community/notifications/read-all",
        headers=headers,
        json={"up_to_public_id": str(middle), "idempotency_key": "ra-1"},
    )
    assert retry.status_code == 200
    assert retry.json() == {"status": "noop", "count": 0}
    del oldest  # named for readability; its state is covered by the set above


def test_read_all_with_another_users_cutoff_is_a_noop(client, session_factory):
    alice, alice_headers = _make_profile(session_factory, user_id=1)
    bob, _ = _make_profile(session_factory, user_id=2)
    mine = _notify(session_factory, recipient=alice, now=_utcnow())
    theirs = _notify(session_factory, recipient=bob, now=_utcnow())

    response = client.post(
        "/community/notifications/read-all",
        headers=alice_headers,
        json={"up_to_public_id": str(theirs)},
    )
    assert response.status_code == 200
    assert response.json() == {"status": "noop", "count": 0}
    assert _unread_ids(session_factory, alice) == {str(mine)}
    assert _unread_ids(session_factory, bob) == {str(theirs)}

    missing_body = client.post(
        "/community/notifications/read-all", headers=alice_headers, json={}
    )
    assert missing_body.status_code == 422


# ---------------------------------------------------------------------------
# Preferences.
# ---------------------------------------------------------------------------


def test_preferences_get_is_a_bare_map_with_every_kind_defaulting_to_in_app(
    client, session_factory
):
    _, headers = _make_profile(session_factory, user_id=1)
    response = client.get("/community/notifications/preferences", headers=headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert "preferences" not in body  # bare map, not an envelope
    assert set(body) == set(NOTIFICATION_TYPE_ALLOWLIST)
    assert set(body.values()) == {"inApp"}


def test_preferences_put_round_trips_and_is_idempotent(client, session_factory):
    _, headers = _make_profile(session_factory, user_id=1)
    put = client.put(
        "/community/notifications/preferences/comment",
        headers=headers,
        json={"level": "push", "idempotency_key": "p-1"},
    )
    assert put.status_code == 200, put.text
    assert put.json()["comment"] == "push"
    assert set(put.json()) == set(NOTIFICATION_TYPE_ALLOWLIST)

    again = client.put(
        "/community/notifications/preferences/comment",
        headers=headers,
        json={"level": "push", "idempotency_key": "p-1"},
    )
    assert again.status_code == 200
    assert again.json()["comment"] == "push"

    got = client.get("/community/notifications/preferences", headers=headers).json()
    assert got["comment"] == "push"
    assert got["mention"] == "inApp"

    disabled = client.put(
        "/community/notifications/preferences/comment",
        headers=headers,
        json={"level": "disabled"},
    )
    assert disabled.json()["comment"] == "disabled"


def test_preferences_are_scoped_per_caller(client, session_factory):
    _, alice = _make_profile(session_factory, user_id=1)
    _, bob = _make_profile(session_factory, user_id=2)
    client.put(
        "/community/notifications/preferences/comment",
        headers=alice,
        json={"level": "disabled"},
    )
    assert (
        client.get("/community/notifications/preferences", headers=bob).json()[
            "comment"
        ]
        == "inApp"
    )


def test_preferences_put_rejects_a_bad_level(client, session_factory):
    _, headers = _make_profile(session_factory, user_id=1)
    response = client.put(
        "/community/notifications/preferences/comment",
        headers=headers,
        json={"level": "loud"},
    )
    assert response.status_code == 422
    assert (
        client.get("/community/notifications/preferences", headers=headers).json()[
            "comment"
        ]
        == "inApp"
    )


# ---------------------------------------------------------------------------
# Auth: anonymous rejected everywhere, profile-less caller → uniform 404.
# ---------------------------------------------------------------------------

_ALL_ROUTES = (
    ("get", "/community/notifications", None),
    ("get", "/community/notifications/preferences", None),
    ("put", "/community/notifications/preferences/comment", {"level": "push"}),
    (
        "post",
        "/community/notifications/read-all",
        {"up_to_public_id": "00000000-0000-0000-0000-000000000001"},
    ),
    (
        "post",
        "/community/notifications/00000000-0000-0000-0000-000000000001/read",
        None,
    ),
)


def test_every_notifications_route_rejects_anonymous_callers(client, app):
    # Walk the REAL route table (not a hand-picked sample) so a route
    # added later without ``CurrentUser`` turns this cell red.
    probe = "00000000-0000-0000-0000-000000000001"
    walked = 0
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        if not route.path.startswith("/community/notifications"):
            continue
        for method in route.methods - {"HEAD", "OPTIONS"}:
            path = route.path.replace("{public_id}", probe).replace(
                "{category}", "comment"
            )
            response = getattr(client, method.lower())(path)
            # ``HTTPBearer(auto_error=True)`` answers a missing header with
            # 403 and a bad token with 401 — both are "not authenticated".
            assert response.status_code in (401, 403), (method, route.path)
            walked += 1
    assert walked == 5


def test_bad_token_is_401(client):
    response = client.get(
        "/community/notifications", headers={"Authorization": "Bearer nope"}
    )
    assert response.status_code == 401


def test_profile_less_caller_gets_uniform_404_on_every_route(client, session_factory):
    headers = _make_user(session_factory, user_id=7)  # no community profile
    for method, path, body in _ALL_ROUTES:
        kwargs = {"headers": headers}
        if body is not None:
            kwargs["json"] = body
        response = getattr(client, method)(path, **kwargs)
        assert response.status_code == 404, (method, path, response.text)
        assert response.json() == {"detail": "caller has no community profile"}


# ---------------------------------------------------------------------------
# Gating through the production factory.
# ---------------------------------------------------------------------------


def _paths(settings: Settings) -> dict[str, set[str]]:
    router = build_community_router(settings)
    assert router is not None
    out: dict[str, set[str]] = {}
    for route in router.routes:
        if isinstance(route, APIRoute):
            out.setdefault(route.path, set()).update(route.methods)
    return {p: m for p, m in out.items() if p.startswith("/community/notifications")}


def test_gating_fully_open_mounts_all_five_routes():
    paths = _paths(_open_settings())
    assert paths == {
        "/community/notifications": {"GET"},
        "/community/notifications/preferences": {"GET"},
        "/community/notifications/preferences/{category}": {"PUT"},
        "/community/notifications/read-all": {"POST"},
        "/community/notifications/{public_id}/read": {"POST"},
    }


def test_gating_writes_flag_off_keeps_reads_drops_mutations():
    paths = _paths(_open_settings(community_writes_enabled=False))
    assert paths == {
        "/community/notifications": {"GET"},
        "/community/notifications/preferences": {"GET"},
    }


def test_gating_writes_flag_off_answers_404_for_mutations(session_factory):
    app = _build_app(session_factory, _open_settings(community_writes_enabled=False))
    recipient, headers = _make_profile(session_factory, user_id=1)
    nid = _notify(session_factory, recipient=recipient, now=_utcnow())
    with TestClient(app) as c:
        assert c.get("/community/notifications", headers=headers).status_code == 200
        gone = c.post(f"/community/notifications/{nid}/read", headers=headers)
        assert gone.status_code == 404
        assert gone.json() == {"detail": "Not Found"}  # route absent, not 403
        assert (
            c.put(
                "/community/notifications/preferences/comment",
                headers=headers,
                json={"level": "push"},
            ).status_code
            == 404
        )
    app.dependency_overrides.clear()


def test_gating_community_disabled_mounts_nothing():
    assert (
        build_community_router(Settings(_env_file=None, community_enabled=False))
        is None
    )
