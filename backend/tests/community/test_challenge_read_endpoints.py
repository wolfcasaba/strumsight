"""Challenge READ endpoints — ``GET /community/challenges``,
``GET /community/challenges/{id}``, ``GET /community/challenges/{id}/me``
(``app/community/routers/challenges.py`` + ``services/
challenge_query_service.py``).

These are the three routes the Flutter ``HttpCommunityChallengeRepository``
was already coded against (``listChallenges`` / ``fetchDefinition`` /
``fetchMyParticipation``). Cells:

* wire shape — every key ``decodeChallengeDefinition`` reads is present
  with the right type (``public_id`` / ``type`` / ``metric`` /
  ``difficulty`` / ``starts_at`` / ``ends_at`` / ``author_public_id`` /
  ``version`` / ``club_id``) and the page envelope is
  ``{"items", "next_cursor"}``;
* visibility — public types for everyone; ``friends`` challenges only
  to the author / invitee / participant; ``club`` challenges only to
  club members; blocked authors dropped; uniform 404 on detail;
* ``/me`` — ``{"participant": null}`` for a readable challenge without
  a relationship, the invite state for an invitee, ``active`` /
  ``completed`` for a participant;
* filters — ``window`` (active / upcoming / ended) and ``club_id``;
* cursor pagination is complete + disjoint, a malformed cursor restarts;
* auth — anonymous callers are rejected; a caller without a profile 404s;
* the existing write routes are untouched (a smoke on the invite POST).
"""

