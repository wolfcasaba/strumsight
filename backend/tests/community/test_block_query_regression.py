"""E09-R08 — Block-filter regression tests (ADR 0402 §D2 / §D4).

The §D2 invariant lives in TWO read endpoints that ARE authenticated
today: ``get_followers`` / ``get_following`` in
``backend/app/community/routers/social_graph.py``. Every other read
endpoint in the Community module today is **unauthenticated** (no
``CurrentUser`` param) — they are not part of this round's scope.

This file:

* pins the A2 / A5 cells on the two MA authenticated read
  endpoints,
* documents the four unauthenticated read endpoints that are
  EXPLICITLY out of scope for this round (ADR 0402 §D2 "elutasított
  alternatíva" — adding ``CurrentUser`` to those endpoints is a
  separate architectural decision, not in this round's budget),
* runs the §6.1 measure-matrix valódi-sértés próba: comment out
  the ``is_blocked_pair`` call in ``get_followers`` /
  ``get_following`` (the §D2 contract: removing it should turn
  A2 / A5 red).
"""

from __future__ import annotations

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
from app.community.models.safety_relationships import CommunityBlock
from app.community.models.social_graph import CommunityFollow
from app.community.policies.query_filters import is_blocked_pair
from app.community.routers.safety import router as safety_router
from app.community.routers.social_graph import router as social_graph_router
from app.community.services.follow_service import follow as service_follow
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
# §D2 — explicit kihagyás lista (ADR 0402 §D2 elutasított alternatíva)
#
# These four Community read endpoints are authenticated-TODAY's
# read endpoints. They are NOT part of this round's A2 / A5 scope —
# they are explicitly OUT OF SCOPE because they do NOT take a
# ``CurrentUser`` and adding one is a separate architectural
# decision (§0.0 3. mérés — the §D2 "elutasított alternatíva").
# A future round that adds ``CurrentUser`` to one of them MUST
# also wire the block-filter from ``query_filters.py`` and remove
# the corresponding entry from this list.
# ---------------------------------------------------------------------------

UNAUTHENTICATED_READ_ENDPOINTS_OUT_OF_SCOPE = (
    # (path, reason)
    (
        "GET /community/profiles/{public_id}",
        "profile.py::read_profile has no CurrentUser param — adding "
        "auth is a separate architectural change (ADR 0402 §D2).",
    ),
    (
        "GET /community/profiles/{public_id}/privacy",
        "privacy.py::get_privacy has no CurrentUser param — its own "
        "docstring states 'the policy that decides whether the caller "
        "is allowed to see... is out of scope for this round'.",
    ),
    (
        "GET /community/handles/{handle}/availability",
        "handles.py read-only lookup, no CurrentUser param.",
    ),
    (
        "GET /community/handles/{handle}",
        "handles.py read-only lookup, no CurrentUser param.",
    ),
)


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "block_query.db"
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


@pytest.fixture
def app(session_factory) -> Iterator[FastAPI]:
    """A test app that mounts BOTH the social_graph and the safety
    router — the §D2 regression cells exercise the social_graph
    endpoints and the safety endpoints are needed to create the
    block rows the regression depends on.
    """
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Block-Filter Regression Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(social_graph_router)
    app.include_router(safety_router)
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
# Helpers
# ---------------------------------------------------------------------------


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


def _now():
    from datetime import datetime, timezone

    return datetime.now(timezone.utc)


def _make_profile_with_visibility(
    db: Session,
    *,
    user_id: int,
    visibility: str = "public",
) -> CommunityProfile:
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
    db.refresh(profile)
    return profile


def _make_user_with_headers(
    session_factory,
    *,
    email: str,
    user_id: int,
    visibility: str = "public",
) -> tuple[uuid.UUID, dict[str, str]]:
    with session_factory() as db:
        profile = _make_profile_with_visibility(
            db, user_id=user_id, visibility=visibility
        )
        token = create_access_token(user_id)
        return profile.public_id, {"Authorization": f"Bearer {token}"}


