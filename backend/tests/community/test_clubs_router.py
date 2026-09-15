"""Clubs router acceptance tests — the HTTP surface over the Kör 24
``club_service`` (``app/community/routers/clubs.py``).

Cells:

* list / detail / join / leave / members — the happy path the Flutter
  ``CommunityClubRepository`` contract needs, asserting the exact
  snake_case wire keys the client entity maps
  (``public_id`` / ``owner_public_id`` / ``member_count`` / ``my_role``
  / ``tags`` / ``created_at`` + the ``{"items", "next_cursor"}`` page
  envelope);
* permissions — a plain member cannot remove another member (403), a
  non-member cannot see a private club (uniform 404), the lone owner
  cannot leave (409), the owner cannot be removed (409);
* 404 — unknown club, unknown member, caller without a profile;
* gating — ``community_clubs_enabled=False`` leaves NO ``/community/
  clubs`` route in the table; ``community_writes_enabled=False`` keeps
  the GET routes and drops every mutation (the posts precedent);
* auth — every clubs route rejects an anonymous caller;
* cursor pagination walks the whole list without overlap and a
  malformed cursor restarts from the top instead of 500-ing;
* the internal integer ``id`` never appears on the wire.

The fixtures follow ``test_challenge_invite_service.py``: a
self-contained ``FastAPI()`` with the router mounted directly over an
alembic-upgraded file-backed SQLite (so the Kör 24 migration chain is
the schema source), JWTs minted through ``create_access_token``.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
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
from app.community.models.club import (
    CLUB_ROLE_MEMBER,
    CLUB_ROLE_MODERATOR,
    CLUB_VISIBILITY_DISCOVERABLE,
    CLUB_VISIBILITY_PRIVATE,
    CLUB_VISIBILITY_PUBLIC,
    CommunityClub,
    CommunityClubMember,
)
from app.community.models.profile import CommunityProfile
from app.community.models.safety_relationships import CommunityBlock
from app.community.routers.clubs import reset_rate_limiters
from app.community.services import club_service as svc
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
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied."""
    db_path = tmp_path / "clubs.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)
    command.upgrade(_alembic_config(), "head")
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)
    factory = sessionmaker(
        bind=engine, autoflush=False, autocommit=False, expire_on_commit=False
    )
    try:
        yield factory
    finally:
        engine.dispose()


@pytest.fixture
def app(session_factory) -> Iterator[FastAPI]:
    """Self-contained FastAPI with ONLY the clubs router mounted."""
    from app.community.routers.clubs import router as clubs_router

    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Clubs Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(clubs_router)
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


@pytest.fixture(autouse=True)
def _reset_limiter() -> Iterator[None]:
    reset_rate_limiters()
    try:
        yield
    finally:
        reset_rate_limiters()


# ---------------------------------------------------------------------------
# Seeding helpers
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