from __future__ import annotations

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
from app.community.models.challenge import (
    CHALLENGE_INVITE_STATE_DECLINED,
    CHALLENGE_INVITE_STATE_SENT,
    CHALLENGE_TYPE_CLUB,
    CHALLENGE_TYPE_DAILY_COMMUNITY,
    CHALLENGE_TYPE_FRIENDS,
    CHALLENGE_TYPE_PERIODIC_GLOBAL,
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from app.community.models.club import CommunityClub, CommunityClubMember
from app.community.models.profile import CommunityProfile
from app.community.models.safety_relationships import CommunityBlock
from app.community.services.challenge_invite_service import reset_rate_limiters
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


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "challenge-read.db"
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
    from app.community.routers.challenges import router as challenges_router

    app = FastAPI(title="Challenge Read Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = Settings(_env_file=None, community_enabled=True)
    app.include_router(challenges_router)
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
def _reset_invite_limiter() -> Iterator[None]:
    reset_rate_limiters()
    try:
        yield
    finally:
        reset_rate_limiters()


# ---------------------------------------------------------------------------
# Seeding helpers
# ---------------------------------------------------------------------------

_NOW = datetime(2026, 9, 15, 12, 0, tzinfo=timezone.utc)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _make_user(
    session_factory, *, user_id: int
) -> tuple[CommunityProfile, dict[str, str]]:
    db: Session = session_factory()
    try:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": user_id,
                "email": f"u{user_id}@s.test",
                "password": hash_password("test-password"),
                "ts": _utcnow(),
            },
        )
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
                "vis": "public",
                "aud": "public",
            },
        )
        db.commit()
        db.refresh(profile)
    finally:
        db.close()
    return profile, {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _make_challenge(
    session_factory,
    *,
    author: CommunityProfile,
    type: str = CHALLENGE_TYPE_DAILY_COMMUNITY,
    starts_at: datetime | None = None,
    ends_at: datetime | None = None,
    club_id: str | None = None,
    created_at: datetime | None = None,
    metric: str = "score",
    difficulty: int = 2,
) -> CommunityChallenge:
    now = _utcnow()
    db: Session = session_factory()
    try:
        challenge = CommunityChallenge(
            public_id=uuid.uuid4(),
            author_profile_id=author.id,
            type=type,
            metric=metric,
            difficulty=difficulty,
            starts_at=starts_at or (now - timedelta(days=1)),
            ends_at=ends_at or (now + timedelta(days=6)),
            version=1,
            club_id=club_id,
            created_at=created_at or now,
            updated_at=created_at or now,
        )
        db.add(challenge)
        db.commit()
        db.refresh(challenge)
        return challenge
    finally:
        db.close()


def _add_invite(
    session_factory,
    *,
    challenge: CommunityChallenge,
    inviter: CommunityProfile,
    invitee: CommunityProfile,
    state: str = CHALLENGE_INVITE_STATE_SENT,
) -> CommunityChallengeInvite:
    now = _utcnow()
    db: Session = session_factory()
    try:
        invite = CommunityChallengeInvite(
            public_id=uuid.uuid4(),
            challenge_id=challenge.id,
            inviter_profile_id=inviter.id,
            invitee_profile_id=invitee.id,
            state=state,
            expires_at=now + timedelta(days=14),
            idempotency_key=f"inv-{uuid.uuid4().hex}",
            created_at=now,
            updated_at=now,
        )
        db.add(invite)
        db.commit()
        db.refresh(invite)
        return invite
    finally:
        db.close()


def _add_participant(
    session_factory,
    *,
    challenge: CommunityChallenge,
    profile: CommunityProfile,
    best_metric_value: int | None = None,
) -> CommunityChallengeParticipant:
    db: Session = session_factory()
    try:
        participant = CommunityChallengeParticipant(
            public_id=uuid.uuid4(),
            challenge_id=challenge.id,
            participant_profile_id=profile.id,
            best_metric_value=best_metric_value,
            joined_at=_utcnow(),
        )
        db.add(participant)
        db.commit()
        db.refresh(participant)
        return participant
    finally:
        db.close()


def _make_club_with_member(
    session_factory, *, owner: CommunityProfile, member: CommunityProfile
) -> CommunityClub:
    now = _utcnow()
    db: Session = session_factory()
    try:
        club = CommunityClub(
            public_id=uuid.uuid4(),
            name="Club",
            description="",
            visibility="private",
            owner_profile_id=owner.id,
            created_at=now,
            updated_at=now,
        )
        db.add(club)
        db.flush()
        for profile, role in ((owner, "owner"), (member, "member")):
            db.add(
                CommunityClubMember(
                    public_id=uuid.uuid4(),
                    club_id=club.id,
                    profile_id=profile.id,
                    role=role,
                    joined_at=now,
                    updated_at=now,
                )
            )
        db.commit()
        db.refresh(club)
        return club
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


# ---------------------------------------------------------------------------
# Wire shape
# ---------------------------------------------------------------------------


def test_list_and_detail_carry_the_flutter_decoder_fields(client, session_factory):
    author, headers = _make_user(session_factory, user_id=1)
    challenge = _make_challenge(session_factory, author=author, club_id="club-x")

    listing = client.get("/community/challenges", headers=headers)
    assert listing.status_code == 200, listing.text
    body = listing.json()
    assert set(body) == {"items", "next_cursor"}
    assert len(body["items"]) == 1
    item = body["items"][0]
    for key in (
        "public_id",
        "type",
        "metric",
        "difficulty",
        "starts_at",
        "ends_at",
        "author_public_id",
        "version",
        "club_id",
    ):
        assert key in item, key
    assert item["public_id"] == str(challenge.public_id)
    assert item["author_public_id"] == str(author.public_id)
    assert item["type"] == CHALLENGE_TYPE_DAILY_COMMUNITY
    assert item["metric"] == "score"
    assert isinstance(item["difficulty"], int)
    assert item["version"] == 1
    assert item["club_id"] == "club-x"
    assert item["participant_count"] == 0
    assert "id" not in item
    datetime.fromisoformat(item["starts_at"])
    datetime.fromisoformat(item["ends_at"])

    detail = client.get(f"/community/challenges/{challenge.public_id}", headers=headers)
    assert detail.status_code == 200
    assert detail.json() == item


# ---------------------------------------------------------------------------
# Visibility
# ---------------------------------------------------------------------------


def test_visibility_rule_public_own_invited_participant_club(client, session_factory):
    author, author_headers = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)
    stranger, _ = _make_user(session_factory, user_id=3)

    public_daily = _make_challenge(session_factory, author=author)
    public_global = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_PERIODIC_GLOBAL
    )
    friends_hidden = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_FRIENDS
    )
    friends_invited = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_FRIENDS
    )
    _add_invite(
        session_factory, challenge=friends_invited, inviter=author, invitee=viewer
    )
    friends_joined = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_FRIENDS
    )
    _add_participant(session_factory, challenge=friends_joined, profile=viewer)
    own = _make_challenge(session_factory, author=viewer, type=CHALLENGE_TYPE_FRIENDS)
    club = _make_club_with_member(session_factory, owner=author, member=viewer)
    club_visible = _make_challenge(
        session_factory,
        author=author,
        type=CHALLENGE_TYPE_CLUB,
        club_id=str(club.public_id),
    )
    club_hidden = _make_challenge(
        session_factory,
        author=stranger,
        type=CHALLENGE_TYPE_CLUB,
        club_id=str(uuid.uuid4()),
    )

    visible = {
        i["public_id"]
        for i in client.get("/community/challenges", headers=viewer_headers).json()[
            "items"
        ]
    }
    assert visible == {
        str(public_daily.public_id),
        str(public_global.public_id),
        str(friends_invited.public_id),
        str(friends_joined.public_id),
        str(own.public_id),
        str(club_visible.public_id),
    }
    assert str(friends_hidden.public_id) not in visible
    assert str(club_hidden.public_id) not in visible

    hidden = client.get(
        f"/community/challenges/{friends_hidden.public_id}", headers=viewer_headers
    )
    unknown = client.get(
        f"/community/challenges/{uuid.uuid4()}", headers=viewer_headers
    )
    assert hidden.status_code == 404
    assert unknown.status_code == 404
    assert hidden.json() == unknown.json()
    # The author sees their own hidden one.
    assert (
        client.get(
            f"/community/challenges/{friends_hidden.public_id}", headers=author_headers
        ).status_code
        == 200
    )