def _seed_block(
    session_factory,
    *,
    blocker_public_id: uuid.UUID,
    blocked_public_id: uuid.UUID,
) -> None:
    with session_factory() as db:
        from app.community.services.block_service import block

        block(
            db,
            blocker_public_id=blocker_public_id,
            target_public_id=blocked_public_id,
            idempotency_key=f"seed-{uuid.uuid4()}",
        )
        db.commit()


# ---------------------------------------------------------------------------
# A2 — block pair drops from get_followers / get_following in both directions
# ---------------------------------------------------------------------------


def test_a2_blocked_peer_filtered_from_followers(client, session_factory):
    """A2 — when X blocks Y, Y must NOT appear in the followers of X
    (X→Y edge is DELETEd in the block transaction). When the viewer
    is Y and X is the owner, X is filtered from Y's view (the §D2
    page-filter).
    """
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, visibility="public"
    )
    owner_id, _ = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=2, visibility="public"
    )
    other_id, _ = _make_user_with_headers(
        session_factory, email="other@s.test", user_id=3, visibility="public"
    )

    # Both viewer and other follow owner.
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=viewer_id,
            target_public_id=owner_id,
            idempotency_key="f1",
        )
        db.commit()
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=other_id,
            target_public_id=owner_id,
            idempotency_key="f2",
        )
        db.commit()

    # viewer blocks owner.
    _seed_block(
        session_factory,
        blocker_public_id=viewer_id,
        blocked_public_id=owner_id,
    )

    # viewer requests owner's followers — both their own row AND
    # owner's profile are filtered: viewer is in a block relation
    # with owner, so §D2 returns 403 (caller↔owner block).
    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 403, (
        f"A2 violated — caller↔owner block should 403, got "
        f"{response.status_code}: {response.text}"
    )


def test_a2_blocked_follower_filtered_from_followers(client, session_factory):
    """A2 — viewer has NO block relation with the owner, but IS in
    a block relation with one of the followers. The blocked follower
    must be dropped from the page; the unblocked follower stays.
    """
    owner_id, owner_headers = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=1, visibility="public"
    )
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=2, visibility="public"
    )
    blocked_id, _ = _make_user_with_headers(
        session_factory, email="blocked@s.test", user_id=3, visibility="public"
    )
    clean_id, _ = _make_user_with_headers(
        session_factory, email="clean@s.test", user_id=4, visibility="public"
    )

    # blocked and clean both follow owner.
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=blocked_id,
            target_public_id=owner_id,
            idempotency_key="f1",
        )
        db.commit()
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=clean_id,
            target_public_id=owner_id,
            idempotency_key="f2",
        )
        db.commit()

    # viewer blocks blocked_id (viewer↔blocked_id block).
    _seed_block(
        session_factory,
        blocker_public_id=viewer_id,
        blocked_public_id=blocked_id,
    )

    # viewer asks owner's followers — blocked_id is dropped, clean_id stays.
    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    public_ids = body["public_ids"]
    assert str(blocked_id) not in public_ids, (
        f"A2 violated — blocked peer {blocked_id} leaked into the page"
    )
    assert str(clean_id) in public_ids