def _make_user(
    session_factory, *, user_id: int, display_name: str | None = None
) -> tuple[CommunityProfile, dict[str, str]]:
    """User + profile + privacy row; returns ``(profile, auth headers)``."""
    db: Session = session_factory()
    try:
        _insert_user(db, user_id, f"u{user_id}@s.test")
        db.commit()
        profile = CommunityProfile(user_id=user_id, display_name=display_name)
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
                "vis": "public",
                "aud": "public",
            },
        )
        db.commit()
        db.refresh(profile)
    finally:
        db.close()
    return profile, {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _headers_without_profile(session_factory, *, user_id: int) -> dict[str, str]:
    db: Session = session_factory()
    try:
        _insert_user(db, user_id, f"noprofile{user_id}@s.test")
        db.commit()
    finally:
        db.close()
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _create_club(
    session_factory,
    *,
    owner: CommunityProfile,
    visibility: str = CLUB_VISIBILITY_DISCOVERABLE,
    name: str | None = None,
    created_at: datetime | None = None,
) -> CommunityClub:
    db: Session = session_factory()
    try:
        club = svc.create_club(
            db,
            owner_profile_id=owner.id,
            name=name or f"Club-{uuid.uuid4().hex[:6]}",
            description="description",
            visibility=visibility,
            idempotency_key=f"create-{uuid.uuid4().hex}",
            now=created_at or _utcnow(),
        )
        db.commit()
        db.refresh(club)
        return club
    finally:
        db.close()


def _add_member(
    session_factory,
    *,
    club: CommunityClub,
    profile: CommunityProfile,
    role: str = CLUB_ROLE_MEMBER,
) -> CommunityClubMember:
    db: Session = session_factory()
    try:
        member = CommunityClubMember(
            public_id=uuid.uuid4(),
            club_id=club.id,
            profile_id=profile.id,
            role=role,
            joined_at=_utcnow(),
            updated_at=_utcnow(),
        )
        db.add(member)
        db.commit()
        db.refresh(member)
        return member
    finally:
        db.close()


def _add_block(
    session_factory, *, blocker: CommunityProfile, blocked: CommunityProfile
):
    db: Session = session_factory()
    try:
        db.add(
            CommunityBlock(blocker_profile_id=blocker.id, blocked_profile_id=blocked.id)
        )
        db.commit()
    finally:
        db.close()


def _assert_no_internal_id(payload: dict) -> None:
    assert "id" not in payload, payload
    for value in payload.values():
        if isinstance(value, dict):
            _assert_no_internal_id(value)
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    _assert_no_internal_id(item)


# ---------------------------------------------------------------------------
# Create + detail — the wire shape the Flutter ``CommunityClub`` maps.
# ---------------------------------------------------------------------------


def test_create_club_returns_flutter_wire_shape(client, session_factory) -> None:
    owner, headers = _make_user(session_factory, user_id=1)

    response = client.post(
        "/community/clubs",
        headers=headers,
        json={
            "name": "  Fingerstyle Friends ",
            "description": "slow blues",
            "visibility": "discoverable",
            "tags": ["blues", "fingerstyle"],
            "idempotency_key": "create-1",
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == {
        "public_id",
        "name",
        "description",
        "visibility",
        "tags",
        "owner_public_id",
        "member_count",
        "my_role",
        "join_request_pending",
        "created_at",
        "updated_at",
        "resource_version",
    }
    assert body["name"] == "Fingerstyle Friends"
    assert body["visibility"] == "discoverable"
    assert body["owner_public_id"] == str(owner.public_id)
    assert body["member_count"] == 1
    assert body["my_role"] == "owner"
    assert body["tags"] == []
    assert body["join_request_pending"] is False
    _assert_no_internal_id(body)

    # Idempotent replay returns the SAME club (no second row).
    replay = client.post(
        "/community/clubs",
        headers=headers,
        json={"name": "Different", "idempotency_key": "create-1"},
    )
    assert replay.status_code == 201
    assert replay.json()["public_id"] == body["public_id"]

    detail = client.get(f"/community/clubs/{body['public_id']}", headers=headers)
    assert detail.status_code == 200
    assert detail.json()["public_id"] == body["public_id"]
    assert detail.json()["my_role"] == "owner"


def test_create_club_rejects_smuggled_owner_and_bad_visibility(
    client, session_factory
) -> None:
    _, headers = _make_user(session_factory, user_id=1)
    forged = client.post(
        "/community/clubs",
        headers=headers,
        json={"name": "x", "owner_public_id": str(uuid.uuid4())},
    )
    assert forged.status_code == 422
    bad_visibility = client.post(
        "/community/clubs", headers=headers, json={"name": "x", "visibility": "secret"}
    )
    assert bad_visibility.status_code == 422
    too_long = client.post("/community/clubs", headers=headers, json={"name": "x" * 61})
    assert too_long.status_code == 422


def test_create_club_is_rate_limited_per_caller(client, session_factory) -> None:
    _, headers = _make_user(session_factory, user_id=1)
    for i in range(10):
        ok = client.post("/community/clubs", headers=headers, json={"name": f"c{i}"})
        assert ok.status_code == 201, ok.text
    limited = client.post("/community/clubs", headers=headers, json={"name": "c-11"})
    assert limited.status_code == 429


# ---------------------------------------------------------------------------
# List — visibility + page envelope + cursor walk.
# ---------------------------------------------------------------------------


def test_list_clubs_hides_private_clubs_from_non_members(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)
    public_club = _create_club(session_factory, owner=owner, visibility="public")
    private_club = _create_club(session_factory, owner=owner, visibility="private")
    joined_private = _create_club(session_factory, owner=owner, visibility="private")
    _add_member(session_factory, club=joined_private, profile=viewer)

    response = client.get("/community/clubs", headers=viewer_headers)
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"items", "next_cursor"}
    ids = {item["public_id"] for item in body["items"]}
    assert str(public_club.public_id) in ids
    assert str(joined_private.public_id) in ids
    assert str(private_club.public_id) not in ids
    assert body["next_cursor"] is None
    by_id = {item["public_id"]: item for item in body["items"]}
    assert by_id[str(public_club.public_id)]["my_role"] is None
    assert by_id[str(joined_private.public_id)]["my_role"] == "member"

    # The owner sees all three.
    owner_view = client.get("/community/clubs", headers=owner_headers).json()
    assert {i["public_id"] for i in owner_view["items"]} == {
        str(public_club.public_id),
        str(private_club.public_id),
        str(joined_private.public_id),
    }
    assert all(i["my_role"] == "owner" for i in owner_view["items"])


def test_list_clubs_cursor_walk_is_complete_and_disjoint(client, session_factory):
    owner, headers = _make_user(session_factory, user_id=1)
    base = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
    expected = [
        str(
            _create_club(
                session_factory,
                owner=owner,
                visibility="public",
                name=f"walk-{i}",
                created_at=base.replace(minute=i),
            ).public_id
        )
        for i in range(5)
    ]

    seen: list[str] = []
    cursor: str | None = None
    for _ in range(10):
        params = {"limit": 2}
        if cursor is not None:
            params["cursor"] = cursor
        page = client.get("/community/clubs", headers=headers, params=params)
        assert page.status_code == 200, page.text
        body = page.json()
        assert len(body["items"]) <= 2
        seen.extend(item["public_id"] for item in body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            break
    assert len(seen) == len(set(seen)) == 5
    # Newest first.
    assert seen == list(reversed(expected))


def test_list_clubs_malformed_cursor_restarts_from_top(client, session_factory):
    owner, headers = _make_user(session_factory, user_id=1)
    club = _create_club(session_factory, owner=owner, visibility="public")
    response = client.get(
        "/community/clubs", headers=headers, params={"cursor": "not-base64!!"}
    )
    assert response.status_code == 200
    assert [i["public_id"] for i in response.json()["items"]] == [str(club.public_id)]


def test_list_clubs_drops_clubs_owned_by_blocked_profile(client, session_factory):
    owner, _ = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)
    _create_club(session_factory, owner=owner, visibility="public")
    _add_block(session_factory, blocker=viewer, blocked=owner)
    response = client.get("/community/clubs", headers=viewer_headers)
    assert response.status_code == 200
    assert response.json()["items"] == []


# ---------------------------------------------------------------------------
# Detail — uniform 404.
# ---------------------------------------------------------------------------


def test_get_private_club_as_non_member_is_uniform_404(client, session_factory):
    owner, _ = _make_user(session_factory, user_id=1)
    _, viewer_headers = _make_user(session_factory, user_id=2)
    private_club = _create_club(session_factory, owner=owner, visibility="private")

    hidden = client.get(
        f"/community/clubs/{private_club.public_id}", headers=viewer_headers
    )
    unknown = client.get(f"/community/clubs/{uuid.uuid4()}", headers=viewer_headers)
    assert hidden.status_code == 404
    assert unknown.status_code == 404
    assert hidden.json() == unknown.json()


def test_caller_without_profile_gets_404(client, session_factory):
    headers = _headers_without_profile(session_factory, user_id=9)
    assert client.get("/community/clubs", headers=headers).status_code == 404
    assert (
        client.post("/community/clubs", headers=headers, json={"name": "x"}).status_code
        == 404
    )


# ---------------------------------------------------------------------------
# Join / leave.
# ---------------------------------------------------------------------------


def test_join_discoverable_club_creates_membership_immediately(client, session_factory):
    owner, _ = _make_user(session_factory, user_id=1)
    _, joiner_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="discoverable")

    response = client.post(
        f"/community/clubs/{club.public_id}/join",
        headers=joiner_headers,
        json={"idempotency_key": "join-1"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["my_role"] == "member"
    assert body["member_count"] == 2
    assert body["join_request_pending"] is False

    # Idempotent repeat.
    again = client.post(
        f"/community/clubs/{club.public_id}/join", headers=joiner_headers
    )
    assert again.status_code == 200
    assert again.json()["member_count"] == 2


def test_join_private_club_files_pending_request_then_owner_accepts(
    client, session_factory
):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    requester, requester_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="private")

    # The requester cannot see the club yet…
    assert (
        client.get(
            f"/community/clubs/{club.public_id}", headers=requester_headers
        ).status_code
        == 404
    )
    # …but may request to join it (the D6 flow).
    requested = client.post(
        f"/community/clubs/{club.public_id}/join",
        headers=requester_headers,
        json={"idempotency_key": "req-1"},
    )
    assert requested.status_code == 200, requested.text
    assert requested.json()["my_role"] is None
    assert requested.json()["join_request_pending"] is True
    assert requested.json()["member_count"] == 1

    # A plain outsider cannot list the requests (403 — not a member).
    _, outsider_headers = _make_user(session_factory, user_id=3)
    assert (
        client.get(
            f"/community/clubs/{club.public_id}/join-requests", headers=outsider_headers
        ).status_code
        == 403
    )

    listing = client.get(
        f"/community/clubs/{club.public_id}/join-requests", headers=owner_headers
    )
    assert listing.status_code == 200
    assert len(listing.json()["items"]) == 1
    req = listing.json()["items"][0]
    assert req["status"] == "pending"
    assert (
        req["inviter_public_id"] == req["invitee_public_id"] == str(requester.public_id)
    )

    accepted = client.post(
        f"/community/clubs/{club.public_id}/join-requests/{req['public_id']}/accept",
        headers=owner_headers,
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["role"] == "member"
    assert accepted.json()["profile_public_id"] == str(requester.public_id)

    # Now the requester sees the club as a member.
    detail = client.get(f"/community/clubs/{club.public_id}", headers=requester_headers)
    assert detail.status_code == 200
    assert detail.json()["my_role"] == "member"

    # Accepting twice is a 409 (invalid transition).
    twice = client.post(
        f"/community/clubs/{club.public_id}/join-requests/{req['public_id']}/accept",
        headers=owner_headers,
    )
    assert twice.status_code == 409
    assert twice.json()["detail"]["error"] == "invalid_club_transition"


def test_decline_join_request_and_cross_club_404(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    _, requester_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="private")
    other = _create_club(session_factory, owner=owner, visibility="private")
    client.post(f"/community/clubs/{club.public_id}/join", headers=requester_headers)
    req = client.get(
        f"/community/clubs/{club.public_id}/join-requests", headers=owner_headers
    ).json()["items"][0]

    wrong_club = client.post(
        f"/community/clubs/{other.public_id}/join-requests/{req['public_id']}/decline",
        headers=owner_headers,
    )
    assert wrong_club.status_code == 404

    declined = client.post(
        f"/community/clubs/{club.public_id}/join-requests/{req['public_id']}/decline",
        headers=owner_headers,
    )
    assert declined.status_code == 200
    assert declined.json()["status"] == "declined"
    assert declined.json()["responded_at"] is not None


def test_join_blocked_by_owner_is_403(client, session_factory):
    owner, _ = _make_user(session_factory, user_id=1)
    joiner, joiner_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_block(session_factory, blocker=owner, blocked=joiner)
    response = client.post(
        f"/community/clubs/{club.public_id}/join", headers=joiner_headers
    )
    assert response.status_code == 403


def test_leave_club_member_ok_lone_owner_409_non_member_404(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    member, member_headers = _make_user(session_factory, user_id=2)
    _, outsider_headers = _make_user(session_factory, user_id=3)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_member(session_factory, club=club, profile=member)

    left = client.post(
        f"/community/clubs/{club.public_id}/leave", headers=member_headers
    )
    assert left.status_code == 200
    assert left.json() == {"club_public_id": str(club.public_id), "left": True}
    assert (
        client.get(f"/community/clubs/{club.public_id}", headers=member_headers).json()[
            "member_count"
        ]
        == 1
    )

    lone_owner = client.post(
        f"/community/clubs/{club.public_id}/leave", headers=owner_headers
    )
    assert lone_owner.status_code == 409
    assert lone_owner.json()["detail"]["error"] == "owner_must_transfer_first"

    not_member = client.post(
        f"/community/clubs/{club.public_id}/leave", headers=outsider_headers
    )
    assert not_member.status_code == 404


# ---------------------------------------------------------------------------
# Members — roster shape, pagination, block filter, private gate.
# ---------------------------------------------------------------------------


def test_members_roster_shape_pagination_and_visibility(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1, display_name="Owner")
    club = _create_club(session_factory, owner=owner, visibility="private")
    members = []
    for uid in range(2, 6):
        profile, _ = _make_user(session_factory, user_id=uid)
        members.append(_add_member(session_factory, club=club, profile=profile))

    first = client.get(
        f"/community/clubs/{club.public_id}/members",
        headers=owner_headers,
        params={"limit": 3},
    )
    assert first.status_code == 200, first.text
    body = first.json()
    assert set(body) == {"items", "next_cursor"}
    assert len(body["items"]) == 3
    assert body["next_cursor"] is not None
    head = body["items"][0]
    assert set(head) == {
        "public_id",
        "club_public_id",
        "profile_public_id",
        "display_name",
        "handle",
        "role",
        "joined_at",
    }
    assert head["role"] == "owner"
    assert head["profile_public_id"] == str(owner.public_id)
    assert head["display_name"] == "Owner"
    assert head["club_public_id"] == str(club.public_id)
    _assert_no_internal_id(body)

    second = client.get(
        f"/community/clubs/{club.public_id}/members",
        headers=owner_headers,
        params={"limit": 3, "cursor": body["next_cursor"]},
    )
    assert second.status_code == 200
    rest = second.json()
    assert len(rest["items"]) == 2
    assert rest["next_cursor"] is None
    all_public = [i["public_id"] for i in body["items"]] + [
        i["public_id"] for i in rest["items"]
    ]
    assert len(set(all_public)) == 5

    # A non-member cannot read a private roster (uniform 404).
    _, outsider_headers = _make_user(session_factory, user_id=7)
    assert (
        client.get(
            f"/community/clubs/{club.public_id}/members", headers=outsider_headers
        ).status_code
        == 404
    )


def test_members_roster_drops_blocked_profiles(client, session_factory):
    owner, _ = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)
    blocked, _ = _make_user(session_factory, user_id=3)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_member(session_factory, club=club, profile=viewer)
    _add_member(session_factory, club=club, profile=blocked)
    _add_block(session_factory, blocker=viewer, blocked=blocked)

    roster = client.get(
        f"/community/clubs/{club.public_id}/members", headers=viewer_headers
    )
    assert roster.status_code == 200
    profiles = {i["profile_public_id"] for i in roster.json()["items"]}
    assert profiles == {str(owner.public_id), str(viewer.public_id)}


# ---------------------------------------------------------------------------
# Member management — remove / promote / demote / transfer.
# ---------------------------------------------------------------------------


def test_remove_member_permissions(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    member_a, a_headers = _make_user(session_factory, user_id=2)
    member_b, _ = _make_user(session_factory, user_id=3)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_member(session_factory, club=club, profile=member_a)
    _add_member(session_factory, club=club, profile=member_b)

    # A plain member cannot remove another member.
    forbidden = client.delete(
        f"/community/clubs/{club.public_id}/members/{member_b.public_id}",
        headers=a_headers,
    )
    assert forbidden.status_code == 403

    # Nobody can remove the owner.
    owner_removal = client.delete(
        f"/community/clubs/{club.public_id}/members/{owner.public_id}",
        headers=owner_headers,
    )
    assert owner_removal.status_code == 409

    # Unknown target → 404.
    unknown = client.delete(
        f"/community/clubs/{club.public_id}/members/{uuid.uuid4()}",
        headers=owner_headers,
        params={"idempotency_key": "rm-x"},
    )
    assert unknown.status_code == 404

    removed = client.delete(
        f"/community/clubs/{club.public_id}/members/{member_b.public_id}",
        headers=owner_headers,
        params={"idempotency_key": "rm-1"},
    )
    assert removed.status_code == 200
    assert removed.json() == {
        "club_public_id": str(club.public_id),
        "profile_public_id": str(member_b.public_id),
        "removed": True,
    }
    roster = client.get(
        f"/community/clubs/{club.public_id}/members", headers=owner_headers
    )
    assert str(member_b.public_id) not in {
        i["profile_public_id"] for i in roster.json()["items"]
    }


def test_promote_demote_and_transfer_ownership(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    member, member_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_member(session_factory, club=club, profile=member)

    self_promote = client.post(
        f"/community/clubs/{club.public_id}/members/{member.public_id}/promote",
        headers=member_headers,
    )
    assert self_promote.status_code == 409

    promoted = client.post(
        f"/community/clubs/{club.public_id}/members/{member.public_id}/promote",
        headers=owner_headers,
    )
    assert promoted.status_code == 200, promoted.text
    assert promoted.json()["role"] == CLUB_ROLE_MODERATOR

    demoted = client.post(
        f"/community/clubs/{club.public_id}/members/{member.public_id}/demote",
        headers=owner_headers,
    )
    assert demoted.status_code == 200
    assert demoted.json()["role"] == CLUB_ROLE_MEMBER

    # Only the owner may transfer; the target must be a member.
    not_owner = client.post(
        f"/community/clubs/{club.public_id}/transfer-ownership",
        headers=member_headers,
        json={"new_owner_public_id": str(owner.public_id)},
    )
    assert not_owner.status_code == 403
    missing_target = client.post(
        f"/community/clubs/{club.public_id}/transfer-ownership",
        headers=owner_headers,
        json={"new_owner_public_id": str(uuid.uuid4())},
    )
    assert missing_target.status_code == 404

    transferred = client.post(
        f"/community/clubs/{club.public_id}/transfer-ownership",
        headers=owner_headers,
        json={"new_owner_public_id": str(member.public_id), "idempotency_key": "t-1"},
    )
    assert transferred.status_code == 200, transferred.text
    assert transferred.json()["owner_public_id"] == str(member.public_id)
    assert transferred.json()["my_role"] == "member"
    as_new_owner = client.get(
        f"/community/clubs/{club.public_id}", headers=member_headers
    )
    assert as_new_owner.json()["my_role"] == "owner"


def test_patch_club_owner_only_and_stale_version(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    member, member_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_member(session_factory, club=club, profile=member)
    current = client.get(
        f"/community/clubs/{club.public_id}", headers=owner_headers
    ).json()

    forbidden = client.patch(
        f"/community/clubs/{club.public_id}",
        headers=member_headers,
        json={"description": "hijack", "visibility": "private"},
    )
    assert forbidden.status_code == 403

    stale = client.patch(
        f"/community/clubs/{club.public_id}",
        headers=owner_headers,
        json={
            "description": "new",
            "visibility": "private",
            "resource_version": "2000-01-01T00:00:00+00:00",
        },
    )
    assert stale.status_code == 409
    assert stale.json()["detail"]["error"] == "stale_resource_version"

    updated = client.patch(
        f"/community/clubs/{club.public_id}",
        headers=owner_headers,
        json={
            "description": "new",
            "visibility": "private",
            "tags": ["x"],
            "resource_version": current["resource_version"],
            "idempotency_key": "patch-1",
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["description"] == "new"
    assert updated.json()["visibility"] == "private"


# ---------------------------------------------------------------------------
# Invites.
# ---------------------------------------------------------------------------


def test_invite_and_cancel_invite(client, session_factory):
    owner, owner_headers = _make_user(session_factory, user_id=1)
    invitee, _ = _make_user(session_factory, user_id=2)
    member, member_headers = _make_user(session_factory, user_id=3)
    club = _create_club(session_factory, owner=owner, visibility="private")
    _add_member(session_factory, club=club, profile=member)

    # A plain member may not invite.
    forbidden = client.post(
        f"/community/clubs/{club.public_id}/invites",
        headers=member_headers,
        json={"invitee_public_id": str(invitee.public_id)},
    )
    assert forbidden.status_code == 403

    created = client.post(
        f"/community/clubs/{club.public_id}/invites",
        headers=owner_headers,
        json={"invitee_public_id": str(invitee.public_id), "idempotency_key": "inv-1"},
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["status"] == "pending"
    assert body["club_public_id"] == str(club.public_id)
    assert body["inviter_public_id"] == str(owner.public_id)
    assert body["invitee_public_id"] == str(invitee.public_id)
    _assert_no_internal_id(body)

    replay = client.post(
        f"/community/clubs/{club.public_id}/invites",
        headers=owner_headers,
        json={"invitee_public_id": str(invitee.public_id), "idempotency_key": "inv-1"},
    )
    assert replay.json()["public_id"] == body["public_id"]

    cancelled = client.delete(
        f"/community/clubs/invites/{body['public_id']}",
        headers=owner_headers,
        params={"idempotency_key": "cancel-1"},
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"
    assert (
        client.delete(
            f"/community/clubs/invites/{uuid.uuid4()}", headers=owner_headers
        ).status_code
        == 404
    )


# ---------------------------------------------------------------------------
# Auth + gating through the production factory.
# ---------------------------------------------------------------------------


def test_every_clubs_route_rejects_anonymous_callers(client, app) -> None:
    probe = str(uuid.uuid4())
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in route.methods - {"HEAD", "OPTIONS"}:
            path = route.path.replace("{club_public_id}", probe)
            path = path.replace("{profile_public_id}", probe)
            path = path.replace("{invite_public_id}", probe)
            response = getattr(client, method.lower())(path)
            assert response.status_code in (401, 403), (method, route.path)


def _paths(settings: Settings) -> dict[str, set[str]]:
    router = build_community_router(settings)
    assert router is not None
    out: dict[str, set[str]] = {}
    for route in router.routes:
        if isinstance(route, APIRoute):
            out.setdefault(route.path, set()).update(route.methods)
    return out


def test_gating_clubs_flag_off_registers_no_clubs_route() -> None:
    paths = _paths(
        Settings(_env_file=None, community_enabled=True, community_clubs_enabled=False)
    )
    assert not any(p.startswith("/community/clubs") for p in paths)


def test_gating_clubs_flag_off_returns_404_not_403(session_factory) -> None:
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI()
    app.state.session_factory = session_factory
    app.state.settings = settings
    router = build_community_router(settings)
    assert router is not None
    app.include_router(router)
    _, headers = _make_user(session_factory, user_id=1)
    with TestClient(app) as c:
        assert c.get("/community/clubs", headers=headers).status_code == 404


def test_gating_writes_flag_off_keeps_reads_drops_mutations() -> None:
    paths = _paths(
        Settings(
            _env_file=None,
            community_enabled=True,
            community_clubs_enabled=True,
            community_writes_enabled=False,
        )
    )
    clubs = {p: m for p, m in paths.items() if p.startswith("/community/clubs")}
    assert clubs, "clubs reads must stay mounted"
    assert clubs["/community/clubs"] == {"GET"}
    assert clubs["/community/clubs/{club_public_id}"] == {"GET"}
    assert clubs["/community/clubs/{club_public_id}/members"] == {"GET"}
    for path, methods in clubs.items():
        assert methods <= {"GET"}, (path, methods)


def test_gating_fully_open_mounts_every_clubs_route() -> None:
    paths = _paths(
        Settings(
            _env_file=None,
            community_enabled=True,
            community_clubs_enabled=True,
            community_writes_enabled=True,
        )
    )
    assert "POST" in paths["/community/clubs"]
    assert "PATCH" in paths["/community/clubs/{club_public_id}"]
    assert "POST" in paths["/community/clubs/{club_public_id}/join"]
    assert "POST" in paths["/community/clubs/{club_public_id}/leave"]
    assert (
        "DELETE"
        in paths["/community/clubs/{club_public_id}/members/{profile_public_id}"]
    )
    assert "POST" in paths["/community/clubs/{club_public_id}/transfer-ownership"]
    assert "POST" in paths["/community/clubs/{club_public_id}/invites"]


def test_visibility_query_filter(client, session_factory) -> None:
    owner, headers = _make_user(session_factory, user_id=1)
    public_club = _create_club(
        session_factory, owner=owner, visibility=CLUB_VISIBILITY_PUBLIC
    )
    _create_club(session_factory, owner=owner, visibility=CLUB_VISIBILITY_PRIVATE)
    response = client.get(
        "/community/clubs", headers=headers, params={"visibility": "public"}
    )
    assert [i["public_id"] for i in response.json()["items"]] == [
        str(public_club.public_id)
    ]


# ---------------------------------------------------------------------------
# Block filter on the page boundary — the walk must not end early.
# ---------------------------------------------------------------------------


def test_members_walk_survives_blocked_member_on_page_boundary(
    client, session_factory
) -> None:
    """Roster: owner, m2, m3(blocked), m4, m5 with ``limit=2`` — page 1
    raw slice is (owner, m2), page 2 raw slice is (m3, m4) of which m3
    is dropped, page 3 is (m5). A ``has_more`` decided on the FILTERED
    slice would have ended the walk after page 2 with one visible row
    and hidden m5."""
    owner, _ = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner, visibility="public")
    _add_member(session_factory, club=club, profile=viewer)
    blocked, _ = _make_user(session_factory, user_id=3)
    _add_member(session_factory, club=club, profile=blocked)
    _add_block(session_factory, blocker=viewer, blocked=blocked)
    tail = []
    for uid in (4, 5):
        profile, _ = _make_user(session_factory, user_id=uid)
        _add_member(session_factory, club=club, profile=profile)
        tail.append(str(profile.public_id))

    seen: list[str] = []
    cursor: str | None = None
    pages = 0
    while True:
        params = {"limit": 2}
        if cursor is not None:
            params["cursor"] = cursor
        page = client.get(
            f"/community/clubs/{club.public_id}/members",
            headers=viewer_headers,
            params=params,
        )
        assert page.status_code == 200, page.text
        pages += 1
        seen.extend(i["profile_public_id"] for i in page.json()["items"])
        cursor = page.json()["next_cursor"]
        if cursor is None or pages > 10:
            break
    assert pages == 3
    assert seen == [str(owner.public_id), str(viewer.public_id), *tail]
    assert str(blocked.public_id) not in seen


def test_clubs_walk_survives_blocked_owner_on_page_boundary(
    client, session_factory
) -> None:
    good_owner, _ = _make_user(session_factory, user_id=1)
    bad_owner, _ = _make_user(session_factory, user_id=2)
    viewer, viewer_headers = _make_user(session_factory, user_id=3)
    _add_block(session_factory, blocker=viewer, blocked=bad_owner)
    base = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
    # Newest-first order: c4, c3(blocked owner), c2, c1 with limit=2 —
    # page 1 raw = (c4, c3) → visible (c4); page 2 = (c2, c1).
    c1 = _create_club(
        session_factory, owner=good_owner, visibility="public", created_at=base
    )
    c2 = _create_club(
        session_factory,
        owner=good_owner,
        visibility="public",
        created_at=base.replace(minute=1),
    )
    _create_club(
        session_factory,
        owner=bad_owner,
        visibility="public",
        created_at=base.replace(minute=2),
    )
    c4 = _create_club(
        session_factory,
        owner=good_owner,
        visibility="public",
        created_at=base.replace(minute=3),
    )

    first = client.get(
        "/community/clubs", headers=viewer_headers, params={"limit": 2}
    ).json()
    assert [i["public_id"] for i in first["items"]] == [str(c4.public_id)]
    assert first["next_cursor"] is not None
    second = client.get(
        "/community/clubs",
        headers=viewer_headers,
        params={"limit": 2, "cursor": first["next_cursor"]},
    ).json()
    assert [i["public_id"] for i in second["items"]] == [
        str(c2.public_id),
        str(c1.public_id),
    ]
    assert second["next_cursor"] is None