def test_blocked_author_challenges_are_dropped(client, session_factory):
    author, _ = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)
    challenge = _make_challenge(session_factory, author=author)
    _add_block(session_factory, blocker=viewer, blocked=author)

    assert (
        client.get("/community/challenges", headers=viewer_headers).json()["items"]
        == []
    )
    assert (
        client.get(
            f"/community/challenges/{challenge.public_id}", headers=viewer_headers
        ).status_code
        == 404
    )


# ---------------------------------------------------------------------------
# /me
# ---------------------------------------------------------------------------


def test_me_null_invitee_participant_and_hidden(client, session_factory):
    author, _ = _make_user(session_factory, user_id=1)
    viewer, viewer_headers = _make_user(session_factory, user_id=2)

    public_challenge = _make_challenge(session_factory, author=author)
    none = client.get(
        f"/community/challenges/{public_challenge.public_id}/me", headers=viewer_headers
    )
    assert none.status_code == 200
    assert none.json() == {"participant": None}

    invited = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_FRIENDS
    )
    invite = _add_invite(
        session_factory,
        challenge=invited,
        inviter=author,
        invitee=viewer,
        state=CHALLENGE_INVITE_STATE_DECLINED,
    )
    declined = client.get(
        f"/community/challenges/{invited.public_id}/me", headers=viewer_headers
    )
    assert declined.status_code == 200
    participant = declined.json()["participant"]
    assert participant["participant_public_id"] == str(viewer.public_id)
    assert participant["invite_state"] == "declined"
    assert participant["best_metric_value"] is None
    assert participant["invite_public_id"] == str(invite.public_id)
    assert participant["challenge_public_id"] == str(invited.public_id)

    joined_active = _make_challenge(session_factory, author=author)
    _add_participant(
        session_factory, challenge=joined_active, profile=viewer, best_metric_value=42
    )
    active = client.get(
        f"/community/challenges/{joined_active.public_id}/me", headers=viewer_headers
    ).json()["participant"]
    assert active["invite_state"] == "active"
    assert active["best_metric_value"] == 42
    assert active["joined_at"] is not None

    joined_ended = _make_challenge(
        session_factory,
        author=author,
        starts_at=_utcnow() - timedelta(days=10),
        ends_at=_utcnow() - timedelta(days=1),
    )
    _add_participant(session_factory, challenge=joined_ended, profile=viewer)
    ended = client.get(
        f"/community/challenges/{joined_ended.public_id}/me", headers=viewer_headers
    ).json()["participant"]
    assert ended["invite_state"] == "completed"

    hidden = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_FRIENDS
    )
    assert (
        client.get(
            f"/community/challenges/{hidden.public_id}/me", headers=viewer_headers
        ).status_code
        == 404
    )


# ---------------------------------------------------------------------------
# Filters + pagination
# ---------------------------------------------------------------------------