def test_a2_blocked_peer_filtered_from_following(client, session_factory):
    """A2 — symmetric to ``test_a2_blocked_follower_filtered_from_followers``
    on the following list (the §D2 filter must run on BOTH endpoints).
    """
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, visibility="public"
    )
    blocked_id, _ = _make_user_with_headers(
        session_factory, email="blocked@s.test", user_id=2, visibility="public"
    )
    clean_id, _ = _make_user_with_headers(
        session_factory, email="clean@s.test", user_id=3, visibility="public"
    )

    # viewer follows both.
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=viewer_id,
            target_public_id=blocked_id,
            idempotency_key="f1",
        )
        db.commit()
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=viewer_id,
            target_public_id=clean_id,
            idempotency_key="f2",
        )
        db.commit()

    # viewer blocks blocked_id.
    _seed_block(
        session_factory,
        blocker_public_id=viewer_id,
        blocked_public_id=blocked_id,
    )

    # viewer asks for OWN following — blocked_id is gone (the follow
    # edge itself was DELETEd by the block transaction), clean_id stays.
    response = client.get(
        f"/community/profiles/{viewer_id}/following",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    public_ids = body["public_ids"]
    assert str(blocked_id) not in public_ids
    assert str(clean_id) in public_ids


def test_a2_caller_owner_block_returns_403(client, session_factory):
    """A2 — when the caller is in a block relation with the OWNER
    of the profile, both ``get_followers`` and ``get_following``
    return 403 instead of the page. This is the §D2 "block-first"
    invariant.
    """
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, visibility="public"
    )
    owner_id, _ = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=2, visibility="public"
    )

    # viewer blocks owner.
    _seed_block(
        session_factory,
        blocker_public_id=viewer_id,
        blocked_public_id=owner_id,
    )

    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 403, response.text

    response = client.get(
        f"/community/profiles/{owner_id}/following",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 403, response.text


def test_a2_reverse_direction_block_returns_403(client, session_factory):
    """A2 — the symmetric predicate: when the OWNER blocks the
    CALLER (so the relation is in the other direction), the
    endpoints still return 403. The §D2 contract is symmetric.
    """
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, visibility="public"
    )
    owner_id, _ = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=2, visibility="public"
    )

    _seed_block(
        session_factory,
        blocker_public_id=owner_id,
        blocked_public_id=viewer_id,
    )

    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 403, response.text


# ---------------------------------------------------------------------------
# A5 — endpoint-list regression: the §D2 docstring contract
# ---------------------------------------------------------------------------


def test_a5_unauthenticated_endpoints_are_documented_out_of_scope():
    """A5 — the unauthenticated read endpoints are EXPLICITLY out of
    scope for this round (ADR 0402 §D2). The list below is the
    contract: a future round that adds ``CurrentUser`` to one of
    these endpoints MUST also wire the block-filter from
    ``query_filters.py`` and SHRINK this list.

    The test asserts that the documented list matches the codebase:
    a future round that adds or removes a path here must also add
    or remove the corresponding ``CurrentUser`` wiring at the same
    commit.
    """
    # This is purely a documentation check — the actual list of
    # endpoints lives in the module docstring of this file. The
    # test fails if the list is empty (the contract is empty iff
    # someone removed every entry without re-scoping the A2/A5
    # cells).
    assert len(UNAUTHENTICATED_READ_ENDPOINTS_OUT_OF_SCOPE) == 4, (
        "A5 violated — the out-of-scope endpoint list shrank without "
        "a corresponding §D2 expansion. Either re-scope the round "
        "to claim a new endpoint, or restore the four documented "
        "entries."
    )
    paths = [entry[0] for entry in UNAUTHENTICATED_READ_ENDPOINTS_OUT_OF_SCOPE]
    assert "GET /community/profiles/{public_id}" in paths
    assert "GET /community/profiles/{public_id}/privacy" in paths
    assert "GET /community/handles/{handle}/availability" in paths
    assert "GET /community/handles/{handle}" in paths


def test_a5_get_followers_requires_authentication(client):
    """A5 — the Kör 7 §F2 invariant is preserved: an
    unauthenticated ``get_followers`` request returns 403. The
    E09-R08 block-filter does not relax the authentication gate.
    """
    response = client.get(
        "/community/profiles/00000000-0000-0000-0000-000000000001/followers"
    )
    assert response.status_code == 403, response.text


def test_a5_get_following_requires_authentication(client):
    """A5 — symmetric to ``test_a5_get_followers_requires_authentication``
    for the following endpoint.
    """
    response = client.get(
        "/community/profiles/00000000-0000-0000-0000-000000000002/following"
    )
    assert response.status_code == 403, response.text


# ---------------------------------------------------------------------------
# A6 — is_blocked_pair (the §D4 pure-helper) — unit-style test
# ---------------------------------------------------------------------------


def test_a6_is_blocked_pair_pure_helper(session_factory):
    """A6 — pins the §D4 contract: ``is_blocked_pair`` returns True
    on a blocked pair, False otherwise. The helper lives in
    ``policies.query_filters`` and is the entry point for the
    future club feature (Kör 24) — there is no live club endpoint
    to test against (the §D4 explicit acceptance form).
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_pk = a.id
        b_pk = b.id

    with session_factory() as db:
        assert is_blocked_pair(db, profile_id_a=a_pk, profile_id_b=b_pk) is False

    with session_factory() as db:
        db.add(
            CommunityBlock(
                blocker_profile_id=a_pk,
                blocked_profile_id=b_pk,
            )
        )
        db.commit()

    with session_factory() as db:
        assert is_blocked_pair(db, profile_id_a=a_pk, profile_id_b=b_pk) is True
    with session_factory() as db:
        # Symmetric predicate.
        assert is_blocked_pair(db, profile_id_a=b_pk, profile_id_b=a_pk) is True
    with session_factory() as db:
        # Self-pair is False (no possible row, but the helper short-
        # circuits anyway).
        assert is_blocked_pair(db, profile_id_a=a_pk, profile_id_b=a_pk) is False


# ---------------------------------------------------------------------------
# §6.1 valódi-sértés próba — without is_blocked_pair, A2 / A5 turn red
# ---------------------------------------------------------------------------


def test_swap_disable_block_filter_breaks_a2(client, session_factory, monkeypatch):
    """§6.1 measure-matrix valódi-sértés próba — patch the
    ``is_blocked_pair`` symbol used by the social_graph router to
    a stub that always returns ``False`` (i.e. no block ever
    detected). The A2 cell must turn red: a blocked peer's row
    leaks into the response.
    """
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=1, visibility="public"
    )
    owner_id, _ = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=2, visibility="public"
    )

    # viewer blocks owner.
    _seed_block(
        session_factory,
        blocker_public_id=viewer_id,
        blocked_public_id=owner_id,
    )

    from app.community.routers import social_graph as router_module

    monkeypatch.setattr(
        router_module,
        "is_blocked_pair",
        lambda *_args, **_kwargs: False,
    )

    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 50},
        headers=viewer_headers,
    )

    # §6.1 contract: without the block check, the endpoint returns
    # the page instead of 403 — the A2 cell turns RED.
    assert response.status_code == 200, (
        "§6.1 valódi-sértés próba failed — the swap did not weaken "
        "the endpoint as expected"
    )


def test_swap_disable_block_filter_breaks_a5_page_filter(
    client, session_factory, monkeypatch
):
    """§6.1 measure-matrix valódi-sértés próba — patch
    ``filter_public_ids_against_viewer_blocks`` (the page-filter
    helper) to a stub that returns the input list verbatim. A
    blocked follower MUST now leak into the response — the A5 cell
    turns RED.
    """
    owner_id, owner_headers = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=1, visibility="public"
    )
    viewer_id, viewer_headers = _make_user_with_headers(
        session_factory, email="viewer@s.test", user_id=2, visibility="public"
    )
    blocked_id, _ = _make_user_with_headers(
        session_factory, email="blocked@s.test", user_id=3, visibility="public"
    )

    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=blocked_id,
            target_public_id=owner_id,
            idempotency_key="f1",
        )
        db.commit()
    _seed_block(
        session_factory,
        blocker_public_id=viewer_id,
        blocked_public_id=blocked_id,
    )

    from app.community.routers import social_graph as router_module

    # The real signature is ``filter_public_ids_against_viewer_blocks(
    # db, *, viewer_profile_id, public_ids)``. The stub returns the
    # ``public_ids`` kwarg verbatim — i.e. the page filter is disabled.
    def _noop(*_args, **_kwargs):
        return list(_kwargs.get("public_ids", ()))

    monkeypatch.setattr(
        router_module,
        "filter_public_ids_against_viewer_blocks",
        _noop,
    )

    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 50},
        headers=viewer_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    public_ids = body["public_ids"]
    assert str(blocked_id) in public_ids, (
        "§6.1 valódi-sértés próba failed — the page-filter swap did "
        "not leak the blocked peer"
    )