def test_window_and_club_filters(client, session_factory):
    author, headers = _make_user(session_factory, user_id=1)
    now = _utcnow()
    active = _make_challenge(session_factory, author=author, club_id="c1")
    upcoming = _make_challenge(
        session_factory,
        author=author,
        starts_at=now + timedelta(days=1),
        ends_at=now + timedelta(days=2),
    )
    ended = _make_challenge(
        session_factory,
        author=author,
        starts_at=now - timedelta(days=3),
        ends_at=now - timedelta(days=1),
    )

    def ids(**params) -> set[str]:
        response = client.get("/community/challenges", headers=headers, params=params)
        assert response.status_code == 200, response.text
        return {i["public_id"] for i in response.json()["items"]}

    assert ids(window="active") == {str(active.public_id)}
    assert ids(window="upcoming") == {str(upcoming.public_id)}
    assert ids(window="ended") == {str(ended.public_id)}
    assert ids(club_id="c1") == {str(active.public_id)}
    assert ids(type=CHALLENGE_TYPE_DAILY_COMMUNITY) == {
        str(active.public_id),
        str(upcoming.public_id),
        str(ended.public_id),
    }
    bad_window = client.get(
        "/community/challenges", headers=headers, params={"window": "sometime"}
    )
    assert bad_window.status_code == 422


def test_cursor_walk_complete_disjoint_and_malformed_restarts(client, session_factory):
    author, headers = _make_user(session_factory, user_id=1)
    base = _NOW
    expected = [
        str(
            _make_challenge(
                session_factory, author=author, created_at=base + timedelta(minutes=i)
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
        page = client.get("/community/challenges", headers=headers, params=params)
        assert page.status_code == 200, page.text
        body = page.json()
        assert len(body["items"]) <= 2
        seen.extend(i["public_id"] for i in body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            break
    assert seen == list(reversed(expected))

    restarted = client.get(
        "/community/challenges", headers=headers, params={"cursor": "%%%not-a-cursor"}
    )
    assert restarted.status_code == 200
    assert len(restarted.json()["items"]) == 5
    assert (
        client.get(
            "/community/challenges", headers=headers, params={"limit": 0}
        ).status_code
        == 422
    )


# ---------------------------------------------------------------------------
# Auth / profile / untouched write routes
# ---------------------------------------------------------------------------


def test_anonymous_and_profileless_callers(client, session_factory):
    assert client.get("/community/challenges").status_code in (401, 403)
    assert client.get(f"/community/challenges/{uuid.uuid4()}").status_code in (401, 403)
    assert client.get(f"/community/challenges/{uuid.uuid4()}/me").status_code in (
        401,
        403,
    )

    db: Session = session_factory()
    try:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 77,
                "email": "noprofile@s.test",
                "password": hash_password("x"),
                "ts": _utcnow(),
            },
        )
        db.commit()
    finally:
        db.close()
    headers = {"Authorization": f"Bearer {create_access_token(77)}"}
    assert client.get("/community/challenges", headers=headers).status_code == 404


def test_existing_invite_write_route_still_works(client, session_factory):
    author, author_headers = _make_user(session_factory, user_id=1)
    invitee, invitee_headers = _make_user(session_factory, user_id=2)
    challenge = _make_challenge(
        session_factory, author=author, type=CHALLENGE_TYPE_FRIENDS
    )

    created = client.post(
        f"/community/challenges/{challenge.public_id}/invites",
        headers=author_headers,
        json={"invitee_public_id": str(invitee.public_id), "idempotency_key": "k1"},
    )
    assert created.status_code == 201, created.text

    # The invitee now sees the challenge and their ``sent`` state.
    me = client.get(
        f"/community/challenges/{challenge.public_id}/me", headers=invitee_headers
    ).json()["participant"]
    assert me["invite_state"] == "sent"
    assert me["invite_public_id"] == created.json()["public_id"]

    accepted = client.post(
        f"/community/challenges/invites/{created.json()['public_id']}/accept",
        headers=invitee_headers,
    )
    assert accepted.status_code == 200, accepted.text
    me_after = client.get(
        f"/community/challenges/{challenge.public_id}/me", headers=invitee_headers
    ).json()["participant"]
    assert me_after["invite_state"] == "active"
    detail = client.get(
        f"/community/challenges/{challenge.public_id}", headers=invitee_headers
    ).json()
    assert detail["participant_count"] == 1
